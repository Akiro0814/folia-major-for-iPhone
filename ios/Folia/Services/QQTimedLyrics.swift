import Foundation
// ios/Folia/Services/QQTimedLyrics.swift

extension QQProvider {
    func wordTimedLyrics(for track: Track) async throws -> LyricsPayload {
        let detail = try await call("music.pf_song_detail_svr", "get_song_detail_yqq", ["song_type": 0, "song_mid": track.mediaID])
        let info = Self.dictionary(detail["track_info"])
        guard let id = info["id"] as? Int else { throw MusicError.invalidResponse }
        func base64(_ value: String) -> String { Data(value.utf8).base64EncodedString() }
        let result = try await call("music.musichallSong.PlayLyricInfo", "GetPlayLyricInfo", [
            "albumName": base64(track.album), "crypt": 1, "ct": 19, "cv": 2111, "interval": Int(track.duration),
            "lrc_t": 0, "qrc": 1, "qrc_t": 0, "roma": 1, "roma_t": 0, "singerName": base64(track.artist),
            "songID": id, "songName": base64(track.title), "trans": 1, "trans_t": 0, "type": 0])
        guard let lyric = result["lyric"] as? String, !lyric.isEmpty else { throw MusicError.unavailable("暂无逐字歌词") }
        let decoded = try TimedLyricsDecoder.qrc(lyric)
        func decodeOptional(_ field: String) throws -> String {
            guard let value = result[field] as? String, !value.isEmpty else { return "" }
            return try TimedLyricsDecoder.qrc(value)
        }
        let translation = try decodeOptional("trans")
        let romanization = try decodeOptional("roma")
        // QRC XML is parsed by the existing bundled Folia renderer, preserving its original word timing.
        return LyricsPayload(original: decoded, translation: translation, romanization: romanization, wordTimed: decoded)
    }
}

