import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case noData
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL 无效"
        case .invalidResponse: return "响应无效"
        case .httpError(let code): return "HTTP 错误 (\(code))"
        case .noData: return "无返回数据"
        case .decodingFailed(let msg): return "解析失败: \(msg)"
        }
    }
}

/// 网络请求封装：URLSession + Basic Auth + 任意编码兜底
final class NetworkManager {
    static let shared = NetworkManager()

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = true
        cfg.httpAdditionalHeaders = [
            "User-Agent": "MyTVBox/1.0 (iOS)"
        ]
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - 公共接口

    /// 发起请求并返回原始 Data
    func data(from urlString: String, timeout: TimeInterval? = nil) async throws -> Data {
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        let request = makeRequest(url: url, timeout: timeout)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return data
    }

    /// 发起请求并解析为字符串（多编码兜底）
    func string(from urlString: String, timeout: TimeInterval? = nil) async throws -> String {
        let data = try await data(from: urlString, timeout: timeout)
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .gbk) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        throw NetworkError.decodingFailed("无法识别字符编码")
    }

    /// JSON Decode 到指定类型
    func decode<T: Decodable>(_ type: T.Type, from urlString: String, timeout: TimeInterval? = nil) async throws -> T {
        let data = try await data(from: urlString, timeout: timeout)
        return try decodeJSON(type, data: data)
    }

    /// 数据 → JSON 对象（容错处理 BOM、注释、尾随逗号）
    func decodeJSON<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        let cleaned = sanitizeJSONData(data)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: cleaned)
        } catch {
            // 尝试 GBK -> UTF-8 二次解析
            if let gbk = String(data: cleaned, encoding: .gbk),
               let reEncoded = gbk.data(using: .utf8) {
                return try decoder.decode(T.self, from: reEncoded)
            }
            throw NetworkError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - 内部

    private func makeRequest(url: URL, timeout: TimeInterval?) -> URLRequest {
        var request: URLRequest
        // 处理 Basic Auth: user:pass@host
        if let user = url.user, let pass = url.password {
            // 重建去掉认证信息的 URL
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.user = nil
            comps?.password = nil
            let cleanURL = comps?.url ?? url
            request = URLRequest(url: cleanURL)
            let authStr = "\(user):\(pass)"
            if let token = authStr.data(using: .utf8)?.base64EncodedString() {
                request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
            }
        } else {
            request = URLRequest(url: url)
        }
        if let timeout = timeout {
            request.timeoutInterval = timeout
        }
        request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.httpError(http.statusCode)
        }
    }

    /// 去除 BOM、JS 风格注释、尾随逗号等常见非标准 JSON 内容
    private func sanitizeJSONData(_ data: Data) -> Data {
        guard var s = String(data: data, encoding: .utf8) else {
            return data
        }
        // 去除 BOM
        if s.hasPrefix("\u{FEFF}") {
            s.removeFirst()
        }
        // 去除单行 // 注释
        s = s.replacingOccurrences(
            of: "(?m)^\\s*//.*$",
            with: "",
            options: .regularExpression
        )
        // 去除 /* */ 块注释
        s = s.replacingOccurrences(
            of: "/\\*[\\s\\S]*?\\*/",
            with: "",
            options: .regularExpression
        )
        // 去除尾随逗号: ,}  ,]
        s = s.replacingOccurrences(
            of: ",(\\s*[}\\]])",
            with: "$1",
            options: .regularExpression
        )
        return s.data(using: .utf8) ?? data
    }
}

// MARK: - String.Encoding GBK 扩展

extension String.Encoding {
    static let gbk: String.Encoding = {
        let cf = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }()
}
