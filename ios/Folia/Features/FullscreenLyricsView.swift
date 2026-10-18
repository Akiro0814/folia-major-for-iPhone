import SwiftUI

// Folia/Features/FullscreenLyricsView.swift — original lyric stage in a native rotating full-screen presentation.
struct FullscreenLyricsView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var chromeVisible = true
    var body: some View {
        FoliaLyricsView(track: playback.currentTrack, lyrics: playback.lyrics, currentTime: playback.currentTime,
            isPlaying: playback.isPlaying, settings: settings.visual, audioPower: playback.audioPower, audioBands: playback.audioBands, onSeek: { playback.seek(to: $0) })
            .background(Color(.systemBackground))
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .top) {
                if chromeVisible {
                    HStack(spacing: 20) {
                        Button { dismiss() } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                            .accessibilityLabel(localized("退出全屏歌词", "Exit fullscreen lyrics"))
                        VStack(alignment: .leading) {
                            Text(playback.currentTrack?.title ?? "Folia").font(.subheadline.weight(.semibold)).lineLimit(1)
                            if let error = playback.lyricsError { Text(error).font(.caption).lineLimit(2).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button { playback.toggle() } label: { Image(systemName: playback.isPlaybackRequested ? "pause.fill" : "play.fill") }
                            .accessibilityLabel(localized("播放或暂停", "Play or pause"))
                        Button { chromeVisible = false } label: { Image(systemName: "eye.slash") }
                            .accessibilityLabel(localized("隐藏控制栏", "Hide controls"))
                    }.padding().glassEffect(.regular, in: .capsule).padding(.horizontal)
                }
            }
            .overlay(alignment: .topTrailing) {
                if !chromeVisible {
                    Button { chromeVisible = true } label: { Image(systemName: "eye").padding(12) }
                        .buttonStyle(.glass).padding().accessibilityLabel(localized("显示控制栏", "Show controls"))
                }
            }
            .statusBarHidden()
    }
}

