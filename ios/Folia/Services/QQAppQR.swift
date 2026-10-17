import Foundation
// ios/Folia/Services/QQAppQR.swift

extension QQProvider {
    func cancelQR() {
        qrTask?.cancel(); qrTask = nil
        qrHeartbeat?.cancel(); qrHeartbeat = nil
        if let socket = qrSocket { Task { await socket.close() } }
        qrSocket = nil; qrKey = nil
    }
    func startAppQR() async throws -> QRLogin {
        cancelQR()
        generation += 1
        let captured = generation
        try await bootstrap()
        let result = try await call("music.login.LoginServer", "CreateQRCode", ["tmeAppID": "qqmusic", "ct": 11, "cv": 14090008], auth: false, overrides: ["ct": 23, "cv": 0])
        guard captured == generation, let key = result["qrcodeID"] as? String,
              let encoded = result["qrcode"] as? String,
              let bytes = Data(base64Encoded: String(encoded.split(separator: ",").last ?? "")),
              bytes.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
              let image = URL(string: "data:image/png;base64," + bytes.base64EncodedString()) else { throw MusicError.invalidResponse }
        let socket = QQSocket()
        // Unicast events are not replayed: establish SUBACK before displaying this QR.
        try await socket.open(key: key)
        guard captured == generation else { await socket.close(); throw MusicError.sessionChanged }
        qrSocket = socket; qrKey = key; qrStatus = .waiting; qrError = nil
        qrTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let event = try await socket.nextEvent()
                    guard let self else { break }
                    let finished = try await self.receiveQREvent(event.0, payload: event.1, key: key, generation: captured)
                    if finished { break }
                }
            } catch { await self?.failAppQR(error, key: key) }
            await socket.close()
        }
        qrHeartbeat = Task { [weak self] in
            do {
                for _ in 0..<6 {
                    try await Task.sleep(for: .seconds(30)); try Task.checkCancellation()
                    try await socket.ping()
                }
                await self?.expireAppQR(key: key)
            } catch { }
        }
        return QRLogin(key: key, url: image, imageURL: image, channel: .qq)
    }
    func pollAppQR(_ login: QRLogin) throws -> QRLoginStatus {
        guard login.key == qrKey else { return .expired }
        if let qrError { throw qrError }
        return qrStatus
    }
    private func receiveQREvent(_ type: String, payload: [String: Any], key: String, generation captured: Int) async throws -> Bool {
        guard captured == generation, qrKey == key else { throw MusicError.sessionChanged }
        switch type {
        case "waiting": qrStatus = .waiting
        case "scanned": qrStatus = .scanned
        case "cookies":
            let cookies = Self.dictionary(payload["cookies"])
            guard let id = Self.dictionary(cookies["qqmusic_uin"])["value"] as? String,
                  let token = Self.dictionary(cookies["qqmusic_key"])["value"] as? String,
                  let numericID = Int64(id) else { throw MusicError.invalidResponse }
            let credential: [String: Any]
            do {
                credential = try await call("music.login.LoginServer", "Login", ["musicid": numericID, "qrCodeID": key, "token": token], auth: false, overrides: ["tmeLoginType": 6])
            } catch {
                // The upstream package validates the direct MQTT credential when exchange fails.
                credential = ["musicid": id, "str_musicid": id, "musickey": token, "loginType": 6]
            }
            guard captured == generation, qrKey == key else { throw MusicError.sessionChanged }
            qrStatus = .authorized(try await establish(credential, type: 6))
            qrHeartbeat?.cancel()
            return true
        case "canceled", "timeout", "loginFailed": qrStatus = .expired; qrHeartbeat?.cancel(); return true
        default: break
        }
        return false
    }
    private func failAppQR(_ error: Error, key: String) {
        guard key == qrKey else { return }
        if error is CancellationError { return }
        qrError = error; qrStatus = .expired; qrHeartbeat?.cancel()
    }
    private func expireAppQR(key: String) {
        guard qrKey == key else { return }
        qrStatus = .expired; qrTask?.cancel()
        if let socket = qrSocket { Task { await socket.close() } }
    }
}
