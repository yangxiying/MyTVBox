import Foundation
import SwiftUI

/// 订阅源（用户添加的接口地址）
struct Subscription: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var url: String
    var isActive: Bool
    var lastUpdated: Date?

    init(id: UUID = UUID(),
         name: String,
         url: String,
         isActive: Bool = true,
         lastUpdated: Date? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.isActive = isActive
        self.lastUpdated = lastUpdated
    }
}

/// 全局应用状态
@MainActor
final class AppState: ObservableObject {

    // MARK: - 配置

    @Published var currentConfig: TVBoxConfig?
    @Published var currentSite: Site?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published var subscriptions: [Subscription] = []
    @Published var activeSubscriptionId: UUID?

    // MARK: - 私有

    private let subscriptionsKey = "MyTVBox.subscriptions"
    private let activeSubKey = "MyTVBox.activeSubscription"
    private let activeSiteKey = "MyTVBox.activeSite"
    private let didSeedDefaultKey = "MyTVBox.didSeedDefaultSubscription"

    // MARK: - 默认订阅源
    private static let defaultSubscriptionName = "默认源"
    private static let defaultSubscriptionURL = "http://wexfnw:wexfnw@cat.xn--4kq62z5rby2qupq9ub.top/index.js.md5"

    init() {
        loadSubscriptions()
        seedDefaultSubscriptionIfNeeded()
    }

    // MARK: - 订阅持久化

    func loadSubscriptions() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: subscriptionsKey),
           let arr = try? JSONDecoder().decode([Subscription].self, from: data) {
            self.subscriptions = arr
        }
        if let s = defaults.string(forKey: activeSubKey),
           let uuid = UUID(uuidString: s) {
            self.activeSubscriptionId = uuid
        }
    }

    /// 首次启动时注入内置默认订阅源，并设为激活
    private func seedDefaultSubscriptionIfNeeded() {
        let defaults = UserDefaults.standard
        // 已经注入过则不再重复
        if defaults.bool(forKey: didSeedDefaultKey) { return }
        // 用户已自行添加过订阅则不注入
        guard subscriptions.isEmpty else {
            defaults.set(true, forKey: didSeedDefaultKey)
            return
        }
        let sub = Subscription(
            name: Self.defaultSubscriptionName,
            url: Self.defaultSubscriptionURL,
            isActive: true
        )
        subscriptions.append(sub)
        activeSubscriptionId = sub.id
        saveSubscriptions()
        defaults.set(true, forKey: didSeedDefaultKey)
    }

    func saveSubscriptions() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(subscriptions) {
            defaults.set(data, forKey: subscriptionsKey)
        }
        if let id = activeSubscriptionId {
            defaults.set(id.uuidString, forKey: activeSubKey)
        } else {
            defaults.removeObject(forKey: activeSubKey)
        }
    }

    func addSubscription(_ sub: Subscription) {
        subscriptions.append(sub)
        if activeSubscriptionId == nil {
            activeSubscriptionId = sub.id
        }
        saveSubscriptions()
    }

    func removeSubscription(_ id: UUID) {
        subscriptions.removeAll { $0.id == id }
        if activeSubscriptionId == id {
            activeSubscriptionId = subscriptions.first?.id
        }
        saveSubscriptions()
    }

    func updateSubscription(_ sub: Subscription) {
        if let idx = subscriptions.firstIndex(where: { $0.id == sub.id }) {
            subscriptions[idx] = sub
            saveSubscriptions()
        }
    }

    func setActive(_ id: UUID) {
        activeSubscriptionId = id
        saveSubscriptions()
    }

    var activeSubscription: Subscription? {
        guard let id = activeSubscriptionId else { return nil }
        return subscriptions.first { $0.id == id }
    }

    /// 是否存在已激活的订阅源
    var hasActiveSubscription: Bool {
        activeSubscription != nil
    }

    // MARK: - 配置加载

    /// 加载当前激活订阅的配置
    func loadConfig() async {
        guard let sub = activeSubscription else {
            self.errorMessage = "未选择订阅源"
            return
        }
        await loadConfig(from: sub.url, subscriptionId: sub.id)
    }

    /// 从指定 URL 加载配置（并更新订阅时间戳）
    func loadConfig(from url: String, subscriptionId: UUID? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let cfg = try await ConfigService.shared.loadConfig(from: url)
            self.currentConfig = cfg
            // 默认选中第一个站点
            if currentSite == nil, let first = cfg.sites?.first {
                self.currentSite = first
            }
            // 更新订阅时间戳
            if let sid = subscriptionId,
               let idx = subscriptions.firstIndex(where: { $0.id == sid }) {
                subscriptions[idx].lastUpdated = Date()
                saveSubscriptions()
            }
        } catch {
            self.errorMessage = error.localizedDescription
            self.currentConfig = nil
        }
    }

    /// 切换当前站点
    func selectSite(_ site: Site) {
        self.currentSite = site
    }
}
