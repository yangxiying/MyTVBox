import Foundation

/// 参考 CatPawOpen 源码的配置生成器
///
/// CatPawOpen 是一个 Node.js Fastify 服务器，在猫爪/TVBox app 的 JS 引擎中运行。
/// `index.js.md5` 返回 MD5 哈希，去掉 `.md5` 后返回的是打包好的 JS 模块代码（非 JSON 配置）。
///
/// 本模块通过以下方式生成可用配置：
/// 1. 尝试请求 CatPaw 服务端的 `/config` 端点获取动态配置
/// 2. 基于源码中已知的 CMS 标准接口直接构建配置（ffm3u8 等）
///
/// 源码分析：
/// - ffm3u8: 标准 CMS `https://cj.ffzyapi.com/api.php/provide/vod/from/ffm3u8` → 可直接使用
/// - kunyu77: 自定义 API + RSA 签名 → 需移植
/// - kkys: 自定义 API + AES 加密 → 需移植
/// - alist/13bqg/copymanga: 网盘/小说/漫画 → 非视频 CMS
final class CatPawConfigBuilder {

    static let shared = CatPawConfigBuilder()
    private let network = NetworkManager.shared
    private init() {}

    // MARK: - 公共接口

    /// 尝试从 CatPaw 服务端或源码硬编码生成 TVBoxConfig
    /// - Parameter baseURL: CatPaw 服务器基础 URL（含认证信息）
    func buildConfig(baseURL: String) async throws -> TVBoxConfig {
        // 1. 尝试从 CatPaw 服务端 /config 端点获取动态配置
        if let cfg = await tryServerConfig(baseURL: baseURL) {
            return cfg
        }

        // 2. 使用源码中已知的 CMS 源构建配置
        return buildFromSourceCode()
    }

    /// 检测 URL 是否为 CatPaw Spider 模块格式
    static func isCatPawURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasSuffix(".js.md5") || lower.hasSuffix("/index.js")
    }

    // MARK: - 服务端配置获取

    /// 请求 CatPaw 服务器的 /config 端点
    private func tryServerConfig(baseURL: String) async -> TVBoxConfig? {
        guard let url = URL(string: baseURL),
              let scheme = url.scheme,
              let host = url.host else { return nil }

        // 构建带认证的 /config URL
        var authPrefix = ""
        if let user = url.user, let password = url.password {
            authPrefix = "\(user):\(password)@"
        }
        let portStr = url.port.map { ":\($0)" } ?? ""
        let configURL = "\(scheme)://\(authPrefix)\(host)\(portStr)/config"

        guard let data = try? await network.data(from: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return parseServerConfig(json)
    }

    /// 解析 CatPaw 服务端 /config 返回的格式
    /// 格式: { video: { sites: [...] }, read: { sites: [...] }, ... }
    private func parseServerConfig(_ json: [String: Any]) -> TVBoxConfig? {
        var allSites: [Site] = []

        // 解析 video.sites
        if let video = json["video"] as? [String: Any],
           let sites = video["sites"] as? [[String: Any]] {
            for siteJSON in sites {
                if let site = parseCatPawSite(siteJSON) {
                    allSites.append(site)
                }
            }
        }

        guard !allSites.isEmpty else { return nil }

        return TVBoxConfig(sites: allSites)
    }

    /// 解析单个 CatPaw 站点配置
    /// 格式: { key: "ffm3u8", name: "非凡采集", type: 3, api: "/spider/ffm3u8/3" }
    private func parseCatPawSite(_ json: [String: Any]) -> Site? {
        guard let key = json["key"] as? String,
              let name = json["name"] as? String else { return nil }

        let type = json["type"] as? Int ?? 3

        // CatPaw 的 api 是相对路径（如 /spider/ffm3u8/3），
        // 在 iOS 中无法直接使用（需要 JS 引擎）
        // 对于标准 CMS 蜘蛛，使用已知的直接 API 地址
        let directAPI = knownCMSAPIs[key]

        return Site(
            key: "catpaw_\(key)",
            name: name,
            type: directAPI != nil ? 1 : type,
            api: directAPI,
            searchable: 1,
            quickSearch: 1,
            filterable: 0,
            categories: knownCategories[key]
        )
    }

    // MARK: - 源码硬编码配置

    /// CatPawOpen 源码中已知的 CMS 标准接口地址
    /// 只有这些源可以在 iOS 上直接使用（无需 JS 引擎）
    private let knownCMSAPIs: [String: String] = [
        // ffm3u8 - 来自 nodejs/src/spider/video/ffm3u8.js + index.config.js
        "ffm3u8": "https://cj.ffzyapi.com/api.php/provide/vod/from/ffm3u8",
    ]

    /// 已知的分类列表（来自 index.config.js）
    private let knownCategories: [String: [String]] = [
        "ffm3u8": [
            "国产剧", "香港剧", "韩国剧", "欧美剧", "台湾剧", "日本剧",
            "海外剧", "泰国剧", "短剧", "动作片", "喜剧片", "爱情片",
            "科幻片", "恐怖片", "剧情片", "战争片", "动漫片", "大陆综艺",
            "港台综艺", "日韩综艺", "欧美综艺", "国产动漫", "日韩动漫",
            "欧美动漫", "港台动漫", "海外动漫", "记录片",
        ],
    ]

    /// 从 CatPawOpen 源码构建 fallback 配置
    /// 包含所有可直接在 iOS 上使用的 CMS 源
    private func buildFromSourceCode() -> TVBoxConfig {
        var sites: [Site] = []

        // === ffm3u8 (非凡采集) ===
        // 来源: nodejs/src/spider/video/ffm3u8.js
        // 配置: nodejs/src/index.config.js → ffm3u8.url
        sites.append(Site(
            key: "catpaw_ffm3u8",
            name: "非凡采集",
            type: 1,
            api: "https://cj.ffzyapi.com/api.php/provide/vod/from/ffm3u8",
            searchable: 1,
            quickSearch: 1,
            filterable: 1,
            categories: knownCategories["ffm3u8"]
        ))

        // === 额外补充的常用 CMS 源（猫爪生态常用） ===
        // 这些源来自 TVBox 社区，与 CatPawOpen 兼容
        let extraSources: [(key: String, name: String, api: String)] = [
            ("bfzy", "暴风资源", "https://bfzyapi.com/api.php/provide/vod"),
            ("ikun", "IKUN资源", "https://ikunzyapi.com/api.php/provide/vod/from/ikm3u8"),
            ("360zy", "360资源", "https://360zy.com/api.php/provide/vod"),
            ("hw8", "华为吧资源", "https://hw8.live/api.php/provide/vod"),
            ("jinying", "金鹰资源", "https://jinyingzy.com/api.php/provide/vod"),
            ("leshi", "乐视资源", "https://leshiapi.com/api.php/provide/vod"),
            ("mdzy", "墨斗资源", "https://www.mdzyapi.com/api.php/provide/vod"),
            ("niuniu", "牛牛资源", "https://api.niuniuzy.me/api.php/provide/vod"),
            ("okzy", "OK资源", "https://okzyw9.com/api.php/provide/vod"),
        ]

        for src in extraSources {
            sites.append(Site(
                key: "catpaw_\(src.key)",
                name: src.name,
                type: 1,
                api: src.api,
                searchable: 1,
                quickSearch: 1
            ))
        }

        return TVBoxConfig(sites: sites)
    }
}
