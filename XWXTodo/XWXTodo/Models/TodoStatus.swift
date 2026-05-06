import Foundation

enum TodoStatus: String, Codable, CaseIterable {
    case pending
    case doing
    case completed
}
