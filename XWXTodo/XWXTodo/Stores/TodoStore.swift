import Foundation
import Combine

enum TodoStoreError: Error, LocalizedError, Equatable {
    case signedOut

    var errorDescription: String? {
        switch self {
        case .signedOut:
            return "请先登录云端账号"
        }
    }
}

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var todos: [TodoItem]
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentRevision: Int?

    private let repository: TodoRepository
    private let cloudTodoClient: CloudTodoClient
    private let tokenProvider: () -> String?

    init(
        repository: TodoRepository,
        cloudTodoClient: CloudTodoClient = CloudAPIClient(),
        tokenProvider: @escaping () -> String? = { nil },
        now: @escaping () -> Date = Date.init,
        loadInitialData: Bool = true
    ) throws {
        self.repository = repository
        self.cloudTodoClient = cloudTodoClient
        self.tokenProvider = tokenProvider
        self.todos = []
        self.currentRevision = nil
        if loadInitialData {
            try reload()
        }
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

    /// 用云端快照整体替换本地缓存，不更新云端 revision。
    func replaceAll(_ items: [TodoItem]) throws {
        do {
            try repository.replaceAll(items)
            try reload()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// 应用云端快照，并忽略低于当前版本的旧响应。
    @discardableResult
    func applySnapshot(_ snapshot: CloudTodoSnapshot) throws -> Bool {
        if let currentRevision, snapshot.revision < currentRevision {
            errorMessage = nil
            return false
        }

        do {
            try repository.replaceAll(snapshot.todoItems())
            try reload()
            currentRevision = snapshot.revision
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// 清空云端快照缓存，避免展示旧账号或旧网络状态的数据。
    func clear() throws {
        do {
            try repository.clear()
            try reload()
            currentRevision = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func addTodo(title: String) async throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        try await performCloudMutation { client, token in
            try await client.addTodo(title: trimmedTitle, token: token)
        }
    }

    func editTodo(id: UUID, title: String) async throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard let item = todos.first(where: { $0.id == id }) else { return }
        guard item.status != .completed else { return }

        try await performCloudMutation { client, token in
            try await client.editTodo(id: id, title: trimmedTitle, token: token)
        }
    }

    func deleteTodo(id: UUID) async throws {
        guard let item = todos.first(where: { $0.id == id }) else { return }
        guard item.status != .completed else { return }

        try await performCloudMutation { client, token in
            try await client.deleteTodo(id: id, token: token)
        }
    }

    func startTodo(id: UUID) async throws {
        guard todos.contains(where: { $0.id == id && $0.status != .completed }) else { return }

        try await performCloudMutation { client, token in
            try await client.startTodo(id: id, token: token)
        }
    }

    func pauseTodo(id: UUID) async throws {
        guard todos.contains(where: { $0.id == id && $0.status == .doing }) else { return }

        try await performCloudMutation { client, token in
            try await client.pauseTodo(id: id, token: token)
        }
    }

    func completeTodo(id: UUID) async throws {
        guard todos.contains(where: { $0.id == id && $0.status != .completed }) else { return }

        try await performCloudMutation { client, token in
            try await client.completeTodo(id: id, token: token)
        }
    }

    private func performCloudMutation(
        _ operation: (CloudTodoClient, String) async throws -> CloudTodoSnapshot
    ) async throws {
        guard let token = tokenProvider() else {
            errorMessage = TodoStoreError.signedOut.localizedDescription
            throw TodoStoreError.signedOut
        }

        do {
            let snapshot = try await operation(cloudTodoClient, token)
            try applySnapshot(snapshot)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}
