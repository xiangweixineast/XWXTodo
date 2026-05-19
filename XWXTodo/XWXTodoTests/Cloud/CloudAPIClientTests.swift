import XCTest
@testable import XWXTodo

final class CloudAPIClientTests: XCTestCase {
    private let baseURL = URL(string: "https://example.test/api/v1")!
    private let token = "token-value"
    private let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let todoID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testLoginUsesExpectedRequestAndDecodesSession() async throws {
        var capturedRequest: URLRequest?
        let client = makeClient { request in
            capturedRequest = request
            return self.jsonResponse(
                for: request,
                body: """
                {
                  "token": "token-value",
                  "token_type": "bearer",
                  "expires_at": "2026-05-20T01:02:03.456789",
                  "user": {
                    "id": "\(self.userID.uuidString)",
                    "username": "alice",
                    "current_revision": 7
                  }
                }
                """
            )
        }

        let session = try await client.login(username: "alice", password: "secret")

        XCTAssertEqual(session.token, token)
        XCTAssertEqual(session.tokenType, "bearer")
        XCTAssertEqual(session.user, CloudUser(id: userID, username: "alice", currentRevision: 7))
        XCTAssertEqual(session.expiresAt.timeIntervalSince1970, utcDate(2026, 5, 20, 1, 2, 3, 456_789_000).timeIntervalSince1970, accuracy: 0.000001)

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/auth/login")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try jsonBody(from: request) as? [String: String], ["username": "alice", "password": "secret"])
    }

    func testMeUsesAuthHeaderAndBuildsSessionFromCurrentToken() async throws {
        var capturedRequest: URLRequest?
        let client = makeClient { request in
            capturedRequest = request
            return self.jsonResponse(
                for: request,
                body: """
                {
                  "expires_at": "2026-05-20T01:02:03",
                  "user": {
                    "id": "\(self.userID.uuidString)",
                    "username": "alice",
                    "current_revision": 3
                  }
                }
                """
            )
        }

        let session = try await client.me(token: token)

        XCTAssertEqual(session.token, token)
        XCTAssertEqual(session.tokenType, "bearer")
        XCTAssertEqual(session.user.currentRevision, 3)

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/v1/auth/me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertTrue(requestBody(from: request).isEmpty)
    }

    func testLogoutUsesAuthHeaderAndAcceptsNoContent() async throws {
        var capturedRequest: URLRequest?
        let client = makeClient { request in
            capturedRequest = request
            return self.emptyResponse(for: request, statusCode: 204)
        }

        try await client.logout(token: token)

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/auth/logout")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertTrue(requestBody(from: request).isEmpty)
    }

