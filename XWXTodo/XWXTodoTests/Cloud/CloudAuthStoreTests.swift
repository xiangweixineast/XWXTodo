import XCTest
@testable import XWXTodo

@MainActor
final class CloudAuthStoreTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    private let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!

    func testRestoreWithoutSavedTokenStaysSignedOut() async {
        let client = FakeAuthClient()
        let sessionStore = FakeSessionStore()
        let store = makeStore(client: client, sessionStore: sessionStore)

        await store.restoreSavedSessionIfNeeded()

        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(store.session)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(client.meTokens.isEmpty)
    }

    func testRestoreSavedTokenUsesMeAndConnects() async {
        let client = FakeAuthClient()
        let sessionStore = FakeSessionStore(token: "saved-token")
        client.meResult = .success(makeSession(token: "saved-token", revision: 3))
        let store = makeStore(client: client, sessionStore: sessionStore)

        await store.restoreSavedSessionIfNeeded()

        XCTAssertEqual(store.phase, .signedIn)
        XCTAssertEqual(store.session?.token, "saved-token")
        XCTAssertEqual(store.currentUser?.currentRevision, 3)
        XCTAssertEqual(store.lastConnectedAt, baseDate)
        XCTAssertEqual(client.meTokens, ["saved-token"])
    }

    func testRestoreUnauthorizedDeletesTokenAndReturnsSignedOut() async {
        let client = FakeAuthClient()
        let sessionStore = FakeSessionStore(token: "expired-token")
        client.meResult = .failure(CloudAPIError.unauthorized)
        let store = makeStore(client: client, sessionStore: sessionStore)

        await store.restoreSavedSessionIfNeeded()

        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(store.session)
        XCTAssertNil(sessionStore.token)
        XCTAssertEqual(sessionStore.deleteCount, 1)
        XCTAssertEqual(store.errorMessage, "登录状态已失效")
    }

    func testRestoreNetworkFailureKeepsTokenAndShowsConnectionFailure() async {
        let client = FakeAuthClient()
        let sessionStore = FakeSessionStore(token: "saved-token")
        client.meResult = .failure(CloudAPIError.transport("offline"))
        let store = makeStore(client: client, sessionStore: sessionStore)

        await store.restoreSavedSessionIfNeeded()

        XCTAssertEqual(store.phase, .connectionFailed)
        XCTAssertNil(store.session)
        XCTAssertEqual(sessionStore.token, "saved-token")
        XCTAssertEqual(store.errorMessage, "网络请求失败：offline")
    }

    func testLoginSuccessSavesTokenAndConnects() async {
        let client = FakeAuthClient()
        let sessionStore = FakeSessionStore()
        client.loginResult = .success(makeSession(token: "new-token", revision: 5))
        let store = makeStore(client: client, sessionStore: sessionStore)

        await store.login(username: "  alice  ", password: "secret")

        XCTAssertEqual(store.phase, .signedIn)
        XCTAssertEqual(store.currentUser?.username, "alice")
        XCTAssertEqual(sessionStore.token, "new-token")
        XCTAssertEqual(sessionStore.savedTokens, ["new-token"])
        XCTAssertEqual(client.loginCalls.map(\.username), ["alice"])
        XCTAssertEqual(client.loginCalls.map(\.password), ["secret"])
    }

    func testLoginFailureDoesNotSaveToken() async {
        let client = FakeAuthClient()
        let sessionStore = FakeSessionStore()
        client.loginResult = .failure(CloudAPIError.unauthorized)
        let store = makeStore(client: client, sessionStore: sessionStore)

        await store.login(username: "alice", password: "bad")

        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(store.session)
        XCTAssertNil(sessionStore.token)
        XCTAssertTrue(sessionStore.savedTokens.isEmpty)
        XCTAssertEqual(store.errorMessage, "登录状态已失效")
    }

    func testLogoutSuccessClearsLocalToken() async {
        let client = FakeAuthClient()
        let sessionStore = FakeSessionStore()
        client.loginResult = .success(makeSession(token: "new-token"))
        let store = makeStore(client: client, sessionStore: sessionStore)
        await store.login(username: "alice", password: "secret")

        await store.logout()

        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(store.session)
        XCTAssertNil(sessionStore.token)
        XCTAssertEqual(client.logoutTokens, ["new-token"])
        XCTAssertNil(store.errorMessage)
    }

    func testLogoutRemoteFailureStillClearsLocalToken() async {
        let client = FakeAuthClient()
        let sessionStore = FakeSessionStore()
        client.loginResult = .success(makeSession(token: "new-token"))
        client.logoutResult = .failure(CloudAPIError.transport("offline"))
        let store = makeStore(client: client, sessionStore: sessionStore)
        await store.login(username: "alice", password: "secret")

        await store.logout()

        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(store.session)
        XCTAssertNil(sessionStore.token)
        XCTAssertEqual(client.logoutTokens, ["new-token"])
        XCTAssertEqual(store.errorMessage, "已退出本机，服务器退出请求失败：网络请求失败：offline")
    }

    private func makeStore(
        client: FakeAuthClient,
        sessionStore: FakeSessionStore
    ) -> CloudAuthStore {
        CloudAuthStore(client: client, sessionStore: sessionStore, now: { self.baseDate })
    }

    private func makeSession(
        token: String,
        username: String = "alice",
        revision: Int = 1
    ) -> CloudSession {
        CloudSession(
            token: token,
            tokenType: "bearer",
            expiresAt: baseDate.addingTimeInterval(3600),
            user: CloudUser(id: userID, username: username, currentRevision: revision)
        )
    }
}

private final class FakeAuthClient: CloudAuthClient {
    var loginResult: Result<CloudSession, Error> = .failure(TestError.unexpectedCall)
    var meResult: Result<CloudSession, Error> = .failure(TestError.unexpectedCall)
    var logoutResult: Result<Void, Error> = .success(())

    private(set) var loginCalls: [(username: String, password: String)] = []
    private(set) var meTokens: [String] = []
    private(set) var logoutTokens: [String] = []

    func login(username: String, password: String) async throws -> CloudSession {
        loginCalls.append((username, password))
        return try loginResult.get()
    }

    func me(token: String) async throws -> CloudSession {
        meTokens.append(token)
        return try meResult.get()
    }

    func logout(token: String) async throws {
        logoutTokens.append(token)
        try logoutResult.get()
    }
}

private final class FakeSessionStore: CloudSessionStore {
    var token: String?
    var savedTokens: [String] = []
    var deleteCount = 0

    init(token: String? = nil) {
        self.token = token
    }

    func saveToken(_ token: String) throws {
        self.token = token
        savedTokens.append(token)
    }

    func loadToken() throws -> String? {
        token
    }

    func deleteToken() throws {
        token = nil
        deleteCount += 1
    }
}

private enum TestError: Error {
    case unexpectedCall
}
