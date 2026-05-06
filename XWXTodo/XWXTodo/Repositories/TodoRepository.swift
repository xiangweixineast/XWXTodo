import Foundation

protocol TodoRepository {
    func loadAll() throws -> [TodoItem]
    func insert(_ item: TodoItem) throws
    func update(_ item: TodoItem) throws
    func delete(id: UUID) throws
    func setDoing(id: UUID, updatedAt: Date) throws
    func complete(id: UUID, completedAt: Date) throws
}
