import Foundation
import WebKit

/// CatPaw Spider JS 执行引擎（WKWebView 版本，iOS 17+）
///
/// 使用 WKWebView 执行 CatPaw webpack bundle。
/// iOS 17+ WebKit 支持 ES2018+ 正则（lookbehind 等）。
/// 通过 SpiderSchemeHandler 提供 JS 文件，
/// bundle 执行后 Fastify server 监听端口，
/// Swift 通过 HTTP 调用 spider API。
final class WebViewSpiderEngine {

    static let shared = WebViewSpiderEngine()
    private init() {}

    private var webViews: [String: WKWebView] = [:]
    private var schemeHandler: SpiderSchemeHandler?
    private let lock = NSLock()

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    // MARK: - 公共接口

    func execute(jsCode: String, method: String, args: [String: Any], spiderKey: String?) async -> [String: Any]? {
        let key = spiderKey ?? "__default__"
        let webView: WKWebView
        if let existing = withLock({ webViews[key] }) {
            webView = existing
        } else {
            webView = await createWebView(jsCode: jsCode, spiderKey: spiderKey)
            withLock { webViews[key] = webView }
        }
        return await callMethod(webView: webView, method: method, args: args, spiderKey: spiderKey)
    }

    func remove(spiderKey: String) { withLock { webViews.removeValue(forKey: spiderKey) } }
    func removeAll() { withLock { webViews.removeAll() } }

    // MARK: - WKWebView 创建

