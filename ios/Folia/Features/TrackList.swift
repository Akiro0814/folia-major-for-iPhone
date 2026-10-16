import SwiftUI

// Folia/Features/TrackList.swift — shared online song actions and artwork.
struct ArtworkView: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
            Rectangle().fill(.quaternary).overlay { Image(systemName: "music.note").font(.title).foregroundStyle(.secondary) }
        }.clipped().accessibilityHidden(true)
    }
}

struct TrackRows: View {
    let tracks: [Track]
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppSettings.self) private var settings
    @State private var actionError: String?
    var body: some View {
        ForEach(tracks) { track in
            Button { playback.play(track, in: tracks) } label: {
                HStack(spacing: 12) {
                    ArtworkView(url: track.artworkURL).frame(width: 46, height: 46).clipShape(.rect(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).foregroundStyle(.primary).lineLimit(1)
                        Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if playback.currentTrack?.id == track.id { Image(systemName: "waveform").foregroundStyle(.tint) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            .contextMenu {
                Button(localized("接下来播放", "Play next"), systemImage: "text.line.first.and.arrowtriangle.forward") { playback.enqueueNext(track) }
                Button(localized("设备收藏 / 取消收藏", "Toggle device favorite"), systemImage: "heart") { settings.toggleFavorite(track) }
                Button(localized("喜欢（同步到平台）", "Like on provider"), systemImage: "heart.circle") {
                    Task { do { try await playback.service.setLiked(true, track: track) } catch { actionError = error.localizedDescription } }
                }
                if let url = track.artworkURL { ShareLink(item: url) { Label(localized("分享封面", "Share artwork"), systemImage: "square.and.arrow.up") } }
            }
        }
        .alert(localized("平台操作失败", "Provider action failed"), isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button(localized("好", "OK")) { actionError = nil }
        } message: { Text(actionError ?? "") }
    }
}

struct SearchView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var query = ""
    @State private var tracks: [Track] = []
    @State private var error: String?
    @State private var loading = false
    @State private var submitted = ""

    var body: some View {
        @Bindable var settings = settings
        List {
            Picker(localized("音乐平台", "Provider"), selection: $settings.preferredProvider) {
                ForEach(MusicProvider.allCases) { Text($0.displayName).tag($0) }
            }
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            TrackRows(tracks: tracks)
            if tracks.isEmpty && !loading && error == nil {
                ContentUnavailableView(localized("找到下一首心动", "Find your next favorite"), systemImage: "magnifyingglass", description: Text(localized("搜索在线歌曲、歌手或专辑。", "Search online songs, artists or albums.")))
            }
        }
        .navigationTitle(localized("搜索", "Search"))
        .searchable(text: $query, prompt: localized("歌曲、歌手、专辑", "Songs, artists, albums"))
        .onSubmit(of: .search) { submitted = query }
        .task(id: "\(submitted)|\(settings.preferredProvider.rawValue)") {
            guard !submitted.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            loading = true; error = nil; tracks = []
            do {
                let result = try await playback.service.search(submitted, provider: settings.preferredProvider)
                try Task.checkCancellation(); tracks = result
            } catch is CancellationError { } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
    }
}

struct LibraryView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var collections: [MusicCollection] = []
    @State private var error: String?
    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                Picker(localized("音乐平台", "Provider"), selection: $settings.preferredProvider) {
                    ForEach(MusicProvider.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section(localized("设备收藏", "Device favorites")) {
                if settings.favorites.isEmpty { Text(localized("长按歌曲即可收藏", "Touch and hold a song to favorite it")).foregroundStyle(.secondary) }
                TrackRows(tracks: settings.favorites)
            }
            Section(localized("账户歌单", "Account playlists")) {
                if let error { Text(error).font(.callout).foregroundStyle(.secondary) }
                ForEach(collections) { collection in
                    NavigationLink { CollectionView(collection: collection) } label: {
                        HStack {
                            ArtworkView(url: collection.artworkURL).frame(width: 48, height: 48).clipShape(.rect(cornerRadius: 8))
                            Text(collection.title)
                        }
                    }
                }
            }
        }
        .navigationTitle("Folia")
        .toolbar { NavigationLink { AccountsView() } label: { Image(systemName: "person.crop.circle") } }
        .task(id: settings.preferredProvider) { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        error = nil; collections = []
        do { let result = try await playback.service.playlists(provider: settings.preferredProvider); try Task.checkCancellation(); collections = result }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct CollectionView: View {
    let collection: MusicCollection
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var tracks: [Track] = []
    @State private var error: String?
    var body: some View {
        List { if let error { Text(error).foregroundStyle(.red) }; TrackRows(tracks: tracks) }
            .navigationTitle(collection.title)
            .task {
                do { tracks = try await playback.service.tracks(in: collection) }
                catch { self.error = error.localizedDescription }
            }
    }
}

