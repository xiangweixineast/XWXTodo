import Foundation

/// 云端账号快照，供登录恢复和状态展示使用。
struct CloudUser: Equatable, Decodable {
    let id: UUID
    let username: String
    let currentRevision: Int
}

/// 云端登录会话，token 由调用方决定是否持久化。
struct CloudSession: Equatable, Decodable {
    let token: String
    let tokenType: String
    let expiresAt: Date
    let user: CloudUser
}

/// 云端 TODO 记录，字段对应服务端快照。
struct CloudTodo: Equatable, Decodable {
    let id: UUID
    let title: String
    let status: TodoStatus
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
    let sortOrder: Int

    /// 将云端 TODO 转为本地领域模型，不产生持久化副作用。
    func todoItem() -> TodoItem {
        TodoItem(
            id: id,
            title: title,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt,
            sortOrder: sortOrder
        )
    }
}

/// 云端 TODO 快照，revision 表示账号数据版本。
struct CloudTodoSnapshot: Equatable, Decodable {
    let revision: Int
    let todos: [CloudTodo]

    func todoItems() -> [TodoItem] {
        todos.map { $0.todoItem() }
    }
}

enum CloudDateParser {
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func parse(_ value: String) -> Date? {
        // 服务端 DATETIME 没有时区后缀，客户端统一按 UTC 解释。
        if let date = parseServerUTCDate(value) {
            return date
        }

        return parseISODate(value)
    }

    private static func parseServerUTCDate(_ value: String) -> Date? {
        let parts = value.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let base = String(parts[0])
        guard base.count == 19 else {
            return nil
        }
        guard let baseDate = serverDateFormatter.date(from: base) else {
            return nil
        }

        guard parts.count == 2 else {
            return baseDate
        }

        let fractionText = parts[1].prefix(6)
        guard parts[1].allSatisfy({ $0.isNumber }) else {
            return nil
        }
        guard let microseconds = Int(fractionText.padding(toLength: 6, withPad: "0", startingAt: 0)) else {
            return nil
        }

        return baseDate.addingTimeInterval(Double(microseconds) / 1_000_000)
    }

    private static func parseISODate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static let serverDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}
