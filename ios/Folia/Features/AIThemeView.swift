import SwiftUI

// Folia/Features/AIThemeView.swift — explicit user-triggered palette generation without bundled credentials.
struct AIThemeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var configuration = AIThemeConfiguration()
    @State private var message: String?
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    private let service = AIThemeService()
    var body: some View {
        Form {
            Section(localized("兼容的 AI 服务", "Compatible AI service")) {
                TextField("https://api.example.com/v1", text: $configuration.server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField(localized("模型名称", "Model name"), text: $configuration.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("API Key", text: $configuration.apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(localized("保存到钥匙串", "Save to Keychain")) {
                    do { try AIThemeService.save(configuration); message = localized("AI 配置已安全保存", "AI configuration saved securely") }
                    catch { message = error.localizedDescription }
                }
                Button(localized("删除 AI 凭证", "Delete AI credentials"), role: .destructive) {
                    do { try AIThemeService.save(nil); configuration = AIThemeConfiguration(); message = localized("凭证已移除", "Credentials removed") }
                    catch { message = error.localizedDescription }
                }
            }
            Section(localized("为当前歌曲生成配色", "Create a palette for the current song")) {
                if let track = playback.currentTrack { Text("\(track.title) · \(track.artist)") }
                else { Text(localized("先选择一首在线歌曲", "Choose an online song first")).foregroundStyle(.secondary) }
                Button(localized("发送歌曲信息并生成", "Send song context and generate"), systemImage: "sparkles") { generate() }
                    .disabled(busy || playback.currentTrack == nil || configuration.apiKey.isEmpty || configuration.model.isEmpty)
                if busy { ProgressView() }
                if let colors = settings.visual.themeColors {
                    HStack {
                        ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                            Circle().fill(paletteColor(color)).frame(width: 40, height: 40).overlay(Circle().stroke(.gray.opacity(0.3)))
                                .accessibilityLabel(color)
                        }
                    }
                    Button(localized("使用默认配色", "Use default palette")) { settings.visual.themeColors = nil }
                }
                if let message { Text(message).font(.callout) }
            }
            Section {
                Text(localized("仅在点击生成时，将当前歌曲标题、歌手和最多 3000 字歌词发送给你配置的 HTTPS 服务。可能产生服务商费用。密钥仅保存在此设备的钥匙串，不包含在视觉配置导出中。", "Only when you tap Generate, the song title, artist and up to 3,000 lyric characters are sent to your configured HTTPS service. Provider charges may apply. The API key stays in this device’s Keychain and is excluded from visual exports.")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(localized("AI 配色", "AI palette"))
        .task {
            do { configuration = try AIThemeService.configuration() ?? AIThemeConfiguration() }
            catch { message = error.localizedDescription }
        }
        .onDisappear { task?.cancel(); configuration.apiKey = "" }
    }
    private func generate() {
        guard let track = playback.currentTrack else { return }
        busy = true; message = nil
        let snapshot = configuration; let lyrics = playback.lyrics?.original ?? ""
        task?.cancel()
        task = Task {
            defer { busy = false }
            do {
                let colors = try await service.generate(configuration: snapshot, track: track, lyrics: lyrics)
                try Task.checkCancellation()
                guard playback.currentTrack?.id == track.id else { message = localized("歌曲已切换，请重新生成", "Song changed. Generate again."); return }
                settings.visual.themeColors = colors
                message = localized("已应用，配色会随视觉配置一起导出", "Applied. The palette is included in visual exports.")
            } catch is CancellationError { } catch { message = error.localizedDescription }
        }
    }
    private func paletteColor(_ hex: String) -> Color {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