    func testTodoEndpointsUseExpectedMethodsPathsHeadersAndBodies() async throws {
        struct EndpointCase {
            let method: String
            let path: String
            let body: [String: String]?
            let action: (CloudAPIClient) async throws -> CloudTodoSnapshot
        }

        let cases = [
            EndpointCase(method: "GET", path: "/api/v1/todos", body: nil) { client in
                try await client.getTodos(token: self.token)
            },
            EndpointCase(method: "POST", path: "/api/v1/todos", body: ["title": "写代码"]) { client in
                try await client.addTodo(title: "写代码", token: self.token)
            },
            EndpointCase(method: "PATCH", path: "/api/v1/todos/\(todoID.uuidString)", body: ["title": "改标题"]) { client in
                try await client.editTodo(id: self.todoID, title: "改标题", token: self.token)
            },
            EndpointCase(method: "DELETE", path: "/api/v1/todos/\(todoID.uuidString)", body: nil) { client in
                try await client.deleteTodo(id: self.todoID, token: self.token)
            },
            EndpointCase(method: "POST", path: "/api/v1/todos/\(todoID.uuidString)/start", body: nil) { client in
                try await client.startTodo(id: self.todoID, token: self.token)
            },
            EndpointCase(method: "POST", path: "/api/v1/todos/\(todoID.uuidString)/pause", body: nil) { client in
                try await client.pauseTodo(id: self.todoID, token: self.token)
            },
            EndpointCase(method: "POST", path: "/api/v1/todos/\(todoID.uuidString)/complete", body: nil) { client in
                try await client.completeTodo(id: self.todoID, token: self.token)
            },
        ]

        for endpointCase in cases {
            var capturedRequest: URLRequest?
            let client = makeClient { request in
                capturedRequest = request
                return self.jsonResponse(for: request, body: self.snapshotJSON())
            }

            let snapshot = try await endpointCase.action(client)

            XCTAssertEqual(snapshot.revision, 9)
            let request = try XCTUnwrap(capturedRequest)
            XCTAssertEqual(request.httpMethod, endpointCase.method)
            XCTAssertEqual(request.url?.path, endpointCase.path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")

            if let body = endpointCase.body {
                XCTAssertEqual(try jsonBody(from: request) as? [String: String], body)
            } else {
                XCTAssertTrue(requestBody(from: request).isEmpty)
            }
        }
    }

    func testHTTPStatusErrorsAreMapped() async throws {
        let cases: [(Int, String, CloudAPIError)] = [
            (401, "unauthorized", .unauthorized),
            (404, "todo_not_found", .notFound("todo_not_found")),
            (409, "todo_state_conflict", .conflict("todo_state_conflict")),
            (422, "title_required", .validation("title_required")),
            (500, "server_error", .httpStatus(500, "server_error")),
        ]

        for (statusCode, detail, expectedError) in cases {
            let client = makeClient { request in
                self.jsonResponse(
                    for: request,
                    statusCode: statusCode,
                    body: #"{"detail":"\#(detail)"}"#
                )
            }

            do {
                _ = try await client.getTodos(token: token)
                XCTFail("Expected CloudAPIError for status \(statusCode)")
            } catch let error as CloudAPIError {
                XCTAssertEqual(error, expectedError)
            }
        }
    }

    func testDecodingAndTransportErrorsAreMapped() async throws {
        let invalidJSONClient = makeClient { request in
            self.jsonResponse(for: request, body: #"{"revision":"bad"}"#)
        }

        do {
            _ = try await invalidJSONClient.getTodos(token: token)
            XCTFail("Expected decoding error")
        } catch let error as CloudAPIError {
            guard case .decoding = error else {
                return XCTFail("Expected decoding error, got \(error)")
            }
        }

        let transportClient = makeClient { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            _ = try await transportClient.getTodos(token: token)
            XCTFail("Expected transport error")
        } catch let error as CloudAPIError {
            guard case .transport(let message) = error else {
                return XCTFail("Expected transport error, got \(error)")
            }
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testDateDecodingAndTodoItemMapping() async throws {
        let client = makeClient { request in
            self.jsonResponse(
                for: request,
                body: """
                {
                  "revision": 9,
                  "todos": [
                    {
                      "id": "\(self.todoID.uuidString)",
                      "title": "完成 T07",
                      "status": "completed",
                      "created_at": "2026-05-20T01:02:03.456789",
                      "updated_at": "2026-05-20T01:02:04",
                      "completed_at": "2026-05-20T01:02:04",
                      "sort_order": 4
                    }
                  ]
                }
                """
            )
        }

        let snapshot = try await client.getTodos(token: token)

        let todo = try XCTUnwrap(snapshot.todos.first)
        XCTAssertEqual(todo.id, todoID)
        XCTAssertEqual(todo.title, "完成 T07")
        XCTAssertEqual(todo.status, .completed)
        XCTAssertEqual(todo.createdAt.timeIntervalSince1970, utcDate(2026, 5, 20, 1, 2, 3, 456_789_000).timeIntervalSince1970, accuracy: 0.000001)
        XCTAssertEqual(todo.updatedAt, utcDate(2026, 5, 20, 1, 2, 4))
        XCTAssertEqual(todo.completedAt, utcDate(2026, 5, 20, 1, 2, 4))

        let item = todo.todoItem()
        XCTAssertEqual(item.id, todo.id)
        XCTAssertEqual(item.title, todo.title)
        XCTAssertEqual(item.status, todo.status)
        XCTAssertEqual(item.sortOrder, 4)
        XCTAssertEqual(snapshot.todoItems(), [item])
    }

    private func makeClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> CloudAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestHandler = handler
        return CloudAPIClient(baseURL: baseURL, session: URLSession(configuration: configuration))
    }

    private func snapshotJSON() -> String {
        """
        {
          "revision": 9,
          "todos": [
            {
              "id": "\(todoID.uuidString)",
              "title": "写代码",
              "status": "pending",
              "created_at": "2026-05-20T01:02:03",
              "updated_at": "2026-05-20T01:02:03",
              "completed_at": null,
              "sort_order": 0
            }
          ]
        }
        """
    }

    private func jsonResponse(
        for request: URLRequest,
        statusCode: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private func emptyResponse(
        for request: URLRequest,
        statusCode: Int
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data())
    }

    private func jsonBody(from request: URLRequest) throws -> Any {
        try JSONSerialization.jsonObject(with: requestBody(from: request))
    }

    private func requestBody(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }

    private func utcDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int,
        _ nanosecond: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = nanosecond
        return components.date!
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
