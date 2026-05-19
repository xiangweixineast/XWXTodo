import Foundation

/// 云端认证接口，便于 UI 状态机替换测试客户端。
protocol CloudAuthClient {
    func login(username: String, password: String) async throws -> CloudSession
    func me(token: String) async throws -> CloudSession
    func logout(token: String) async throws
}

extension CloudAPIClient: CloudAuthClient {}
