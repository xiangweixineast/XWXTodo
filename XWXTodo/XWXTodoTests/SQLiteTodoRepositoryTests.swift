import XCTest
@testable import XWXTodo

final class SQLiteTodoRepositoryTests: XCTestCase {
    private func makeTemporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
    }

    func testInitializesEmptyDatabase() throws {
        let repository = try SQLiteTodoRepository(databaseURL: makeTemporaryDatabaseURL())
        XCTAssertEqual(try repository.loadAll(), [])
    }

    func testPersistsInsertedTodoAcrossRepositoryInstances() throws {
        let url = makeTemporaryDatabaseURL()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let item = TodoItem(id: UUID(), title: "写代码", status: .pending, createdAt: createdAt, updatedAt: createdAt, completedAt: nil, sortOrder: 0)

        try SQLiteTodoRepository(databaseURL: url).insert(item)
        let reloaded = try SQLiteTodoRepository(databaseURL: url).loadAll()

        XCTAssertEqual(reloaded, [item])
    }

    func testSetDoingIsTransactionalAndLeavesOnlyOneDoing() throws {
        let repository = try SQLiteTodoRepository(databaseURL: makeTemporaryDatabaseURL())
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = TodoItem(id: UUID(), title: "A", status: .pending, createdAt: date, updatedAt: date, completedAt: nil, sortOrder: 0)
        let second = TodoItem(id: UUID(), title: "B", status: .pending, createdAt: date, updatedAt: date, completedAt: nil, sortOrder: 1)
        try repository.insert(first)
        try repository.insert(second)

        try repository.setDoing(id: first.id, updatedAt: date.addingTimeInterval(1))
        try repository.setDoing(id: second.id, updatedAt: date.addingTimeInterval(2))

        let todos = try repository.loadAll()
        XCTAssertEqual(todos.filter { $0.status == .doing }.map(\.id), [second.id])
        XCTAssertEqual(todos.first { $0.id == first.id }?.status, .pending)
    }

    func testCompleteWritesCompletedAtAndSortsViaStoreLater() throws {
        let repository = try SQLiteTodoRepository(databaseURL: makeTemporaryDatabaseURL())
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let completedAt = createdAt.addingTimeInterval(10)
        let item = TodoItem(id: UUID(), title: "A", status: .pending, createdAt: createdAt, updatedAt: createdAt, completedAt: nil, sortOrder: 0)
        try repository.insert(item)

        try repository.complete(id: item.id, completedAt: completedAt)

        let completed = try XCTUnwrap(repository.loadAll().first)
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.completedAt, completedAt)
    }
}
