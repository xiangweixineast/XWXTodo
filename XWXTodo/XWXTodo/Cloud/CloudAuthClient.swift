import Foundation

/// 云端认证接口，便于 UI 状态机替换测试客户端。
protocol CloudAuthClient {
    func login(username: String, password: String) async throws -> CloudSession
    func me(token: String) async throws -> CloudSession
    func logout(token: String) async throws
}

/// 云端 TODO 操作接口，便于同步循环和业务操作替换测试客户端。
protocol CloudTodoClient {
    func getTodos(token: String) async throws -> CloudTodoSnapshot
    func addTodo(title: String, token: String) async throws -> CloudTodoSnapshot
    func editTodo(id: UUID, title: String, token: String) async throws -> CloudTodoSnapshot
    func deleteTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot
    func startTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot
    func pauseTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot
    func completeTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot
}

extension CloudAPIClient: CloudAuthClient {}
extension CloudAPIClient: CloudTodoClient {}
