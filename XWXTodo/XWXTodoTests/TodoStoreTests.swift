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
        XCTAssertEqual(store.collapsedNotchTitle, "尚有1项待办事项")
    }

    func testAddTodoRejectsEmptyTitle() throws {
        let store = try TodoStore(repository: InMemoryTodoRepository(), now: { self.baseDate })

        try store.addTodo(title: "   ")

        XCTAssertTrue(store.activeTodos.isEmpty)
    }

    func testCollapsedNotchTitleShowsDoneMessageWhenNoActiveTodos() throws {
        let store = try TodoStore(repository: InMemoryTodoRepository(), now: { self.baseDate })

        XCTAssertEqual(store.notchTitle, "XWXTodo")
        XCTAssertEqual(store.collapsedNotchTitle, "牛!全干完了!")
    }

    func testCollapsedNotchTitleShowsPendingCountWhenNoDoingTodo() throws {
        let first = makeTodo(title: "A", sortOrder: 0)
        let second = makeTodo(title: "B", sortOrder: 1)
        let completed = makeTodo(title: "C", status: .completed, completedAt: baseDate, sortOrder: 2)
        let store = try TodoStore(
            repository: InMemoryTodoRepository(items: [first, second, completed]),
            now: { self.baseDate }
        )

        XCTAssertEqual(store.notchTitle, "XWXTodo")
        XCTAssertEqual(store.collapsedNotchTitle, "尚有2项待办事项")
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
        XCTAssertEqual(store.collapsedNotchTitle, "B")
    }

    func testPauseTodoMovesDoingItemBackToPending() throws {
        let pausedAt = baseDate.addingTimeInterval(10)
        let id = UUID()
        let doing = makeTodo(id: id, title: "A", status: .doing)
        let store = try TodoStore(repository: InMemoryTodoRepository(items: [doing]), now: { pausedAt })

        try store.pauseTodo(id: id)

        let reloaded = try XCTUnwrap(store.activeTodos.first { $0.id == id })
        XCTAssertEqual(reloaded.status, .pending)
        XCTAssertEqual(reloaded.updatedAt, pausedAt)
        XCTAssertNil(store.doingTodo)
        XCTAssertEqual(store.notchTitle, "XWXTodo")
        XCTAssertEqual(store.collapsedNotchTitle, "尚有1项待办事项")
    }

    func testPauseTodoDoesNotMutatePendingOrCompletedItems() throws {
        let pendingID = UUID()
        let completedID = UUID()
        let pending = makeTodo(id: pendingID, title: "Pending", updatedAt: baseDate)
        let completed = makeTodo(
            id: completedID,
            title: "Done",
            status: .completed,
            updatedAt: baseDate,
            completedAt: baseDate
        )
        let store = try TodoStore(
            repository: InMemoryTodoRepository(items: [pending, completed]),
            now: { self.baseDate.addingTimeInterval(10) }
        )

        try store.pauseTodo(id: pendingID)
        try store.pauseTodo(id: completedID)

        XCTAssertEqual(store.activeTodos[0].status, .pending)
        XCTAssertEqual(store.activeTodos[0].updatedAt, baseDate)
        XCTAssertEqual(store.completedTodos[0].status, .completed)
        XCTAssertEqual(store.completedTodos[0].updatedAt, baseDate)
        XCTAssertEqual(store.completedTodos[0].completedAt, baseDate)
    }

    func testCompleteTodoMovesItToCompletedList() throws {
        let store = try TodoStore(repository: InMemoryTodoRepository(), now: { self.baseDate })
        try store.addTodo(title: "A")
        let id = store.activeTodos[0].id

        try store.completeTodo(id: id)

        XCTAssertTrue(store.activeTodos.isEmpty)
        XCTAssertEqual(store.completedTodos.map(\.title), ["A"])
        XCTAssertEqual(store.completedTodos[0].completedAt, baseDate)
        XCTAssertEqual(store.collapsedNotchTitle, "牛!全干完了!")
    }

    func testDeleteDoesNotDeleteCompletedTodos() throws {
        let store = try TodoStore(repository: InMemoryTodoRepository(), now: { self.baseDate })
        try store.addTodo(title: "A")
        let id = store.activeTodos[0].id
        try store.completeTodo(id: id)

        try store.deleteTodo(id: id)

        XCTAssertEqual(store.completedTodos.count, 1)
    }

    func testEditTodoTrimsActiveTitleAndUpdatesTimestamp() throws {
        let id = UUID()
        let editedAt = baseDate.addingTimeInterval(10)
        let item = makeTodo(id: id, title: "Original")
        let store = try TodoStore(repository: InMemoryTodoRepository(items: [item]), now: { editedAt })

        try store.editTodo(id: id, title: "  Changed  ")

        XCTAssertEqual(store.activeTodos[0].title, "Changed")
        XCTAssertEqual(store.activeTodos[0].updatedAt, editedAt)
    }

    func testDeleteTodoRemovesActiveTodo() throws {
        let firstID = UUID()
        let secondID = UUID()
        let first = makeTodo(id: firstID, title: "A", sortOrder: 0)
        let second = makeTodo(id: secondID, title: "B", sortOrder: 1)
        let store = try TodoStore(repository: InMemoryTodoRepository(items: [first, second]), now: { self.baseDate })

        try store.deleteTodo(id: firstID)

        XCTAssertEqual(store.activeTodos.map(\.id), [secondID])
        XCTAssertEqual(store.activeTodos.map(\.title), ["B"])
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

    func testStartTodoDoesNotStartCompletedItem() throws {
        let id = UUID()
        let completed = makeTodo(id: id, title: "Done", status: .completed, completedAt: baseDate)
        let store = try TodoStore(repository: InMemoryTodoRepository(items: [completed]), now: { self.baseDate })

        try store.startTodo(id: id)

        XCTAssertEqual(store.completedTodos[0].status, .completed)
        XCTAssertNil(store.doingTodo)
        XCTAssertEqual(store.notchTitle, "XWXTodo")
        XCTAssertEqual(store.collapsedNotchTitle, "牛!全干完了!")
    }

    func testCompleteTodoDoesNotMutateCompletedItem() throws {
        let id = UUID()
        let completed = makeTodo(
            id: id,
            title: "Done",
            status: .completed,
            updatedAt: baseDate,
            completedAt: baseDate
        )
        let store = try TodoStore(
            repository: InMemoryTodoRepository(items: [completed]),
            now: { self.baseDate.addingTimeInterval(10) }
        )

        try store.completeTodo(id: id)

        XCTAssertEqual(store.completedTodos[0].completedAt, baseDate)
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
