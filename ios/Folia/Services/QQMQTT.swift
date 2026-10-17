import Foundation
// ios/Folia/Services/QQMQTT.swift

enum QQMQTT {
    static func variable(_ input: Int) -> Data {
        var value = input, result = Data()
        repeat {
            var byte = UInt8(value % 128); value /= 128
            if value > 0 { byte |= 0x80 }
            result.append(byte)
        } while value > 0
        return result
    }
    static func utf8(_ text: String) -> Data {
        let bytes = Data(text.utf8), length = UInt16(bytes.count)
        return Data([UInt8(length >> 8), UInt8(length & 255)]) + bytes
    }
    static func properties(_ auth: String? = nil, _ fields: [(String, String)]) -> Data {
        var content = Data()
        if let auth { content += Data([0x15]) + utf8(auth) }
        for (name, value) in fields { content += Data([0x26]) + utf8(name) + utf8(value) }
        return variable(content.count) + content
    }
    static func wrap(_ header: UInt8, _ data: Data) -> Data { Data([header]) + variable(data.count) + data }
    static func connect(_ key: String) -> Data {
        wrap(0x10, utf8("MQTT") + Data([5, 2, 0, 45]) + properties("pass", [("tmeAppID", "qqmusic"),
            ("business", "management"), ("hashTag", key), ("clientTag", "management.user"), ("userID", key)]) + utf8(UUID().uuidString))
    }
    static func subscribe(_ key: String) -> Data {
        wrap(0x82, Data([0, 1]) + properties(nil, [("authorization", "tmelogin"), ("pubsub", "unicast")]) + utf8("management.qrcode_login/\(key)") + Data([0]))
    }
    struct Cursor {
        let bytes: [UInt8]
        var index: Int = 0
        mutating func byte() throws -> UInt8 {
            guard index < bytes.count else { throw MusicError.invalidResponse }
            defer { index += 1 }; return bytes[index]
        }
        mutating func integer() throws -> Int {
            var result = 0, multiplier = 1
            for _ in 0..<4 {
                let current = try byte(); result += Int(current & 0x7f) * multiplier
                if current & 0x80 == 0 { return result }; multiplier *= 128
            }
            throw MusicError.invalidResponse
        }
        mutating func word() throws -> Int { Int(try byte()) * 256 + Int(try byte()) }
        mutating func string() throws -> String {
            let length = try word()
            guard index + length <= bytes.count else { throw MusicError.invalidResponse }
            defer { index += length }
            return String(decoding: bytes[index..<index + length], as: UTF8.self)
        }
        mutating func properties() throws -> [String: String] {
            let count = try integer(), end = index + count
            guard end <= bytes.count else { throw MusicError.invalidResponse }
            var result: [String: String] = [:]
            while index < end {
                let key = try byte()
                switch key {
                case 0x26: let name = try string(); result[name] = try string()
                case 0x1c: result["serverReference"] = try string()
                case 0x1f, 0x03, 0x08, 0x12, 0x15, 0x1a: _ = try string()
                case 0x13, 0x21, 0x22, 0x23: index += 2
                case 0x02, 0x11, 0x18, 0x27: index += 4
                case 0x01, 0x17, 0x19, 0x24, 0x25, 0x28, 0x29, 0x2a: index += 1
                case 0x09, 0x16: let length = try word(); index += length
                case 0x0b: _ = try integer()
                default: throw MusicError.invalidResponse
                }
                guard index <= end else { throw MusicError.invalidResponse }
            }
            return result
        }
    }
}

actor QQSocket {
    var task: URLSessionWebSocketTask?
    var buffer = Data()
    private let network = URLSession(configuration: .ephemeral)
    func close() { task?.cancel(with: .normalClosure, reason: nil); task = nil; buffer = Data() }
    func open(key: String) async throws {
        close()
        var path = "/ws/handshake"
        for attempt in 0...3 {
            guard let url = URL(string: "wss://mu.y.qq.com" + path) else { throw MusicError.invalidResponse }
            let socket = network.webSocketTask(with: url, protocols: ["mqtt"])
            task = socket; buffer = Data(); socket.resume()
            try await socket.send(.data(QQMQTT.connect(key)))
            let packet = try await nextPacket()
            var cursor = QQMQTT.Cursor(bytes: Array(packet)); _ = try cursor.byte(); _ = try cursor.integer(); _ = try cursor.byte()
            let reason = try cursor.byte(), props = try cursor.properties()
            if reason == 0 {
                try await socket.send(.data(QQMQTT.subscribe(key)))
                while true {
                    let acknowledgement = try await nextPacket()
                    if acknowledgement.first.map({ $0 >> 4 }) == 9 {
                        guard let code = acknowledgement.last, code < 0x80 else { throw MusicError.invalidResponse }
                        return
                    }
                }
            }
            socket.cancel(with: .normalClosure, reason: nil)
            guard [0x9c, 0x9d].contains(reason), let reference = props["serverReference"], attempt < 3,
                  reference.range(of: "^[A-Za-z0-9:._-]+$", options: .regularExpression) != nil else {
                throw MusicError.server(Int(reason), "QQ 扫码消息服务拒绝连接")
            }
            var parts = path.split(separator: "/").map(String.init)
            if parts.last?.contains(":") == true { parts[parts.count - 1] = reference } else { parts.append(reference) }
            path = "/" + parts.joined(separator: "/")
        }
    }
    func nextPacket() async throws -> Data {
        while true {
            if buffer.count > 1 {
                var cursor = QQMQTT.Cursor(bytes: Array(buffer), index: 1)
                if let length = try? cursor.integer(), buffer.count >= cursor.index + length {
                    let packet = Data(buffer.prefix(cursor.index + length)); buffer.removeFirst(cursor.index + length); return packet
                }
            }
            guard let task else { throw CancellationError() }
            let message = try await task.receive()
            switch message { case .data(let data): buffer += data; case .string(let text): buffer += Data(text.utf8); @unknown default: throw MusicError.invalidResponse }
            guard buffer.count <= 1048576 else { throw MusicError.invalidResponse }
        }
    }
    func nextEvent() async throws -> (String, [String: Any]) {
        while true {
            let data = try await nextPacket()
            guard let header = data.first, header >> 4 == 3 else { continue }
            var cursor = QQMQTT.Cursor(bytes: Array(data)); _ = try cursor.byte(); _ = try cursor.integer(); _ = try cursor.string()
            let qos = (header >> 1) & 3
            let identifier = qos > 0 ? try cursor.word() : 0
            let props = try cursor.properties()
            let payload = Data(cursor.bytes[cursor.index...])
            if qos == 1 { try await task?.send(.data(Data([0x40, 2, UInt8(identifier >> 8), UInt8(identifier & 255)]))) }
            let parsed = (try? JSONSerialization.jsonObject(with: payload) as? [String: Any]) ?? [:]
            return (props["type"] ?? "", parsed)
        }
    }
    func ping() async throws { try await task?.send(.data(Data([0xc0, 0]))) }
}
