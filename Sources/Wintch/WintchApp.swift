import AppKit
import SwiftUI
import WintchCore

/// アプリ起動完了時にメニューバー常駐設定とコーディネーター開始を実行する AppDelegate
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// アプリ全体を制御する共有コーディネーター
    let coordinator = AppCoordinator()

    /// アプリケーション起動完了時に呼ばれるライフサイクルメソッド
    /// - Parameter notification: 起動通知
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock にアイコンを表示しないメニューバー常駐アプリとして動作させる
        NSApplication.shared.setActivationPolicy(.accessory)
        coordinator.start()
    }
}

/// Wintch アプリケーションのメインエントリポイント
@main
struct WintchApp: App {
    /// アプリ起動フック用の AppDelegate アダプタ
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// アプリケーションのルートシーン定義（メニューバー常駐アイコンとメニュー）
    var body: some Scene {
        MenuBarExtra {
            if appDelegate.coordinator.permissionStatus == .denied {
                Button("アクセシビリティ権限が必要です...") {
                    appDelegate.coordinator.openPermissionGuide()
                }

                Divider()
            }

            Button("設定を開く...") {
                appDelegate.coordinator.openSettings()
            }
            .keyboardShortcut(",")

            Divider()

            Button("Wintch を終了") {
                appDelegate.coordinator.quit()
            }
            .keyboardShortcut("q")
        } label: {
            if let menuBarImage = Self.loadMenuBarIcon() {
                Image(nsImage: menuBarImage)
            } else {
                Image(systemName: "circle.circle")
            }
        }
    }

    /// バンドル内のメニューバー用ウィンチ SVG アイコンをテンプレート画像として読み込む
    /// - Returns: テンプレート設定済みの NSImage（未バンドル実行時は nil）
    private static func loadMenuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
