import SwiftUI
// ios/Folia/Features/FoliaSyncView.swift

struct FoliaSyncView: View {
    @Environment(AppSettings.self) private var settings
    @AppStorage("folia.sync.server") private var server = ""
    @State private var token = FoliaSyncCredentials().read()
    @State private var busy = false
    @State private var message: String?
    private let service = FoliaSyncService()

    var body: some View {
        Form {
            Section(localized("自托管 Folia 同步服务器", "Self-hosted Folia sync server")) {
                TextField("https://sync.example.com", text: $server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("SYNC_TOKEN", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text(localized("使用原项目 sync-server 地址与令牌。令牌保存在钥匙串。公网服务器请使用 HTTPS。", "Use your existing Folia sync-server URL and token. The token stays in Keychain. Use HTTPS for public servers.")).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button(localized("下载服务器外观设置", "Download server appearance")) { synchronize(upload: false) }.disabled(busy)
                Button(localized("上传当前外观设置", "Upload current appearance")) { synchronize(upload: true) }.disabled(busy)
                if busy { ProgressView() }
                if let message { Text(message).font(.callout).accessibilityIdentifier("sync.result") }
            }
            Section {
                Text(localized("手动同步歌词模式、背景、字幕与字号。上传会先读取远端配置，保留桌面专属参数；其他设备同时写入仍遵循服务器最后写入时间。主题库、自动同步与歌词偏移尚未接入。", "Manual sync includes renderer, background, subtitles and font size. Upload preserves desktop-only fields and uses the server's last-write-wins behavior. Theme libraries, automatic sync and lyric offset are not included.")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(localized("外观同步", "Appearance sync"))
    }
    private func synchronize(upload: Bool) {
        busy = true; message = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                if upload {
                    try await service.upload(settings.visual, server: server, token: token)
                    message = localized("外观设置已上传", "Appearance uploaded")
                } else if let visual = try await service.download(server: server, token: token, existing: settings.visual) {
                    guard VisualMode.bundled.contains(where: { $0.mode == visual.renderer }) else { throw MusicError.unavailable("服务器歌词模式不在当前版本中。") }
                    settings.visual = visual
                    message = localized("外观设置已下载", "Appearance downloaded")
                } else { message = localized("服务器暂无外观设置", "The server has no appearance settings") }
                try FoliaSyncCredentials().save(token)
            } catch { message = error.localizedDescription }
        }
    }
}
