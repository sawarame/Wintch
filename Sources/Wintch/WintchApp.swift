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

    /// メニューバーと設定画面で共有される通常スイッチャー表示形式の双方向バインディング
    private var normalDisplayStyleBinding: Binding<SwitcherDisplayStyle> {
        Binding(
            get: { appDelegate.coordinator.normalDisplayStyle },
            set: { appDelegate.coordinator.updateNormalDisplayStyle($0) }
        )
    }

    /// メニューバーと設定画面で共有される検索ランチャー表示形式の双方向バインディング
    private var launcherDisplayStyleBinding: Binding<LauncherDisplayStyle> {
        Binding(
            get: { appDelegate.coordinator.launcherDisplayStyle },
            set: { appDelegate.coordinator.updateLauncherDisplayStyle($0) }
        )
    }

    /// アプリケーションのルートシーン定義（メニューバー常駐アイコンとメニュー）
    var body: some Scene {
        MenuBarExtra {
            if appDelegate.coordinator.permissionStatus == .denied {
                Button("アクセシビリティ権限が必要です...") {
                    appDelegate.coordinator.openPermissionGuide()
                }

                Divider()
            }

            Menu("表示形式") {
                Section("通常スイッチャー") {
                    Picker("通常スイッチャー", selection: normalDisplayStyleBinding) {
                        ForEach(SwitcherDisplayStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("検索ランチャー") {
                    Picker("検索ランチャー", selection: launcherDisplayStyleBinding) {
                        ForEach(LauncherDisplayStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }

            Button("設定を開く...") {
                appDelegate.coordinator.openSettings()
            }
            .keyboardShortcut(",")

            Divider()

            Button(appDelegate.coordinator.appIdentity.quitMenuTitle) {
                appDelegate.coordinator.quit()
            }
            .keyboardShortcut("q")
        } label: {
            if let menuBarImage = Self.loadMenuBarIcon() {
                Image(nsImage: menuBarImage)
            } else {
                Image(systemName: "macwindow.on.rectangle")
            }
        }
    }

    /// バンドル内のメニューバー用 SVG アイコンをテンプレート画像として読み込む
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
