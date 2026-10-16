import SwiftUI
import UniformTypeIdentifiers

// Folia/Features/AppSettings.swift — persisted appearance and portable visual configuration.
struct VisualSettings: Codable, Equatable {
    var renderer = "classic"
    var background = "common"
    var showTranslation = true
    var showRomanization = false
    var lyricOffset: Double = 0
    var fontSize: Double = 36
    var themeColors: [String]? = nil
}

@MainActor @Observable final class AppSettings {
    var visual: VisualSettings { didSet { save() } }
    var preferredProvider: MusicProvider { didSet { save() } }
    var favorites: [Track] { didSet { save() } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        visual = defaults.data(forKey: "folia.visual").flatMap { try? JSONDecoder().decode(VisualSettings.self, from: $0) } ?? VisualSettings()
        preferredProvider = MusicProvider(rawValue: defaults.string(forKey: "folia.provider") ?? "") ?? .netease
        favorites = defaults.data(forKey: "folia.favorites").flatMap { try? JSONDecoder().decode([Track].self, from: $0) } ?? []
    }

    func toggleFavorite(_ track: Track) {
        if favorites.contains(where: { $0.id == track.id }) { favorites.removeAll { $0.id == track.id } }
        else { favorites.append(track) }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(visual), forKey: "folia.visual")
        defaults.set(preferredProvider.rawValue, forKey: "folia.provider")
        defaults.set(try? JSONEncoder().encode(favorites), forKey: "folia.favorites")
    }
}

struct VisualSettingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var settings: VisualSettings
    init(settings: VisualSettings) { self.settings = settings }
    init(configuration: ReadConfiguration) throws {
        settings = try JSONDecoder().decode(VisualSettings.self, from: configuration.file.regularFileContents ?? Data())
        guard settings.fontSize.isFinite, (14...96).contains(settings.fontSize), settings.lyricOffset.isFinite else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try JSONEncoder().encode(settings))
    }
}

extension MusicProvider {
    var displayName: String {
        switch self { case .netease: "网易云音乐"; case .kugou: "酷狗音乐"; case .qq: "QQ 音乐"; case .navidrome: "Navidrome" }
    }
}

func localized(_ chinese: String, _ english: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese : english
}

