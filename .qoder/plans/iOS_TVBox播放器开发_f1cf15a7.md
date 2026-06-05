# iOS TVBox 猫爪播放器开发计划

## 概述

从零构建一个原生 Swift/SwiftUI iOS 应用，支持导入 TVBox/猫爪格式的接口地址，解析视频/音频源，提供分类浏览、搜索、播放（含后台播放）等完整功能，最终生成可通过 AltStore 等工具侧载的 IPA 安装包。

## 技术架构

- **语言**: Swift 5.9+
- **UI框架**: SwiftUI + UIKit（播放器部分）
- **播放引擎**: AVKit / AVFoundation
- **网络层**: URLSession + async/await
- **数据持久化**: UserDefaults（接口地址） + FileManager（缓存）
- **最低支持**: iOS 16.0
- **构建工具**: Xcode 15+, xcodebuild 命令行

## 核心数据流

```
用户输入接口URL -> 下载JSON配置 -> 解析sites/lives/parses
  -> 展示分类列表 -> 选择视频/音频 -> 获取播放地址 -> AVPlayer播放
```

## 任务分解

### Task 1: 初始化 Xcode 项目结构

**目标**: 创建完整的 iOS 项目骨架

**产出**:
- `/Users/yangxiying/Documents/data/my-project/my-tvbox/MyTVBox.xcodeproj`
- SwiftUI App 入口 `MyTVBoxApp.swift`
- Info.plist 配置（后台音频模式、网络权限）
- 项目目录结构:
  ```
  MyTVBox/
  ├── MyTVBoxApp.swift
  ├── Info.plist
  ├── Assets.xcassets/
  ├── Models/          (数据模型)
  ├── Views/           (UI视图)
  ├── ViewModels/      (视图模型)
  ├── Services/        (网络/解析服务)
  └── Player/          (播放器模块)
  ```

**关键配置**:
- `UIBackgroundModes`: `audio`（后台音频播放）
- `NSAppTransportSecurity`: 允许 HTTP 连接（猫爪接口可能为HTTP）
- Bundle ID: `com.mytvbox.app`

---

### Task 2: 数据模型与接口解析服务

**目标**: 实现 TVBox/猫爪 JSON 配置的完整解析

**核心模型**:
```swift
// 顶层配置
struct TVBoxConfig: Codable {
    let spider: String?
    let sites: [Site]
    let lives: [LiveSource]?
    let parses: [ParseRule]?
}

// 站点（视频/音频源）
struct Site: Codable, Identifiable {
    let key: String
    let name: String
    let type: Int          // 0=XPath, 1=API, 3=Spider
    let api: String
    let searchable: Int?
    let categories: [String]?
}

// 分类和视频数据
struct VideoCategory { ... }
struct VideoItem { ... }
struct VideoDetail { ... }
struct PlayURL { ... }
```

**接口解析服务**:
- `ConfigService`: 下载并解析接口JSON配置（支持 HTTP Basic Auth）
- `APIService`: 根据 site.api 调用视频列表/详情/搜索接口
- 支持 URL 格式: `http://user:pass@host/path.json` 和 `.md5` 后缀

---

### Task 3: 接口地址管理模块

**目标**: 用户可添加、管理、切换接口地址

**功能**:
- 添加接口地址（手动输入 / 剪贴板导入）
- 接口地址列表管理（增删改、设为默认）
- 接口状态检测（可用/不可用标识）
- 持久化存储（UserDefaults）
- 首次启动引导用户添加接口

**UI页面**: `SubscriptionView` - 接口管理页面

---

### Task 4: 首页与分类浏览

**目标**: 展示接口中的视频/音频分类和内容列表

**功能**:
- TabView 主界面（首页 / 分类 / 搜索 / 收藏 / 设置）
- 首页推荐内容展示
- 分类列表 + 内容网格/列表展示
- 下拉刷新 + 上拉加载更多
- 视频/音频封面缩略图加载

**UI页面**: `HomeView`, `CategoryView`, `ContentListView`

---

### Task 5: 视频播放器模块

**目标**: 完整的视频播放体验

**功能**:
- 基于 AVPlayer 的自定义视频播放器
- 播放控制（播放/暂停/快进/快退/进度条）
- 全屏/竖屏切换
- 多线路切换（如果有多个播放源）
- 播放记录保存（续播功能）
- 画中画支持（PiP）
- 倍速播放（0.5x ~ 2.0x）

**UI页面**: `VideoPlayerView`（UIViewControllerRepresentable 封装 AVPlayerViewController）

---

### Task 6: 音频播放与后台播放

**目标**: 支持听书/听故事，后台继续播放

**功能**:
- 音频播放器界面（专辑封面、进度条、播放列表）
- AVAudioSession 配置为 `.playback` category
- 锁屏/控制中心显示 Now Playing 信息（MPNowPlayingInfoCenter）
- 远程控制响应（耳机线控、锁屏控制）
- 后台音频播放不中断
- 播放列表顺序/循环/随机模式
- 定时关闭功能

**关键代码**:
```swift
try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
try AVAudioSession.sharedInstance().setActive(true)
```

**UI页面**: `AudioPlayerView`, `MiniPlayerView`（底部迷你播放条）

---

### Task 7: 搜索与收藏功能

**目标**: 跨源搜索和内容收藏

**功能**:
- 全局搜索（支持多站点并发搜索）
- 搜索历史记录
- 收藏/稍后观看列表
- 观看历史记录

**UI页面**: `SearchView`, `FavoritesView`, `HistoryView`

---

### Task 8: 构建与打包 IPA

**目标**: 生成可侧载安装的 IPA 文件

**步骤**:
- 使用 xcodebuild 命令行构建 archive
- 导出为 unsigned IPA（适用于 AltStore/巨魔 签名）
- 构建脚本 `build_ipa.sh`:
  ```bash
  xcodebuild archive -project MyTVBox.xcodeproj \
    -scheme MyTVBox -archivePath build/MyTVBox.xcarchive \
    CODE_SIGNING_ALLOWED=NO
  # 从 xcarchive 中提取并打包为 IPA
  ```

**产出**: `MyTVBox.ipa` 文件

---

## 依赖关系

```
Task 1 (项目初始化)
  └── Task 2 (数据模型与解析) 
       └── Task 3 (接口管理)
       └── Task 4 (首页与分类) ── 依赖 Task 3
       └── Task 5 (视频播放器)
       └── Task 6 (音频与后台播放)
       └── Task 7 (搜索与收藏) ── 依赖 Task 3, Task 4
  └── Task 8 (构建IPA) ── 依赖所有前置任务完成
```

## 注意事项

1. **iOS无法执行JAR爬虫**: TVBox的Type=3(Spider)源在iOS上不可用，仅支持Type=0(XPath)和Type=1(API)类型的站点
2. **HTTP明文传输**: 猫爪接口可能使用HTTP，需要在Info.plist中配置ATS例外
3. **后台播放**: 必须在Capabilities中开启Background Modes -> Audio, AirPlay, and Picture in Picture
4. **自签名限制**: 通过AltStore侧载的应用每7天需要重新签名（免费开发者账号）
5. **网络认证**: 接口URL中的 `user:pass@host` 格式需要在URLSession中正确处理HTTP Basic Auth
