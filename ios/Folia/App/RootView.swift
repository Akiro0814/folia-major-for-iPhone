import SwiftUI

// Folia/App/RootView.swift — system navigation and persistent mini player.
struct RootView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var showPlayer = false

    var body: some View {
        TabView {
            Tab(localized("曲库", "Library"), systemImage: "square.stack") { NavigationStack { LibraryView() } }
            Tab(localized("搜索", "Search"), systemImage: "magnifyingglass", role: .search) { NavigationStack { SearchView() } }
            Tab(localized("设置", "Settings"), systemImage: "gearshape") { NavigationStack { SettingsView() } }
        }
        .tabViewBottomAccessory {
            if let track = playback.currentTrack {
                HStack(spacing: 12) {
                    ArtworkView(url: track.artworkURL).frame(width: 38, height: 38).clipShape(.rect(cornerRadius: 8))
                    Button { showPlayer = true } label: {
                        VStack(alignment: .leading) {
                            Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    Button { playback.toggle() } label: { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill") }
                        .accessibilityLabel(localized("播放或暂停", "Play or pause"))
                    Button { playback.next() } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel(localized("下一首", "Next"))
                }.padding(.horizontal).padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $showPlayer) { PlayerView().presentationDragIndicator(.visible) }
    }
}