    private func createWebView(jsCode: String, spiderKey: String?) async -> WKWebView {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let key = spiderKey ?? "default"

                // 提取 webpack 代码（跳过 IIFE HTML 生成器）
                var modifiedJS = jsCode
                if let range = modifiedJS.range(of: "var k$e=Object.create") {
                    modifiedJS = "var exports={};var module={exports:exports};" + String(modifiedJS[range.lowerBound...])
                }

                // 用 SpiderSchemeHandler 提供 JS 文件
                let handler = SpiderSchemeHandler()
                handler.register(path: "\(key).js", data: modifiedJS.data(using: .utf8) ?? Data())
                let html = self.buildInitHTML(jsFilename: "\(key).js", spiderKey: spiderKey)
                handler.register(path: "\(key).html", data: html.data(using: .utf8) ?? Data())
                self.schemeHandler = handler

                let config = WKWebViewConfiguration()
                config.setURLSchemeHandler(handler, forURLScheme: SpiderSchemeHandler.scheme)
                let webView = WKWebView(frame: .zero, configuration: config)
                webView.isHidden = true

                webView.load(URLRequest(url: URL(string: "\(SpiderSchemeHandler.scheme)://\(key).html")!))

                // 等待 bundle + Fastify server 启动
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    self.runInit(webView: webView)
                    continuation.resume(returning: webView)
                }
            }
        }
    }

    // MARK: - JS Shims

    private var shimsJS: String {
        """
        var __spider_logs__=[];
        var console={log:function(){__spider_logs__.push(Array.prototype.slice.call(arguments).map(String).join(' '));},warn:function(){},error:function(){},info:function(){}};
        function dayjs(i){var d=i?new Date(i):new Date();return{valueOf:function(){return d.getTime();},unix:function(){return Math.floor(d.getTime()/1000);},format:function(f){return f;},add:function(n,u){return dayjs(d);},subtract:function(n,u){return dayjs(d);},toDate:function(){return d;}};}
        dayjs.utc=function(i){return dayjs(i);};
        dayjs.duration=function(v,u){return{asMilliseconds:function(){return v;}};};
        var CryptoJS={enc:{Utf8:{parse:function(s){return s;},stringify:function(s){return typeof s==='string'?s:'';}},Hex:{stringify:function(s){return typeof s==='string'?s:'';},parse:function(s){return s;}},Base64:{stringify:function(s){return btoa(s);},parse:function(s){return atob(s);}}},pad:{Pkcs7:{}},mode:{CBC:{}},MD5:function(s){var h=0;for(var i=0;i<s.length;i++){h=((h<<5)-h)+s.charCodeAt(i);h|=0;}var x=(h>>>0).toString(16).padStart(8,'0');return{toString:function(){return x+x+x+x;}};},AES:{decrypt:function(src){var t=(typeof src==='object'&&src.ciphertext)?src.ciphertext.toString():src.toString();try{return{toString:function(){return atob(t);};};}catch(e){return{toString:function(){return t;}};}}}};
        function req(u,o){o=o||{};var m=(o.method||'get').toUpperCase();var h=o.headers||{};var fo={method:m,headers:h};if(o.data){fo.body=typeof o.data==='string'?o.data:JSON.stringify(o.data);}return fetch(u,fo).then(function(r){var ct=r.headers.get('content-type')||'';if(ct.indexOf('json')!==-1)return r.json();return r.text();}).catch(function(e){return{};});}
        req.get=function(u,o){o=o||{};o.method='get';return req(u,o);};
        req.post=function(u,o){o=o||{};o.method='post';return req(u,o);};
        if(typeof process==='undefined'){var process={env:{NODE_ENV:'production'}};}else if(!process.env){process.env={NODE_ENV:'production'};}
        var exports={};var module={exports:exports};
        var fs={existsSync:function(){return false;},readFileSync:function(){return'';}};
        """
    }

    private func buildInitHTML(jsFilename: String, spiderKey: String?) -> String {
        let router: String
        if let key = spiderKey {
            router = """
            var __spider_key__=\(jsonString(key));
            function __call__(m,a){var fn=window.fn;if(!fn)return null;try{var r=fn.inject().post('/'+__spider_key__+'/'+m).headers({'content-type':'application/json'}).body(JSON.stringify(a||{}));return r.json();}catch(e){return null;}}
            """
        } else {
            router = """
            function __call__(m,a){var fn=window.fn;if(!fn)return null;try{var r=fn.inject().post('/'+m).headers({'content-type':'application/json'}).body(JSON.stringify(a||{}));return r.json();}catch(e){return null;}}
            """
        }
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"></head><body>
        <script>\(self.shimsJS)</script>
        <script>\(router)</script>
        <script src="\(SpiderSchemeHandler.scheme)://\(jsFilename)"></script>
        </body></html>
        """
    }

    private func runInit(webView: WKWebView) {
        webView.evaluateJavaScript("""
        (async function(){
            try{
                var diag = 'scripts=' + document.querySelectorAll('script').length
                    + ' k$e=' + (typeof k$e) + ' module=' + (typeof module)
                    + ' exports_keys=' + JSON.stringify(Object.keys(module.exports||{}))
                    + ' Fpr=' + (typeof Fpr) + ' Lpr=' + (typeof Lpr)
                    + ' fn=' + (typeof window.fn) + ' err=' + (window.__err__||'none');
                console.log('[init-diag] ' + diag);
                var e = module.exports;
                if(e && typeof e.start === 'function'){
                    console.log('[init] calling start()...');
                    await e.start();
                    console.log('[init] done fn=' + (typeof window.fn));
                } else {
                    console.log('[init] no start, exports=' + JSON.stringify(Object.keys(e||{})));
                }
            }catch(err){
                console.log('[init] err=' + err.message + ' stack=' + (err.stack||'').substring(0,200));
            }
        })();
        """, completionHandler: nil)
    }

    // MARK: - 方法调用

    private func callMethod(webView: WKWebView, method: String, args: [String: Any], spiderKey: String?) async -> [String: Any]? {
        let argsJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: args),
           let str = String(data: data, encoding: .utf8) { argsJSON = str }
        else { argsJSON = "{}" }

        let m = method.replacingOccurrences(of: "'", with: "\\'")
        let a = argsJSON.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (function(){try{var args=JSON.parse('\(a)');if(typeof __call__!=='function')return JSON.stringify({_debug:'no __call__'});var r=__call__('\(m)',[args]);if(r===null||r===undefined)return JSON.stringify({_debug:'null',method:'\(m)'});if(typeof r==='string')return r;if(typeof r.then==='function')return r.then(function(x){return x===null||x===undefined?JSON.stringify({}):typeof x==='string'?x:JSON.stringify(x);}).catch(function(e){return JSON.stringify({_error:e.message});});return JSON.stringify(r);}catch(e){return JSON.stringify({_error:e.message});}})()
        """
        return await execJS(webView, script)
    }

    private func execJS(_ webView: WKWebView, _ script: String) async -> [String: Any]? {
        await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                webView.evaluateJavaScript(script) { result, error in
                    if let error = error { NSLog("[WSE] err: \(error.localizedDescription)"); cont.resume(returning: nil); return }
                    if let dict = result as? [String: Any] { cont.resume(returning: dict); return }
                    if let str = result as? String, let data = str.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { cont.resume(returning: json); return }
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func jsonString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let str = String(data: data, encoding: .utf8) else { return "'\(s)'" }
        return String(str.dropFirst().dropLast())
    }
}

// MARK: - URL Scheme Handler

private class SpiderSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "spider"
    private var files: [String: Data] = [:]
    func register(path: String, data: Data) { files[path] = data }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let host = url.host else { task.didFailWithError(NSError(domain: "S", code: -1)); return }
        if let data = files[host] {
            let ext = (host as NSString).pathExtension
            let mime = ext == "html" ? "text/html" : "application/javascript"
            task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8"))
            var off = 0
            while off < data.count { let end = min(off + 256*1024, data.count); task.didReceive(data.subdata(in: off..<end)); off = end }
            task.didFinish()
        } else { task.didFailWithError(NSError(domain: "S", code: 404)) }
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
