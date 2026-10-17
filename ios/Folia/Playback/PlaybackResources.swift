import AVFoundation
import MediaPlayer

// Folia/Playback/PlaybackResources.swift — nonisolated resource lifetime avoids actor deinitialization races.
final class PlaybackResources {
    let player = AVPlayer()
    var loadTask: Task<Void, Never>?
    var artworkTask: Task<Void, Never>?
    var remoteTargets: [(MPRemoteCommand, Any)] = []
    var sleepTask: Task<Void, Never>?
    var timeObserver: Any?
    var notifications: [NSObjectProtocol] = []

    deinit {
        loadTask?.cancel(); sleepTask?.cancel(); artworkTask?.cancel()
        remoteTargets.forEach { command, target in command.removeTarget(target) }
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

