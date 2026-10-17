import AVFoundation
import MediaPlayer
import UIKit

// Folia/Playback/PlaybackSystem.swift — interruption, route and system transport integration.
extension PlaybackCoordinator {
    func configureAudio() {
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay]) }
        catch { self.error = error.localizedDescription }
        let commands = MPRemoteCommandCenter.shared()
        registerRemote(commands.playCommand) { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        registerRemote(commands.pauseCommand) { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        registerRemote(commands.togglePlayPauseCommand) { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        registerRemote(commands.nextTrackCommand) { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        registerRemote(commands.previousTrackCommand) { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        registerRemote(commands.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }; return .success
        }
    }

    private func registerRemote(_ command: MPRemoteCommand, handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        remoteTargets.append((command, command.addTarget(handler: handler)))
    }

    func observeSystemEvents() {
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                guard let self, let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.next(automatic: true)
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.shouldResumeAfterInterruption = self.isPlaybackRequested; self.pause()
                } else if self.shouldResumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    self.resume(); self.shouldResumeAfterInterruption = false
                }
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() } }
        })
    }

    // Fetch once per selected track; a late cover from an old song cannot replace current lock-screen metadata.
    func loadNowPlayingArtwork(for track: Track) {
        artworkTask?.cancel()
        if artworkTrackID == track.id && nowPlayingArtwork != nil { return }
        nowPlayingArtwork = nil; artworkTrackID = nil
        guard let url = track.artworkURL, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        artworkTask = Task { [weak self] in
            do {
                var request = URLRequest(url: url); request.timeoutInterval = 20
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard let self, self.currentTrack?.id == track.id, data.count < 10_000_000,
                      let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                      let image = UIImage(data: data) else { return }
                self.nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.artworkTrackID = track.id; self.updateNowPlaying()
            } catch { /* Missing cover art does not interrupt native audio. */ }
        }
    }
    func updateNowPlaying() {
        guard let track = currentTrack else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album, MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if artworkTrackID == track.id, let nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}



