import SwiftUI
// ios/Folia/WebLyrics/LyricsValidationView.swift

/// Offline integration surface used only by the explicit UI-test launch argument.
struct LyricsValidationView: View {
    @State private var ready = false
    @State private var failed = false
    private let track = Track(mediaID: "offline-lyrics-validation", provider: .netease,
                              title: "Folia lyric rendering", artist: "Offline validation", duration: 30)
    private let lyrics = LyricsPayload(original: "[00:00.00]Folia\n[00:02.00]Music becomes words\n[00:06.00]流动的文字与旋律\n[00:12.00]A native iPhone experience",
                                       translation: "[00:02.00]音乐化为文字\n[00:12.00]原生 iPhone 体验")

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            VStack(spacing: 0) {
                HStack {
                    Text("Folia · bundled lyrics").font(.caption.weight(.semibold))
                    Spacer()
                    Text(landscape ? "Landscape" : "Portrait")
                        .accessibilityIdentifier(landscape ? "lyrics.validation.landscape" : "lyrics.validation.portrait")
                    if failed {
                        Text("Lyrics failed").foregroundStyle(.red).accessibilityIdentifier("lyrics.validation.error")
                    } else if ready {
                        Text("Lyrics ready").foregroundStyle(.green).accessibilityIdentifier("lyrics.validation.ready")
                    } else {
                        ProgressView().accessibilityIdentifier("lyrics.validation.loading")
                    }
                }.font(.caption).padding()
                FoliaLyricsView(track: track, lyrics: lyrics, currentTime: 3, isPlaying: false,
                                settings: VisualSettings(), onReadiness: { value in
                    if value { ready = true; failed = false }
                    else { ready = false; failed = true }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemBackground))
        }
    }
}
