import SwiftUI

// Folia/Features/NavidromeLoginView.swift — user-owned server credentials and explicit Keychain persistence.
struct NavidromeLoginView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var account: MusicAccount?
    @State private var error: String?
    @State private var busy = false
    @State private var operationTask: Task<Void, Never>?
    var body: some View {
        Form {
            if let account {
                Section {
                    Label(account.nickname, systemImage: "person.crop.circle")
                    Button(localized("断开服务器", "Disconnect server"), role: .destructive) {
                        operationTask?.cancel()
                        operationTask = Task {
                            do { try await playback.service.logout(provider: .navidrome); try Task.checkCancellation(); self.account = nil }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }
            } else {
                Section(localized("你的 Navidrome 服务器", "Your Navidrome server")) {
                    TextField("https://music.example.com", text: $server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(localized("用户名", "Username"), text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(localized("密码", "Password"), text: $password).textContentType(.password)
                    Button(localized("连接并验证", "Connect and verify")) {
                        let submittedServer = server, submittedUsername = username, submittedPassword = password
                        operationTask?.cancel(); busy = true; error = nil
                        operationTask = Task {
                            defer { password = ""; busy = false }
                            do {
                                try await playback.service.configureNavidrome(serverURL: submittedServer, username: submittedUsername, password: submittedPassword)
                                try Task.checkCancellation()
                                let result = await playback.service.account(provider: .navidrome)
                                try Task.checkCancellation(); account = result
                            } catch is CancellationError { } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                        }
                    }.disabled(server.isEmpty || username.isEmpty || password.isEmpty || busy)
                }
            }
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            Section {
                Text(localized("Navidrome 需使用密码生成每次请求的认证摘要，因此服务器地址、用户名和密码会保存在系统钥匙串。断开连接将移除凭证。其他音乐平台只保留会话凭证。", "Navidrome needs your password to generate per-request authentication digests. Its server address, username and password are stored in Keychain and removed when disconnected. Other music providers retain session credentials only.")).font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Navidrome")
        .task { account = await playback.service.account(provider: .navidrome) }
        .onDisappear { operationTask?.cancel(); password = "" }
    }
}

