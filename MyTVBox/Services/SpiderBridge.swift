import Foundation
import JavaScriptCore
import CryptoKit

/// Spider JS 模块原生桥接层
///
/// 提供给 JavaScriptCore 运行环境的原生函数：
/// - nativeReq()       — 同步 HTTP 请求（GET/POST）
/// - nativeBase64()    — Base64 编解码
/// - nativeMd5()       — MD5 哈希
/// - nativeAesDecrypt()— AES-CBC 解密（兼容 CryptoJS 填充）
/// - console.log/warn  — 日志输出
enum SpiderBridge {

    // MARK: - HTTP 请求（同步，阻塞调用线程）

    /// 同步 HTTP 请求，桥接 axios req() 接口
    /// JS 侧调用：nativeReq(url, method, headersJSON, body)
    /// 返回 JS 对象：{ data: <JSON或string>, status: <Int>, headers: <Object> }
    static func nativeReq(url: String, method: String, headersJSON: String?, body: String?) -> [String: Any]? {
        guard let requestURL = URL(string: url) else {
            return ["data": "Invalid URL: \(url)", "status": 400] as [String: Any]
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method.uppercased()
        request.timeoutInterval = 30

        // 解析自定义 headers
        if let hdrJSON = headersJSON, let hdrData = hdrJSON.data(using: .utf8),
           let hdrs = try? JSONSerialization.jsonObject(with: hdrData) as? [String: String] {
            for (k, v) in hdrs { request.setValue(v, forHTTPHeaderField: k) }
        }

        // POST body
        if let body = body, !body.isEmpty {
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultResponse: URLResponse?
        var resultError: Error?

        URLSession.shared.dataTask(with: request) { data, resp, err in
            resultData = data
            resultResponse = resp
            resultError = err
            semaphore.signal()
        }.resume()

        let waitResult = semaphore.wait(timeout: .now() + 30)
        if waitResult == .timedOut {
            return ["data": "Request timed out", "status": 408] as [String: Any]
        }
        if let error = resultError {
            return ["data": error.localizedDescription, "status": -1] as [String: Any]
        }

        let status = (resultResponse as? HTTPURLResponse)?.statusCode ?? 200

        guard let data = resultData else {
            return ["data": "", "status": status] as [String: Any]
        }

        // 尝试解析 JSON
        if let json = try? JSONSerialization.jsonObject(with: data) {
            return ["data": json, "status": status] as [String: Any]
        }

        // 回退到字符串
        let text = String(data: data, encoding: .utf8) ?? ""
        return ["data": text, "status": status] as [String: Any]
    }

    // MARK: - Base64 编解码

    static func nativeBase64(_ input: String, decode: Bool) -> String {
        if decode {
            guard let data = Data(base64Encoded: input) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        } else {
            return Data(input.utf8).base64EncodedString()
        }
    }

    // MARK: - MD5 哈希

    static func nativeMd5(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - AES-CBC 解密（兼容 CryptoJS Pkcs7）

    /// AES-CBC 解密，密钥/IV 均为 UTF-8 字符串
    static func nativeAesDecrypt(ciphertext: String, key: String, iv: String) -> String {
        guard let cipherData = Data(base64Encoded: ciphertext),
              let keyData = key.data(using: .utf8),
              let ivData = iv.data(using: .utf8) else { return "" }

        // 裁剪到合法 AES 密钥长度（16/24/32 字节）
        let validLengths = [16, 24, 32]
        var effectiveKeyData = keyData
        if !validLengths.contains(keyData.count) {
            if let target = validLengths.first(where: { $0 >= keyData.count }) {
                effectiveKeyData = keyData.prefix(target)
            } else {
                effectiveKeyData = keyData.prefix(32)
            }
        }

        // 使用 CommonCrypto 做 AES-CBC 解密
        let bufferSize = cipherData.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var bytesDecrypted = 0

        let status = buffer.withUnsafeMutableBytes { bufferBytes in
            cipherData.withUnsafeBytes { cipherBytes in
                ivData.withUnsafeBytes { ivBytes in
                    effectiveKeyData.withUnsafeBytes { keyBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, effectiveKeyData.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress, cipherData.count,
                            bufferBytes.baseAddress, bufferSize,
                            &bytesDecrypted
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return "" }
        return String(data: buffer.prefix(bytesDecrypted), encoding: .utf8) ?? ""
    }
}
