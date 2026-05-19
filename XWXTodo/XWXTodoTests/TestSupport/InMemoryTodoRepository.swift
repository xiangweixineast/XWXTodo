import Foundation
@testable import XWXTodo

final class InMemoryTodoRepository: TodoRepository {
    private var items: [TodoItem]

    init(items: [TodoItem] = []) {
        self.items = items
    }

    func loadAll() throws -> [TodoItem] {
        items
    }

    func replaceAll(_ items: [TodoItem]) throws {
        self.items = items
    }

    func clear() throws {
        items = []
    }

    func insert(_ item: TodoItem) throws {
        items.append(item)
    }

    func update(_ item: TodoItem) throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    func delete(id: UUID) throws {
        items.removeAll { $0.id == id }
    }

    func setDoing(id: UUID, updatedAt: Date) throws {
        for index in items.indices where items[index].status == .doing {
            items[index].status = .pending
            items[index].updatedAt = updatedAt
        }

        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .doing
        items[index].updatedAt = updatedAt
    }

    func setPending(id: UUID, updatedAt: Date) throws {
        guard let index = items.firstIndex(where: { $0.id == id && $0.status == .doing }) else { return }
        items[index].status = .pending
        items[index].updatedAt = updatedAt
    }

    func complete(id: UUID, completedAt: Date) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .completed
        items[index].updatedAt = completedAt
        items[index].completedAt = completedAt
    }
}
