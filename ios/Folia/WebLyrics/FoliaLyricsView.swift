import SwiftUI
import WebKit

// ios/Folia/WebLyrics/FoliaLyricsView.swift
struct FoliaLyricsView: View {
    var track: Track?
    var lyrics: LyricsPayload?
    var currentTime: Double
    var isPlaying: Bool
    var settings: VisualSettings
    var onSeek: ((Double) -> Void)? = nil
    var onReadiness: ((Bool) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var failure: String?

    var body: some View {
        ZStack {
            LyricsWebSurface(track: track, lyrics: lyrics, currentTime: currentTime, isPlaying: isPlaying,
                settings: settings, daylight: colorScheme == .light, reduceMotion: reduceMotion,
                visible: scenePhase == .active, onSeek: onSeek, onReadiness: onReadiness, failure: $failure)
                .accessibilityHidden(true)
            if failure != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(localized("歌词画面暂不可用", "Lyrics renderer unavailable")).font(.caption).foregroundStyle(.secondary)
                        Text(lyrics?.original.isEmpty == false ? lyrics!.original : localized("暂无歌词", "No lyrics"))
                            .font(.title3).textSelection(.enabled)
                    }.padding()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lyrics?.original ?? localized("暂无歌词", "No lyrics"))
    }
}

private struct LyricsWebSurface: UIViewRepresentable {
    var track: Track?
    var lyrics: LyricsPayload?
    var currentTime: Double
    var isPlaying: Bool
    var settings: VisualSettings
    var daylight: Bool
    var reduceMotion: Bool
    var visible: Bool
    var onSeek: ((Double) -> Void)?
    var onReadiness: ((Bool) -> Void)?
    @Binding var failure: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "folia")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false; view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        context.coordinator.webView = view
        guard let folder = Bundle.main.url(forResource: "Lyrics", withExtension: nil),
              FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path) else {
            DispatchQueue.main.async { failure = "Missing bundled lyrics" }; return view
        }
        view.loadFileURL(folder.appendingPathComponent("index.html"), allowingReadAccessTo: folder)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sendSnapshot()
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "folia")
        view.stopLoading(); view.navigationDelegate = nil
        coordinator.webView = nil
    }

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: LyricsWebSurface
        weak var webView: WKWebView?
        var ready = false
        var generation = 0
        var sequence = 0
        var trackKey: String?
        init(_ parent: LyricsWebSurface) { self.parent = parent }

        // Pass structured arguments, never interpolate untrusted lyric text into JavaScript source.
        func sendSnapshot() {
            guard ready, let webView else { return }
            let key = parent.track?.id ?? ""
            if trackKey != key { generation += 1; trackKey = key }
            sequence += 1
            let lyricData = (try? JSONEncoder().encode(parent.lyrics ?? LyricsPayload())) ?? Data("{}".utf8)
            let settingsData = (try? JSONEncoder().encode(parent.settings)) ?? Data("{}".utf8)
            let payload: [String: Any] = [
                "version": 1, "generation": generation, "sequence": sequence, "trackKey": key,
                "time": parent.currentTime.isFinite ? max(0, parent.currentTime) : 0,
                "duration": max(0, parent.track?.duration ?? 0), "playing": parent.isPlaying,
                "visible": parent.visible, "title": parent.track?.title ?? "",
                "artist": parent.track?.artist ?? "", "album": parent.track?.album ?? "",
                "coverUrl": parent.track?.artworkURL?.absoluteString ?? "",
                "lyrics": (try? JSONSerialization.jsonObject(with: lyricData)) ?? [:],
                "settings": (try? JSONSerialization.jsonObject(with: settingsData)) ?? [:],
                "daylight": parent.daylight, "reduceMotion": parent.reduceMotion,
            ]
            Task { [weak self, weak webView] in
                do {
                    _ = try await webView?.callAsyncJavaScript("window.foliaReceive(payload)", arguments: ["payload": payload],
                        in: nil, contentWorld: .page)
                } catch {
                    self?.parent.failure = "Lyrics bridge failed"
                    self?.parent.onReadiness?(false)
                }
            }
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready": ready = true; parent.failure = nil; sendSnapshot()
            case "rendered": parent.onReadiness?(true)
            case "error": parent.failure = body["message"] as? String ?? "Lyrics unavailable"; parent.onReadiness?(false)
            case "seek":
                if let time = body["time"] as? Double, time.isFinite, time >= 0 { parent.onSeek?(time) }
            default: break
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.failure = error.localizedDescription; parent.onReadiness?(false) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.failure = error.localizedDescription; parent.onReadiness?(false) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ready = false; parent.failure = "Lyrics renderer restarted"; parent.onReadiness?(false); webView.reload()
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }
    }
}
