import Foundation

/// 通用的 JSON 任意值容器，便于 Codable 处理 ext 等不固定结构字段。
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable cannot decode value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: container.codingPath,
                                      debugDescription: "AnyCodable cannot encode value")
            )
        }
    }

    /// 便捷转 String
    public var stringValue: String? {
        if let s = value as? String { return s }
        if let i = value as? Int { return String(i) }
        if let d = value as? Double { return String(d) }
        if let b = value as? Bool { return String(b) }
        return nil
    }
}

// MARK: - 容错解码扩展
//
// TVBox / 猫爪 生态中，同一字段在不同源里可能是 Int / String / Double / Bool。
// 例如：`"playerType": 1` 与 `"playerType": "1"` 都常见。
// 此处提供宽松解码方法，避免因类型不一致导致整个配置解析失败。
extension KeyedDecodingContainer {

    /// 宽松解码 Int：支持 Int / Double / String / Bool
    func decodeIntFlexible(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if let i = Int(trimmed) { return i }
            if let d = Double(trimmed) { return Int(d) }
        }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b ? 1 : 0 }
        return nil
    }

    /// 宽松解码 String：支持 String / Int / Double / Bool
    func decodeStringFlexible(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return String(b) }
        return nil
    }
}
