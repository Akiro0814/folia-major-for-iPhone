import AVFoundation
import MediaPlayer
import Observation

// Folia/Playback/PlaybackCoordinator.swift — native audio lifetime, queue, and stale-request protection.
@MainActor @Observable final class PlaybackCoordinator {
    let service: OmniService
    private let resources = PlaybackResources()
    var player: AVPlayer { resources.player }
    private var queueState = PlaybackQueue(ids: [], index: nil)
    private var loadTask: Task<Void, Never>? {
        get { resources.loadTask } set { resources.loadTask = newValue }
    }
    private var sleepTask: Task<Void, Never>? {
        get { resources.sleepTask } set { resources.sleepTask = newValue }
    }
    private var generation = UUID()
    private var timeObserver: Any? {
        get { resources.timeObserver } set { resources.timeObserver = newValue }
    }
    var notifications: [NSObjectProtocol] {
        get { resources.notifications } set { resources.notifications = newValue }
    }
    private var statusObservation: NSKeyValueObservation?
    var shouldResumeAfterInterruption = false
    private var retriedStream = false
    var tracks: [Track] = []
    var currentTrack: Track?
    var nowPlayingArtwork: MPMediaItemArtwork?
    var artworkTrackID: String?
    var artworkTask: Task<Void, Never>? {
        get { resources.artworkTask } set { resources.artworkTask = newValue }
    }
    var remoteTargets: [(MPRemoteCommand, Any)] {
        get { resources.remoteTargets } set { resources.remoteTargets = newValue }
    }
    var lyrics: LyricsPayload?
    var lyricsError: String?
    var currentTime: Double = 0
    var duration: Double = 0
    var isPlaying = false
    var isPlaybackRequested = false
    var audioPower: Double = 0
    var audioBands: [Double] = [0, 0, 0, 0, 0]
    var audioAnalysisAvailable = false
    private var lastPersistedPosition: Double = 0
    var isLoading = false
    var error: String?
    var sleepDeadline: Date?
    var repeatMode: RepeatMode = .off { didSet { queueState.repeatMode = repeatMode; persist() } }
    var shuffle = false { didSet { queueState.shuffle = shuffle; persist() } }
    var quality: AudioQuality = AudioQuality(rawValue: UserDefaults.standard.string(forKey: "folia.quality") ?? "") ?? .high {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "folia.quality") }
    }

    init(service: OmniService) {
        self.service = service
        configureAudio()
        restore()
        // Half-second samples feed controls and the interpolating lyric bridge, never per-frame SwiftUI state.
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                guard self.player.currentItem != nil, !self.isLoading else { return }
                let seconds = time.seconds
                if seconds.isFinite { self.currentTime = seconds }
                let length = self.player.currentItem?.duration.seconds ?? 0
                if length.isFinite && length > 0 { self.duration = length }
                self.isPlaying = self.player.timeControlStatus == .playing
                self.updateAudioLevels()
                if abs(self.currentTime - self.lastPersistedPosition) >= 10 {
                    self.persist(); self.lastPersistedPosition = self.currentTime
                }
                self.updateNowPlaying()
            }
        }
        observeSystemEvents()
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
    private func load(_ track: Track, position: Double, retry: Bool = false, autoplay: Bool = true) {
        loadTask?.cancel(); player.pause(); statusObservation = nil; player.replaceCurrentItem(with: nil)
        generation = UUID(); let request = generation
        resources.audioAnalysis = nil; updateAudioLevels()
        currentTrack = track; lyrics = nil; lyricsError = nil; currentTime = position; duration = track.duration
        isPlaying = false; isPlaybackRequested = autoplay; isLoading = true; error = nil; retriedStream = retry
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let source = try await service.stream(for: track, quality: quality)
                try Task.checkCancellation(); guard generation == request else { return }
                guard source.url.scheme?.lowercased() == "https" || source.url.scheme?.lowercased() == "http" else { throw MusicError.unavailable("只允许在线播放地址。") }
                let asset = AVURLAsset(url: source.url, options: ["AVURLAssetHTTPHeaderFieldsKey": source.headers])
                let item = AVPlayerItem(asset: asset)
                let analysis = NativeAudioAnalysis()
                let attached = await analysis.attach(to: item)
                try Task.checkCancellation(); guard generation == request else { return }
                resources.audioAnalysis = attached ? analysis : nil
                statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    Task { @MainActor in
                        guard let self, self.generation == request else { return }
                        if item.status == .failed { self.handleFailure(item.error) }
                    }
                }
                player.replaceCurrentItem(with: item)
                if position > 0 { await player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
                try Task.checkCancellation(); guard generation == request else { return }
                if isPlaybackRequested {
                    try AVAudioSession.sharedInstance().setActive(true); player.play(); isPlaying = true
                }
                isLoading = false; persist(); updateNowPlaying(); loadNowPlayingArtwork(for: track)
                do {
                    let payload = try await service.lyrics(for: track)
                    try Task.checkCancellation(); guard generation == request else { return }; lyrics = payload
                } catch {
                    if generation == request && !Task.isCancelled { lyricsError = "\(track.provider.title): \(error.localizedDescription)" }
                }
            } catch is CancellationError { } catch {
                guard generation == request else { return }
                self.error = error.localizedDescription; isLoading = false; isPlaying = false; isPlaybackRequested = false
            }
        }
    }

    func toggle() { if isPlaybackRequested { pause() } else { resume() } }
    func resume() {
        isPlaybackRequested = true
        guard !isLoading else { return }
        if player.currentItem == nil, let track = currentTrack { load(track, position: currentTime); return }
        guard player.currentItem != nil else { isPlaybackRequested = false; return }
        do { try AVAudioSession.sharedInstance().setActive(true); player.play() }
        catch { self.error = error.localizedDescription; isPlaybackRequested = false }
        persist(); updateNowPlaying()
    }
    func pause() {
        isPlaybackRequested = false; player.pause(); isPlaying = false; updateAudioLevels(); persist(); updateNowPlaying()
    }
    private func updateAudioLevels() {
        let measured = resources.audioAnalysis?.snapshot() ?? AudioAnalysisSnapshot()
        audioAnalysisAvailable = measured.available
        audioPower = isPlaying ? measured.power : 0
        audioBands = isPlaying ? measured.bands : [0, 0, 0, 0, 0]
    }

    func queueSnapshot() -> PlaybackSnapshot {
        PlaybackSnapshot(tracks: tracks.map(FoliaBackup.reference), index: queueState.index,
                         position: currentTime, repeatMode: repeatMode, shuffle: shuffle, quality: quality)
    }
    func restoreQueue(_ snapshot: PlaybackSnapshot) throws {
        let state = try snapshot.validated()
        loadTask?.cancel(); artworkTask?.cancel(); generation = UUID(); statusObservation = nil
        player.pause(); player.replaceCurrentItem(with: nil); resources.audioAnalysis = nil; updateAudioLevels()
        tracks = state.tracks; queueState = PlaybackQueue(ids: tracks.map(\.id), index: state.index)
        currentTrack = state.index.map { tracks[$0] }; currentTime = state.position
        duration = currentTrack?.duration ?? 0; lyrics = nil; lyricsError = nil
        nowPlayingArtwork = nil; artworkTrackID = nil; isLoading = false; error = nil
        isPlaybackRequested = false; isPlaying = false
        repeatMode = state.repeatMode; shuffle = state.shuffle; quality = state.quality
        persist(); updateNowPlaying()
    }
    func savePlaybackState() { persist() }
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
        if !retriedStream, let track = currentTrack { load(track, position: currentTime, retry: true, autoplay: isPlaybackRequested) }
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











