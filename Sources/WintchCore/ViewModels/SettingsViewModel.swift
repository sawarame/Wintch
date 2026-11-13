import Foundation
import Observation

/// 設定画面の状態管理（ショートカット、自動起動、権限ステータス）を行う ViewModel
@MainActor
@Observable
public final class SettingsViewModel {
    /// 現在のショートカット設定
    public private(set) var shortcut: ShortcutPreference

    /// ログイン時自動起動の有効状態
    public private(set) var isLaunchAtLoginEnabled: Bool

    /// 自動起動設定の更新に失敗した場合のエラーメッセージ
    public private(set) var launchAtLoginError: String?

    /// 現在のアクセシビリティ権限状態
    public private(set) var permissionStatus: AccessibilityPermissionStatus

    /// 設定永続化ストア
    private let preferencesStore: any PreferencesStoring
    /// グローバルホットキー監視サービス
    private let hotKeyMonitor: any HotKeyMonitoring
    /// ログイン時自動起動管理サービス
    private let launchAtLoginService: any LaunchAtLoginServicing
    /// アクセシビリティ権限管理サービス
    private let permissionService: any AccessibilityPermissionServicing

    /// 設定 ViewModel を初期化する
    /// - Parameters:
    ///   - preferencesStore: 設定永続化ストア
    ///   - hotKeyMonitor: ホットキー監視サービス
    ///   - launchAtLoginService: ログイン時自動起動サービス
    ///   - permissionService: アクセシビリティ権限サービス
    public init(
        preferencesStore: any PreferencesStoring,
        hotKeyMonitor: any HotKeyMonitoring,
        launchAtLoginService: any LaunchAtLoginServicing,
        permissionService: any AccessibilityPermissionServicing
    ) {
        self.preferencesStore = preferencesStore
        self.hotKeyMonitor = hotKeyMonitor
        self.launchAtLoginService = launchAtLoginService
        self.permissionService = permissionService
        self.shortcut = preferencesStore.loadShortcut()
        self.isLaunchAtLoginEnabled = launchAtLoginService.isEnabled
        self.permissionStatus = permissionService.currentStatus()
    }

    /// 修飾キーを更新して永続化および監視サービスへ即時反映する
    /// - Parameter modifier: 新しい修飾キー
    public func updateModifier(_ modifier: ModifierKeyOption) {
        let updated = ShortcutPreference(modifier: modifier, trigger: shortcut.trigger)
        applyShortcut(updated)
    }

    /// トリガーキーを更新して永続化および監視サービスへ即時反映する
    /// - Parameter trigger: 新しいトリガーキー
    public func updateTrigger(_ trigger: TriggerKeyOption) {
        let updated = ShortcutPreference(modifier: shortcut.modifier, trigger: trigger)
        applyShortcut(updated)
    }

    /// ログイン時自動起動の有効・無効を切り替える
    /// - Parameter enabled: 有効にする場合は true
    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "自動起動の設定変更に失敗しました（.app バンドルとして起動しているか確認してください）: \(error.localizedDescription)"
        }
        // OS 側の実ステータスと常に同期する
        isLaunchAtLoginEnabled = launchAtLoginService.isEnabled
    }

    /// 外部（システム設定）での変更を UI へ再同期する
    public func refreshStatus() {
        isLaunchAtLoginEnabled = launchAtLoginService.isEnabled
        permissionStatus = permissionService.currentStatus()
    }

    /// アクセシビリティ権限設定画面を開く
    public func openAccessibilitySettings() {
        permissionService.openAccessibilitySettings()
    }

    /// ショートカット変更を保存し、監視サービスへ即時適用する
    /// - Parameter updated: 更新後のショートカット設定
    private func applyShortcut(_ updated: ShortcutPreference) {
        shortcut = updated
        preferencesStore.saveShortcut(updated)
        hotKeyMonitor.updateShortcut(updated)
    }
}
