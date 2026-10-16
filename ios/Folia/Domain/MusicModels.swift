import Foundation
// ios/Folia/Domain/MusicModels.swift

enum MusicProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case netease, kugou, qq
    var id: String { rawValue }
    var title: String { switch self { case .netease: "网易云音乐"; case .kugou: "酷狗音乐"; case .qq: "QQ 音乐" } }
}
enum AudioQuality: String, Codable, CaseIterable, Sendable { case standard, high, lossless }
enum LoginMethod: String, CaseIterable, Sendable { case sms, password, qr }
struct Track: Identifiable, Codable, Hashable, Sendable {
    var mediaID: String
    var provider: MusicProvider
    var title: String
    var artist: String
    var album: String = ""
    var artworkURL: URL?
    var duration: Double = 0
    var id: String { "\(provider.rawValue):\(mediaID)" }
}
struct MusicCollection: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var provider: MusicProvider
    var title: String
    var artworkURL: URL?
    var trackCount: Int = 0
}
struct MusicAccount: Codable, Sendable {
    var id: String
    var provider: MusicProvider
    var nickname: String
    var avatarURL: URL?
}
struct AudioSource: Sendable { var url: URL; var headers: [String: String] = [:]; var expiresAt: Date? }
struct LyricsPayload: Codable, Sendable {
    var original: String = ""
    var translation: String = ""
    var romanization: String = ""
    var wordTimed: String = ""
}
struct QRLogin: Sendable { var key: String; var url: URL }
enum QRLoginStatus: Sendable { case waiting, scanned, expired, authorized(MusicAccount) }
enum MusicError: LocalizedError, Sendable {
    case unsupported(String), authenticationRequired, unavailable(String), invalidResponse, server(Int, String), sessionChanged
    var errorDescription: String? {
        switch self {
        case .unsupported(let message), .unavailable(let message): message
        case .authenticationRequired: "请先登录此音乐平台。"
        case .invalidResponse: "音乐平台返回了无法识别的数据。"
        case .server(let code, let message): "\(message)（\(code)）"
        case .sessionChanged: "账户已切换，请重试。"
        }
    }
}
