import Foundation

/// 播放记录管理（UserDefaults 持久化，最多保存 100 条）
final class PlayHistoryManager {
    static let shared = PlayHistoryManager()

    // MARK: - Model

    struct PlayRecord: Codable, Identifiable, Hashable {
        var id: String { vodId }
        let vodId: String
        let vodName: String
        let vodPic: String?
        let episodeName: String
        let sourceIndex: Int
        let episodeIndex: Int
        let progress: Double      // 播放进度（秒）
        let duration: Double      // 总时长（秒）
        let timestamp: Date       // 记录时间

        /// 进度百分比 (0...1)
        var percent: Double {
            guard duration > 0 else { return 0 }
            return min(max(progress / duration, 0), 1)
        }
    }

    // MARK: - Storage

    private let key = "MyTVBox.playHistory.v1"
    private let limit = 100
    private let queue = DispatchQueue(label: "MyTVBox.PlayHistory.queue")

    private init() {}

    // MARK: - Public API

    func saveRecord(_ record: PlayRecord) {
        queue.sync {
            var list = readAll()
            list.removeAll { $0.vodId == record.vodId }
            list.insert(record, at: 0)
            if list.count > limit {
                list = Array(list.prefix(limit))
            }
            writeAll(list)
        }
    }

    func getRecord(vodId: String) -> PlayRecord? {
        queue.sync {
            readAll().first { $0.vodId == vodId }
        }
    }

    func getAllRecords() -> [PlayRecord] {
        queue.sync { readAll() }
    }

    func deleteRecord(vodId: String) {
        queue.sync {
            var list = readAll()
            list.removeAll { $0.vodId == vodId }
            writeAll(list)
        }
    }

    func clearAll() {
        queue.sync {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Internal

    private func readAll() -> [PlayRecord] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PlayRecord].self, from: data)) ?? []
    }

    private func writeAll(_ list: [PlayRecord]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Favorite Manager (轻量收藏，配合详情页使用)

final class FavoritesManager {
    static let shared = FavoritesManager()
    private let key = "MyTVBox.favorites.v1"
    private init() {}

    struct FavoriteItem: Codable, Identifiable, Hashable {
        var id: String { vodId }
        let vodId: String
        let vodName: String
        let vodPic: String?
        let timestamp: Date
    }

    private func readAll() -> [FavoriteItem] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([FavoriteItem].self, from: data)) ?? []
    }

    private func writeAll(_ list: [FavoriteItem]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func isFavorite(vodId: String) -> Bool {
        readAll().contains { $0.vodId == vodId }
    }

    func toggle(vodId: String, vodName: String, vodPic: String?) -> Bool {
        var list = readAll()
        if let idx = list.firstIndex(where: { $0.vodId == vodId }) {
            list.remove(at: idx)
            writeAll(list)
            return false
        } else {
            let item = FavoriteItem(vodId: vodId, vodName: vodName, vodPic: vodPic, timestamp: Date())
            list.insert(item, at: 0)
            writeAll(list)
            return true
        }
    }

    func getAll() -> [FavoriteItem] { readAll() }
}
