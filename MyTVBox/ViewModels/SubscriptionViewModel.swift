import Foundation
import SwiftUI
import Combine

/// 接口订阅管理 ViewModel
///
/// 作为 `AppState` 的视图门面（facade）：所有持久化由 AppState 统一负责，
/// 这里只暴露面向视图的便捷 CRUD / 校验 / 加载语义。
///
/// 使用方式：
/// ```swift
/// @StateObject private var vm = SubscriptionViewModel()
/// // ...
/// .task { vm.attach(appState: appState) }
/// ```
@MainActor
final class SubscriptionViewModel: ObservableObject {

    // MARK: - 对外可观察状态

    @Published var subscriptions: [Subscription] = []
    @Published var activeId: UUID?
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    // MARK: - 依赖

    private weak var appState: AppState?

    init() {}

    /// 绑定 AppState（重复调用同一实例时安全）
    func attach(appState: AppState) {
        guard self.appState !== appState else { return }
        self.appState = appState

        // 同步初始值
        self.subscriptions = appState.subscriptions
        self.activeId = appState.activeSubscriptionId

        // 持续镜像 AppState 的状态变化（AppState 已在 MainActor 上发布）
        appState.$subscriptions
            .assign(to: &$subscriptions)
        appState.$activeSubscriptionId
            .assign(to: &$activeId)
    }

    // MARK: - 派生属性

    /// 当前激活订阅
    var activeSubscription: Subscription? {
        guard let id = activeId else { return nil }
        return subscriptions.first { $0.id == id }
    }

    // MARK: - CRUD

    /// 新增订阅；保存后自动尝试加载一次以验证可用性
    func addSubscription(name: String, url: String) async {
        guard let appState else { return }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedURL.isEmpty else {
            present(error: "URL 不能为空")
            return
        }
        guard isLikelyValidURL(trimmedURL) else {
            present(error: "URL 格式不合法")
            return
        }

        let displayName = trimmedName.isEmpty ? autoName(from: trimmedURL) : trimmedName
        let sub = Subscription(name: displayName, url: trimmedURL)
        appState.addSubscription(sub)

        // 自动测试可用性（首个订阅会被设置为 active）
        isLoading = true
        let ok = await testSubscription(url: trimmedURL)
        isLoading = false

        if !ok {
            present(error: "已保存，但无法解析配置：\(errorMessage.isEmpty ? "未知错误" : errorMessage)")
        }

        // 若添加完成后是激活源，则真正加载一次配置
        if appState.activeSubscriptionId == sub.id {
            await appState.loadConfig()
        }
    }

    /// 滑动删除
    func deleteSubscription(at offsets: IndexSet) {
        guard let appState else { return }
        let toDelete = offsets.map { subscriptions[$0] }
        for sub in toDelete {
            appState.removeSubscription(sub.id)
        }
    }

    /// 单条删除
    func deleteSubscription(_ subscription: Subscription) {
        appState?.removeSubscription(subscription.id)
    }

    /// 切换激活订阅，并立即加载其配置
    func activateSubscription(_ subscription: Subscription) async {
        guard let appState else { return }
        appState.setActive(subscription.id)
        isLoading = true
        await appState.loadConfig()
        isLoading = false
        if let err = appState.errorMessage {
            present(error: err)
        }
    }

    /// 验证一个 URL 是否能加载到合法配置
    @discardableResult
    func testSubscription(url: String) async -> Bool {
        do {
            _ = try await ConfigService.shared.loadConfig(from: url)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - 持久化代理

    func loadSubscriptions() {
        appState?.loadSubscriptions()
    }

    func saveSubscriptions() {
        appState?.saveSubscriptions()
    }

    // MARK: - 辅助

    /// 简单 URL 校验：协议 + 主机
    private func isLikelyValidURL(_ s: String) -> Bool {
        guard let url = URL(string: s) else { return false }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// 根据 URL 自动生成一个友好的名称
    private func autoName(from url: String) -> String {
        if let u = URL(string: url), let host = u.host, !host.isEmpty {
            return host
        }
        return "未命名接口"
    }

    private func present(error: String) {
        self.errorMessage = error
        self.showError = true
    }
}
