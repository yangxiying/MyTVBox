import Foundation

/// CatPaw Spider 配置生成器
///
/// 从 CatPaw `.js.md5` URL 获取打包好的 JS 源码，
/// 通过正则提取各 spider 的 meta 信息，配合已知 CMS API 地址生成多站点配置。
///
/// 生成流程：
/// 1. `.js.md5` → 取 MD5 → 下载打包 JS 源码
/// 2. 正则提取 `meta: { key: '...', name: '...', type: N }`
/// 3. 通过 knownCMSAPIs 映射生成 TVBoxConfig（type=1 CMS 站点）
/// 4. 未知 spider 标记为 type=3（需 JS 引擎，当前显示为不可用）
final class CatPawConfigBuilder {

    static let shared = CatPawConfigBuilder()
    private let network = NetworkManager.shared
    private init() {}

    // MARK: - 公共接口

    func buildConfig(baseURL: String) async throws -> TVBoxConfig {
        // 1. 如果是 CatPaw URL，从打包 JS 中提取 spider 站点
        var catpawSites: [Site] = []
        if Self.isCatPawURL(baseURL) {
            if let sites = (await tryExtractFromBundle(baseURL: baseURL))?.sites {
                catpawSites = sites
            } else if let sites = (await tryServerConfig(baseURL: baseURL))?.sites {
                catpawSites = sites
            }
        } else if let sites = (await tryServerConfig(baseURL: baseURL))?.sites {
            catpawSites = sites
        }

        // 2. 始终追加内置已知 CMS 源（确保数量充足）
        let builtinSites = buildBuiltinCMSSources()

        // 3. 合并去重（按 key 去重）
        var seen = Set(catpawSites.map { $0.key })
        var allSites = catpawSites
        for site in builtinSites where !seen.contains(site.key) {
            allSites.append(site)
            seen.insert(site.key)
        }

        guard !allSites.isEmpty else { return buildFromSourceCode() }
        return TVBoxConfig(sites: allSites)
    }

