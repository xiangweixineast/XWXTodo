import Foundation
import Combine

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var todos: [TodoItem]
    @Published private(set) var errorMessage: String?

    private let repository: TodoRepository
    private let now: () -> Date

    init(repository: TodoRepository, now: @escaping () -> Date = Date.init) throws {
        self.repository = repository
        self.now = now
        self.todos = []
        try reload()
    }

    var activeTodos: [TodoItem] {
        todos
            .filter { $0.status != .completed }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.createdAt < $1.createdAt
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    var completedTodos: [TodoItem] {
        todos
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var doingTodo: TodoItem? {
        activeTodos.first { $0.status == .doing }
    }

    var collapsedNotchTitle: String {
        if let doingTodo {
            return doingTodo.title
        }

        let pendingCount = todos.filter { $0.status == .pending }.count
        if pendingCount > 0 {
            return "尚有\(pendingCount)项待办事项"
        }

        return "牛!全干完了!"
    }

    func reload() throws {
        do {
            todos = try repository.loadAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func addTodo(title: String) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let timestamp = now()
        let sortOrder = (todos.map(\.sortOrder).max() ?? -1) + 1
        let item = TodoItem(
            id: UUID(),
            title: trimmedTitle,
            status: .pending,
            createdAt: timestamp,
            updatedAt: timestamp,
            completedAt: nil,
            sortOrder: sortOrder
        )

        do {
            try repository.insert(item)
            try reload()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func editTodo(id: UUID, title: String) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard var item = todos.first(where: { $0.id == id }) else { return }
        guard item.status != .completed else { return }

        item.title = trimmedTitle
        item.updatedAt = now()

        do {
            try repository.update(item)
            try reload()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func deleteTodo(id: UUID) throws {
        guard let item = todos.first(where: { $0.id == id }) else { return }
        guard item.status != .completed else { return }

        do {
            try repository.delete(id: id)
            try reload()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func startTodo(id: UUID) throws {
        guard todos.contains(where: { $0.id == id && $0.status != .completed }) else { return }

        do {
            try repository.setDoing(id: id, updatedAt: now())
            try reload()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func pauseTodo(id: UUID) throws {
        guard todos.contains(where: { $0.id == id && $0.status == .doing }) else { return }

        do {
            try repository.setPending(id: id, updatedAt: now())
            try reload()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func completeTodo(id: UUID) throws {
        guard todos.contains(where: { $0.id == id && $0.status != .completed }) else { return }

        do {
            try repository.complete(id: id, completedAt: now())
            try reload()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}
