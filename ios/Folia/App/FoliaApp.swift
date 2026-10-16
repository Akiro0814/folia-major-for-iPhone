import SwiftUI

// Folia/App/FoliaApp.swift — application lifetime owns one audio coordinator.
@main struct FoliaApp: App {
    @State private var settings = AppSettings()
    @State private var playback = PlaybackCoordinator(service: OmniService())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(playback)
                .tint(Color(red: 0.25, green: 0.47, blue: 0.37))
        }
    }
}
