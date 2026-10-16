import SwiftUI
import UniformTypeIdentifiers

// Folia/Features/SettingsView.swift — native visual preferences and JSON interchange.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var exporting = false
    @State private var importing = false
    @State private var message: String?
    private let renderers = VisualMode.bundled
    var body: some View {
        @Bindable var settings = settings
        @Bindable var playback = playback
        Form {
            Section(localized("音乐", "Music")) {
                NavigationLink(localized("账户与音乐服务", "Accounts & services")) { AccountsView() }
                NavigationLink(localized("跨设备同步", "Cross-device sync")) { FoliaSyncView() }
                Picker(localized("音质", "Audio quality"), selection: $playback.quality) {
                    ForEach(AudioQuality.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Text(localized("音质取决于平台账号权益与歌曲版权。设备收藏只保存歌曲引用，不下载音频。", "Quality depends on your provider subscription and track availability. Favorites store references only.")).font(.footnote).foregroundStyle(.secondary)
            }
            Section(localized("歌词与外观", "Lyrics & appearance")) {
                NavigationLink(localized("AI 配色", "AI palette")) { AIThemeView() }
                Picker(localized("歌词动画", "Lyric renderer"), selection: $settings.visual.renderer) {
                    ForEach(renderers) { Text($0.label).tag($0.mode) }
                }
                Picker(localized("背景", "Background"), selection: $settings.visual.background) {
                    ForEach(["common", "latent", "monet", "nomand", "sora"], id: \.self) { Text($0.capitalized).tag($0) }
                }
                Toggle(localized("显示翻译", "Show translation"), isOn: $settings.visual.showTranslation)
                Toggle(localized("显示音译", "Show romanization"), isOn: $settings.visual.showRomanization)
                VStack(alignment: .leading) {
                    Text(localized("歌词字号", "Lyric font size") + " \(Int(settings.visual.fontSize))")
                    Slider(value: $settings.visual.fontSize, in: 14...72, step: 1)
                }
                VStack(alignment: .leading) {
                    Text(localized("歌词偏移", "Lyric offset") + String(format: " %+.1f s", settings.visual.lyricOffset))
                    Slider(value: $settings.visual.lyricOffset, in: -10...10, step: 0.1)
                }
            }
            Section(localized("配置", "Configuration")) {
                Button(localized("导出视觉配置", "Export visual configuration"), systemImage: "square.and.arrow.up") { exporting = true }
                Button(localized("导入视觉配置", "Import visual configuration"), systemImage: "square.and.arrow.down") { importing = true }
                Button(localized("恢复默认外观", "Reset appearance"), role: .destructive) { settings.visual = VisualSettings() }
                if let message { Text(message).font(.caption) }
            }
            Section(localized("关于", "About")) {
                LabeledContent("Folia", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                Link(localized("原项目与许可证", "Original project & license"), destination: URL(string: "https://github.com/chthollyphile/folia-major")!)
                Link(localized("iPhone 项目", "iPhone project"), destination: URL(string: "https://github.com/L1angK1NG/folia-major-for-iPhone")!)
                Text(localized("支持 iOS 26 及以上。后台音频、AirPlay 与系统锁屏由原生播放器提供。", "Requires iOS 26 or later. Native audio provides background playback, AirPlay and Lock Screen controls.")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(localized("设置", "Settings"))
        .fileExporter(isPresented: $exporting, document: VisualSettingsDocument(settings: settings.visual), contentType: .json, defaultFilename: "Folia-visual-settings") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                guard data.count < 1_000_000 else { throw CocoaError(.fileReadTooLarge) }
                let imported = try JSONDecoder().decode(VisualSettings.self, from: data)
                guard renderers.contains(where: { $0.mode == imported.renderer }), imported.fontSize.isFinite, (14...96).contains(imported.fontSize), imported.lyricOffset.isFinite else { throw CocoaError(.fileReadCorruptFile) }
                if let colors = imported.themeColors { _ = try AIThemeService.validate(colors) }
                settings.visual = imported; message = localized("视觉配置已导入", "Visual settings imported")
            } catch { message = error.localizedDescription }
        }
    }
}


