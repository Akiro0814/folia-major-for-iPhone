import Foundation
import Network
import Security
// ios/Folia/Services/BodianGETBodyHTTP.swift

/// Bodian's pinned desktop protocol uses signed GET bodies, which URLSession does not send.
/// This narrow HTTPS/1.1 transport retains system TLS trust and only targets the fixed API host.
final class BodianGETBodyHTTP: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Folia.Bodian.GETBody")
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<Data, Error>?
    private var bytes = Data()
    private var cancelled = false
    private var finished = false

    func send(_ request: URLRequest) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.continuation = continuation
                    if self.cancelled { self.finish(.failure(CancellationError())); return }
                    self.start(request)
                }
            }
        } onCancel: {
            self.queue.async { self.cancelled = true; self.finish(.failure(CancellationError())) }
        }
    }
    private func start(_ request: URLRequest) {
        guard let url = request.url, url.scheme == "https", url.host == "bd-api.kuwo.cn", url.port == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { finish(.failure(MusicError.invalidResponse)); return }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, "bd-api.kuwo.cn")
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        let connection = NWConnection(host: "bd-api.kuwo.cn", port: 443, using: NWParameters(tls: tls, tcp: NWProtocolTCP.Options()))
        self.connection = connection
        let target = components.percentEncodedPath + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        let body = request.httpBody ?? Data()
        var header = "GET \(target) HTTP/1.1\r\nHost: bd-api.kuwo.cn\r\nConnection: close\r\nAccept-Encoding: identity\r\nContent-Length: \(body.count)\r\n"
        for (name, value) in request.allHTTPHeaderFields ?? [:] where !["host", "connection", "accept-encoding", "content-length"].contains(name.lowercased()) {
            guard !name.contains("\r"), !name.contains("\n"), !value.contains("\r"), !value.contains("\n") else { finish(.failure(MusicError.invalidResponse)); return }
            header += "\(name): \(value)\r\n"
        }
        var packet = Data((header + "\r\n").utf8); packet.append(body)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.finished else { return }
            switch state {
            case .ready:
                connection.send(content: packet, completion: .contentProcessed { error in
                    if let error { self.finish(.failure(error)) } else { self.receive() }
                })
            case .failed(let error): self.finish(.failure(error))
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 30) { [weak self] in self?.finish(.failure(URLError(.timedOut))) }
    }
    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
            guard !self.finished else { return }
            if let data { self.bytes.append(data) }
            guard self.bytes.count < 8 * 1024 * 1024 else { self.finish(.failure(MusicError.invalidResponse)); return }
            if let error { self.finish(.failure(error)); return }
            if complete {
                do { self.finish(.success(try Self.decode(self.bytes))) } catch { self.finish(.failure(error)) }
            } else { self.receive() }
        }
    }
    private func finish(_ result: Result<Data, Error>) {
        guard !finished else { return }
        // Cancellation can precede continuation installation; the start path will observe it.
        guard let continuation else { return }
        finished = true; self.continuation = nil
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        continuation.resume(with: result)
    }
    static func decode(_ bytes: Data) throws -> Data {
        guard let split = bytes.range(of: Data("\r\n\r\n".utf8)), let header = String(data: bytes[..<split.lowerBound], encoding: .isoLatin1) else { throw MusicError.invalidResponse }
        let lines = header.components(separatedBy: "\r\n")
        guard let first = lines.first, let status = Int(first.split(separator: " ").dropFirst().first ?? "") else { throw MusicError.invalidResponse }
        guard (200..<300).contains(status) else { throw MusicError.server(status, "波点音乐播放接口请求失败") }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            fields[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard fields["content-encoding"] == nil || fields["content-encoding"]?.lowercased() == "identity" else { throw MusicError.unavailable("波点播放接口返回了不支持的压缩格式。") }
        let body = Data(bytes[split.upperBound...])
        if fields["transfer-encoding"]?.lowercased().contains("chunked") == true {
            var cursor = 0; var decoded = Data()
            while cursor < body.count {
                guard let end = body.range(of: Data("\r\n".utf8), in: cursor..<body.count),
                      let text = String(data: body[cursor..<end.lowerBound], encoding: .ascii),
                      let count = Int(text.split(separator: ";").first ?? "", radix: 16), count >= 0 else { throw MusicError.invalidResponse }
                cursor = end.upperBound
                if count == 0 { return decoded }
                guard count <= body.count - cursor, cursor + count + 2 <= body.count,
                      body[cursor + count] == 13, body[cursor + count + 1] == 10 else { throw MusicError.invalidResponse }
                decoded.append(body[cursor..<cursor + count]); cursor += count + 2
            }
            throw MusicError.invalidResponse
        }
        if let length = fields["content-length"] {
            guard let count = Int(length), count >= 0, body.count == count else { throw MusicError.invalidResponse }
        }
        return body
    }
}
