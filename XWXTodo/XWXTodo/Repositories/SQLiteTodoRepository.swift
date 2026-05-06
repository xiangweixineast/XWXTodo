import Foundation
import SQLite3

final class SQLiteTodoRepository: TodoRepository {
    private var database: OpaquePointer?

    convenience init() throws {
        try self.init(databaseURL: Self.defaultDatabaseURL())
    }

    init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            let message = Self.message(from: database)
            sqlite3_close(database)
            database = nil
            throw SQLiteError.openFailed(message)
        }

        do {
            try migrate()
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
    }

    static func defaultDatabaseURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("XWXTodo")
            .appendingPathComponent("xwxtodo.sqlite")
    }

    func loadAll() throws -> [TodoItem] {
        let sql = """
        SELECT id, title, status, created_at, updated_at, completed_at, sort_order
        FROM todos
        ORDER BY sort_order ASC, created_at ASC;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var items: [TodoItem] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return items
            }

            guard result == SQLITE_ROW else {
                throw SQLiteError.stepFailed(Self.message(from: database))
            }

            items.append(try todoItem(from: statement))
        }
    }

    func insert(_ item: TodoItem) throws {
        let sql = """
        INSERT INTO todos (id, title, status, created_at, updated_at, completed_at, sort_order)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        try withPreparedStatement(sql) { statement in
            try bind(item, to: statement)
            try stepDone(statement)
        }
    }

    func update(_ item: TodoItem) throws {
        let sql = """
        UPDATE todos
        SET title = ?, status = ?, created_at = ?, updated_at = ?, completed_at = ?, sort_order = ?
        WHERE id = ?;
        """
        try withPreparedStatement(sql) { statement in
            try bindText(item.title, to: statement, at: 1)
            try bindText(item.status.rawValue, to: statement, at: 2)
            try bindDate(item.createdAt, to: statement, at: 3)
            try bindDate(item.updatedAt, to: statement, at: 4)
            try bindOptionalDate(item.completedAt, to: statement, at: 5)
            try bindInt(item.sortOrder, to: statement, at: 6)
            try bindText(item.id.uuidString, to: statement, at: 7)
            try stepDone(statement)
        }
    }

    func delete(id: UUID) throws {
        let sql = "DELETE FROM todos WHERE id = ? AND status <> 'completed';"
        try withPreparedStatement(sql) { statement in
            try bindText(id.uuidString, to: statement, at: 1)
            try stepDone(statement)
        }
    }

    func setDoing(id: UUID, updatedAt: Date) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try withPreparedStatement("UPDATE todos SET status = 'pending', updated_at = ? WHERE status = 'doing';") { statement in
                try bindDate(updatedAt, to: statement, at: 1)
                try stepDone(statement)
            }

            try withPreparedStatement("UPDATE todos SET status = 'doing', updated_at = ? WHERE id = ? AND status <> 'completed';") { statement in
                try bindDate(updatedAt, to: statement, at: 1)
                try bindText(id.uuidString, to: statement, at: 2)
                try stepDone(statement)
                guard sqlite3_changes(database) == 1 else {
                    throw SQLiteError.stepFailed("无法开始不存在或已完成的待办事项")
                }
            }

            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func complete(id: UUID, completedAt: Date) throws {
        let sql = """
        UPDATE todos
        SET status = 'completed', completed_at = ?, updated_at = ?
        WHERE id = ? AND status <> 'completed';
        """
        try withPreparedStatement(sql) { statement in
            try bindDate(completedAt, to: statement, at: 1)
            try bindDate(completedAt, to: statement, at: 2)
            try bindText(id.uuidString, to: statement, at: 3)
            try stepDone(statement)
        }
    }

    private func migrate() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS todos (
          id TEXT PRIMARY KEY NOT NULL,
          title TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL,
          completed_at REAL,
          sort_order INTEGER NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_todos_single_doing
        ON todos(status)
        WHERE status = 'doing';
        """

        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteError.migrationFailed(Self.message(from: database))
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteError.stepFailed(Self.message(from: database))
        }
    }

    private func withPreparedStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.prepareFailed(Self.message(from: database))
        }
        return statement
    }

    private func bind(_ item: TodoItem, to statement: OpaquePointer) throws {
        try bindText(item.id.uuidString, to: statement, at: 1)
        try bindText(item.title, to: statement, at: 2)
        try bindText(item.status.rawValue, to: statement, at: 3)
        try bindDate(item.createdAt, to: statement, at: 4)
        try bindDate(item.updatedAt, to: statement, at: 5)
        try bindOptionalDate(item.completedAt, to: statement, at: 6)
        try bindInt(item.sortOrder, to: statement, at: 7)
    }

    private func bindText(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
        let destructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, index, value, -1, destructor) == SQLITE_OK else {
            throw SQLiteError.bindFailed(Self.message(from: database))
        }
    }

    private func bindDate(_ value: Date, to statement: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_double(statement, index, value.timeIntervalSince1970) == SQLITE_OK else {
            throw SQLiteError.bindFailed(Self.message(from: database))
        }
    }

    private func bindOptionalDate(_ value: Date?, to statement: OpaquePointer, at index: Int32) throws {
        if let value {
            try bindDate(value, to: statement, at: index)
        } else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw SQLiteError.bindFailed(Self.message(from: database))
            }
        }
    }

    private func bindInt(_ value: Int, to statement: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
            throw SQLiteError.bindFailed(Self.message(from: database))
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.stepFailed(Self.message(from: database))
        }
    }

    private func todoItem(from statement: OpaquePointer) throws -> TodoItem {
        guard
            let idText = sqlite3_column_text(statement, 0),
            let titleText = sqlite3_column_text(statement, 1),
            let statusText = sqlite3_column_text(statement, 2),
            let id = UUID(uuidString: String(cString: idText)),
            let status = TodoStatus(rawValue: String(cString: statusText))
        else {
            throw SQLiteError.stepFailed("数据库中存在无法读取的待办事项")
        }

        let completedAt: Date?
        if sqlite3_column_type(statement, 5) == SQLITE_NULL {
            completedAt = nil
        } else {
            completedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
        }

        return TodoItem(
            id: id,
            title: String(cString: titleText),
            status: status,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
            completedAt: completedAt,
            sortOrder: Int(sqlite3_column_int64(statement, 6))
        )
    }

    private static func message(from database: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(database) else {
            return "未知错误"
        }
        return String(cString: message)
    }
}
