import Foundation
import Security

/// 云同步会话存储，只持久化 bearer token。
protocol CloudSessionStore {
    func saveToken(_ token: String) throws
    func loadToken() throws -> String?
    func deleteToken() throws
}

enum KeychainSessionStoreError: Error, Equatable, LocalizedError {
    case invalidTokenData
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidTokenData:
            return "Keychain 中的 token 数据无效"
        case .unexpectedStatus(let status):
            return "Keychain 操作失败：\(status)"
        }
    }
}

/// 基于 macOS Keychain 的 token 存储实现。
final class KeychainSessionStore: CloudSessionStore {
    private let service: String
    private let account: String

    init(
        service: String = "com.komavideo.XWXTodo.cloud-session",
        account: String = "bearer-token"
    ) {
        self.service = service
        self.account = account
    }

    func saveToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainSessionStoreError.invalidTokenData
        }

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            return
        }

        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery() as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainSessionStoreError.unexpectedStatus(updateStatus)
            }
            return
        }

        throw KeychainSessionStoreError.unexpectedStatus(status)
    }

    func loadToken() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainSessionStoreError.unexpectedStatus(status)
        }
        guard
            let data = result as? Data,
            let token = String(data: data, encoding: .utf8)
        else {
            throw KeychainSessionStoreError.invalidTokenData
        }

        return token
    }

    func deleteToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSessionStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        // service/account 隔离正式凭据与测试凭据。
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
