import SwiftUI

// Folia/Features/PlaylistActionView.swift — server mutations always pass through Omni.
struct PlaylistActionView: View {
    let track: Track
    let add: Bool
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.dismiss) private var dismiss
    @State private var collections: [MusicCollection] = []
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            List {
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(collections) { collection in
                    Button(collection.title) {
                        busy = true; error = nil
                        Task {
                            do { try await playback.service.changePlaylist(collection, track: track, add: add); dismiss() }
                            catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    }.disabled(busy)
                }
                if collections.isEmpty && !busy && error == nil { Text(localized("此账户暂无可修改歌单", "No editable playlists for this account")) }
            }
            .navigationTitle(add ? localized("添加到歌单", "Add to playlist") : localized("从歌单移除", "Remove from playlist"))
            .toolbar { Button(localized("取消", "Cancel")) { dismiss() } }
            .task {
                busy = true
                do { collections = try await playback.service.playlists(provider: track.provider) }
                catch { self.error = error.localizedDescription }
                busy = false
            }
        }
    }
}
