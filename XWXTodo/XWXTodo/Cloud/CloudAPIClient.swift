import Foundation

/// 云同步 HTTP 客户端，只负责请求、解码和错误映射。
final class CloudAPIClient {
    static let productionBaseURL = URL(string: "https://xwxai.cn/xwxtodo/api/v1")!

    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseURL: URL = CloudAPIClient.productionBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.encoder = JSONEncoder()

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = CloudDateParser.parse(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid date: \(value)"
                )
            }
            return date
        }
        self.decoder = decoder
    }

    func login(username: String, password: String) async throws -> CloudSession {
        try await send(
            method: "POST",
            path: "auth/login",
            body: LoginRequest(username: username, password: password)
        )
    }

    func logout(token: String) async throws {
        try await sendVoid(
            method: "POST",
            path: "auth/logout",
            token: token
        )
    }

    func me(token: String) async throws -> CloudSession {
        let response: MeResponse = try await send(
            method: "GET",
            path: "auth/me",
            token: token
        )
        return response.session(token: token)
    }

    func getTodos(token: String) async throws -> CloudTodoSnapshot {
        try await send(method: "GET", path: "todos", token: token)
    }

    func addTodo(title: String, token: String) async throws -> CloudTodoSnapshot {
        try await send(
            method: "POST",
            path: "todos",
            token: token,
            body: TodoTitleRequest(title: title)
        )
    }

    func editTodo(id: UUID, title: String, token: String) async throws -> CloudTodoSnapshot {
        try await send(
            method: "PATCH",
            path: "todos/\(id.uuidString)",
            token: token,
            body: TodoTitleRequest(title: title)
        )
    }

    func deleteTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot {
        try await send(
            method: "DELETE",
            path: "todos/\(id.uuidString)",
            token: token
        )
    }

    func startTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot {
        try await send(
            method: "POST",
            path: "todos/\(id.uuidString)/start",
            token: token
        )
    }

    func pauseTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot {
        try await send(
            method: "POST",
            path: "todos/\(id.uuidString)/pause",
            token: token
        )
    }

    func completeTodo(id: UUID, token: String) async throws -> CloudTodoSnapshot {
        try await send(
            method: "POST",
            path: "todos/\(id.uuidString)/complete",
            token: token
        )
    }

    private func send<Response: Decodable, Body: Encodable>(
        method: String,
        path: String,
        token: String? = nil,
        body: Body
    ) async throws -> Response {
        let bodyData = try encode(body)
        return try await send(method: method, path: path, token: token, bodyData: bodyData)
    }

    private func send<Response: Decodable>(
        method: String,
        path: String,
        token: String? = nil
    ) async throws -> Response {
        try await send(method: method, path: path, token: token, bodyData: nil)
    }

    private func send<Response: Decodable>(
        method: String,
        path: String,
        token: String?,
        bodyData: Data?
    ) async throws -> Response {
        let (data, _) = try await perform(method: method, path: path, token: token, bodyData: bodyData)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw CloudAPIError.decoding(error.localizedDescription)
        }
    }

    private func sendVoid(
        method: String,
        path: String,
        token: String? = nil
    ) async throws {
        _ = try await perform(method: method, path: path, token: token, bodyData: nil)
    }

    private func perform(
        method: String,
        path: String,
        token: String?,
        bodyData: Data?
    ) async throws -> (Data, HTTPURLResponse) {
        let request = try makeRequest(method: method, path: path, token: token, bodyData: bodyData)
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CloudAPIError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw apiError(statusCode: httpResponse.statusCode, data: data)
        }

        return (data, httpResponse)
    }

    private func makeRequest(
        method: String,
        path: String,
        token: String?,
        bodyData: Data?
    ) throws -> URLRequest {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = baseURL.appendingPathComponent(cleanPath)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token {
            // token 由上层显式传入，网络层不读取或修改 Keychain。
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw CloudAPIError.encoding(error.localizedDescription)
        }
    }

    private func apiError(statusCode: Int, data: Data) -> CloudAPIError {
        let detail = (try? decoder.decode(ErrorResponse.self, from: data))?.detail

        switch statusCode {
        case 401:
            return .unauthorized
        case 404:
            return .notFound(detail)
        case 409:
            return .conflict(detail)
        case 422:
            return .validation(detail)
        default:
            return .httpStatus(statusCode, detail)
        }
    }
}

private struct LoginRequest: Encodable {
    let username: String
    let password: String
}

private struct TodoTitleRequest: Encodable {
    let title: String
}

private struct MeResponse: Decodable {
    let expiresAt: Date
    let user: CloudUser

    func session(token: String) -> CloudSession {
        CloudSession(
            token: token,
            tokenType: "bearer",
            expiresAt: expiresAt,
            user: user
        )
    }
}

private struct ErrorResponse: Decodable {
    let detail: String?

    private enum CodingKeys: String, CodingKey {
        case detail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .detail) {
            self.detail = value
        } else if let value = try? container.decode([String: String].self, forKey: .detail) {
            self.detail = value
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ",")
        } else {
            self.detail = nil
        }
    }
}
