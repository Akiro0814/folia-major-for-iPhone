import SwiftUI

// Folia/Features/NavidromeBrowseView.swift — server albums and artists behind the Omni boundary.
struct NavidromeBrowseView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var albums: [MusicCollection] = []
    @State private var artists: [NavidromeArtist] = []
    @State private var search = ""
    @State private var showingArtists = false
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        List {
            Picker(localized("浏览", "Browse"), selection: $showingArtists) {
                Text(localized("专辑", "Albums")).tag(false)
                Text(localized("歌手", "Artists")).tag(true)
            }.pickerStyle(.segmented)
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            if showingArtists {
                ForEach(artists.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { artist in
                    NavigationLink { ArtistAlbumsView(artist: artist) } label: {
                        LabeledContent(artist.name, value: "\(artist.albumCount)")
                    }
                }
            } else {
                ForEach(albums.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { album in
                    NavigationLink { CollectionView(collection: album) } label: { albumRow(album) }
                }
                if !albums.isEmpty && search.isEmpty {
                    Button(localized("加载更多专辑", "Load more albums")) { Task { await loadMore() } }.disabled(busy)
                }
            }
        }
        .navigationTitle(localized("专辑与歌手", "Albums & artists"))
        .searchable(text: $search, prompt: localized("筛选已加载内容", "Filter loaded content"))
        .task {
            busy = true
            do { albums = try await playback.service.browseAlbums(provider: .navidrome); artists = try await playback.service.browseArtists(provider: .navidrome) }
            catch { self.error = error.localizedDescription }; busy = false
        }
    }
    private func loadMore() async {
        busy = true; error = nil
        do {
            let next = try await playback.service.browseAlbums(provider: .navidrome, offset: albums.count)
            let existing = Set(albums.map(\.id)); albums += next.filter { !existing.contains($0.id) }
        } catch { self.error = error.localizedDescription }; busy = false
    }
}

struct ArtistAlbumsView: View {
    let artist: NavidromeArtist
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var albums: [MusicCollection] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(albums) { album in NavigationLink { CollectionView(collection: album) } label: { albumRow(album) } }
        }.navigationTitle(artist.name)
        .task {
            do { albums = try await playback.service.browseAlbums(provider: .navidrome, artistID: artist.id) }
            catch { self.error = error.localizedDescription }
        }
    }
}

private func albumRow(_ album: MusicCollection) -> some View {
    HStack {
        ArtworkView(url: album.artworkURL).frame(width: 48, height: 48).clipShape(.rect(cornerRadius: 8))
        VStack(alignment: .leading) { Text(album.title); Text("\(album.trackCount)").font(.caption).foregroundStyle(.secondary) }
    }
}
