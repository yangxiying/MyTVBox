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
    private var loadedSiteKey: String?

    // MARK: - 接口

    func loadCategories(site: Site) async {
        errorMessage = nil
        do {
            if site.type == 3, let code = SpiderContextManager.shared.moduleCode(for: site.key) {
                let result = await SpiderEngine.shared.execute(jsCode: code, method: "home", args: [:], spiderKey: site.spiderKey)
                if let classList = result?["class"] as? [[String: Any]] {
                    self.categories = classList.compactMap { dict in
                        guard let typeId = dict["type_id"] as? String ?? (dict["type_id"] as? Int).map(String.init),
                              let typeName = dict["type_name"] as? String else { return nil }
                        return VideoCategory(typeId: typeId, typeName: typeName)
                    }
                }
            } else {
                let cats = try await apiService.fetchCategories(site: site)
                self.categories = cats
            }
        } catch {
            self.errorMessage = error.localizedDescription
            self.categories = []
        }
    }

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
            if site.type == 3, let code = SpiderContextManager.shared.moduleCode(for: site.key) {
                let args: [String: Any] = ["id": typeId, "pg": 1]
                let result = await SpiderEngine.shared.execute(jsCode: code, method: "category", args: args, spiderKey: site.spiderKey)
                guard loadedSiteKey == site.key else { return }
                let parsed = parseSpiderList(result)
                self.videoList = parsed.list
                self.totalPages = max(1, parsed.pageCount)
                self.currentPage = parsed.page
            } else {
                let resp = try await apiService.fetchVideoList(site: site, categoryId: typeId, page: 1)
                guard loadedSiteKey == site.key else { return }
                self.videoList = resp.list ?? []
                self.totalPages = max(1, resp.pagecount ?? 1)
                self.currentPage = resp.page ?? 1
            }
        } catch {
            guard loadedSiteKey == site.key else { return }
            self.errorMessage = error.localizedDescription
        }
    }

    func loadMore(site: Site) async {
        guard !isLoading, !isLoadingMore else { return }
        guard currentPage < totalPages else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextPage = currentPage + 1
        let typeId = currentCategory?.typeId ?? ""
        do {
            if site.type == 3, let code = SpiderContextManager.shared.moduleCode(for: site.key) {
                let args: [String: Any] = ["id": typeId, "pg": nextPage]
                let result = await SpiderEngine.shared.execute(jsCode: code, method: "category", args: args, spiderKey: site.spiderKey)
                guard loadedSiteKey == site.key else { return }
                let parsed = parseSpiderList(result)
                let known = Set(self.videoList.map { $0.vodId })
                let appended = parsed.list.filter { !known.contains($0.vodId) }
                self.videoList.append(contentsOf: appended)
                self.totalPages = max(self.totalPages, parsed.pageCount)
                self.currentPage = nextPage
            } else {
                let resp = try await apiService.fetchVideoList(site: site, categoryId: typeId, page: nextPage)
                guard loadedSiteKey == site.key else { return }
                if let items = resp.list {
                    let known = Set(self.videoList.map { $0.vodId })
                    let appended = items.filter { !known.contains($0.vodId) }
                    self.videoList.append(contentsOf: appended)
                }
                self.totalPages = max(self.totalPages, resp.pagecount ?? self.totalPages)
                self.currentPage = resp.page ?? nextPage
            }
        } catch {
            print("[ContentViewModel] loadMore error: \(error.localizedDescription)")
        }
    }

    func refresh(site: Site) async {
        await loadVideoList(site: site, category: currentCategory)
    }

    // MARK: - Spider 结果解析

    private struct SpiderListResult {
        var list: [VideoItem]
        var page: Int
        var pageCount: Int
    }

    private func parseSpiderList(_ result: [String: Any]?) -> SpiderListResult {
        guard let result = result else { return SpiderListResult(list: [], page: 1, pageCount: 1) }
        let vodList = (result["list"] as? [[String: Any]] ?? []).map { dict -> VideoItem in
            VideoItem(
                vodId: dict["vod_id"] as? String ?? "\(dict["vod_id"] ?? "")",
                vodName: dict["vod_name"] as? String ?? "",
                vodPic: dict["vod_pic"] as? String,
                vodRemarks: dict["vod_remarks"] as? String,
                vodYear: dict["vod_year"] as? String,
                vodArea: dict["vod_area"] as? String
            )
        }
        return SpiderListResult(
            list: vodList,
            page: (result["page"] as? Int) ?? 1,
            pageCount: (result["pagecount"] as? Int) ?? 1
        )
    }
}
