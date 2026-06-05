# MyTVBox - iOS 视频聚合播放器

基于 SwiftUI 的 iOS 视频聚合播放器，兼容 TVBox / 猫爪 JSON 配置格式，支持多源订阅、多站点切换、视频与音频播放。

> 本项目仅提供播放器框架本身，不内置任何内容源，所有订阅源均由用户自行添加。

---

## 功能特性

- **多源订阅管理**：支持导入 TVBox / 猫爪 标准 JSON 配置（URL 订阅）
- **多站点切换**：在已订阅源的多个站点间自由切换浏览
- **视频搜索**：支持当前订阅下的全站点聚合搜索
- **视频播放**：多线路、多集数选择，自动记录并续播进度
- **音频播放**：后台播放、锁屏控制、播放模式切换、定时关闭
- **收藏与历史**：本地收藏夹与播放历史记录
- **深色主题 UI**：默认深色风格，符合影音类应用使用习惯

---

## 环境要求

- iOS 16.0+
- Xcode 14.0+（本地构建；CI 使用 Xcode 15.2）
- [XcodeGen](https://github.com/yonyomaru/XcodeGen)（用于生成 `.xcodeproj`）
- Swift 5.9

> macOS 仅安装 Command Line Tools 无法构建 iOS 应用，必须安装完整 Xcode。

---

## 构建方式

### 方式一：本地构建（推荐开发者使用）

```bash
# 1. 安装 xcodegen
brew install xcodegen

# 2. 生成 Xcode 工程
xcodegen generate

# 3. 打开工程
open MyTVBox.xcodeproj
```

随后在 Xcode 中选择真机或模拟器运行即可。

### 方式二：GitHub Actions 自动构建

- 推送代码到 `main` 或 `master` 分支自动触发构建
- 也可在仓库 **Actions** 页面手动触发 `Build IPA` 工作流
- 构建产物 `MyTVBox-IPA` 在 Workflow 运行结果的 **Artifacts** 中下载

工作流配置见 [.github/workflows/build-ipa.yml](.github/workflows/build-ipa.yml)。

### 方式三：本地生成免签名 IPA

```bash
./build_ipa.sh
```

执行成功后，IPA 产物输出到：

```
./build/ipa/MyTVBox.ipa
```

---

## 使用方法

1. **添加订阅**：首次启动后进入「订阅」页，添加 TVBox / 猫爪 配置 URL
2. **浏览内容**：在「首页」选择站点，按分类浏览或使用搜索
3. **播放视频**：进入详情页 → 选择线路 → 选择集数 → 开始播放
4. **音频模式**：进入音频列表后即可后台播放，支持锁屏与控制中心控制
5. **收藏与历史**：在「我的」页查看收藏与播放历史，可直接点击续播

---

## 注意事项

- 本应用仅为播放器外壳，**不内置任何内容源**，需用户自行添加合法的第三方接口
- 请确保所使用的订阅源与内容**符合所在地区法律法规**，由此引发的责任由使用者自行承担
- 应用启用了 `NSAllowsArbitraryLoads`（允许 HTTP 明文传输）以兼容部分接口，请避免在不可信网络环境下使用
- TVBox 配置中 `Type=3 (Spider/JAR 爬虫)` 类型的源在 iOS 上**无法执行**，仅支持 `Type=0 (XPath)` 与 `Type=1 (API)`
- 接口 URL 形如 `user:pass@host` 的 HTTP Basic Auth 已在网络层处理
- IPA 为**免签名包**，需配合 [AltStore](https://altstore.io/) / [TrollStore](https://github.com/opa334/TrollStore) 等工具安装，或自行使用开发者证书签名
- 通过 AltStore 等免费签名方案安装的应用，需每 7 天重新签名一次

---

## 项目结构

```
my-tvbox/
├── MyTVBox/
│   ├── Models/             # 数据模型（TVBoxConfig、Site、VideoModels 等）
│   ├── Services/           # 网络与配置服务（APIService、ConfigService）
│   ├── ViewModels/         # 状态管理（AppState、ContentViewModel 等）
│   ├── Views/              # SwiftUI 页面与组件
│   ├── Player/             # 视频/音频播放器及历史管理
│   ├── Assets.xcassets/    # 图标与颜色资源
│   ├── Info.plist
│   └── MyTVBoxApp.swift    # 应用入口
├── .github/workflows/
│   └── build-ipa.yml       # GitHub Actions CI 配置
├── project.yml             # XcodeGen 工程配置
├── build_ipa.sh            # 本地免签名 IPA 构建脚本
└── README.md
```

---

## 技术栈

- **SwiftUI** + **Combine**：声明式 UI 与响应式数据流
- **AVKit / AVFoundation**：视频与音频播放
- **URLSession**：原生网络请求
- **UserDefaults**：本地数据持久化（订阅、收藏、历史）
- **零第三方依赖**：项目不引入任何 CocoaPods / SPM 第三方包

---

## License

[MIT License](LICENSE)
