import Foundation
import SwiftUI

/// 内容浏览 ViewModel —— 负责分类、视频列表、分页与刷新
@MainActor
final class ContentViewModel: ObservableObject {

    // MARK: - Published

    @Published var categories: [VideoCategory] = []
    @Published var currentCategory: VideoCategory?
    @Published var videoList: [VideoItem] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var currentPage: Int = 1
    @Published var totalPages: Int = 1
    @Published var errorMessage: String?

    // MARK: - 私有

    private let apiService = APIService.shared
    /// 记录最后一次拉取所属的站点 key，避免站点切换后旧请求结果污染
    private var loadedSiteKey: String?

    // MARK: - 接口

    /// 加载分类列表（连同来自 ac=class 的 list 一并拿到的视频会被忽略，
    /// 调用方需另外调用 loadVideoList 来拿数据）
    func loadCategories(site: Site) async {
        errorMessage = nil
        do {
            let cats = try await apiService.fetchCategories(site: site)
            self.categories = cats
        } catch {
            self.errorMessage = error.localizedDescription
            self.categories = []
        }
    }

    /// 加载某分类（nil 表示全站最新）的视频列表（重置为第 1 页）
    func loadVideoList(site: Site, category: VideoCategory?) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        currentCategory = category
        currentPage = 1
        totalPages = 1
        videoList = []
        loadedSiteKey = site.key
        defer { isLoading = false }

        let typeId = category?.typeId ?? ""
        do {
            let resp = try await apiService.fetchVideoList(
                site: site, categoryId: typeId, page: 1
            )
            // 切换太快时，避免旧响应覆盖新站点
            guard loadedSiteKey == site.key else { return }
            self.videoList = resp.list ?? []
            self.totalPages = max(1, resp.pagecount ?? 1)
            self.currentPage = resp.page ?? 1
        } catch {
            guard loadedSiteKey == site.key else { return }
            self.errorMessage = error.localizedDescription
        }
    }

    /// 加载下一页（如果还有更多）
    func loadMore(site: Site) async {
        guard !isLoading, !isLoadingMore else { return }
        guard currentPage < totalPages else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextPage = currentPage + 1
        let typeId = currentCategory?.typeId ?? ""
        do {
            let resp = try await apiService.fetchVideoList(
                site: site, categoryId: typeId, page: nextPage
            )
            guard loadedSiteKey == site.key else { return }
            if let items = resp.list {
                // 简单去重（按 vod_id）
                let known = Set(self.videoList.map { $0.vodId })
                let appended = items.filter { !known.contains($0.vodId) }
                self.videoList.append(contentsOf: appended)
            }
            self.totalPages = max(self.totalPages, resp.pagecount ?? self.totalPages)
            self.currentPage = resp.page ?? nextPage
        } catch {
            // 加载更多的错误不弹整页，控制台输出即可
            print("[ContentViewModel] loadMore error: \(error.localizedDescription)")
        }
    }

    /// 下拉刷新（保留当前分类）
    func refresh(site: Site) async {
        await loadVideoList(site: site, category: currentCategory)
    }
}
