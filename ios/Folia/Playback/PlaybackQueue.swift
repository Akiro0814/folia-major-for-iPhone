import Foundation

// Folia/Playback/PlaybackQueue.swift — deterministic queue policy independent of AVPlayer.
enum RepeatMode: String, CaseIterable, Codable { case off, all, one }
struct PlaybackQueue {
    var ids: [String]
    var index: Int?
    var repeatMode: RepeatMode = .off
    var shuffle = false

    mutating func advance(automatic: Bool) -> Int? {
        guard let current = index, !ids.isEmpty else { return nil }
        if automatic && repeatMode == .one { return current }
        if shuffle && ids.count > 1 {
            let choices = ids.indices.filter { $0 != current }
            index = choices.randomElement(); return index
        }
        if current + 1 < ids.count { index = current + 1; return index }
        if repeatMode == .all { index = 0; return 0 }
        return nil
    }
    mutating func remove(at position: Int) {
        guard ids.indices.contains(position) else { return }
        ids.remove(at: position)
        guard let current = index else { return }
        if ids.isEmpty { index = nil }
        else if position < current { index = current - 1 }
        else { index = min(current, ids.count - 1) }
    }
}
