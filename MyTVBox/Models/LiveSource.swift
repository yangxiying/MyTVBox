import Foundation

/// 直播源
struct LiveSource: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let type: Int?
    let url: String?
    let playerType: Int?
    let epg: String?
    let logo: String?

    enum CodingKeys: String, CodingKey {
        case name, type, url, playerType, epg, logo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "未命名"
        self.type = try? c.decodeIfPresent(Int.self, forKey: .type)
        self.url = try? c.decodeIfPresent(String.self, forKey: .url)
        self.playerType = try? c.decodeIfPresent(Int.self, forKey: .playerType)
        self.epg = try? c.decodeIfPresent(String.self, forKey: .epg)
        self.logo = try? c.decodeIfPresent(String.self, forKey: .logo)
    }

    init(name: String,
         type: Int? = nil,
         url: String? = nil,
         playerType: Int? = nil,
         epg: String? = nil,
         logo: String? = nil) {
        self.name = name
        self.type = type
        self.url = url
        self.playerType = playerType
        self.epg = epg
        self.logo = logo
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(playerType, forKey: .playerType)
        try c.encodeIfPresent(epg, forKey: .epg)
        try c.encodeIfPresent(logo, forKey: .logo)
    }
}
