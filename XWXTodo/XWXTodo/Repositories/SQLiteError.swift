import Foundation

enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "数据库打开失败：\(message)"
        case .prepareFailed(let message): return "SQL 准备失败：\(message)"
        case .stepFailed(let message): return "SQL 执行失败：\(message)"
        case .bindFailed(let message): return "SQL 参数绑定失败：\(message)"
        case .migrationFailed(let message): return "数据库迁移失败：\(message)"
        }
    }
}
