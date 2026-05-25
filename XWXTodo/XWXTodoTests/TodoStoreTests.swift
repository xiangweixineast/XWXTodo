import XCTest
@testable import XWXTodo

@MainActor
final class TodoStoreTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    private let token = "cloud-token"

    func testAddTodoTrimsTitleAndAppliesCloudSnapshot() async throws {
        let cloudItem = makeTodo(title: "写规格", sortOrder: 3)
        let client = FakeCloudTodoClient()
        client.results = [.success(makeSnapshot(items: [cloudItem], revision: 2))]
        let (store, cache, _) = try makeCloudStore(client: client)

        try await store.addTodo(title: "  写规格  ")

        XCTAssertEqual(client.calls, [.add(title: "写规格", token: token)])
        XCTAssertEqual(store.activeTodos, [cloudItem])
        XCTAssertEqual(try cache.loadTodos(), [cloudItem])
        XCTAssertEqual(store.currentRevision, 2)
        XCTAssertEqual(store.collapsedNotchTitle, "尚有1项待办事项")
    }

    func testAddTodoRejectsEmptyTitleWithoutCallingCloud() async throws {
        let existing = makeTodo(title: "Old")
        let client = FakeCloudTodoClient()
        let (store, cache, _) = try makeCloudStore(initialTodos: [existing], client: client)

        try await store.addTodo(title: "   ")

        XCTAssertTrue(client.calls.isEmpty)
        XCTAssertEqual(store.activeTodos, [existing])
        XCTAssertEqual(try cache.loadTodos(), [existing])
    }

    func testTodoOperationWithoutTokenFailsAndDoesNotMutateLocalState() async throws {
        let existing = makeTodo(title: "Old")
        let client = FakeCloudTodoClient()
        let (store, cache, _) = try makeCloudStore(initialTodos: [existing], token: nil, client: client)

        do {
            try await store.addTodo(title: "New")
            XCTFail("Expected signed out error")
        } catch let error as TodoStoreError {
            XCTAssertEqual(error, .signedOut)
        }

        XCTAssertTrue(client.calls.isEmpty)
        XCTAssertEqual(store.activeTodos, [existing])
        XCTAssertEqual(try cache.loadTodos(), [existing])
        XCTAssertEqual(store.errorMessage, "请先登录云端账号")
    }

    func testTodoOperationFailureDoesNotMutateLocalState() async throws {
        let existing = makeTodo(title: "Old")
        let client = FakeCloudTodoClient()
        client.results = [.failure(CloudAPIError.transport("offline"))]
        let (store, cache, _) = try makeCloudStore(initialTodos: [existing], client: client)

        do {
            try await store.editTodo(id: existing.id, title: "Changed")
            XCTFail("Expected cloud error")
        } catch let error as CloudAPIError {
            XCTAssertEqual(error, .transport("offline"))
        }

        XCTAssertEqual(client.calls, [.edit(id: existing.id, title: "Changed", token: token)])
        XCTAssertEqual(store.activeTodos, [existing])
        XCTAssertEqual(try cache.loadTodos(), [existing])
        XCTAssertNil(store.currentRevision)
        XCTAssertEqual(store.errorMessage, "网络请求失败：offline")
    }

    func testTodoMutationsUseCloudAndApplyReturnedSnapshots() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let first = makeTodo(id: firstID, title: "A")
        let edited = makeTodo(id: firstID, title: "B")
        let doing = makeTodo(id: firstID, title: "B", status: .doing)
        let pending = makeTodo(id: firstID, title: "B")
        let second = makeTodo(id: secondID, title: "C")
        let completed = makeTodo(id: secondID, title: "C", status: .completed, completedAt: baseDate)
        let client = FakeCloudTodoClient()
        client.results = [
            .success(makeSnapshot(items: [edited], revision: 1)),
            .success(makeSnapshot(items: [doing], revision: 2)),
            .success(makeSnapshot(items: [pending], revision: 3)),
            .success(makeSnapshot(items: [second], revision: 4)),
            .success(makeSnapshot(items: [completed], revision: 5)),
        ]
        let (store, cache, _) = try makeCloudStore(initialTodos: [first], client: client)

        try await store.editTodo(id: firstID, title: "  B  ")
        try await store.startTodo(id: firstID)
        try await store.pauseTodo(id: firstID)
        try await store.deleteTodo(id: firstID)
        try await store.completeTodo(id: secondID)

        XCTAssertEqual(
            client.calls,
            [
                .edit(id: firstID, title: "B", token: token),
                .start(id: firstID, token: token),
                .pause(id: firstID, token: token),
                .delete(id: firstID, token: token),
                .complete(id: secondID, token: token),
            ]
        )
        XCTAssertEqual(store.completedTodos, [completed])
        XCTAssertEqual(try cache.loadTodos(), [completed])
        XCTAssertEqual(store.currentRevision, 5)
    }

    func testApplySnapshotIgnoresOlderRevision() throws {
        let newer = makeTodo(title: "Newer")
        let older = makeTodo(title: "Older")
        let store = try TodoStore(cache: InMemoryTodoSnapshotCache())

        XCTAssertTrue(try store.applySnapshot(makeSnapshot(items: [newer], revision: 5)))
        XCTAssertFalse(try store.applySnapshot(makeSnapshot(items: [older], revision: 4)))

        XCTAssertEqual(store.activeTodos, [newer])
        XCTAssertEqual(store.currentRevision, 5)
    }

    func testClearRemovesCachedTodosAndRevision() throws {
        let active = makeTodo(title: "A")
        let completed = makeTodo(title: "Done", status: .completed, completedAt: baseDate)
        let store = try TodoStore(cache: InMemoryTodoSnapshotCache(items: [active, completed]))
        try store.applySnapshot(makeSnapshot(items: [active, completed], revision: 8))

        try store.clear()

        XCTAssertTrue(store.activeTodos.isEmpty)
        XCTAssertTrue(store.completedTodos.isEmpty)
        XCTAssertNil(store.currentRevision)
        XCTAssertEqual(store.collapsedNotchTitle, "牛!全干完了!")
    }

    func testCollapsedNotchTitleShowsDoneMessageWhenNoActiveTodos() throws {
        let store = try TodoStore(cache: InMemoryTodoSnapshotCache())

        XCTAssertEqual(store.collapsedNotchTitle, "牛!全干完了!")
    }

    func testCollapsedNotchTitleShowsPendingCountWhenNoDoingTodo() throws {
        let first = makeTodo(title: "A", sortOrder: 0)
        let second = makeTodo(title: "B", sortOrder: 1)
        let completed = makeTodo(title: "C", status: .completed, completedAt: baseDate, sortOrder: 2)
        let store = try TodoStore(cache: InMemoryTodoSnapshotCache(items: [first, second, completed]))

        XCTAssertEqual(store.collapsedNotchTitle, "尚有2项待办事项")
    }

    func testActiveTodosTieBreakEqualSortOrderByCreatedAtAscending() throws {
        let later = makeTodo(title: "Later", createdAt: baseDate.addingTimeInterval(10), sortOrder: 0)
        let earlier = makeTodo(title: "Earlier", createdAt: baseDate, sortOrder: 0)
        let store = try TodoStore(cache: InMemoryTodoSnapshotCache(items: [later, earlier]))

        XCTAssertEqual(store.activeTodos.map(\.title), ["Earlier", "Later"])
    }

    func testCompletedTodosSortByCompletedAtDescending() throws {
        let older = makeTodo(
            title: "Older",
            status: .completed,
            completedAt: baseDate,
            sortOrder: 0
        )
        let newer = makeTodo(
            title: "Newer",
            status: .completed,
            completedAt: baseDate.addingTimeInterval(10),
            sortOrder: 1
        )
        let store = try TodoStore(cache: InMemoryTodoSnapshotCache(items: [older, newer]))

        XCTAssertEqual(store.completedTodos.map(\.title), ["Newer", "Older"])
    }

    private func makeCloudStore(
        initialTodos: [TodoItem] = [],
        token: String? = "cloud-token",
        client: FakeCloudTodoClient
    ) throws -> (TodoStore, InMemoryTodoSnapshotCache, FakeCloudTodoClient) {
        let cache = InMemoryTodoSnapshotCache(items: initialTodos)
        let store = try TodoStore(
            cache: cache,
            cloudTodoClient: client,
            tokenProvider: { token }
        )
        return (store, cache, client)
    }

    private func makeSnapshot(items: [TodoItem], revision: Int = 1) -> CloudTodoSnapshot {
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
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        completedAt: Date? = nil,
        sortOrder: Int = 0
    ) -> TodoItem {
        let createdAt = createdAt ?? baseDate
        return TodoItem(
            id: id,
            title: title,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            completedAt: completedAt,
            sortOrder: sortOrder
        )
    }
}

