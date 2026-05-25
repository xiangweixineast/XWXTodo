import Foundation

/// 云端 TODO 快照的本地缓存，只保存最近一次成功同步的 TODO 列表。
protocol TodoSnapshotCache {
    func loadTodos() throws -> [TodoItem]
    func replaceTodos(with todos: [TodoItem]) throws
    func clearTodos() throws
}
