import Foundation

/// 资源站点配置
struct Site: Codable, Identifiable, Hashable {
    var id: String { key }
    let key: String
    let name: String
    /// 0 = XPath, 1 = JSON API (CMS标准接口), 3 = Spider (jar/js)
    let type: Int
    let api: String?
    /// 1 = 可搜索
    let searchable: Int?
    /// 1 = 支持快速搜索
    let quickSearch: Int?
    /// 1 = 可筛选
    let filterable: Int?
    /// 播放器类型：0 系统, 1 IJK, 2 Exo
    let playerType: Int?
    /// 扩展配置（JSON / URL / 字符串）
    let ext: String?
    /// 站点支持的分类 ID 列表（用于过滤）
    let categories: [String]?
    /// jar 包地址（spider 站点用）
    let jar: String?

    enum CodingKeys: String, CodingKey {
        case key, name, type, api
        case searchable, quickSearch, filterable, playerType
        case ext, categories, jar
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try c.decode(String.self, forKey: .key)
        self.name = try c.decode(String.self, forKey: .name)
        self.type = try c.decodeIfPresent(Int.self, forKey: .type) ?? 1
        self.api = try c.decodeIfPresent(String.self, forKey: .api)
        self.searchable = try c.decodeIfPresent(Int.self, forKey: .searchable)
        self.quickSearch = try c.decodeIfPresent(Int.self, forKey: .quickSearch)
        self.filterable = try c.decodeIfPresent(Int.self, forKey: .filterable)
        self.playerType = try c.decodeIfPresent(Int.self, forKey: .playerType)
        self.categories = try c.decodeIfPresent([String].self, forKey: .categories)
        self.jar = try c.decodeIfPresent(String.self, forKey: .jar)

        // ext 可能是字符串、对象或数组，统一转字符串方便存储
        if let s = try? c.decodeIfPresent(String.self, forKey: .ext) {
            self.ext = s
        } else if let any = try? c.decodeIfPresent(AnyCodable.self, forKey: .ext) {
            if let data = try? JSONSerialization.data(withJSONObject: any.value, options: []),
               let s = String(data: data, encoding: .utf8) {
                self.ext = s
            } else {
                self.ext = nil
            }
        } else {
            self.ext = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(api, forKey: .api)
        try c.encodeIfPresent(searchable, forKey: .searchable)
        try c.encodeIfPresent(quickSearch, forKey: .quickSearch)
        try c.encodeIfPresent(filterable, forKey: .filterable)
        try c.encodeIfPresent(playerType, forKey: .playerType)
        try c.encodeIfPresent(ext, forKey: .ext)
        try c.encodeIfPresent(categories, forKey: .categories)
        try c.encodeIfPresent(jar, forKey: .jar)
    }

    var isSearchable: Bool { (searchable ?? 0) == 1 }
    var isFilterable: Bool { (filterable ?? 0) == 1 }
}