private enum CloudTodoCall: Equatable {
    case get(token: String)
    case add(title: String, token: String)
    case edit(id: UUID, title: String, token: String)
    case delete(id: UUID, token: String)
    case start(id: UUID, token: String)
    case pause(id: UUID, token: String)
    case complete(id: UUID, token: String)
}

private final class FakeCloudTodoClient: CloudTodoClient {
    var results: [Result<CloudTodoSnapshot, Error>] = []
    private(set) var calls: [CloudTodoCall] = []

    func getTodos(token: String) async throws -> CloudTodoSnapshot {
        calls.append(.get(token: token))
        return try nextResult()
    }

    func addTodo(title: String, token: String) async throws -> CloudTodoSnapshot {
        calls.append(.add(title: title, token: token))
        return try nextResult()
    }

    func editTodo(id: UUID, title: String, token: String) async throws -> CloudTodoSnapshot {
        calls.append(.edit(id: id, title: title, token: token))
        return try nextResult()
    }

    func deleteTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot {
        calls.append(.delete(id: id, token: token))
        return try nextResult()
    }

    func startTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot {
        calls.append(.start(id: id, token: token))
        return try nextResult()
    }

    func pauseTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot {
        calls.append(.pause(id: id, token: token))
        return try nextResult()
    }

    func completeTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot {
        calls.append(.complete(id: id, token: token))
        return try nextResult()
    }

    private func nextResult() throws -> CloudTodoSnapshot {
        guard !results.isEmpty else {
            throw TestCloudTodoError.unexpectedCall
        }
        return try results.removeFirst().get()
    }
}

private enum TestCloudTodoError: Error {
    case unexpectedCall
}
