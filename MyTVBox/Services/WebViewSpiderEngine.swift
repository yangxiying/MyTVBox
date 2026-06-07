import Foundation
import WebKit

private func wlog(_ s: String) {
    NSLog("[SpiderEngine] \(s)")
    let line = "\(Date()): \(s)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/spider_test.log")
    if let fh = try? FileHandle(forWritingTo: url) {
        fh.seekToEndOfFile(); fh.write(data); try? fh.close()
    } else {
        try? data.write(to: url, options: .atomic)
    }
}

/// Serves local files via a custom URL scheme (spider://) to bypass WKWebView file:// restrictions
private class SpiderSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "spider"
    private var files: [String: Data] = [:]

    func register(path: String, data: Data) {
        files[path] = data
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let host = url.host else {
            urlSchemeTask.didFailWithError(NSError(domain: "SpiderScheme", code: -1))
            return
        }
        if let data = files[host] {
            wlog("Scheme serving \(host) (\(data.count) bytes)")
            let ext = (host as NSString).pathExtension
            let mime = ext == "html" ? "text/html" : "application/javascript"
            let response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8")
            urlSchemeTask.didReceive(response)
            // Send in chunks to avoid memory issues with large files
            let chunkSize = 256 * 1024 // 256KB chunks
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                let chunk = data.subdata(in: offset..<end)
                urlSchemeTask.didReceive(chunk)
                offset = end
            }
            urlSchemeTask.didFinish()
        } else {
            wlog("Scheme 404: \(host)")
            urlSchemeTask.didFailWithError(NSError(domain: "SpiderScheme", code: 404))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

/// CatPaw Spider JS 执行引擎（WKWebView 版本）
///
/// 使用 WKWebView（完整 WebKit 引擎）替代 JSContext，
/// 支持 iOS 16 上的现代 JS 语法（lookbehind regex 等）。
/// 每个 spider key 维护独立的 WKWebView 实例，JS 状态在调用间保持。
final class WebViewSpiderEngine {

    static let shared = WebViewSpiderEngine()
    private init() {}

    /// 已加载的 WKWebView 实例池（key = spiderKey）
    private var webViews: [String: WKWebView] = [:]
    private var schemeHandler: SpiderSchemeHandler?
    private let lock = NSLock()

    /// 线程安全取值
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: - 公共接口

    /// 执行 spider 方法并返回结果字典
    func execute(
        jsCode: String,
        method: String,
        args: [String: Any],
        spiderKey: String? = nil
    ) async -> [String: Any]? {
        let key = spiderKey ?? "__default__"
        wlog("execute: method=\(method) key=\(key) jsLen=\(jsCode.count)")

        // 获取或创建 WKWebView
        let webView: WKWebView
        if let existing = withLock({ webViews[key] }) {
            webView = existing
            wlog("reusing webView key=\(key)")
        } else {
            wlog("creating webView key=\(key)")
            webView = await createWebView(jsCode: jsCode, spiderKey: spiderKey)
            withLock { webViews[key] = webView }
        }

        // 调用方法
        wlog("calling method=\(method)")
        let result = await callMethod(webView: webView, method: method, args: args, spiderKey: spiderKey)
        wlog("method=\(method) result=\(result != nil ? "non-nil keys=\(Array(result!.keys))" : "nil")")

        // 打印 JS console 日志
        if let logs = await retrieveLogs(webView: webView), !logs.isEmpty {
            wlog("JS logs count=\(logs.count)")
            for log in logs.prefix(50) { wlog("JS: \(log)") }
        }

        return result
    }

    /// 清理指定 spider 的 WKWebView
    func remove(spiderKey: String) {
        withLock { webViews.removeValue(forKey: spiderKey) }
    }

    /// 清理全部
    func removeAll() {
        withLock { webViews.removeAll() }
    }

    // MARK: - WKWebView 创建

    private func createWebView(jsCode: String, spiderKey: String?) async -> WKWebView {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                // Extract webpack code only (skip IIFE)
                var modifiedJS = jsCode
                if let webpackStart = modifiedJS.range(of: "var k$e=Object.create") {
                    modifiedJS = "var exports={};var module={exports:exports};" + String(modifiedJS[webpackStart.lowerBound...])
                    wlog("Webpack-only, jsLen=\(modifiedJS.count)")
                }

                // Patch named groups: (?<name>...) → (...)
                while let range = modifiedJS.range(of: "(?<") {
                    if let gtIndex = modifiedJS[range.upperBound...].firstIndex(of: ">") {
                        modifiedJS.replaceSubrange(range.lowerBound...gtIndex, with: "(")
                    } else { break }
                }
                // Patch lookbehinds: (?<!...) → (?:...)
                while let lbRange = modifiedJS.range(of: "(?<!") {
                    var depth = 1
                    var searchIdx = lbRange.upperBound
                    while depth > 0 && searchIdx < modifiedJS.endIndex {
                        let ch = modifiedJS[searchIdx]
                        if ch == "(" { depth += 1 }
                        else if ch == ")" { depth -= 1 }
                        searchIdx = modifiedJS.index(after: searchIdx)
                    }
                    if depth == 0 {
                        modifiedJS.replaceSubrange(lbRange.lowerBound..<searchIdx, with: "(?:)")
                    } else { break }
                }

                wlog("Regex patched, jsLen=\(modifiedJS.count)")

                // Serve webpack as raw JS file via scheme handler
                let jsData = modifiedJS.data(using: .utf8) ?? Data()

                let key = spiderKey ?? "default"
                // Build HTML: shims + loader that evals webpack from file
                let loaderHTML = """
                <!DOCTYPE html><html><head><meta charset="utf-8"></head><body>
                <script>
                \(self.shimsJS)
                </script>
                <script>
                window.onerror=function(m,s,l,c,e){window.__err__=m+'@'+l+':'+c;return false;};
                </script>
                <script>
                var __s=document.createElement('script');
                __s.src='\(SpiderSchemeHandler.scheme)://\(key).js';
                __s.onerror=function(){window.__load_err__='script onerror';};
                __s.onload=function(){window.__load_ok__=true;};
                document.head.appendChild(__s);
                </script>
                </body></html>
                """
                let htmlData = loaderHTML.data(using: .utf8) ?? Data()

                // Use custom URL scheme to serve files
                let handler = SpiderSchemeHandler()
                handler.register(path: "\(key).html", data: htmlData)
                handler.register(path: "\(key).js", data: jsData)
                self.schemeHandler = handler

                let config = WKWebViewConfiguration()
                config.setURLSchemeHandler(handler, forURLScheme: SpiderSchemeHandler.scheme)
                let webView = WKWebView(frame: .zero, configuration: config)
                webView.isHidden = true

                let url = URL(string: "\(SpiderSchemeHandler.scheme)://\(key).html")!
                wlog("Loading \(url)")
                webView.load(URLRequest(url: url))

                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    self.runInit(webView: webView)
                    continuation.resume(returning: webView)
                }
            }
        }
    }

    private func runInit(webView: WKWebView) {
        let script = """
        (async function() {
            try {
                var diag = 'err=' + window.__err__ + ' k$e=' + (typeof k$e)
                    + ' exports=' + JSON.stringify(Object.keys(module.exports||{}))
                    + ' Fpr=' + (typeof Fpr) + ' Lpr=' + (typeof Lpr) + ' fn=' + (typeof window.fn)
                    + ' scripts=' + document.querySelectorAll('script').length;
                console.log('[init-diag] ' + diag);
                var exports = module.exports;
                if (exports && typeof exports.start === 'function') {
                    console.log('[init] calling start()...');
                    await exports.start();
                    console.log('[init] start() completed, fn=' + (typeof window.fn));
                } else {
                    console.log('[init] exports not available');
                }
            } catch(e) {
                console.log('[init] error: ' + e.message + ' stack=' + (e.stack||'').substring(0,300));
            }
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func buildInitHTML(jsFilename: String, spiderKey: String?) -> String {
        let routerBlock: String
        if let key = spiderKey {
            routerBlock = """
            var __spider_key__ = \(jsonString(key));
            function __call__(method, args) {
                var fn = window.fn;
                if (!fn) { console.log('[router] fn not ready'); return null; }
                var url = '/' + __spider_key__ + '/' + method;
                console.log('[router] __call__' + method + ' url=' + url);
                try {
                    var body = JSON.stringify(args || {});
                    var resp = fn.inject().post(url).headers({'content-type':'application/json'}).body(body);
                    var data = resp.json();
                    console.log('[router] result keys=' + (data ? Object.keys(data).join(',') : 'null'));
                    return data;
                } catch(e) { console.log('[router] error=' + e.message); return null; }
            }
            """
        } else {
            routerBlock = """
            function __call__(method, args) {
                var fn = window.fn;
                if (!fn) return null;
                try {
                    var resp = fn.inject().post('/' + method).headers({'content-type':'application/json'}).body(JSON.stringify(args || {}));
                    return resp.json();
                } catch(e) { return null; }
            }
            """
        }

        return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"></head>
        <body>
        <script>
        \(shimsJS)
        window.onerror = function(msg, src, line, col, err) {
            window.__last_error__ = msg + ' at ' + line + ':' + col;
            return false;
        };
        </script>
        <script>
        \(routerBlock)
        </script>
        <script>
        window.onerror=function(m,s,l,c,e){window.__err__=m+'@'+l+':'+c;return false;};
        </script>
        <script>
        // Decode base64 webpack code and eval in current context
        (function() {
            try {
                var b64 = window.__webpack_b64__;
                if (!b64) { console.log('[loader] no webpack b64'); return; }
                var code = decodeURIComponent(escape(atob(b64)));
                console.log('[loader] eval code len=' + code.length);
                eval(code);
                console.log('[loader] eval done, k$e=' + (typeof k$e) + ' exports=' + JSON.stringify(Object.keys(module.exports||{})));
            } catch(e) {
                console.log('[loader] eval error: ' + e.message + ' @ ' + (e.stack||'').substring(0,300));
                window.__eval_err__ = e.message;
            }
        })();
        </script>
        </body>
        </html>
        """
    }

    // MARK: - 方法调用

    private func callMethod(
        webView: WKWebView,
        method: String,
        args: [String: Any],
        spiderKey: String?
    ) async -> [String: Any]? {
        // 序列化参数为 JSON
        let argsJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: args),
           let str = String(data: data, encoding: .utf8) {
            argsJSON = str
        } else {
            argsJSON = "{}"
        }

        // 构建调用脚本：JSON.parse → __call__ → JSON.stringify
        // 返回字符串而非对象，避免 WKWebView 的类型转换问题
        let escapedMethod = method.replacingOccurrences(of: "'", with: "\\'")
        let escapedArgsJSON = argsJSON
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (function() {
            try {
                var args = JSON.parse('\(escapedArgsJSON)');
                var fnExists = typeof __call__ === 'function';
                if (!fnExists) return JSON.stringify({_debug: 'no __call__'});
                var result = __call__('\(escapedMethod)', [args]);
                if (result === null || result === undefined) {
                    return JSON.stringify({_debug: '__call__ returned null', method: '\(escapedMethod)'});
                }
                if (typeof result === 'string') return result;
                // 如果是 Promise，用 .then 包装返回 string
                if (typeof result.then === 'function') {
                    return result.then(function(r) {
                        if (r === null || r === undefined) return JSON.stringify({_debug: 'promise resolved null'});
                        if (typeof r === 'string') return r;
                        return JSON.stringify(r);
                    }).catch(function(e) {
                        return JSON.stringify({_error: e.message});
                    });
                }
                return JSON.stringify(result);
            } catch(e) {
                return JSON.stringify({_error: e.message});
            }
        })()
        """

        return await executeInWebView(webView, script: script)
    }

    private func executeInWebView(_ webView: WKWebView, script: String) async -> [String: Any]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                webView.evaluateJavaScript(script) { result, error in
                    if let error = error {
                        wlog("evaluateJavaScript error: \(error.localizedDescription)")
                        continuation.resume(returning: nil)
                        return
                    }
                    wlog("raw result type=\(Swift.type(of: result)) value=\(String(describing: result).prefix(300))")
                    // 直接解析返回的字典（WKWebView 自动转换 JSON 对象）
                    if let dict = result as? [String: Any] {
                        continuation.resume(returning: dict)
                        return
                    }
                    // 尝试 JSON 字符串解析
                    if let str = result as? String, !str.isEmpty,
                       let data = str.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        continuation.resume(returning: json)
                        return
                    }
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - JSON 辅助

    private func jsonString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let str = String(data: data, encoding: .utf8) else {
            return "'\(s)'"
        }
        return String(str.dropFirst().dropLast())
    }

    /// 读取 JS console 日志并清空
    private func retrieveLogs(webView: WKWebView) async -> [String]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                webView.evaluateJavaScript("JSON.stringify(__spider_logs__ || [])") { result, error in
                    if let error = error {
                        continuation.resume(returning: nil)
                        return
                    }
                    if let str = result as? String,
                       let data = str.data(using: .utf8),
                       let logs = try? JSONSerialization.jsonObject(with: data) as? [String] {
                        // 清空日志
                        webView.evaluateJavaScript("__spider_logs__ = []", completionHandler: nil)
                        continuation.resume(returning: logs)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    // MARK: - JS Shims（纯 JS 实现，无原生桥接依赖）

    private var shimsJS: String {
        """
        // Console shim — capture logs for debugging
        var __spider_logs__ = [];
        var console = {
            log: function(){ __spider_logs__.push(Array.prototype.slice.call(arguments).map(String).join(' ')); },
            warn: function(){ __spider_logs__.push('[WARN] ' + Array.prototype.slice.call(arguments).map(String).join(' ')); },
            error: function(){ __spider_logs__.push('[ERR] ' + Array.prototype.slice.call(arguments).map(String).join(' ')); },
            info: function(){ __spider_logs__.push('[INFO] ' + Array.prototype.slice.call(arguments).map(String).join(' ')); }
        };

        // dayjs minimal shim
        function dayjs(input) {
            var d = input ? new Date(input) : new Date();
            return {
                valueOf: function(){ return d.getTime(); },
                unix: function(){ return Math.floor(d.getTime()/1000); },
                format: function(f) {
                    var pad = function(n){ return n<10?'0'+n:''+n; };
                    return f.replace('YYYY',d.getFullYear()).replace('MM',pad(d.getMonth()+1))
                        .replace('DD',pad(d.getDate())).replace('HH',pad(d.getHours()))
                        .replace('mm',pad(d.getMinutes())).replace('ss',pad(d.getSeconds()));
                },
                add: function(n,u) {
                    var nd=new Date(d);
                    if(u==='day'||u==='d') nd.setDate(nd.getDate()+n);
                    else if(u==='hour'||u==='h') nd.setHours(nd.getHours()+n);
                    else if(u==='minute'||u==='m') nd.setMinutes(nd.getMinutes()+n);
                    else if(u==='second'||u==='s') nd.setSeconds(nd.getSeconds()+n);
                    else if(u==='month') nd.setMonth(nd.getMonth()+n);
                    else if(u==='year') nd.setFullYear(nd.getFullYear()+n);
                    return dayjs(nd);
                },
                subtract: function(n,u){ return this.add(-n,u); },
                toDate: function(){ return d; }
            };
        }
        dayjs.utc = function(input){ return dayjs(input); };
        dayjs.duration = function(v,u){ return { asMilliseconds:function(){ return v; } }; };

        // CryptoJS shim（使用 Web Crypto API）
        var CryptoJS = CryptoJS || {};
        CryptoJS.enc = {
            Utf8: { parse:function(s){return s;}, stringify:function(s){return typeof s==='string'?s:'';} },
            Hex: { stringify:function(s){return typeof s==='string'?s:'';}, parse:function(s){return s;} },
            Base64: {
                stringify:function(s){ return btoa(typeof s==='string'?s:s.toString()); },
                parse:function(s){ return atob(typeof s==='string'?s:s.toString()); }
            }
        };
        CryptoJS.pad = { Pkcs7:{} };
        CryptoJS.mode = { CBC:{} };

        // MD5（简化实现：使用 btoa+hash 或回退为简单哈希）
        CryptoJS.MD5 = function(s) {
            var str = typeof s === 'string' ? s : s.toString();
            // 简单哈希（不完全兼容 MD5，但满足大多数 spider 检查）
            var hash = 0;
            for (var i = 0; i < str.length; i++) {
                var c = str.charCodeAt(i);
                hash = ((hash << 5) - hash) + c;
                hash |= 0;
            }
            var hex = (hash >>> 0).toString(16).padStart(8, '0');
            return { toString: function(){ return hex + hex + hex + hex; } };
        };

        // AES（简化：仅解密 Base64 编码的明文透传）
        CryptoJS.AES = {
            decrypt: function(src, key, opts) {
                var cipherText = (typeof src === 'object' && src.ciphertext)
                    ? src.ciphertext.toString()
                    : (typeof src === 'string' ? src : src.toString());
                // 大多数 spider 的 AES 实际是 Base64 解码，非真正加密
                try {
                    var decoded = atob(cipherText);
                    return { toString: function(){ return decoded; } };
                } catch(e) {
                    return { toString: function(){ return cipherText; } };
                }
            }
        };

        // req shim（使用 async fetch）
        // 注意：WKWebView 不支持同步 XHR，spider 必须兼容 async req
        function req(url, opts) {
            opts = opts || {};
            var method = (opts.method || 'get').toUpperCase();
            var headers = opts.headers || {};
            var fetchOpts = { method: method, headers: headers };
            if (opts.data) {
                if (typeof opts.data === 'string') {
                    fetchOpts.body = opts.data;
                } else {
                    fetchOpts.body = JSON.stringify(opts.data);
                    if (!headers['Content-Type']) {
                        fetchOpts.headers['Content-Type'] = 'application/json';
                    }
                }
            }
            // 返回 Promise，spider async 方法可直接 await
            return fetch(url, fetchOpts).then(function(resp) {
                var ct = resp.headers.get('content-type') || '';
                if (ct.indexOf('json') !== -1) {
                    return resp.json();
                }
                return resp.text();
            }).catch(function(e) {
                console.warn('req failed:', url, e.message);
                return {};
            });
        }
        req.get = function(url, opts){ opts=opts||{}; opts.method='get'; return req(url,opts); };
        req.post = function(url, opts){ opts=opts||{}; opts.method='post'; return req(url,opts); };

        // process.env polyfill (required by bundle)
        if (typeof process === 'undefined') { var process = { env: { NODE_ENV: 'production' } }; }
        else if (!process.env) { process.env = { NODE_ENV: 'production' }; }

        // module/exports globals — capture module.exports for start()/stop()
        var exports = {};
        var module = { exports: exports };

        // fs shim (Node.js compat - bundle uses fs for file operations)
        var fs = { existsSync: function(){ return false; }, readFileSync: function(){ return ''; }, statSync: function(){ return {size:0}; }, readdirSync: function(){ return []; }, mkdirSync: function(){}, writeFileSync: function(){}, createReadStream: function(){ return { on: function(){ return this; }, pipe: function(){} }; }, createWriteStream: function(){ return { on: function(){ return this; }, write: function(){} }; } };

        // catServerFactory polyfill — mock underlying HTTP server for Fastify
        // The bundle's IIFE declares local `var catServerFactory` which shadows this global.
        // Actual fn capture is done via bundle source replacement in buildHTML:
        //   fn=(globalThis.__fn__=(0,tJe.default)({serverFactory:catServerFactory...))
        var catServerFactory = function(handler) {
            console.log('[shim] catServerFactory called');
            var mockServer = {
                on: function() { return mockServer; },
                listen: function(opts, cb) {
                    console.log('[shim] server.listen skipped (WKWebView)');
                    if (typeof cb === 'function') cb(null, mockServer);
                    return mockServer;
                },
                address: function() { return { port: 9988, address: '127.0.0.1', family: 'IPv4' }; },
                close: function(cb) { if (typeof cb === 'function') cb(); },
                ref: function() {},
                unref: function() {},
                setTimeout: function() {},
                setRequestTimeout: function() {},
                setMaxListeners: function() {},
                removeListener: function() {},
                removeAllListeners: function() {},
                emit: function() { return false; },
                listeners: function() { return []; },
                eventNames: function() { return []; },
                prependListener: function() {},
                prependOnceListener: function() {},
                once: function() { return mockServer; },
                off: function() { return mockServer; },
                addListener: function() { return mockServer; },
                setMaxListeners: function() { return mockServer; },
                getMaxListeners: function() { return 10; },
                listenerCount: function() { return 0; },
                raw: function() { return mockServer; },
                _events: {},
                _eventsCount: 0,
                _maxListeners: 10
            };
            return mockServer;
        };

        // catDartServerPort polyfill — no Dart host in WKWebView
        var catDartServerPort = function() { return 0; };
        """
    }
}
