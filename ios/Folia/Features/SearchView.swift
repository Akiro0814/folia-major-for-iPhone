import SwiftUI

// Folia/Features/SearchView.swift — native provider song, artist, and album discovery through Omni.
private enum SearchScope: String, CaseIterable {
    case songs, albums, artists
    var title: String {
        switch self { case .songs: localized("歌曲", "Songs"); case .albums: localized("专辑", "Albums"); case .artists: localized("歌手", "Artists") }
    }
}

struct SearchView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var query = ""
    @State private var tracks: [Track] = []
    @State private var catalog: [MusicCollection] = []
    @State private var scope: SearchScope = .songs
    @State private var error: String?
    @State private var loading = false
    @State private var submitted = ""
    var body: some View {
        @Bindable var settings = settings
        List {
            Picker(localized("音乐平台", "Provider"), selection: $settings.preferredProvider) {
                ForEach(MusicProvider.allCases) { Text($0.displayName).tag($0) }
            }
            Picker(localized("搜索类型", "Search type"), selection: $scope) {
                ForEach(SearchScope.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            if scope == .songs { TrackRows(tracks: tracks) }
            else {
                ForEach(catalog) { item in
                    NavigationLink { CollectionView(collection: item) } label: {
                        HStack(spacing: 12) {
                            ArtworkView(url: item.artworkURL).frame(width: 48, height: 48).clipShape(.rect(cornerRadius: 8))
                            Text(item.title)
                        }
                    }
                }
            }
            if tracks.isEmpty && catalog.isEmpty && !loading && error == nil {
                ContentUnavailableView(localized("找到下一首心动", "Find your next favorite"), systemImage: "magnifyingglass", description: Text(localized("搜索在线歌曲、歌手或专辑。", "Search online songs, artists or albums.")))
            }
        }
        .navigationTitle(localized("搜索", "Search"))
        .searchable(text: $query, prompt: localized("歌曲、歌手、专辑", "Songs, artists, albums"))
        .onSubmit(of: .search) { submitted = query }
        .task(id: "\(submitted)|\(settings.preferredProvider.rawValue)|\(scope.rawValue)") {
            guard !submitted.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            loading = true; error = nil; tracks = []; catalog = []
            do {
                if scope == .songs {
                    let result = try await playback.service.search(submitted, provider: settings.preferredProvider)
                    try Task.checkCancellation(); tracks = result
                } else {
                    let result = try await playback.service.searchCatalog(submitted, provider: settings.preferredProvider, kind: scope == .albums ? .album : .artist)
                    try Task.checkCancellation(); catalog = result
                }
            } catch is CancellationError { } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
    }
}
