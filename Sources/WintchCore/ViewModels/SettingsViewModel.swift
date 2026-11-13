import Foundation
import Observation

/// ショートカット設定のエラー発生元セクション
public enum ShortcutValidationTarget: Equatable, Sendable {
    /// 通常スイッチャー設定
    case normal
    /// 検索ランチャー設定
    case launcher
}

/// 設定画面の状態管理（通常/ランチャーショートカット、記録状態、自動起動、権限ステータス）を行う ViewModel
@MainActor
@Observable
public final class SettingsViewModel {
    /// 現在の通常スイッチャー用ショートカット設定
    public private(set) var shortcut: ShortcutPreference

    /// 現在の検索ランチャー用ショートカット設定
    public private(set) var launcherShortcut: LauncherShortcutPreference

    /// 通常スイッチャーのショートカットレコーダーがキー入力待機中かどうか
    public private(set) var isRecordingNormalShortcut: Bool = false

    /// ランチャーショートカットレコーダーがキー入力待機中かどうか
    public private(set) var isRecordingLauncherShortcut: Bool = false

    /// ショートカットの妥当性検証または重複チェックのエラーメッセージ
    public private(set) var shortcutValidationError: String?

    /// エラーを表示すべきセクション対象
    public private(set) var shortcutValidationTarget: ShortcutValidationTarget?

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
        self.launcherShortcut = preferencesStore.loadLauncherShortcut()
        self.isLaunchAtLoginEnabled = launchAtLoginService.isEnabled
        self.permissionStatus = permissionService.currentStatus()
    }

    /// 通常スイッチャーの修飾キーを更新し、競合がなければ永続化および監視サービスへ即時反映する（互換用）
    /// - Parameter modifier: 新しい修飾キー
    public func updateModifier(_ modifier: ModifierKeyOption) {
        let candidate = ShortcutPreference(
            keyCode: shortcut.keyCode,
            modifiers: [modifier.shortcutModifierFlag],
            keyLabel: shortcut.keyLabel
        )
        applyNormalShortcutIfValid(candidate)
    }

    /// 通常スイッチャーのトリガーキーを更新し、競合がなければ永続化および監視サービスへ即時反映する（互換用）
    /// - Parameter trigger: 新しいトリガーキー
    public func updateTrigger(_ trigger: TriggerKeyOption) {
        let candidate = ShortcutPreference(
            keyCode: trigger.keyCode,
            modifiers: shortcut.modifiers,
            keyLabel: trigger.symbol
        )
        applyNormalShortcutIfValid(candidate)
    }

    /// 通常スイッチャーショートカットの記録待機を開始し、グローバルホットキー監視を一時停止する
    public func beginRecordingNormalShortcut() {
        isRecordingLauncherShortcut = false
        shortcutValidationError = nil
        shortcutValidationTarget = nil
        isRecordingNormalShortcut = true
        hotKeyMonitor.isSuspendedForRecording = true
    }

    /// 通常スイッチャーショートカットの記録待機をキャンセル・終了し、必要なら監視を再開する
    public func cancelRecordingNormalShortcut() {
        guard isRecordingNormalShortcut else { return }
        isRecordingNormalShortcut = false
        syncRecordingSuspension()
    }

    /// レコーダーから受け取った通常スイッチャーショートカット候補を検証し、有効なら保存・反映する
    /// - Parameter candidate: 入力された通常スイッチャーショートカット候補
    public func recordNormalShortcut(_ candidate: ShortcutPreference) {
        guard applyNormalShortcutIfValid(candidate) else { return }
        cancelRecordingNormalShortcut()
    }

    /// ランチャーショートカットの記録待機を開始し、グローバルホットキー監視を一時停止する
    public func beginRecordingLauncherShortcut() {
        isRecordingNormalShortcut = false
        shortcutValidationError = nil
        shortcutValidationTarget = nil
        isRecordingLauncherShortcut = true
        hotKeyMonitor.isSuspendedForRecording = true
    }

    /// ランチャーショートカットの記録待機をキャンセル・終了し、必要なら監視を再開する
    public func cancelRecordingLauncherShortcut() {
        guard isRecordingLauncherShortcut else { return }
        isRecordingLauncherShortcut = false
        syncRecordingSuspension()
    }

    /// レコーダーから受け取ったランチャーショートカット候補を検証し、有効なら保存・反映する
    /// - Parameter candidate: 入力されたショートカット候補
    public func recordLauncherShortcut(_ candidate: LauncherShortcutPreference) {
        let validation = ShortcutConflictValidator.validateLauncherShortcut(candidate, against: shortcut)
        guard validation.isValid else {
            shortcutValidationError = validation.errorMessage
            shortcutValidationTarget = .launcher
            return
        }

        shortcutValidationError = nil
        shortcutValidationTarget = nil
        launcherShortcut = candidate
        preferencesStore.saveLauncherShortcut(candidate)
        hotKeyMonitor.updateLauncherShortcut(candidate)
        cancelRecordingLauncherShortcut()
    }

    /// 進行中のすべてのショートカット記録待機を解除し、ホットキー監視を再開する
    public func cancelAllRecordings() {
        isRecordingNormalShortcut = false
        isRecordingLauncherShortcut = false
        hotKeyMonitor.isSuspendedForRecording = false
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

    /// 通常ショートカット候補をランチャーとの競合チェック付きで適用・保存する
    /// - Parameter candidate: 変更候補のショートカット設定
    /// - Returns: 検証を通過して適用された場合は true
    @discardableResult
    private func applyNormalShortcutIfValid(_ candidate: ShortcutPreference) -> Bool {
        let validation = ShortcutConflictValidator.validateNormalShortcut(candidate, against: launcherShortcut)
        guard validation.isValid else {
            shortcutValidationError = validation.errorMessage
            shortcutValidationTarget = .normal
            return false
        }

        shortcutValidationError = nil
        shortcutValidationTarget = nil
        shortcut = candidate
        preferencesStore.saveShortcut(candidate)
        hotKeyMonitor.updateShortcut(candidate)
        return true
    }

    /// いずれかのレコーダーが待機中かどうかに合わせて監視サスペンド状態を同期する
    private func syncRecordingSuspension() {
        hotKeyMonitor.isSuspendedForRecording = isRecordingNormalShortcut || isRecordingLauncherShortcut
    }
}
