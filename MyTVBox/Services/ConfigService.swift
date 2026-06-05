import Foundation

/// 配置下载与解析服务
final class ConfigService {
    static let shared = ConfigService()

    private let network = NetworkManager.shared

    private init() {}

    /// 从给定 URL 下载并解析 TVBox / 猫爪 JSON 配置
    /// - 支持 .md5 后缀（先尝试直接获取，若返回内容是 32 位 md5 则去掉 .md5 重新请求）
    /// - 支持 URL 内嵌 Basic Auth: http://user:pass@host/path
    func loadConfig(from urlString: String) async throws -> TVBoxConfig {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NetworkError.invalidURL }

        // 第一步：尝试直接请求
        let primaryData = try await network.data(from: trimmed)
        if let cfg = try? decode(primaryData) {
            return cfg
        }

        // 第二步：检查是否是纯 md5 字符串
        if let text = String(data: primaryData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           isMD5Hash(text), trimmed.lowercased().hasSuffix(".md5") {
            // 去掉 .md5 重新请求
            let realURL = String(trimmed.dropLast(4))
            let realData = try await network.data(from: realURL)
            if let cfg = try? decode(realData) {
                return cfg
            }
        }

        // 第三步：若 url 以 .md5 结尾但内容不是 md5，也尝试去掉后缀
        if trimmed.lowercased().hasSuffix(".md5") {
            let realURL = String(trimmed.dropLast(4))
            let realData = try await network.data(from: realURL)
            return try decode(realData)
        }

        // 兜底：再次解析（抛出真实错误）
        return try decode(primaryData)
    }

    // MARK: - 工具

    private func decode(_ data: Data) throws -> TVBoxConfig {
        return try network.decodeJSON(TVBoxConfig.self, data: data)
    }

    private func isMD5Hash(_ s: String) -> Bool {
        guard s.count == 32 else { return false }
        let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return s.unicodeScalars.allSatisfy { hexSet.contains($0) }
    }
}
