import XCTest
@testable import XWXTodo

final class SQLiteTodoSnapshotCacheTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeTemporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
    }

    func testInitializesEmptyDatabase() throws {
        let cache = try SQLiteTodoSnapshotCache(databaseURL: makeTemporaryDatabaseURL())
        XCTAssertEqual(try cache.loadTodos(), [])
    }

    func testReplaceTodosDeletesOldTodosAndPersistsSnapshot() throws {
        let cache = try SQLiteTodoSnapshotCache(databaseURL: makeTemporaryDatabaseURL())
        let old = makeTodo(title: "Old")
        let snapshot = makeTodo(title: "Cloud", status: .doing, sortOrder: 2)
        try cache.replaceTodos(with: [old])

        try cache.replaceTodos(with: [snapshot])

        XCTAssertEqual(try cache.loadTodos(), [snapshot])
    }

    func testReplaceTodosWithEmptySnapshotClearsTodos() throws {
        let cache = try SQLiteTodoSnapshotCache(databaseURL: makeTemporaryDatabaseURL())
        let item = makeTodo(title: "A")
        try cache.replaceTodos(with: [item])

        try cache.replaceTodos(with: [])

        XCTAssertEqual(try cache.loadTodos(), [])
    }

    func testClearTodosRemovesAllTodos() throws {
        let cache = try SQLiteTodoSnapshotCache(databaseURL: makeTemporaryDatabaseURL())
        let item = makeTodo(title: "A")
        try cache.replaceTodos(with: [item])

        try cache.clearTodos()

        XCTAssertEqual(try cache.loadTodos(), [])
    }

    func testPersistsSnapshotAcrossCacheInstances() throws {
        let url = makeTemporaryDatabaseURL()
        let item = makeTodo(title: "写代码")

        try SQLiteTodoSnapshotCache(databaseURL: url).replaceTodos(with: [item])
        let reloaded = try SQLiteTodoSnapshotCache(databaseURL: url).loadTodos()

        XCTAssertEqual(reloaded, [item])
    }

    func testLoadTodosSortsBySortOrderThenCreatedAt() throws {
        let cache = try SQLiteTodoSnapshotCache(databaseURL: makeTemporaryDatabaseURL())
        let later = makeTodo(title: "Later", createdAt: baseDate.addingTimeInterval(10), sortOrder: 0)
        let earlier = makeTodo(title: "Earlier", createdAt: baseDate, sortOrder: 0)
        let second = makeTodo(title: "Second", createdAt: baseDate, sortOrder: 1)

        try cache.replaceTodos(with: [second, later, earlier])

        XCTAssertEqual(try cache.loadTodos(), [earlier, later, second])
    }

    func testReplaceTodosRollsBackInvalidSnapshotWithMultipleDoingTodos() throws {
        let cache = try SQLiteTodoSnapshotCache(databaseURL: makeTemporaryDatabaseURL())
        let old = makeTodo(title: "Old")
        let firstDoing = makeTodo(title: "A", status: .doing)
        let secondDoing = makeTodo(title: "B", status: .doing, sortOrder: 1)
        try cache.replaceTodos(with: [old])

        XCTAssertThrowsError(try cache.replaceTodos(with: [firstDoing, secondDoing]))
        XCTAssertEqual(try cache.loadTodos(), [old])
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
