import Combine
import CoreImage
import Foundation
import SwiftUI
import UIKit

@MainActor
final class IOS15AccountStore: ObservableObject {
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isRefreshing = false

    var isLoggedIn: Bool {
        NeteaseClient.shared.isLoggedIn
    }

    func refresh() async {
        guard isLoggedIn else {
            profile = nil
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        profile = try? await NeteaseAPI.userAccount()
    }

    func logout() async {
        await NeteaseAPI.logout()
        profile = nil
    }
}

private enum IOS15ReleaseChecker {
    struct Release {
        let version: String
        let url: URL
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func latest() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/missuo/kumone/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let html = object["html_url"] as? String,
              let url = URL(string: html)
        else {
            throw NeteaseAPIError.decoding("release")
        }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, url: url)
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").map { Int($0) ?? 0 }
        let localParts = local.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(remoteParts.count, localParts.count) {
            let remoteValue = index < remoteParts.count ? remoteParts[index] : 0
            let localValue = index < localParts.count ? localParts[index] : 0
            if remoteValue != localValue { return remoteValue > localValue }
        }
        return false
    }
}

struct IOS15SettingsView: View {
    @ObservedObject var account: IOS15AccountStore
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.openURL) private var openURL

    @State private var showLogin = false
    @State private var isCheckingUpdate = false
    @State private var updateMessage: String?
    @State private var updateURL: URL?

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("账户")) {
                    if let profile = account.profile {
                        HStack(spacing: 12) {
                            AsyncImage(url: profile.avatarUrl?.resizedImageURL(96)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.secondary.opacity(0.16)
                            }
                            .frame(width: 42, height: 42)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.nickname)
                                    .font(.body.weight(.semibold))
                                Text("已登录网易云音乐")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Button("退出登录", role: .destructive) {
                            Task { await account.logout() }
                        }
                    } else {
                        Button {
                            showLogin = true
                        } label: {
                            Label("登录网易云音乐", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }

                Section(header: Text("关于")) {
                    HStack {
                        Text("当前版本")
                        Spacer()
                        Text(IOS15ReleaseChecker.currentVersion)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        checkForUpdates()
                    } label: {
                        HStack {
                            Label("检查更新", systemImage: "arrow.down.circle")
                            Spacer()
                            if isCheckingUpdate {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isCheckingUpdate)

                    if let updateMessage {
                        Text(updateMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    if let updateURL {
                        Button {
                            openURL(updateURL)
                        } label: {
                            Label("打开下载页面", systemImage: "safari")
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationBarTitle("设置", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showLogin) {
            IOS15LoginSheet(account: account)
        }
        .task {
            await account.refresh()
        }
    }

    private func checkForUpdates() {
        isCheckingUpdate = true
        updateMessage = nil
        updateURL = nil
        Task {
            defer { isCheckingUpdate = false }
            do {
                let release = try await IOS15ReleaseChecker.latest()
                updateURL = release.url
                if IOS15ReleaseChecker.isNewer(release.version, than: IOS15ReleaseChecker.currentVersion) {
                    updateMessage = "发现新版本 \(release.version)，可打开下载页面侧载更新。"
                } else {
                    updateMessage = "当前已是最新版本（远端 \(release.version)）。"
                }
            } catch {
                updateMessage = "检查更新失败，请稍后重试。"
            }
        }
    }
}

struct IOS15LoginSheet: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case qr = "扫码登录"
        case sms = "手机验证码"

        var id: String { rawValue }
    }

    private enum QRPhase: Equatable {
        case loading
        case waiting
        case scanned(String)
        case expired
        case failed(String)
    }

    @ObservedObject var account: IOS15AccountStore
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.scenePhase) private var scenePhase

    @State private var mode: Mode = .qr
    @State private var qrPhase: QRPhase = .loading
    @State private var qrImage: UIImage?
    @State private var qrKey: String?
    @State private var pollTask: Task<Void, Never>?

    @State private var phone = ""
    @State private var code = ""
    @State private var cooldown = 0
    @State private var isSendingCode = false
    @State private var isLoggingIn = false
    @State private var loginMessage: String?
    @State private var cooldownTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Picker("登录方式", selection: $mode) {
                    ForEach(Mode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.top, 16)

                if mode == .qr {
                    qrContent
                } else {
                    smsContent
                }

                Spacer(minLength: 0)
            }
            .navigationBarTitle("登录网易云音乐", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            startQRLogin()
        }
        .onDisappear {
            pollTask?.cancel()
            cooldownTask?.cancel()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, mode == .qr else { return }
            if case .failed = qrPhase {
                startQRLogin(reuseKey: true)
            } else if pollTask == nil || pollTask?.isCancelled == true {
                startQRLogin(reuseKey: true)
            }
        }
        .onChange(of: mode) { newMode in
            guard newMode == .qr else { return }
            if case .failed = qrPhase {
                startQRLogin(reuseKey: true)
            } else if pollTask == nil || pollTask?.isCancelled == true {
                startQRLogin(reuseKey: true)
            }
        }
    }

    private var qrContent: some View {
        VStack(spacing: 16) {
            Text("使用网易云音乐 App 扫码登录")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 224, height: 224)
                    .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)

                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 188, height: 188)
                        .blur(radius: qrOverlayVisible ? 3 : 0)
                } else {
                    ProgressView()
                }

                if qrOverlayVisible {
                    VStack(spacing: 8) {
                        if case .expired = qrPhase {
                            Text("二维码已失效")
                                .font(.subheadline.weight(.semibold))
                            Button("刷新二维码") {
                                startQRLogin()
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        } else if case .scanned(let nickname) = qrPhase {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.green)
                            Text("\(nickname)，请在手机上确认")
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            Text(qrStatusText)
                .font(.footnote)
                .foregroundColor(.secondary)

            Text("只有一台设备？截图二维码，在网易云音乐 App 的扫一扫中选择相册识别，再回到这里即可。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .padding(.top, 20)
    }

    private var smsContent: some View {
        VStack(spacing: 14) {
            Text("使用手机号和短信验证码登录")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Text("+86")
                    .font(.body.weight(.medium))
                    .foregroundColor(.secondary)
                TextField("手机号", text: $phone)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }

            HStack(spacing: 8) {
                TextField("验证码", text: $code)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                Button {
                    sendSMSCode()
                } label: {
                    if isSendingCode {
                        ProgressView()
                    } else if cooldown > 0 {
                        Text("\(cooldown) 秒")
                            .monospacedDigit()
                    } else {
                        Text("获取验证码")
                    }
                }
                .frame(width: 96)
                .disabled(isSendingCode || cooldown > 0 || phone.count < 11)
            }

            if let loginMessage {
                Text(loginMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                loginWithSMSCode()
            } label: {
                if isLoggingIn {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("登录")
                        .font(.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.red, in: Capsule())
            .foregroundColor(.white)
            .disabled(isLoggingIn || phone.count < 11 || code.count < 4)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
    }

    private var qrStatusText: String {
        switch qrPhase {
        case .loading:
            return "正在获取二维码…"
        case .waiting:
            return "打开网易云音乐 App，扫一扫登录"
        case .scanned:
            return "等待手机确认…"
        case .expired:
            return "二维码已失效，请刷新"
        case .failed(let message):
            return message
        }
    }

    private var qrOverlayVisible: Bool {
        switch qrPhase {
        case .expired, .scanned:
            return true
        default:
            return false
        }
    }

    /// Reuses the same QR key after returning from the NetEase app. Short network
    /// interruptions while backgrounded are tolerated instead of ending polling.
    private func startQRLogin(reuseKey: Bool = false) {
        pollTask?.cancel()
        let existingKey = reuseKey ? qrKey : nil
        if existingKey == nil {
            qrPhase = .loading
            qrImage = nil
        } else {
            qrPhase = .waiting
        }

        pollTask = Task {
            do {
                let key: String
                if let existingKey {
                    key = existingKey
                } else {
                    key = try await NeteaseAPI.qrKey()
                    qrKey = key
                    qrImage = Self.makeQRCode(NeteaseAPI.qrLoginURL(unikey: key))
                    qrPhase = .waiting
                }

                var consecutiveErrors = 0
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    guard !Task.isCancelled else { return }
                    do {
                        let check = try await NeteaseAPI.qrCheck(unikey: key)
                        consecutiveErrors = 0
                        switch check.code {
                        case 800:
                            qrPhase = .expired
                            qrKey = nil
                            return
                        case 801:
                            qrPhase = .waiting
                        case 802:
                            qrPhase = .scanned(check.nickname ?? "已扫码")
                        case 803:
                            await account.refresh()
                            presentationMode.wrappedValue.dismiss()
                            return
                        default:
                            break
                        }
                    } catch {
                        consecutiveErrors += 1
                        if consecutiveErrors >= 15 { throw error }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    qrPhase = .failed("网络暂时不可用，返回 App 后会自动继续。")
                }
            }
        }
    }

    private func sendSMSCode() {
        isSendingCode = true
        loginMessage = nil
        Task {
            defer { isSendingCode = false }
            do {
                try await NeteaseAPI.sendSMSCode(phone: phone)
                loginMessage = "验证码已发送"
                cooldown = 60
                cooldownTask?.cancel()
                cooldownTask = Task {
                    while cooldown > 0, !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !Task.isCancelled else { return }
                        cooldown -= 1
                    }
                }
            } catch {
                loginMessage = error.localizedDescription
            }
        }
    }

    private func loginWithSMSCode() {
        isLoggingIn = true
        loginMessage = nil
        Task {
            defer { isLoggingIn = false }
            do {
                try await NeteaseAPI.loginCellphone(phone: phone, captcha: code)
                pollTask?.cancel()
                await account.refresh()
                presentationMode.wrappedValue.dismiss()
            } catch {
                loginMessage = error.localizedDescription
            }
        }
    }

    private static func makeQRCode(_ string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let image = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}
