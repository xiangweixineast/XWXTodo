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

    func testUpdatePersistsChangedTodo() throws {
        let repository = try SQLiteTodoRepository(databaseURL: makeTemporaryDatabaseURL())
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let updatedAt = createdAt.addingTimeInterval(10)
        let item = TodoItem(id: UUID(), title: "Before", status: .pending, createdAt: createdAt, updatedAt: createdAt, completedAt: nil, sortOrder: 0)
        try repository.insert(item)

        let updated = TodoItem(
            id: item.id,
            title: "After",
            status: .doing,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: nil,
            sortOrder: 2
        )
        try repository.update(updated)

        XCTAssertEqual(try repository.loadAll(), [updated])
    }

    func testDeleteRemovesActiveTodo() throws {
        let repository = try SQLiteTodoRepository(databaseURL: makeTemporaryDatabaseURL())
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = TodoItem(id: UUID(), title: "A", status: .pending, createdAt: date, updatedAt: date, completedAt: nil, sortOrder: 0)
        let second = TodoItem(id: UUID(), title: "B", status: .pending, createdAt: date, updatedAt: date, completedAt: nil, sortOrder: 1)
        try repository.insert(first)
        try repository.insert(second)

        try repository.delete(id: first.id)

        XCTAssertEqual(try repository.loadAll(), [second])
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

    func testSetDoingMissingIDThrowsAndLeavesExistingDoingUnchanged() throws {
        let repository = try SQLiteTodoRepository(databaseURL: makeTemporaryDatabaseURL())
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let doingAt = date.addingTimeInterval(1)
        let failedAt = date.addingTimeInterval(2)
        let item = TodoItem(id: UUID(), title: "A", status: .pending, createdAt: date, updatedAt: date, completedAt: nil, sortOrder: 0)
        try repository.insert(item)
        try repository.setDoing(id: item.id, updatedAt: doingAt)

        XCTAssertThrowsError(try repository.setDoing(id: UUID(), updatedAt: failedAt))

        let reloaded = try XCTUnwrap(repository.loadAll().first)
        XCTAssertEqual(reloaded.status, .doing)
        XCTAssertEqual(reloaded.updatedAt, doingAt)
    }

    func testSetDoingCompletedIDThrowsAndLeavesExistingDoingUnchanged() throws {
        let repository = try SQLiteTodoRepository(databaseURL: makeTemporaryDatabaseURL())
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let doingAt = date.addingTimeInterval(1)
        let completedAt = date.addingTimeInterval(2)
        let failedAt = date.addingTimeInterval(3)
        let doing = TodoItem(id: UUID(), title: "A", status: .pending, createdAt: date, updatedAt: date, completedAt: nil, sortOrder: 0)
        let completed = TodoItem(id: UUID(), title: "B", status: .pending, createdAt: date, updatedAt: date, completedAt: nil, sortOrder: 1)
        try repository.insert(doing)
        try repository.insert(completed)
        try repository.setDoing(id: doing.id, updatedAt: doingAt)
        try repository.complete(id: completed.id, completedAt: completedAt)

        XCTAssertThrowsError(try repository.setDoing(id: completed.id, updatedAt: failedAt))

        let todos = try repository.loadAll()
        let reloadedDoing = try XCTUnwrap(todos.first { $0.id == doing.id })
        let reloadedCompleted = try XCTUnwrap(todos.first { $0.id == completed.id })
        XCTAssertEqual(reloadedDoing.status, .doing)
        XCTAssertEqual(reloadedDoing.updatedAt, doingAt)
        XCTAssertEqual(reloadedCompleted.status, .completed)
        XCTAssertEqual(reloadedCompleted.completedAt, completedAt)
    }

    func testCompleteAlreadyCompletedItemDoesNotRewriteTimestamps() throws {
        let repository = try SQLiteTodoRepository(databaseURL: makeTemporaryDatabaseURL())
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let firstCompletedAt = date.addingTimeInterval(1)
        let secondCompletedAt = date.addingTimeInterval(2)
        let item = TodoItem(id: UUID(), title: "A", status: .pending, createdAt: date, updatedAt: date, completedAt: nil, sortOrder: 0)
        try repository.insert(item)
        try repository.complete(id: item.id, completedAt: firstCompletedAt)

        try repository.complete(id: item.id, completedAt: secondCompletedAt)

        let reloaded = try XCTUnwrap(repository.loadAll().first)
        XCTAssertEqual(reloaded.status, .completed)
        XCTAssertEqual(reloaded.completedAt, firstCompletedAt)
        XCTAssertEqual(reloaded.updatedAt, firstCompletedAt)
    }
}
