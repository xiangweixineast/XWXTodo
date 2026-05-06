import XCTest
@testable import XWXTodo

@MainActor
final class TodoStoreTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testAddTodoTrimsTitleAndAppendsPendingItem() throws {
        let repository = InMemoryTodoRepository()
        let store = try TodoStore(repository: repository, now: { self.baseDate })

        try store.addTodo(title: "  写规格  ")

        XCTAssertEqual(store.activeTodos.count, 1)
        XCTAssertEqual(store.activeTodos[0].title, "写规格")
        XCTAssertEqual(store.activeTodos[0].status, .pending)
        XCTAssertEqual(store.notchTitle, "XWXTodo")
    }

    func testAddTodoRejectsEmptyTitle() throws {
        let store = try TodoStore(repository: InMemoryTodoRepository(), now: { self.baseDate })

        try store.addTodo(title: "   ")

        XCTAssertTrue(store.activeTodos.isEmpty)
    }

    func testStartingTodoAllowsOnlyOneDoingItem() throws {
        let store = try TodoStore(repository: InMemoryTodoRepository(), now: { self.baseDate })
        try store.addTodo(title: "A")
        try store.addTodo(title: "B")
        let first = store.activeTodos[0].id
        let second = store.activeTodos[1].id

        try store.startTodo(id: first)
        try store.startTodo(id: second)

        XCTAssertEqual(store.activeTodos.filter { $0.status == .doing }.map(\.id), [second])
        XCTAssertEqual(store.activeTodos.first { $0.id == first }?.status, .pending)
        XCTAssertEqual(store.notchTitle, "B")
    }

    func testCompleteTodoMovesItToCompletedList() throws {
        let store = try TodoStore(repository: InMemoryTodoRepository(), now: { self.baseDate })
        try store.addTodo(title: "A")
        let id = store.activeTodos[0].id

        try store.completeTodo(id: id)

        XCTAssertTrue(store.activeTodos.isEmpty)
        XCTAssertEqual(store.completedTodos.map(\.title), ["A"])
        XCTAssertEqual(store.completedTodos[0].completedAt, baseDate)
    }

    func testDeleteDoesNotDeleteCompletedTodos() throws {
        let store = try TodoStore(repository: InMemoryTodoRepository(), now: { self.baseDate })
        try store.addTodo(title: "A")
        let id = store.activeTodos[0].id
        try store.completeTodo(id: id)

        try store.deleteTodo(id: id)

        XCTAssertEqual(store.completedTodos.count, 1)
    }

    func testActiveTodosTieBreakEqualSortOrderByCreatedAtAscending() throws {
        let later = makeTodo(title: "Later", createdAt: baseDate.addingTimeInterval(10), sortOrder: 0)
        let earlier = makeTodo(title: "Earlier", createdAt: baseDate, sortOrder: 0)
        let store = try TodoStore(repository: InMemoryTodoRepository(items: [later, earlier]), now: { self.baseDate })

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
        let store = try TodoStore(repository: InMemoryTodoRepository(items: [older, newer]), now: { self.baseDate })

        XCTAssertEqual(store.completedTodos.map(\.title), ["Newer", "Older"])
    }

    func testEditTodoDoesNotEditCompletedItem() throws {
        let id = UUID()
        let completed = makeTodo(id: id, title: "Done", status: .completed, completedAt: baseDate)
        let store = try TodoStore(repository: InMemoryTodoRepository(items: [completed]), now: { self.baseDate })

        try store.editTodo(id: id, title: "Changed")

        XCTAssertEqual(store.completedTodos[0].title, "Done")
        XCTAssertEqual(store.completedTodos[0].updatedAt, baseDate)
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
