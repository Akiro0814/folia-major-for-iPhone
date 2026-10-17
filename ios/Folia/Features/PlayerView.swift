import SwiftUI
import AVKit

// Folia/Features/PlayerView.swift — adaptive portrait/landscape native transport and lyric stage.
struct PlayerView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var seekPosition: Double = 0
    @State private var seeking = false
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            Group {
                if landscape {
                    HStack(spacing: 24) {
                        ScrollView { controls(compact: true) }.frame(width: max(240, geometry.size.width * 0.38))
                        lyricStage
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 28) {
                            controls()
                            lyricStage.frame(height: max(300, geometry.size.height * 0.48))
                        }
                    }
                }
            }.padding(24)
        }
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .top) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.down") }.accessibilityLabel(localized("收起播放器", "Close player"))
                Spacer()
                Text(localized("正在播放", "Now playing")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { showQueue = true } label: { Image(systemName: "list.bullet") }.accessibilityLabel(localized("播放队列", "Queue"))
            }.padding().glassEffect(.regular, in: .capsule).padding(.horizontal)
        }
        .sheet(isPresented: $showQueue) { QueueView() }
    }
    private var lyricStage: some View {
        VStack(spacing: 8) {
            if let lyricsError = playback.lyricsError { Text(lyricsError).font(.caption).foregroundStyle(.secondary).accessibilityLabel(localized("歌词请求失败", "Lyrics request failed") + ": " + lyricsError) }
            FoliaLyricsView(track: playback.currentTrack, lyrics: playback.lyrics, currentTime: playback.currentTime, isPlaying: playback.isPlaying, settings: settings.visual, onSeek: { playback.seek(to: $0) })
            .clipShape(.rect(cornerRadius: 24))
        }
    }
    private func controls(compact: Bool = false) -> some View {
        VStack(spacing: compact ? 12 : 20) {
            if let track = playback.currentTrack {
                if !compact {
                    ArtworkView(url: track.artworkURL).aspectRatio(1, contentMode: .fit).frame(maxWidth: 340, maxHeight: 340)
                        .clipShape(.rect(cornerRadius: 20))
                }
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(track.title).font(.title2.weight(.bold)).lineLimit(2)
                        Text(track.artist).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { settings.toggleFavorite(track) } label: {
                        Image(systemName: settings.favorites.contains(where: { $0.id == track.id }) ? "heart.fill" : "heart")
                    }.accessibilityLabel(localized("收藏", "Favorite"))
                }
            }
            if playback.isLoading { ProgressView() }
            if let error = playback.error { Text(error).font(.caption).foregroundStyle(.red) }
            VStack(spacing: 4) {
                Slider(value: Binding(get: { seeking ? seekPosition : playback.currentTime }, set: { seekPosition = $0 }), in: 0...max(playback.duration, 1)) { editing in
                    if editing { seekPosition = playback.currentTime; seeking = true }
                    else { playback.seek(to: seekPosition); seeking = false }
                }.accessibilityLabel(localized("播放进度", "Playback position"))
                HStack { Text(time(playback.currentTime)); Spacer(); Text(time(playback.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 32) {
                Button { playback.previous() } label: { Image(systemName: "backward.end.fill").font(.title) }.accessibilityLabel(localized("上一首", "Previous"))
                Button { playback.toggle() } label: { Image(systemName: playback.isPlaybackRequested ? "pause.fill" : "play.fill").font(.largeTitle).frame(width: 72, height: 72) }
                    .buttonStyle(.glass).accessibilityLabel(localized("播放或暂停", "Play or pause"))
                Button { playback.next() } label: { Image(systemName: "forward.end.fill").font(.title) }.accessibilityLabel(localized("下一首", "Next"))
            }
            HStack {
                Button { playback.shuffle.toggle() } label: { Image(systemName: "shuffle").foregroundStyle(playback.shuffle ? Color.accentColor : .secondary) }.accessibilityLabel(localized("随机播放", "Shuffle"))
                Spacer()
                Menu {
                    ForEach(RepeatMode.allCases, id: \.self) { mode in Button(mode.rawValue) { playback.repeatMode = mode } }
                } label: { Image(systemName: playback.repeatMode == .one ? "repeat.1" : "repeat").foregroundStyle(playback.repeatMode != .off ? Color.accentColor : .secondary) }
                .accessibilityLabel(localized("循环模式", "Repeat mode"))
                Spacer()
                Menu {
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in Button("\(minutes) min") { playback.setSleep(minutes: minutes) } }
                    Button(localized("取消定时", "Cancel timer")) { playback.setSleep(minutes: nil) }
                } label: { Image(systemName: playback.sleepDeadline == nil ? "moon" : "moon.fill") }.accessibilityLabel(localized("睡眠定时", "Sleep timer"))
                Spacer()
                AirPlayRoutePicker().frame(width: 30, height: 30)
            }.font(.title3).padding(.horizontal, 12)
        }
    }
    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = max(0, Int(seconds)); return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}

struct QueueView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(playback.tracks.enumerated()), id: \.offset) { index, track in
                    Button { playback.playQueueItem(at: index) } label: {
                        HStack { Text(track.title); Spacer(); if track.id == playback.currentTrack?.id { Image(systemName: "waveform") } }
                    }.swipeActions { Button(role: .destructive) { playback.removeFromQueue(at: index) } label: { Label(localized("移除", "Remove"), systemImage: "trash") } }
                }
            }.navigationTitle(localized("播放队列", "Queue"))
        }
    }
}





