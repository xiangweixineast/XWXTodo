import Combine
import Foundation

/// 主窗口认证状态，用于区分登录、恢复和连接异常。
enum CloudAuthPhase: Equatable {
    case signedOut
    case restoring
    case signingIn
    case signedIn
    case connectionFailed

    var isBusy: Bool {
        self == .restoring || self == .signingIn
    }
}

@MainActor
final class CloudAuthStore: ObservableObject {
    @Published private(set) var phase: CloudAuthPhase
    @Published private(set) var session: CloudSession?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastConnectedAt: Date?

    private let client: CloudAuthClient
    private let sessionStore: CloudSessionStore
    private let now: () -> Date
    private var currentToken: String?
    private var hasAttemptedRestore = false

    init(
        client: CloudAuthClient = CloudAPIClient(),
        sessionStore: CloudSessionStore = KeychainSessionStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.sessionStore = sessionStore
        self.now = now
        self.phase = .signedOut
    }

    var currentUser: CloudUser? {
        session?.user
    }

    func restoreSavedSessionIfNeeded() async {
        guard !hasAttemptedRestore else { return }
        hasAttemptedRestore = true
        await restoreSavedSession()
    }

    func restoreSavedSession() async {
        phase = .restoring
        errorMessage = nil
        session = nil

        let token: String?
        do {
            token = try sessionStore.loadToken()
        } catch {
            currentToken = nil
            phase = .signedOut
            errorMessage = "读取登录状态失败：\(error.localizedDescription)"
            return
        }

        guard let token else {
            currentToken = nil
            phase = .signedOut
            return
        }

        currentToken = token

        do {
            let restoredSession = try await client.me(token: token)
            applyConnectedSession(restoredSession)
        } catch CloudAPIError.unauthorized {
            handleExpiredToken()
        } catch {
            phase = .connectionFailed
            errorMessage = error.localizedDescription
        }
    }

    func login(username: String, password: String) async {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            phase = .signedOut
            errorMessage = "请输入用户名和密码"
            return
        }

        phase = .signingIn
        errorMessage = nil
        session = nil
        currentToken = nil

        do {
            let newSession = try await client.login(username: trimmedUsername, password: password)
            try sessionStore.saveToken(newSession.token)
            applyConnectedSession(newSession)
        } catch {
            phase = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        let tokenToLogout = currentToken ?? session?.token
        var remoteLogoutError: Error?

        if let tokenToLogout {
            do {
                try await client.logout(token: tokenToLogout)
            } catch {
                remoteLogoutError = error
            }
        }

        do {
            try sessionStore.deleteToken()
            clearLocalSession()
            if let remoteLogoutError {
                errorMessage = "已退出本机，服务器退出请求失败：\(remoteLogoutError.localizedDescription)"
            }
        } catch {
            clearLocalSession()
            errorMessage = "退出登录失败：\(error.localizedDescription)"
        }
    }

    /// 服务端判定 token 失效时，清理本机会话并回到未登录状态。
    func expireCurrentSession() {
        handleExpiredToken()
    }

    private func applyConnectedSession(_ session: CloudSession) {
        self.session = session
        self.currentToken = session.token
        self.lastConnectedAt = now()
        self.errorMessage = nil
        self.phase = .signedIn
    }

    private func handleExpiredToken() {
        do {
            try sessionStore.deleteToken()
            clearLocalSession()
            errorMessage = "登录状态已失效"
        } catch {
            clearLocalSession()
            errorMessage = "登录状态已失效，本机清理失败：\(error.localizedDescription)"
        }
    }

    private func clearLocalSession() {
        session = nil
        currentToken = nil
        lastConnectedAt = nil
        phase = .signedOut
    }
}
