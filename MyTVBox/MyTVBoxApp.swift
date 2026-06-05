import SwiftUI
import UIKit

// MARK: - AppDelegate（管理运行时方向锁定）

class AppDelegate: NSObject, UIApplicationDelegate {
    /// 当前允许的方向
    var orientationLock: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        orientationLock
    }

    /// 获取共享 AppDelegate 实例
    static var shared: AppDelegate? {
        UIApplication.shared.delegate as? AppDelegate
    }
}

// MARK: - 方向管理器

@MainActor
enum OrientationManager {
    /// 强制横屏（全屏播放时调用）
    static func forceLandscape() {
        AppDelegate.shared?.orientationLock = .landscape
        forceOrientation(.landscapeRight)
    }

    /// 恢复竖屏（退出全屏时调用）
    static func forcePortrait() {
        AppDelegate.shared?.orientationLock = .allButUpsideDown
        forceOrientation(.portrait)
    }

    private static func forceOrientation(_ orientation: UIInterfaceOrientation) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        if #available(iOS 16.0, *) {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientationMask(for: orientation))) { _ in }
            // iOS 16+ 仍需设置 device orientation 以触发 SwiftUI 布局刷新
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        } else {
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        }
    }

    private static func orientationMask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .landscapeLeft:  return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portrait:       return .portrait
        default:              return .allButUpsideDown
        }
    }
}

@main
struct MyTVBoxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
