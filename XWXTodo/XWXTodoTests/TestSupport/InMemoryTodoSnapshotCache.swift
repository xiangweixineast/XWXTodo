import Foundation
@testable import XWXTodo

final class InMemoryTodoSnapshotCache: TodoSnapshotCache {
    private var items: [TodoItem]

    init(items: [TodoItem] = []) {
        self.items = items
    }

    func loadTodos() throws -> [TodoItem] {
        items
    }

    func replaceTodos(with todos: [TodoItem]) throws {
        items = todos
    }

    func clearTodos() throws {
        items = []
    }
}
