import Foundation
import JavaScriptCore
import WebKit

/// CatPaw Spider JS 模块执行引擎
///
/// 通过 JavaScriptCore 加载 esbuild 打包好的 Spider JS 模块，
/// 并提供 nativeReq / dayjs / CryptoJS 等 shims，
/// 使 .js.md5 源可在 iOS 上直接解析视频列表/详情/播放地址。
///
/// 模块接口约定（与 CatPawOpen 一致）：
/// - home()      → { class: [...], list: [...] }
/// - category()  → { page, pagecount, total, list: [...] }
/// - detail()    → { list: [{ vod_id, vod_play_url, ... }] }
/// - play()      → { url, header }
/// - search()    → { list: [...] }
final class SpiderEngine {

    static let shared = SpiderEngine()
    private init() {}

    // MARK: - 公共接口

    /// 从远程 JS 模块 URL 构建 SpiderConfig（带分类 + 视频列表）
    func buildConfig(jsURL: String, siteKey: String, siteName: String) async -> TVBoxConfig? {
        // 1. 下载 JS 模块源码
        guard let jsCode = await fetchModuleCode(jsURL: jsURL) else {
            print("[SpiderEngine] 下载模块失败: \(jsURL)")
            return nil
        }

        // 2. 创建 JSContext 并加载模块
        let context = createContext()
        guard injectModule(context: context, code: jsCode) else {
            print("[SpiderEngine] 模块加载失败")
            return nil
        }

        // 3. 调用 init()
        callMethod(context: context, name: "init", args: [])

        // 4. 调用 home() 获取分类列表
        guard let homeResult = callMethod(context: context, name: "home", args: []) else {
            print("[SpiderEngine] home() 调用失败")
            return nil
        }

        return buildTVBoxConfig(
            from: homeResult,
            context: context,
            siteKey: siteKey,
            siteName: siteName,
            jsCode: jsCode
        )
    }

    /// 执行 JS 模块并调用指定方法，返回原始 JS 结果字典
    ///
    /// - Parameters:
    ///   - jsCode: 完整 JS 代码（单模块或多 spider bundle）
    ///   - method: 调用的方法名（home / category / detail / player / search）
    ///   - args: 方法参数字典
    ///   - spiderKey: bundle 中的 spider key（多 spider bundle 时必传，用于路由）
    func execute(jsCode: String, method: String, args: [String: Any], spiderKey: String? = nil) async -> [String: Any]? {
        // 优先使用 Node.js Mobile（完整 ES2018+ 支持）
        return await NodeSpiderEngine.shared.execute(
            jsCode: jsCode, method: method, args: args, spiderKey: spiderKey
        )
    }

    // MARK: - 内部工具

