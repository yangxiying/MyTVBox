# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Generate Xcode project via XcodeGen
xcodegen generate

# Open in Xcode
open MyTVBox.xcodeproj

# Build unsigned IPA locally
./build_ipa.sh

# CI (GitHub Actions)
# Push to main/master or manual trigger "Build IPA" in Actions tab
```

Target: iOS 16.0+, Xcode 15+, Swift 5.9. No third-party dependencies.

## Architecture

SwiftUI + Combine + AVKit/AVFoundation. MVVM pattern. Zero external dependencies.

### Layered Structure

```
MyTVBox/
├── Models/        # TVBox/CatPaw JSON data models
├── Services/      # Network, config parsing, CMS API calls
├── ViewModels/    # @MainActor ObservableObject state managers
├── Views/         # SwiftUI screens and components
├── Player/        # AVPlayer wrappers, playback controls, history
└── MyTVBoxApp.swift  # Entry point, orientation, background audio
```

### Key Flows

**Config loading**: `AppState.loadConfig()` → `ConfigService.loadConfig()` → downloads JSON (handles .md5, base64, array formats, CatPaw spider modules) → parses into `TVBoxConfig` (sites, lives, parses).

**Content browsing**: Site select → `ContentViewModel.loadCategories()` + `loadVideoList()` → `APIService` calls CMS `ac=class` / `ac=detail` endpoints → displays in `ContentGridView` with pagination.

**Video playback**: `VideoDetailView` → parse `vod_play_from`/`vod_play_url` ($$$/#/$ delimiters) into `[PlaySource]` → `VideoPlayerViewModel` drives `AVPlayer` → `PlayerControlsView` for controls. Fullscreen auto-rotates via `OrientationManager`.

**Audio playback**: `AudioPlayerManager` manages AVPlayer for audio URLs. Background playback via `AVAudioSession` category `.playback`. Supports playlist, shuffle, repeat, sleep timer.

### Critical Patterns

- **Flexible JSON decoding**: `Site`, `VideoCategory`, `VideoItem` handle Int/String polymorphism for `id`, `type`, etc. via custom `init(from:)`. See `decodeStringFlexible`/`decodeIntFlexible` extensions in `Site.swift`.
- **Network layer**: `NetworkManager` handles Basic Auth (user:pass@host in URL), redirect auth persistence, BOM/comment/trailing-comma JSON sanitization, GBK encoding fallback, multiple charset fallbacks. Timeout 20s request / 30s resource.
- **CatPaw integration**: `CatPawConfigBuilder` detects spider module URLs (`.js.md5`), attempts server `/config` endpoint, falls back to known CMS API addresses hardcoded from CatPawOpen source analysis.
- **Subscription persistence**: `AppState` manages `[Subscription]` in UserDefaults (JSON-encoded). First-launch seeds a default CatPaw-based source.

### Important Constraints

- **Type 3 (Spider/JAR) sites cannot execute on iOS** — only Type 0 (XPath) and Type 1 (API/CMS) work. The app auto-filters these and shows a warning.
- **NSAllowsArbitraryLoads = YES** for HTTP source compatibility — app communicates this trade-off.
- **Background video → audio**: When app enters background, AVPlayer video track must be disabled (posted via `appDidEnterBackground` notification) or iOS suspends playback.
- **Free provisioning (AltStore/etc.)**: IPA is unsigned; requires 7-day re-sign cycle.

## Key Commands

| Command | Description |
|---------|-------------|
| `brew install xcodegen` | Install XcodeGen once |
| `xcodegen generate` | Generate .xcodeproj from project.yml |
| `open MyTVBox.xcodeproj` | Open in Xcode |
| `./build_ipa.sh` | Build unsigned IPA |
| `rtk proxy ls` | List RPK proxy diagnostics (if RTK installed) |
