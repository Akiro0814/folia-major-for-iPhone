import SwiftUI

// Folia/App/FoliaApp.swift — application lifetime owns one audio coordinator.
@main struct FoliaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = AppSettings()
    @State private var playback = PlaybackCoordinator(service: OmniService())

    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--lyrics-validation") { LyricsValidationView() }
                else { RootView() }
            }
                .onChange(of: scenePhase) { _, phase in if phase != .active { playback.savePlaybackState() } }
                .environment(settings)
                .environment(playback)
                .tint(Color(red: 0.25, green: 0.47, blue: 0.37))
        }
    }
}


