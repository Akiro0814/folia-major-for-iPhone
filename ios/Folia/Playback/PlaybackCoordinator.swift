import AVFoundation
import MediaPlayer
import Observation

// Folia/Playback/PlaybackCoordinator.swift — native audio lifetime, queue, and stale-request protection.
@MainActor @Observable final class PlaybackCoordinator {
    let service: OmniService
    let player = AVPlayer()
    private var queueState = PlaybackQueue(ids: [], index: nil)
    private var loadTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var generation = UUID()
    private var timeObserver: Any?
    var notifications: [NSObjectProtocol] = []
    private var statusObservation: NSKeyValueObservation?
    var shouldResumeAfterInterruption = false
    private var retriedStream = false
    var tracks: [Track] = []
    var currentTrack: Track?
    var lyrics: LyricsPayload?
    var currentTime: Double = 0
    var duration: Double = 0
    var isPlaying = false
    var isLoading = false
    var error: String?
    var sleepDeadline: Date?
    var repeatMode: RepeatMode = .off { didSet { queueState.repeatMode = repeatMode; persist() } }
    var shuffle = false { didSet { queueState.shuffle = shuffle; persist() } }
    var quality: AudioQuality = .high

    init(service: OmniService) {
        self.service = service
        configureAudio()
        restore()
        // Half-second samples feed controls and the interpolating lyric bridge, never per-frame SwiftUI state.
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite { self.currentTime = seconds }
                let length = self.player.currentItem?.duration.seconds ?? 0
                if length.isFinite && length > 0 { self.duration = length }
                self.isPlaying = self.player.timeControlStatus == .playing
                self.updateNowPlaying()
            }
        }
        observeSystemEvents()
    }

    deinit {
        loadTask?.cancel(); sleepTask?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func playQueueItem(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        queueState.index = index; load(tracks[index], position: 0)
    }

    func play(_ track: Track, in collection: [Track]? = nil) {
        if let collection { tracks = collection }
        if !tracks.contains(where: { $0.id == track.id }) { tracks.append(track) }
        queueState.ids = tracks.map(\.id)
        queueState.index = tracks.firstIndex(where: { $0.id == track.id })
        load(track, position: 0)
    }

    // Each stream/lyric resolution belongs to a generation; a late response cannot replace a newer song.
    private func load(_ track: Track, position: Double, retry: Bool = false) {
        loadTask?.cancel(); player.pause()
        generation = UUID(); let request = generation
        currentTrack = track; lyrics = nil; currentTime = position; duration = track.duration
        isPlaying = false; isLoading = true; error = nil; retriedStream = retry
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let source = try await service.stream(for: track, quality: quality)
                try Task.checkCancellation(); guard generation == request else { return }
                guard source.url.scheme?.lowercased() == "https" || source.url.scheme?.lowercased() == "http" else { throw MusicError.unavailable("只允许在线播放地址。") }
                let asset = AVURLAsset(url: source.url, options: ["AVURLAssetHTTPHeaderFieldsKey": source.headers])
                let item = AVPlayerItem(asset: asset)
                statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    Task { @MainActor in
                        guard let self, self.generation == request else { return }
                        if item.status == .failed { self.handleFailure(item.error) }
                    }
                }
                player.replaceCurrentItem(with: item)
                if position > 0 { await player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
                try Task.checkCancellation(); guard generation == request else { return }
                try AVAudioSession.sharedInstance().setActive(true)
                player.play(); isPlaying = true; isLoading = false; persist(); updateNowPlaying()
                do {
                    let payload = try await service.lyrics(for: track)
                    try Task.checkCancellation(); guard generation == request else { return }; lyrics = payload
                } catch { /* Audio remains available if the provider has no lyrics. */ }
            } catch is CancellationError { } catch {
                guard generation == request else { return }
                self.error = error.localizedDescription; isLoading = false; isPlaying = false
            }
        }
    }

    func toggle() {
        if player.currentItem == nil, let track = currentTrack { load(track, position: currentTime); return }
        if isPlaying { player.pause(); isPlaying = false } else { try? AVAudioSession.sharedInstance().setActive(true); player.play(); isPlaying = true }
        persist(); updateNowPlaying()
    }
    func pause() { player.pause(); isPlaying = false; persist(); updateNowPlaying() }
    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        currentTime = max(0, min(seconds, max(duration, 0)))
        player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600)); persist(); updateNowPlaying()
    }
    func next(automatic: Bool = false) {
        guard let index = queueState.advance(automatic: automatic), tracks.indices.contains(index) else { pause(); return }
        load(tracks[index], position: 0)
    }
    func previous() {
        if currentTime > 3 { seek(to: 0); return }
        guard let index = queueState.index, !tracks.isEmpty else { return }
        queueState.index = max(0, index - 1); load(tracks[max(0, index - 1)], position: 0)
    }
    func enqueueNext(_ track: Track) {
        let position = min((queueState.index ?? -1) + 1, tracks.count)
        tracks.insert(track, at: position); queueState.ids = tracks.map(\.id); persist()
    }
    func removeFromQueue(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        let removesCurrent = queueState.index == index
        tracks.remove(at: index); queueState.remove(at: index)
        if removesCurrent {
            if let next = queueState.index { load(tracks[next], position: 0) }
            else { loadTask?.cancel(); generation = UUID(); player.replaceCurrentItem(with: nil); currentTrack = nil; lyrics = nil; pause() }
        }; persist()
    }
    func setSleep(minutes: Int?) {
        sleepTask?.cancel(); sleepDeadline = nil
        guard let minutes else { return }
        sleepDeadline = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(Double(minutes) * 60)); self?.pause(); self?.sleepDeadline = nil }
            catch { }
        }
    }

    private func handleFailure(_ failure: Error?) {
        if !retriedStream, let track = currentTrack { load(track, position: currentTime, retry: true) }
        else { error = failure?.localizedDescription ?? localized("无法播放这首歌曲", "This song cannot be played"); isLoading = false; pause() }
    }
    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(tracks), forKey: "folia.queue")
        defaults.set(queueState.index, forKey: "folia.queueIndex")
        defaults.set(currentTime, forKey: "folia.position")
        defaults.set(repeatMode.rawValue, forKey: "folia.repeat")
        defaults.set(shuffle, forKey: "folia.shuffle")
    }
    private func restore() {
        let defaults = UserDefaults.standard
        tracks = defaults.data(forKey: "folia.queue").flatMap { try? JSONDecoder().decode([Track].self, from: $0) } ?? []
        let index = defaults.integer(forKey: "folia.queueIndex")
        queueState = PlaybackQueue(ids: tracks.map(\.id), index: tracks.indices.contains(index) ? index : nil)
        if let index = queueState.index { currentTrack = tracks[index]; currentTime = defaults.double(forKey: "folia.position"); duration = tracks[index].duration }
        let savedRepeat = RepeatMode(rawValue: defaults.string(forKey: "folia.repeat") ?? "") ?? .off
        let savedShuffle = defaults.bool(forKey: "folia.shuffle")
        repeatMode = savedRepeat; shuffle = savedShuffle
    }
}



