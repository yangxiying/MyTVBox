import Foundation

/// Node.js Spider 引擎 —— 使用 node_start() 在同进程运行 Node.js
///
/// node_start() 是阻塞调用，在后台线程运行。
/// 通过文件系统通信：Node.js 写 port 文件，Swift 轮询读取。
final class NodeSpiderEngine {

    static let shared = NodeSpiderEngine()
    private init() {}

    private var instances: [String: NodeInstance] = [:]
    private let lock = NSLock()

    struct NodeInstance {
        let port: Int
        let tempDir: String
    }

    // MARK: - 公共接口

    func execute(jsCode: String, method: String, args: [String: Any], spiderKey: String?) async -> [String: Any]? {
        let key = spiderKey ?? "__default__"

        let instance: NodeInstance
        if let existing = lock.withLock({ instances[key] }) {
            instance = existing
        } else {
            guard let newInstance = await startNode(jsCode: jsCode, spiderKey: key) else {
                NSLog("[NodeSpiderEngine] Failed to start Node for key=\(key)")
                return nil
            }
            lock.withLock { instances[key] = newInstance }
            instance = newInstance
        }

        return await callAPI(port: instance.port, method: method, args: args)
    }

    func remove(spiderKey: String) {
        lock.withLock {
            if let inst = instances.removeValue(forKey: spiderKey) {
                try? FileManager.default.removeItem(atPath: inst.tempDir)
            }
        }
    }

    func removeAll() {
        lock.withLock {
            for (_, inst) in instances {
                try? FileManager.default.removeItem(atPath: inst.tempDir)
            }
            instances.removeAll()
        }
    }

    // MARK: - Node.js 启动

    private func startNode(jsCode: String, spiderKey: String) async -> NodeInstance? {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("node_spider_\(spiderKey)")
            .path
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        // 写入 bundle JS（CommonJS 模块）
        let bundlePath = "\(tempDir)/bundle.js"
        let commonJSCode = "module.exports = (function() { var exports = {}; var module = { exports: exports };\n" + jsCode + "\nreturn module.exports; })();"
        try? commonJSCode.write(toFile: bundlePath, atomically: true, encoding: .utf8)

        // 写入 bootstrap JS
        let bootstrapPath = "\(tempDir)/bootstrap.js"
        let bootstrap = """
        var fastify = require('fastify')({
            serverFactory: catServerFactory,
            forceCloseConnections: true,
            logger: false,
            maxParamLength: 10240
        });

        var bundle = require('./bundle.js');
        if (bundle.start) {
            bundle.start({server: fastify});
        }

        fastify.listen({ port: 0, host: '127.0.0.1' }, function(err, address) {
            if (err) {
                var fs = require('fs');
                fs.writeFileSync(process.env['NODE_PATH'] + '/port.txt', 'ERROR:' + err.message);
                return;
            }
            var port = fastify.server.address().port;
            var fs = require('fs');
            fs.writeFileSync(process.env['NODE_PATH'] + '/port.txt', String(port));
        });
        """
        try? bootstrap.write(toFile: bootstrapPath, atomically: true, encoding: .utf8)

        // 清空 port.txt
        try? "".write(toFile: "\(tempDir)/port.txt", atomically: true, encoding: .utf8)

        NSLog("[NodeSpiderEngine] Starting node_start() for key=\(spiderKey)")

        // 设置 NODE_PATH 环境变量
        setenv("NODE_PATH", tempDir, 1)

        // 在后台线程运行 node_start()
        let tempDirCopy = tempDir
        DispatchQueue.global(qos: .userInitiated).async {
            var cArgs = [UnsafeMutablePointer<CChar>?]()
            let progName = "node".withCString { strdup($0) }
            let scriptPath = bootstrapPath.withCString { strdup($0) }
            cArgs.append(progName)
            cArgs.append(scriptPath)
            cArgs.append(nil)

            node_start(Int32(cArgs.count - 1), &cArgs)

            // node_start 返回后清理
            free(progName)
            free(scriptPath)
            NSLog("[NodeSpiderEngine] node_start() returned for \(tempDirCopy)")
        }

        // 轮询 port.txt 等待端口号（最多 15 秒）
        let portFile = "\(tempDir)/port.txt"
        var port = 0
        for _ in 0..<150 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let content = try? String(contentsOfFile: portFile),
               !content.isEmpty {
                if content.hasPrefix("ERROR:") {
                    NSLog("[NodeSpiderEngine] Node error: \(content)")
                    break
                }
                if let p = Int(content.trimmingCharacters(in: .whitespacesAndNewlines)), p > 0 {
                    port = p
                    break
                }
            }
        }

        guard port > 0 else {
            NSLog("[NodeSpiderEngine] Node.js failed to start (no port after 15s)")
            try? FileManager.default.removeItem(atPath: tempDir)
            return nil
        }

        NSLog("[NodeSpiderEngine] Node.js running, port=\(port)")
        return NodeInstance(port: port, tempDir: tempDir)
    }

    // MARK: - HTTP API 调用

    private func callAPI(port: Int, method: String, args: [String: Any]) async -> [String: Any]? {
        let url = URL(string: "http://127.0.0.1:\(port)/\(method)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        if let data = try? JSONSerialization.data(withJSONObject: args) {
            request.httpBody = data
        }

        return await withCheckedContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    NSLog("[NodeSpiderEngine] HTTP \(method) error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    NSLog("[NodeSpiderEngine] HTTP \(method) invalid response")
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: json)
            }
            task.resume()
        }
    }
}
