import Foundation
import Testing
@testable import WintchCore

/// テスト用のダミーエラー
private struct MockLaunchError: LocalizedError {
    var errorDescription: String? { "モック登録エラー" }
}

/// SettingsViewModel の設定保存・監視反映・自動起動切り替えを検証するテストスイート
@Suite("SettingsViewModel テスト")
struct SettingsViewModelTests {
    /// 修飾キーとトリガーキーを変更した際に永続化とホットキー監視への即時反映が行われることを検証する
    @Test("ショートカット変更がストア保存とホットキー監視へ即時反映される")
    @MainActor
    func shortcutChangePersistsAndUpdatesMonitor() {
        let store = MockPreferencesStore()
        let hotKeyMonitor = MockHotKeyMonitor()
        let launchService = MockLaunchAtLoginService()
        let permissionService = MockAccessibilityPermissionService()

        let viewModel = SettingsViewModel(
            preferencesStore: store,
            hotKeyMonitor: hotKeyMonitor,
            launchAtLoginService: launchService,
            permissionService: permissionService
        )

        #expect(viewModel.shortcut == .default)

        viewModel.updateModifier(.control)
        viewModel.updateTrigger(.space)

        let expected = ShortcutPreference(modifier: .control, trigger: .space)
        #expect(viewModel.shortcut == expected)
        #expect(store.storedShortcut == expected)
        #expect(store.saveCallCount == 2)
        #expect(hotKeyMonitor.updatedShortcuts.last == expected)
    }

    /// ログイン時自動起動のトグル成功および失敗時のロールバックを検証する
    @Test("自動起動トグルの成功とエラー時のロールバック・メッセージ表示")
    @MainActor
    func launchAtLoginToggleAndErrorHandling() {
        let store = MockPreferencesStore()
        let hotKeyMonitor = MockHotKeyMonitor()
        let launchService = MockLaunchAtLoginService()
        let permissionService = MockAccessibilityPermissionService()

        let viewModel = SettingsViewModel(
            preferencesStore: store,
            hotKeyMonitor: hotKeyMonitor,
            launchAtLoginService: launchService,
            permissionService: permissionService
        )

        // 成功ケース
        viewModel.setLaunchAtLogin(true)
        #expect(viewModel.isLaunchAtLoginEnabled == true)
        #expect(launchService.isEnabled == true)
        #expect(viewModel.launchAtLoginError == nil)

        // 失敗ケース（状態が元の true に戻りエラーメッセージが表示される）
        launchService.errorToThrow = MockLaunchError()
        viewModel.setLaunchAtLogin(false)
        #expect(viewModel.isLaunchAtLoginEnabled == true)
        #expect(viewModel.launchAtLoginError != nil)
    }
}
