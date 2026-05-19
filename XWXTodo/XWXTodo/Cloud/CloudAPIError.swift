import Foundation

/// 云端 API 统一错误，供上层状态机分类处理。
enum CloudAPIError: Error, Equatable, LocalizedError {
    case transport(String)
    case invalidResponse
    case encoding(String)
    case decoding(String)
    case unauthorized
    case notFound(String?)
    case conflict(String?)
    case validation(String?)
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .transport(let message):
            return "网络请求失败：\(message)"
        case .invalidResponse:
            return "服务器响应无效"
        case .encoding(let message):
            return "请求编码失败：\(message)"
        case .decoding(let message):
            return "响应解析失败：\(message)"
        case .unauthorized:
            return "登录状态已失效"
        case .notFound(let detail):
            return detail ?? "云端数据不存在"
        case .conflict(let detail):
            return detail ?? "云端状态冲突"
        case .validation(let detail):
            return detail ?? "请求数据无效"
        case .httpStatus(let statusCode, let detail):
            if let detail {
                return "服务器错误 \(statusCode)：\(detail)"
            }
            return "服务器错误 \(statusCode)"
        }
    }
}