    static func isCatPawURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasSuffix(".js.md5") || lower.hasSuffix("/index.js")
    }

    // MARK: - 从打包 JS 中提取 spider meta

    /// 下载打包 JS 源码，正则提取所有 spider 的 meta，生成多站点配置
    private func tryExtractFromBundle(baseURL: String) async -> TVBoxConfig? {
        // 下载打包 JS（处理 .md5 → MD5 → JS 路径）
        guard let jsCode = await fetchBundleCode(jsURL: baseURL) else {
            print("[CatPawConfigBuilder] 下载 JS 源码失败: \(baseURL)")
            return nil
        }

        // 提取所有 meta 对象
        let metas = extractSpiderMetas(from: jsCode)
        guard !metas.isEmpty else {
            print("[CatPawConfigBuilder] 未提取到 spider meta")
            return nil
        }

        print("[CatPawConfigBuilder] 提取到 \(metas.count) 个 spider: \(metas.map { $0.key }.joined(separator: ", "))")

        // 每个 spider 生成一个 Site
        var sites: [Site] = []
        for meta in metas {
            guard let api = knownCMSAPIs[meta.key] else {
                // 未知 CMS 的 spider 标记为 type=3（需 JS 引擎）
                sites.append(Site(
                    key: "catpaw_\(meta.key)",
                    name: meta.name,
                    type: 3,
                    api: nil,
                    searchable: meta.key == "kkys" ? 1 : 0,
                    quickSearch: 0
                ))
                continue
            }

            sites.append(Site(
                key: "catpaw_\(meta.key)",
                name: meta.name,
                type: 1,
                api: api,
                searchable: 1,
                quickSearch: 1,
                filterable: 1,
                categories: knownCategories[meta.key]
            ))
        }

        guard !sites.isEmpty else { return nil }
        return TVBoxConfig(sites: sites)
    }

    // MARK: - JS Bundle 下载

    private func fetchBundleCode(jsURL: String) async -> String? {
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

        guard let data = try? await network.data(from: actualURL),
              let code = String(data: data, encoding: .utf8) else {
            return nil
        }
        return code
    }

    // MARK: - Spider Meta 提取

    private struct SpiderMeta {
        let key: String
        let name: String
        let type: Int
    }

    /// 从打包 JS 源码中用正则提取所有 `meta: { key: '...', name: '...', type: N }`
    private func extractSpiderMetas(from jsCode: String) -> [SpiderMeta] {
        // 匹配 meta: { key: 'ffm3u8', name: '非凡采集', type: 3 }
        // 注意 key/name 顺序不固定，type 可能缺省（默认 3）
        let pattern = #"meta\s*:\s*\{[^}]*key\s*:\s*['"]([^'"]+)['"][^}]*name\s*:\s*['"]([^'"]+)['"][^}]*(?:type\s*:\s*(\d+))?[^}]*\}"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        let range = NSRange(jsCode.startIndex..., in: jsCode)
        let matches = regex.matches(in: jsCode, options: [], range: range)

        var seen = Set<String>()
        var results: [SpiderMeta] = []

        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: jsCode),
                  let nameRange = Range(match.range(at: 2), in: jsCode) else { continue }

            let key = String(jsCode[keyRange])
            let name = String(jsCode[nameRange])
            let type: Int
            if let typeRange = Range(match.range(at: 3), in: jsCode) {
                type = Int(String(jsCode[typeRange])) ?? 3
            } else {
                type = 3
            }

            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(SpiderMeta(key: key, name: name, type: type))
        }

        return results
    }

    // MARK: - 已知 CMS API 地址映射

    /// CatPawOpen 各 spider 对应的 CMS 标准接口地址
    /// 这些地址来自源码分析和 TVBox 社区，是各 spider 实际请求的后端 API
    private let knownCMSAPIs: [String: String] = [
        // === CatPawOpen 内置 spider ===
        "ffm3u8": "https://cj.ffzyapi.com/api.php/provide/vod/from/ffm3u8",
        // kkys / kunyu77 使用自定义加密 API，无法直接用 CMS 替代

        // === 采集站（标准 CMS）===
        "ffzy":   "https://cj.ffzyapi.com/api.php/provide/vod",
        "bfzy":   "https://bfzyapi.com/api.php/provide/vod",
        "ikun":   "https://ikunzyapi.com/api.php/provide/vod/from/ikm3u8",
        "360zy":  "https://360zy.com/api.php/provide/vod",
        "hw8":    "https://hw8.live/api.php/provide/vod",
        "jinying":"https://jinyingzy.com/api.php/provide/vod",
        "leshi":  "https://leshiapi.com/api.php/provide/vod",
        "mdzy":   "https://www.mdzyapi.com/api.php/provide/vod",
        "niuniu": "https://api.niuniuzy.me/api.php/provide/vod",
        "okzy":   "https://okzyw9.com/api.php/provide/vod",
        "hongniuzy": "https://www.hongniuzy2.com/api.php/provide/vod",
        "lyd":    "https://api.lydapi.com/api.php/provide/vod",
        "wolongzy": "https://collect.wolongzyw.com/api.php/provide/vod",
        "heimuer": "https://json.heimuer.xyz/api.php/provide/vod",
        "tpzy":   "https://cj.tianpi.top/api.php/provide/vod",
        "dbzy":   "https://www.dbzyapi.com/api.php/provide/vod",
        "jszy":   "https://www.jszyapi.com/api.php/provide/vod",
        "sdzy":   "https://sdzyapi.com/api.php/provide/vod",
        "mozidian": "https://mozidian.com/api.php/provide/vod",
        "hnzy":   "https://hnzyapi.com/api.php/provide/vod",
        "tianying": "https://api.tiany.top/api.php/provide/vod",
        "kbzy":   "https://www.kbzyapi.com/api.php/provide/vod",
        "ckzy":   "https://www.ckzyw.com/api.php/provide/vod",
        "feisu":  "https://www.feisuzyapi.com/api.php/provide/vod",
        "baiwanzy": "https://www.baiwanzy.com/api.php/provide/vod",
        "liangzi": "https://cj.lziapi.com/api.php/provide/vod",
        "tianyi": "https://api.tiany.top/api.php/provide/vod",
        "luobozy": "https://luobozyapi.com/api.php/provide/vod",
        "maozhuatv": "https://www.mzryapi.com/api.php/provide/vod",
        "guangsu": "https://api.guangsuapi.com/api.php/provide/vod",
        "taopian": "https://www.taopianapi.com/api.php/provide/vod",
        "wujin":  "https://api.wujinapi.me/api.php/provide/vod",
        "longlong": "https://api.longlongdian.com/api.php/provide/vod",
        "kuaiche": "https://caiji.kczyapi.com/api.php/provide/vod",
        "mahua":  "https://www.mahuazy.com/api.php/provide/vod",
        "kuaikan": "https://www.kuaikanzy.com/api.php/provide/vod",

        // === 秒播站 ===
        "guazisp":  "https://guaziapi.com/api.php/provide/vod",
        "hjsp":     "https://hanjuapi.cc/api.php/provide/vod",
        "bobosp":   "https://api.bobozy.com/api.php/provide/vod",
        "yueyuesp": "https://yueyueapi.com/api.php/provide/vod",
        "dubosp":   "https://duboapi.com/api.php/provide/vod",
        "wencaisp": "https://wencaiapi.com/api.php/provide/vod",

        // === 爱看系列 ===
        "aikan":    "https://ikanapi.com/api.php/provide/vod",

        // === 短剧源 ===
        "dipindj":  "https://www.dipinapi.com/api.php/provide/vod",
        "baidusp":  "https://baiduapi.cc/api.php/provide/vod",
        "xiaoweidj": "https://www.xiaoweisp.com/api.php/provide/vod",

        // === 听书源（音频）===
        "yueting":  "https://www.yuetingts.com/api.php/provide/vod",
        "jipin":    "https://www.jipints.com/api.php/provide/vod",
        "wuyou":    "https://www.wuyouts.com/api.php/provide/vod",
        "jingpin":  "https://www.jingpints.com/api.php/provide/vod",
    ]

    /// 已知分类列表（来自 index.config.js）
    private let knownCategories: [String: [String]] = [
        "ffm3u8": [
            "国产剧", "香港剧", "韩国剧", "欧美剧", "台湾剧", "日本剧",
            "海外剧", "泰国剧", "短剧", "动作片", "喜剧片", "爱情片",
            "科幻片", "恐怖片", "剧情片", "战争片", "动漫片", "大陆综艺",
            "港台综艺", "日韩综艺", "欧美综艺", "国产动漫", "日韩动漫",
            "欧美动漫", "港台动漫", "海外动漫", "记录片",
        ],
    ]

    /// 将所有 knownCMSAPIs 转换为内置 CMS Site 列表
    private func buildBuiltinCMSSources() -> [Site] {
        let allAPIs: [(key: String, name: String, api: String)] = [
            // === 采集站（标准 CMS）===
            ("ffm3u8",     "非凡采集",   "https://cj.ffzyapi.com/api.php/provide/vod/from/ffm3u8"),
            ("ffzy",       "非凡资源",   "https://cj.ffzyapi.com/api.php/provide/vod"),
            ("bfzy",       "暴风资源",   "https://bfzyapi.com/api.php/provide/vod"),
            ("ikun",       "IKUN资源",   "https://ikunzyapi.com/api.php/provide/vod/from/ikm3u8"),
            ("360zy",      "360资源",    "https://360zy.com/api.php/provide/vod"),
            ("hw8",        "华为吧资源", "https://hw8.live/api.php/provide/vod"),
            ("jinying",    "金鹰资源",   "https://jinyingzy.com/api.php/provide/vod"),
            ("leshi",      "乐视资源",   "https://leshiapi.com/api.php/provide/vod"),
            ("mdzy",       "墨斗资源",   "https://www.mdzyapi.com/api.php/provide/vod"),
            ("niuniu",     "牛牛资源",   "https://api.niuniuzy.me/api.php/provide/vod"),
            ("okzy",       "OK资源",     "https://okzyw9.com/api.php/provide/vod"),
            ("hongniuzy",  "红牛资源",   "https://www.hongniuzy2.com/api.php/provide/vod"),
            ("lyd",        "闪电资源",   "https://api.lydapi.com/api.php/provide/vod"),
            ("wolongzy",   "卧龙资源",   "https://collect.wolongzyw.com/api.php/provide/vod"),
            ("heimuer",    "黑木耳",     "https://json.heimuer.xyz/api.php/provide/vod"),
            ("tpzy",       "天盘资源",   "https://cj.tianpi.top/api.php/provide/vod"),
            ("dbzy",       "豆瓣资源",   "https://www.dbzyapi.com/api.php/provide/vod"),
            ("jszy",       "极速资源",   "https://www.jszyapi.com/api.php/provide/vod"),
            ("sdzy",       "闪电资源",   "https://sdzyapi.com/api.php/provide/vod"),
            ("hnzy",       "华人资源",   "https://hnzyapi.com/api.php/provide/vod"),
            ("tianying",   "天鹰资源",   "https://api.tiany.top/api.php/provide/vod"),
            ("kbzy",       "快播资源",   "https://www.kbzyapi.com/api.php/provide/vod"),
            ("ckzy",       "超碰资源",   "https://www.ckzyw.com/api.php/provide/vod"),
            ("feisu",      "飞速资源",   "https://www.feisuzyapi.com/api.php/provide/vod"),
            ("baiwanzy",   "百万资源",   "https://www.baiwanzy.com/api.php/provide/vod"),
            ("liangzi",    "量子资源",   "https://cj.lziapi.com/api.php/provide/vod"),
            ("luobozy",    "萝卜资源",   "https://luobozyapi.com/api.php/provide/vod"),
            ("maozhuatv",  "猫抓TV",     "https://www.mzryapi.com/api.php/provide/vod"),
            ("mozidian",   "魔都资源",   "https://mozidian.com/api.php/provide/vod"),

            // === 秒播站（猫爪常见源）===
            ("guazisp",    "瓜子秒播",   "https://guaziapi.com/api.php/provide/vod"),
            ("hjsp",       "韩剧秒播",   "https://hanjuapi.cc/api.php/provide/vod"),
            ("bobosp",     "伯伯秒播",   "https://api.bobozy.com/api.php/provide/vod"),
            ("yueyuesp",   "悦悦秒播",   "https://yueyueapi.com/api.php/provide/vod"),
            ("dubosp",     "独播秒播",   "https://duboapi.com/api.php/provide/vod"),
            ("wencaisp",   "文才秒播",   "https://wencaiapi.com/api.php/provide/vod"),

            // === 爱看系列 ===
            ("aikan",      "爱看采集",   "https://ikanapi.com/api.php/provide/vod"),

            // === 短剧源 ===
            ("dipindj",    "帝品短剧",   "https://www.dipinapi.com/api.php/provide/vod"),
            ("baidusp",    "百度短剧",   "https://baiduapi.cc/api.php/provide/vod"),
            ("xiaoweidj",  "小薇短剧",   "https://www.xiaoweisp.com/api.php/provide/vod"),

            // === 听书源（音频）===
            ("yueting",    "悦听听书",   "https://www.yuetingts.com/api.php/provide/vod"),
            ("jipin",      "极品听书",   "https://www.jipints.com/api.php/provide/vod"),
            ("wuyou",      "无忧听书",   "https://www.wuyouts.com/api.php/provide/vod"),
            ("jingpin",    "精品听书",   "https://www.jingpints.com/api.php/provide/vod"),

            // === 其他知名采集站 ===
            ("guangsu",    "光速资源",   "https://api.guangsuapi.com/api.php/provide/vod"),
            ("taopian",    "淘片资源",   "https://www.taopianapi.com/api.php/provide/vod"),
            ("wujin",      "无尽资源",   "https://api.wujinapi.me/api.php/provide/vod"),
            ("longlong",   "龙龙采集",   "https://api.longlongdian.com/api.php/provide/vod"),
            ("kuaiche",    "快车资源",   "https://caiji.kczyapi.com/api.php/provide/vod"),
            ("mahua",      "麻花资源",   "https://www.mahuazy.com/api.php/provide/vod"),
            ("kuaikan",    "快看资源",   "https://www.kuaikanzy.com/api.php/provide/vod"),
            ("xiandu",     "线路多",     "https://api.xianduapi.com/api.php/provide/vod"),
            ("lzzy",       "量子采集",   "https://cj.lziapi.com/api.php/provide/vod"),
            ("jbb",        "久久采集",   "https://www.jiujiumiao.com/api.php/provide/vod"),
            ("hwsp",       "华为秒播",   "https://www.hwmiaobo.com/api.php/provide/vod"),
            ("tianlai",    "天籁资源",   "https://api.tianlaijichang.com/api.php/provide/vod"),
            ("feifan",     "非凡秒播",   "https://cj.ffzyapi.com/api.php/provide/vod/from/ffm3u8"),
            ("sdzy2",      "闪电采集",   "https://sdzyapi.com/api.php/provide/vod"),
            ("dandan",     "弹弹资源",   "https://www.dandanzy.com/api.php/provide/vod"),
            ("tianyi",     "天翼资源",   "https://api.tiany.top/api.php/provide/vod"),
            ("juji",       "剧酷资源",   "https://www.jukuapi.com/api.php/provide/vod"),
            ("hbzy",       "HB资源",     "https://hbzyapi.com/api.php/provide/vod"),
            ("dy1990",     "达达资源",   "https://www.dadazy.com/api.php/provide/vod"),
            ("wolongzy2",  "卧龙采集",   "https://collect.wolongzyw.com/api.php/provide/vod"),
            ("jyzy",       "金叶资源",   "https://www.jinyezy.com/api.php/provide/vod"),
            ("lianbo",     "联播资源",   "https://cj.lianboapi.com/api.php/provide/vod"),
            ("sdxc",       "闪电新款",   "https://sdxcapi.com/api.php/provide/vod"),
            ("txzy",       "天兴资源",   "https://api.tianxingapi.com/api.php/provide/vod"),
        ]

        return allAPIs.map { src in
            Site(
                key: "builtin_\(src.key)",
                name: src.name,
                type: 1,
                api: src.api,
                searchable: 1,
                quickSearch: 1
            )
        }
    }

    // MARK: - 服务端配置获取（CatPaw 服务器运行时）

    private func tryServerConfig(baseURL: String) async -> TVBoxConfig? {
        guard let url = URL(string: baseURL),
              let scheme = url.scheme,
              let host = url.host else { return nil }

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

    private func parseServerConfig(_ json: [String: Any]) -> TVBoxConfig? {
        var allSites: [Site] = []

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

    private func parseCatPawSite(_ json: [String: Any]) -> Site? {
        guard let key = json["key"] as? String,
              let name = json["name"] as? String else { return nil }

        let type = json["type"] as? Int ?? 3
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

    // MARK: - 内置已知 CMS 源（fallback）

    private func buildFromSourceCode() -> TVBoxConfig {
        var sites: [Site] = []

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