    /// 将 Swift 字典转为 JSON 字符串（JS 中使用）
    private func jsonString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let str = String(data: data, encoding: .utf8) else {
            return "'\(s)'"
        }
        // JSONSerialization 输出 ["s"]，去掉 [ 和 ] 得到 "s"
        return String(str.dropFirst().dropLast())
    }

    /// 将参数字典转为 JSValue 数组
    private func buildJSArgs(args: [String: Any], context: JSContext) -> [Any] {
        if args.isEmpty { return [] }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: args),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return [NSNull()]
        }
        let jsObj = context.evaluateScript("(\(jsonString))")
        return [jsObj as Any]
    }

    /// 下载模块源码（支持 .js.md5 → 取 MD5 → 下载对应 JS 文件）
    func fetchModuleCode(jsURL: String) async -> String? {
        let network = NetworkManager.shared

        // 如果是 .js.md5，先取 MD5 再下载对应文件
        let actualURL: String
        if jsURL.lowercased().hasSuffix(".js.md5") {
            guard let md5Data = try? await network.data(from: jsURL),
                  let md5 = String(data: md5Data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let baseURL = jsURL.components(separatedBy: ".md5").first else {
                return nil
            }
            actualURL = "\(baseURL)/\(md5)"
        } else {
            actualURL = jsURL
        }

        // 尝试构造的 URL
        if let data = try? await network.data(from: actualURL),
           let code = String(data: data, encoding: .utf8),
           !code.contains("<html>") {
            return code
        }

        // Fallback：对 .js.md5 URL，尝试跟随 .js 的 302 重定向
        if jsURL.lowercased().hasSuffix(".js.md5"),
           let jsPath = jsURL.components(separatedBy: ".md5").first,
           let data = try? await network.data(from: jsPath),
           let code = String(data: data, encoding: .utf8),
           !code.contains("<html>") {
            return code
        }

        return nil
    }

    /// 创建带原生桥接的 JSContext
    private func createContext() -> JSContext {
        let context = JSContext()!
        setupConsole(context: context)
        setupDayjs(context: context)
        setupCryptoShims(context: context)
        setupReqShim(context: context)
        setupNativeBridge(context: context)
        return context
    }

    /// 注入并执行模块代码
    private func injectModule(context: JSContext, code: String) -> Bool {
        context.evaluateScript(code)
        return !context.exception.isUndefined
    }

    // MARK: - JS Shims

    private func setupConsole(context: JSContext) {
        context.evaluateScript("""
        var console = {
            log: function() {},
            warn: function() {},
            error: function() {},
            info: function() {}
        };
        """)
    }

    /// 最小化 dayjs shim —— 覆盖模块中 dayjs().valueOf() / .unix() / .format() / .subtract()
    private func setupDayjs(context: JSContext) {
        context.evaluateScript("""
        function dayjs(input) {
            var d = input ? new Date(input) : new Date();
            return {
                valueOf: function() { return d.getTime(); },
                unix: function() { return Math.floor(d.getTime() / 1000); },
                format: function(f) {
                    var pad = function(n) { return n < 10 ? '0' + n : '' + n; };
                    return f
                        .replace('YYYY', d.getFullYear())
                        .replace('MM', pad(d.getMonth() + 1))
                        .replace('DD', pad(d.getDate()))
                        .replace('HH', pad(d.getHours()))
                        .replace('mm', pad(d.getMinutes()))
                        .replace('ss', pad(d.getSeconds()));
                },
                add: function(n, unit) {
                    var nd = new Date(d);
                    if (unit === 'day' || unit === 'd') nd.setDate(nd.getDate() + n);
                    else if (unit === 'hour' || unit === 'h') nd.setHours(nd.getHours() + n);
                    else if (unit === 'minute' || unit === 'm') nd.setMinutes(nd.getMinutes() + n);
                    else if (unit === 'second' || unit === 's') nd.setSeconds(nd.getSeconds() + n);
                    else if (unit === 'month') nd.setMonth(nd.getMonth() + n);
                    else if (unit === 'year') nd.setFullYear(nd.getFullYear() + n);
                    return dayjs(nd);
                },
                subtract: function(n, unit) { return this.add(-n, unit); },
                toDate: function() { return d; }
            };
        }
        dayjs.utc = function(input) { return dayjs(input); };
        dayjs.duration = function(v, u) { return { asMilliseconds: function() { return v; } }; };
        """)
    }

    /// CryptoJS 最小化 shim（MD5 / Hex / Base64 / AES）
    private func setupCryptoShims(context: JSContext) {
        context.evaluateScript("""
        var CryptoJS = CryptoJS || {};

        // MD5
        CryptoJS.MD5 = function(s) {
            var r = nativeMd5(typeof s === 'string' ? s : s.toString());
            return { toString: function() { return r; } };
        };

        // 编码工具
        CryptoJS.enc = {
            Utf8: {
                parse: function(s) { return s; },
                stringify: function(s) { return typeof s === 'string' ? s : ''; }
            },
            Hex: {
                stringify: function(s) { return typeof s === 'string' ? s : ''; },
                parse: function(s) { return s; }
            },
            Base64: {
                stringify: function(s) { return nativeBase64(typeof s === 'string' ? s : s.toString(), false); },
                parse: function(s) { return nativeBase64(typeof s === 'string' ? s : s.toString(), true); }
            }
        };

        // AES 解密
        CryptoJS.AES = {
            decrypt: function(src, key, opts) {
                var cipherText = (typeof src === 'object' && src.ciphertext) ? nativeBase64(src.ciphertext.toString(), true) : src.toString();
                var k = typeof key === 'string' ? key : key.toString();
                var iv = (opts && opts.iv) ? (typeof opts.iv === 'string' ? opts.iv : opts.iv.toString()) : '';
                var decrypted = nativeAesDecrypt(cipherText, k, iv);
                return {
                    toString: function(enc) { return decrypted; }
                };
            }
        };

        // Pad
        CryptoJS.pad = { Pkcs7: {} };
        CryptoJS.mode = { CBC: {} };
        """)
    }

    /// axios-style req shim
    private func setupReqShim(context: JSContext) {
        context.evaluateScript("""
        function req(url, opts) {
            opts = opts || {};
            var method = (opts.method || 'get').toLowerCase();
            var headers = opts.headers || {};
            var headersJSON = JSON.stringify(headers);
            var body = null;
            if (opts.data) {
                if (typeof opts.data === 'string') {
                    body = opts.data;
                } else {
                    body = JSON.stringify(opts.data);
                    if (!headers['Content-Type']) {
                        headers['Content-Type'] = 'application/json';
                        headersJSON = JSON.stringify(headers);
                    }
                }
            }
            var result = nativeReq(url, method, headersJSON, body);
            if (typeof result === 'string') {
                try { result = JSON.parse(result); } catch(e) {}
            }
            return result;
        }
        req.get = function(url, opts) {
            opts = opts || {};
            opts.method = 'get';
            return req(url, opts);
        };
        req.post = function(url, opts) {
            opts = opts || {};
            opts.method = 'post';
            return req(url, opts);
        };
        """)
    }

    /// 注入 nativeReq / nativeBase64 / nativeMd5 / nativeAesDecrypt 桥接
    private func setupNativeBridge(context: JSContext) {
        // nativeReq
        let reqBlock: @convention(block) (String, String, String?, String?) -> [String: Any]? = { url, method, headersJSON, body in
            SpiderBridge.nativeReq(url: url, method: method, headersJSON: headersJSON, body: body)
        }
        context.setObject(reqBlock, forKeyedSubscript: "nativeReq" as NSString)

        // nativeBase64
        let b64Block: @convention(block) (String, Bool) -> String = { input, decode in
            SpiderBridge.nativeBase64(input, decode: decode)
        }
        context.setObject(b64Block, forKeyedSubscript: "nativeBase64" as NSString)

        // nativeMd5
        let md5Block: @convention(block) (String) -> String = { input in
            SpiderBridge.nativeMd5(input)
        }
        context.setObject(md5Block, forKeyedSubscript: "nativeMd5" as NSString)

        // nativeAesDecrypt
        let aesBlock: @convention(block) (String, String, String) -> String = { cipher, key, iv in
            SpiderBridge.nativeAesDecrypt(ciphertext: cipher, key: key, iv: iv)
        }
        context.setObject(aesBlock, forKeyedSubscript: "nativeAesDecrypt" as NSString)
    }

    // MARK: - JS 方法调用

    private func callMethod(context: JSContext, name: String, args: [Any]) -> [String: Any]? {
        let fn = context.objectForKeyedSubscript(name)
        guard let fn = fn, !fn.isUndefined else { return nil }

        var jsArgs: [Any] = []
        for arg in args {
            if let dict = arg as? [String: Any] {
                // 通过 JSON 序列化将 Dictionary 转为 JS 对象
                if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    let jsObj = context.evaluateScript("(\(jsonString))")
                    jsArgs.append(jsObj as Any)
                } else {
                    jsArgs.append(jsObject(from: [:], context: context))
                }
            } else {
                jsArgs.append(arg)
            }
        }

        let result = fn.call(withArguments: jsArgs)
        guard let result = result, !result.isUndefined else { return nil }
        guard let dict = result.toObject() as? [String: Any] else { return nil }
        return dict
    }

    /// 将 Swift 字典转为 JSValue（用于参数传递）
    private func jsObject(from dict: [String: Any], context: JSContext) -> JSValue {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return JSValue(object: NSDictionary(), in: context)
        }
        return context.evaluateScript("(\(jsonString))")
    }

    // MARK: - 配置构建

    /// 从 home() 返回的 { class: [...] } 构建 TVBoxConfig
    private func buildTVBoxConfig(
        from homeResult: [String: Any],
        context: JSContext,
        siteKey: String,
        siteName: String,
        jsCode: String
    ) -> TVBoxConfig? {
        // 解析分类列表
        guard let classList = homeResult["class"] as? [[String: Any]], !classList.isEmpty else {
            return nil
        }

        var categories: [String] = []
        for cat in classList {
            if let name = cat["type_name"] as? String {
                categories.append(name)
            }
        }

        let site = Site(
            key: siteKey,
            name: siteName,
            type: 3,  // Spider 类型
            api: nil,
            searchable: 1,
            quickSearch: 1,
            categories: categories.isEmpty ? nil : categories
        )

        // 将 JSContext 和模块代码存入全局引用，后续调用复用
        SpiderContextManager.shared.register(key: siteKey, context: context)
        SpiderContextManager.shared.registerModuleCode(key: siteKey, code: jsCode)

        return TVBoxConfig(sites: [site])
    }
}

// MARK: - JSContext 生命周期管理

/// 管理已加载的 Spider JSContext，避免重复加载
final class SpiderContextManager {
    static let shared = SpiderContextManager()
    private var contexts: [String: JSContext] = [:]
    private var moduleCodes: [String: String] = [:]
    private init() {}

    func register(key: String, context: JSContext) {
        contexts[key] = context
    }

    func context(for key: String) -> JSContext? {
        contexts[key]
    }

    func registerModuleCode(key: String, code: String) {
        moduleCodes[key] = code
    }

    func moduleCode(for key: String) -> String? {
        moduleCodes[key]
    }

    func allModuleCodes() -> [(String, String)] {
        Array(moduleCodes.map { ($0.key, $0.value) })
    }

    func remove(key: String) {
        contexts.removeValue(forKey: key)
        moduleCodes.removeValue(forKey: key)
    }
}
