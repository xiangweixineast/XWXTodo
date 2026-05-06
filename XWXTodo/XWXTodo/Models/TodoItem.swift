import Foundation

struct TodoItem: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var status: TodoStatus
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var sortOrder: Int
}
