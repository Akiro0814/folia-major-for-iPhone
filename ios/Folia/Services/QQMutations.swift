import Foundation
// ios/Folia/Services/QQMutations.swift

extension QQProvider {
    func recommendations() async throws -> [Track] {
        let result = try await call("music.srfDissInfo.aiDissInfo", "uniform_get_Dissinfo", ["dirid": 202, "optype": 3, "tag": 1, "userinfo": 0, "pic_dpi": 300])
        return (result["songlist"] as? [[String: Any]] ?? []).compactMap(Self.normalize)
    }
    func setLiked(_ liked: Bool, track: Track) async throws {
        let detail = try await call("music.pf_song_detail_svr", "get_song_detail_yqq", ["song_type": 0, "song_mid": track.mediaID])
        let info = Self.dictionary(detail["track_info"])
        guard let id = info["id"] as? Int, info["mid"] as? String == track.mediaID else { throw MusicError.invalidResponse }
        let status = try await call("music.musicasset.SongFavRead", "IsSongFanByMid", ["v_songMid": [track.mediaID]])
        if (status["m_fan"] as? [String: Bool])?[track.mediaID] == liked { return }
        let result = try await call("music.musicasset.PlaylistDetailWrite", liked ? "AddSonglist" : "DelSonglist", ["dirId": 201, "v_songInfo": [["songId": id, "songType": 0]]])
        guard result["retCode"] as? Int == 0 else { throw MusicError.invalidResponse }
        let verified = try await call("music.musicasset.SongFavRead", "IsSongFanByMid", ["v_songMid": [track.mediaID]])
        guard (verified["m_fan"] as? [String: Bool])?[track.mediaID] == liked else { throw MusicError.unavailable("QQ 音乐未确认收藏变更，请刷新后重试。") }
    }
    func changePlaylist(_ collection: MusicCollection, track: Track, add: Bool) async throws {
        guard collection.provider == .qq, track.provider == .qq, let user = session.account else { throw MusicError.authenticationRequired }
        let created = try await call("music.musicasset.PlaylistBaseRead", "GetPlaylistByUin", ["uin": user.id])
        guard let playlist = (created["v_playlist"] as? [[String: Any]])?.first(where: { Self.collectionID($0) == collection.id }),
              let dir = playlist["dirId"] as? Int, (1..<200).contains(dir),
              playlist["dirType"] == nil || playlist["dirType"] as? Int == 0 else { throw MusicError.unsupported("只能编辑自己创建的普通歌单。") }
        let detail = try await call("music.pf_song_detail_svr", "get_song_detail_yqq", ["song_type": 0, "song_mid": track.mediaID])
        let info = Self.dictionary(detail["track_info"])
        guard let id = info["id"] as? Int, info["mid"] as? String == track.mediaID else { throw MusicError.invalidResponse }
        let result = try await call("music.musicasset.PlaylistDetailWrite", add ? "AddSonglist" : "DelSonglist", ["dirId": dir, "v_songInfo": [["songId": id, "songType": 0]]])
        guard result["retCode"] as? Int == 0 else { throw MusicError.invalidResponse }
    }
}
