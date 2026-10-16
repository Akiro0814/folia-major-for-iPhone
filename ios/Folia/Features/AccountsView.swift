import SwiftUI

// Folia/Features/AccountsView.swift — provider-advertised login and cancellable QR polling.
struct AccountsView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    var body: some View {
        List(MusicProvider.allCases) { provider in
            NavigationLink(provider.displayName) { LoginView(provider: provider) }
        }.navigationTitle(localized("账户与音乐服务", "Accounts & services"))
    }
}

struct LoginView: View {
    let provider: MusicProvider
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var methods: [LoginMethod] = []
    @State private var method: LoginMethod = .sms
    @State private var account: MusicAccount?
    @State private var phone = ""
    @State private var credential = ""
    @State private var message: String?
    @State private var busy = false
    @State private var qr: QRLogin?
    @State private var qrGeneration = 0

    var body: some View {
        if provider == .navidrome { NavidromeLoginView() } else { standardForm }
    }
    private var standardForm: some View {
        Form {
            if let account {
                Section { Label(account.nickname, systemImage: "person.crop.circle.fill")
                    Button(localized("退出登录", "Sign out"), role: .destructive) { perform { try await playback.service.logout(provider: provider); self.account = nil } }
                }
            } else if methods.isEmpty {
                Section { Text(localized("此平台的设备直连登录协议暂未就绪。不会将其他应用的微信身份冒充本平台授权。", "Direct device sign-in is not available for this provider yet.")) }
            } else {
                Picker(localized("登录方式", "Sign-in method"), selection: $method) {
                    ForEach(methods, id: \.self) { method in Text(methodTitle(method)).tag(method) }
                }
                if method == .qr {
                    Section {
                        if let qr { QRCodeView(url: qr.url, imageURL: qr.imageURL)
                            ShareLink(item: qr.url) { Label(localized("打开或分享授权链接", "Open or share authorization"), systemImage: "qrcode") }
                            Link(localized("在浏览器中授权", "Authorize in browser"), destination: qr.url)
                        }
                        Button(localized("生成登录二维码", "Create sign-in QR")) { qrGeneration += 1 }
                    }
                } else {
                    TextField(localized("手机号 / 账户", "Phone / account"), text: $phone).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if method == .sms {
                        TextField(localized("验证码", "Verification code"), text: $credential).textContentType(.oneTimeCode).keyboardType(.numberPad)
                        Button(localized("发送验证码", "Send verification code")) { perform { try await playback.service.sendCode(phone: phone, provider: provider); message = localized("验证码已发送", "Code sent") } }.disabled(phone.isEmpty || busy)
                    } else { SecureField(localized("密码", "Password"), text: $credential).textContentType(.password) }
                    Button(localized("登录", "Sign in")) {
                        perform {
                            defer { credential = "" }
                            account = try await playback.service.login(phone: phone, credential: credential, method: method, provider: provider)
                        }
                    }.disabled(phone.isEmpty || credential.isEmpty || busy)
                }
            }
            if busy { ProgressView() }
            if let message { Section { Text(message).font(.callout) } }
            Section { Text(localized("凭证保存在系统钥匙串。密码不会持久化。平台可能要求额外验证或会员权限。", "Credentials stay in Keychain. Passwords are never saved. Providers may require additional verification or membership.")).font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle(provider.displayName)
        .task { methods = await playback.service.loginMethods(provider: provider); method = methods.first ?? .sms; account = await playback.service.account(provider: provider) }
        .task(id: qrGeneration) {
            guard qrGeneration > 0, method == .qr else { return }
            do {
                let ticket = try await playback.service.startQR(provider: provider)
                try Task.checkCancellation(); qr = ticket
                for _ in 0..<100 {
                    try await Task.sleep(for: .seconds(2)); try Task.checkCancellation()
                    let status = try await playback.service.pollQR(ticket, provider: provider)
                    switch status {
                    case .authorized(let account): self.account = account; qr = nil; return
                    case .expired: message = localized("二维码已过期，请重新生成", "QR expired. Generate a new one."); qr = nil; return
                    case .scanned: message = localized("请在平台确认登录", "Confirm sign-in in the provider app")
                    case .waiting: break
                    }
                }
            } catch is CancellationError { } catch { message = error.localizedDescription }
        }
        .onChange(of: method) { qr = nil; qrGeneration = 0; credential = "" }
        .onDisappear { credential = "" }
    }
    private func methodTitle(_ method: LoginMethod) -> String {
        switch method { case .sms: localized("短信验证码", "SMS code"); case .password: localized("账号密码", "Password"); case .qr: provider == .qq ? localized("微信扫码", "WeChat QR") : localized("扫码授权", "QR authorization") }
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        busy = true; message = nil
        Task { do { try await operation() } catch { message = error.localizedDescription }; busy = false }
    }
}



