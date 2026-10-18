import SwiftUI

// Folia/Features/BackupView.swift — user-selected JSON export/import with validation before any state changes.
struct BackupView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var exporting = false
    @State private var importing = false
    @State private var snapshot = FoliaBackup()
    @State private var message: String?
    var body: some View {
        Form {
            Section(localized("完整应用备份", "App backup")) {
                Button(localized("导出备份 JSON", "Export backup JSON"), systemImage: "square.and.arrow.up") {
                    snapshot = FoliaBackup(visual: settings.visual, palettes: settings.palettes,
                        favorites: settings.favorites.map(FoliaBackup.reference), playback: playback.queueSnapshot(), preferredProvider: settings.preferredProvider)
                    exporting = true
                }
                Button(localized("导入备份 JSON", "Import backup JSON"), systemImage: "square.and.arrow.down") { importing = true }
                if let message { Text(message).font(.callout) }
            }
            Section {
                Text(localized("备份包含视觉配置、主题库、设备收藏和在线歌曲队列引用。导入会替换这些数据，恢复后保持暂停。备份不含音频、密码、平台登录凭证或 AI 密钥；需要时请在设备重新登录。", "Backups include visual settings, saved palettes, device favorites and online queue references. Import replaces these data and restores playback paused. Audio, passwords, provider sessions and AI keys are excluded; sign in again on the device when needed.")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(localized("应用备份", "App backup"))
        .fileExporter(isPresented: $exporting, document: FoliaBackupDocument(backup: snapshot), contentType: .json, defaultFilename: "Folia-app-backup") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 8_000_000 else { throw CocoaError(.fileReadTooLarge) }
                let data = try Data(contentsOf: url)
                guard data.count <= 8_000_000 else { throw CocoaError(.fileReadTooLarge) }
                let backup = try JSONDecoder().decode(FoliaBackup.self, from: data).validated()
                try playback.restoreQueue(backup.playback)
                settings.visual = backup.visual; settings.palettes = backup.palettes
                settings.favorites = backup.favorites; settings.preferredProvider = backup.preferredProvider
                message = localized("备份已恢复，播放保持暂停", "Backup restored with playback paused")
            } catch { message = error.localizedDescription }
        }
    }
}
