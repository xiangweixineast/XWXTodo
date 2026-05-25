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

@MainActor
final class AppStateCloudTodoSyncTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    private let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!

    func testRestoreSavedSessionFetchesTodosAndReplacesLocalCache() async throws {
        let old = makeTodo(title: "Old")
        let cloudItem = makeTodo(title: "Cloud", sortOrder: 3)
        let authClient = FakeAuthClient()
        let sessionStore = FakeSessionStore(token: "saved-token")
        let todoClient = FakeTodoClient()
        authClient.meResult = .success(makeSession(token: "saved-token"))
        todoClient.results = [.success(makeSnapshot(items: [cloudItem]))]
        let (appState, store, cache) = try makeAppState(
            authClient: authClient,
            sessionStore: sessionStore,
            todoClient: todoClient,
            initialTodos: [old]
        )

        await appState.restoreCloudSessionIfNeeded()

        XCTAssertEqual(appState.cloudAuthStore.phase, .signedIn)
        XCTAssertEqual(todoClient.tokens, ["saved-token"])
        XCTAssertEqual(store.activeTodos, [cloudItem])
        XCTAssertEqual(try cache.loadTodos(), [cloudItem])
        XCTAssertNil(appState.syncErrorMessage)
    }

    func testLoginSuccessFetchesTodosAndReplacesLocalCache() async throws {
        let old = makeTodo(title: "Old")
        let cloudItem = makeTodo(title: "After Login")
        let authClient = FakeAuthClient()
        let sessionStore = FakeSessionStore()
        let todoClient = FakeTodoClient()
        authClient.loginResult = .success(makeSession(token: "new-token"))
        todoClient.results = [.success(makeSnapshot(items: [cloudItem]))]
        let (appState, store, cache) = try makeAppState(
            authClient: authClient,
            sessionStore: sessionStore,
            todoClient: todoClient,
            initialTodos: [old]
        )

        await appState.login(username: "alice", password: "secret")

        XCTAssertEqual(appState.cloudAuthStore.phase, .signedIn)
        XCTAssertEqual(sessionStore.token, "new-token")
        XCTAssertEqual(todoClient.tokens, ["new-token"])
        XCTAssertEqual(store.activeTodos, [cloudItem])
        XCTAssertEqual(try cache.loadTodos(), [cloudItem])
    }

    func testRestoreTodoFetchFailureClearsTodosAndKeepsSignedInSession() async throws {
        let old = makeTodo(title: "Old")
        let authClient = FakeAuthClient()
        let sessionStore = FakeSessionStore(token: "saved-token")
        let todoClient = FakeTodoClient()
        authClient.meResult = .success(makeSession(token: "saved-token"))
        todoClient.results = [.failure(CloudAPIError.transport("offline"))]
        let (appState, store, cache) = try makeAppState(
            authClient: authClient,
            sessionStore: sessionStore,
            todoClient: todoClient,
            initialTodos: [old]
        )

        await appState.restoreCloudSessionIfNeeded()

        XCTAssertEqual(appState.cloudAuthStore.phase, .signedIn)
        XCTAssertEqual(sessionStore.token, "saved-token")
        XCTAssertTrue(store.activeTodos.isEmpty)
        XCTAssertEqual(try cache.loadTodos(), [])
        XCTAssertEqual(appState.syncErrorMessage, "同步 TODO 失败：网络请求失败：offline")
    }

    func testRestoreWithoutTokenClearsLocalTodos() async throws {
        let old = makeTodo(title: "Old")
        let authClient = FakeAuthClient()
        let sessionStore = FakeSessionStore()
        let todoClient = FakeTodoClient()
        let (appState, store, cache) = try makeAppState(
            authClient: authClient,
            sessionStore: sessionStore,
            todoClient: todoClient,
            initialTodos: [old]
        )

        await appState.restoreCloudSessionIfNeeded()

        XCTAssertEqual(appState.cloudAuthStore.phase, .signedOut)
        XCTAssertTrue(todoClient.tokens.isEmpty)
        XCTAssertTrue(store.activeTodos.isEmpty)
        XCTAssertEqual(try cache.loadTodos(), [])
        XCTAssertNil(appState.syncErrorMessage)
    }

    func testRestoreUnauthorizedClearsTokenAndLocalTodos() async throws {
        let old = makeTodo(title: "Old")
        let authClient = FakeAuthClient()
        let sessionStore = FakeSessionStore(token: "expired-token")
        let todoClient = FakeTodoClient()
        authClient.meResult = .failure(CloudAPIError.unauthorized)
        let (appState, store, cache) = try makeAppState(
            authClient: authClient,
            sessionStore: sessionStore,
            todoClient: todoClient,
            initialTodos: [old]
        )

        await appState.restoreCloudSessionIfNeeded()

        XCTAssertEqual(appState.cloudAuthStore.phase, .signedOut)
        XCTAssertNil(sessionStore.token)
        XCTAssertTrue(todoClient.tokens.isEmpty)
        XCTAssertTrue(store.activeTodos.isEmpty)
        XCTAssertEqual(try cache.loadTodos(), [])
    }

    func testRetryTodoSyncReplacesTodosAndClearsSyncError() async throws {
        let old = makeTodo(title: "Old")
        let cloudItem = makeTodo(title: "Retried")
        let authClient = FakeAuthClient()
        let sessionStore = FakeSessionStore(token: "saved-token")
        let todoClient = FakeTodoClient()
        authClient.meResult = .success(makeSession(token: "saved-token"))
        todoClient.results = [
            .failure(CloudAPIError.transport("offline")),
            .success(makeSnapshot(items: [cloudItem])),
        ]
        let (appState, store, cache) = try makeAppState(
            authClient: authClient,
            sessionStore: sessionStore,
            todoClient: todoClient,
            initialTodos: [old]
        )

        await appState.restoreCloudSessionIfNeeded()
        await appState.retryTodoSync()

        XCTAssertEqual(todoClient.tokens, ["saved-token", "saved-token"])
        XCTAssertEqual(store.activeTodos, [cloudItem])
        XCTAssertEqual(try cache.loadTodos(), [cloudItem])
        XCTAssertNil(appState.syncErrorMessage)
    }

    func testPollingRefreshesTodosAfterLogin() async throws {
        let initial = makeTodo(title: "Initial")
        let polled = makeTodo(title: "Polled")
        let authClient = FakeAuthClient()
        let sessionStore = FakeSessionStore()
        let todoClient = FakeTodoClient()
        let pollingExpectation = expectation(description: "polling fetch")
        authClient.loginResult = .success(makeSession(token: "new-token"))
        todoClient.results = [
            .success(makeSnapshot(items: [initial], revision: 1)),
            .success(makeSnapshot(items: [polled], revision: 2)),
        ]
        todoClient.onGetTodos = { count in
            if count == 2 {
                pollingExpectation.fulfill()
            }
        }
        let (appState, store, _) = try makeAppState(
            authClient: authClient,
            sessionStore: sessionStore,
            todoClient: todoClient,
            initialTodos: [],
            todoPollingIntervalNanoseconds: 50_000_000
        )

        await appState.login(username: "alice", password: "secret")
        await fulfillment(of: [pollingExpectation], timeout: 1.0)
        try await Task.sleep(nanoseconds: 5_000_000)

        XCTAssertEqual(todoClient.tokens, ["new-token", "new-token"])
        XCTAssertEqual(store.activeTodos, [polled])
        XCTAssertNil(appState.syncErrorMessage)
    }

    func testPollingFailureKeepsLastSuccessfulSnapshot() async throws {
        let initial = makeTodo(title: "Initial")
        let authClient = FakeAuthClient()
        let sessionStore = FakeSessionStore()
        let todoClient = FakeTodoClient()
        let pollingExpectation = expectation(description: "polling failure")
        authClient.loginResult = .success(makeSession(token: "new-token"))
        todoClient.results = [
            .success(makeSnapshot(items: [initial], revision: 1)),
            .failure(CloudAPIError.transport("offline")),
        ]
        todoClient.onGetTodos = { count in
            if count == 2 {
                pollingExpectation.fulfill()
            }
        }
        let (appState, store, cache) = try makeAppState(
            authClient: authClient,
            sessionStore: sessionStore,
            todoClient: todoClient,
            initialTodos: [],
            todoPollingIntervalNanoseconds: 50_000_000
        )

        await appState.login(username: "alice", password: "secret")
        await fulfillment(of: [pollingExpectation], timeout: 1.0)
        try await Task.sleep(nanoseconds: 5_000_000)

        XCTAssertEqual(todoClient.tokens, ["new-token", "new-token"])
        XCTAssertEqual(store.activeTodos, [initial])
        XCTAssertEqual(try cache.loadTodos(), [initial])
        XCTAssertEqual(appState.syncErrorMessage, "同步 TODO 失败：网络请求失败：offline")
    }

    private func makeAppState(
        authClient: FakeAuthClient,
        sessionStore: FakeSessionStore,
        todoClient: FakeTodoClient,
        initialTodos: [TodoItem],
        todoPollingIntervalNanoseconds: UInt64 = 3_000_000_000
    ) throws -> (AppState, TodoStore, InMemoryTodoSnapshotCache) {
        let authStore = CloudAuthStore(
            client: authClient,
            sessionStore: sessionStore,
            now: { self.baseDate }
        )
        let cache = InMemoryTodoSnapshotCache(items: initialTodos)
        let store = try TodoStore(
            cache: cache,
            cloudTodoClient: todoClient,
            tokenProvider: { authStore.session?.token },
            now: { self.baseDate }
        )
        let appState = AppState(
            store: store,
            cloudAuthStore: authStore,
            cloudTodoClient: todoClient,
            todoPollingIntervalNanoseconds: todoPollingIntervalNanoseconds
        )
        return (appState, store, cache)
    }

    private func makeSession(token: String, revision: Int = 1) -> CloudSession {
        CloudSession(
            token: token,
            tokenType: "bearer",
            expiresAt: baseDate.addingTimeInterval(3600),
            user: CloudUser(id: userID, username: "alice", currentRevision: revision)
        )
    }

    private func makeSnapshot(items: [TodoItem], revision: Int = 9) -> CloudTodoSnapshot {
        CloudTodoSnapshot(
            revision: revision,
            todos: items.map { item in
                CloudTodo(
                    id: item.id,
                    title: item.title,
                    status: item.status,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt,
                    completedAt: item.completedAt,
                    sortOrder: item.sortOrder
                )
            }
        )
    }

    private func makeTodo(
        id: UUID = UUID(),
        title: String,
        status: TodoStatus = .pending,
        completedAt: Date? = nil,
        sortOrder: Int = 0
    ) -> TodoItem {
        TodoItem(
            id: id,
            title: title,
            status: status,
            createdAt: baseDate,
            updatedAt: baseDate,
            completedAt: completedAt,
            sortOrder: sortOrder
        )
    }
}

private final class FakeTodoClient: CloudTodoClient {
    var results: [Result<CloudTodoSnapshot, Error>] = []
    var onGetTodos: ((Int) -> Void)?
    private(set) var tokens: [String] = []

    func getTodos(token: String) async throws -> CloudTodoSnapshot {
        tokens.append(token)
        onGetTodos?(tokens.count)
        guard !results.isEmpty else {
            throw TestError.unexpectedCall
        }
        return try results.removeFirst().get()
    }

    func addTodo(title: String, token: String) async throws -> CloudTodoSnapshot {
        throw TestError.unexpectedCall
    }

    func editTodo(id: UUID, title: String, token: String) async throws -> CloudTodoSnapshot {
        throw TestError.unexpectedCall
    }

    func deleteTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot {
        throw TestError.unexpectedCall
    }

    func startTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot {
        throw TestError.unexpectedCall
    }

    func pauseTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot {
        throw TestError.unexpectedCall
    }

    func completeTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot {
        throw TestError.unexpectedCall
    }
}
