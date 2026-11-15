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

    /// ランチャーショートカットの記録サスペンド制御・有効更新・双方向重複ブロックを検証する
    @Test("ランチャーショートカットの記録サスペンドと双方向重複ブロックが正しく機能する")
    @MainActor
    func launcherShortcutRecordingAndBidirectionalConflictBlock() {
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

        #expect(viewModel.launcherShortcut == .default)

        // 記録開始でホットキー監視がサスペンドされる
        viewModel.beginRecordingLauncherShortcut()
        #expect(viewModel.isRecordingLauncherShortcut == true)
        #expect(hotKeyMonitor.isSuspendedForRecording == true)

        // 通常スイッチャーの逆順（Option + Shift + Tab）と重複する場合はブロックされる
        let conflictWithReverse = LauncherShortcutPreference(keyCode: 48, modifiers: [.option, .shift], keyLabel: "⇥")
        viewModel.recordLauncherShortcut(conflictWithReverse)
        #expect(viewModel.launcherShortcut == .default)
        #expect(viewModel.shortcutValidationError != nil)
        #expect(store.saveLauncherCallCount == 0)

        // 有効な Control + Space を記録すると保存・反映され記録モードが終了する
        let controlSpace = LauncherShortcutPreference(keyCode: 49, modifiers: [.control], keyLabel: "Space")
        viewModel.recordLauncherShortcut(controlSpace)
        #expect(viewModel.launcherShortcut == controlSpace)
        #expect(viewModel.shortcutValidationError == nil)
        #expect(viewModel.isRecordingLauncherShortcut == false)
        #expect(hotKeyMonitor.isSuspendedForRecording == false)
        #expect(store.storedLauncherShortcut == controlSpace)
        #expect(hotKeyMonitor.updatedLauncherShortcuts.last == controlSpace)

        // 逆に通常スイッチャー側をランチャーと同じ Control + Space へ変更しようとした場合もブロックされる
        viewModel.updateModifier(.control) // 現在 trigger は .tab なので Control + Tab（重複しない）は通る
        #expect(viewModel.shortcut == ShortcutPreference(modifier: .control, trigger: .tab))

        viewModel.updateTrigger(.space) // Control + Space はランチャーと重複するためブロック
        #expect(viewModel.shortcut == ShortcutPreference(modifier: .control, trigger: .tab))
        #expect(viewModel.shortcutValidationError != nil)
    }

    /// 通常スイッチャーのキャプチャ記録・排他制御・Shift拒否・重複ブロックを検証する
    @Test("通常スイッチャーもキャプチャ方式で記録・排他・バリデーションできる")
    @MainActor
    func normalShortcutCaptureRecordingAndValidation() {
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

        // ランチャー記録中に通常スイッチャー記録を開始すると排他で切り替わる
        viewModel.beginRecordingLauncherShortcut()
        #expect(viewModel.isRecordingLauncherShortcut == true)
        viewModel.beginRecordingNormalShortcut()
        #expect(viewModel.isRecordingLauncherShortcut == false)
        #expect(viewModel.isRecordingNormalShortcut == true)
        #expect(hotKeyMonitor.isSuspendedForRecording == true)

        // Shift を含む組み合わせは拒否される
        let withShift = ShortcutPreference(keyCode: 40, modifiers: [.option, .shift], keyLabel: "K")
        viewModel.recordNormalShortcut(withShift)
        #expect(viewModel.shortcut == .default)
        #expect(viewModel.shortcutValidationTarget == .normal)
        #expect(viewModel.shortcutValidationError != nil)

        // ランチャー（Option + Space）と重複する場合もブロックされる
        let conflict = ShortcutPreference(keyCode: 49, modifiers: [.option], keyLabel: "Space")
        viewModel.recordNormalShortcut(conflict)
        #expect(viewModel.shortcut == .default)
        #expect(viewModel.shortcutValidationTarget == .normal)

        // 有効な Option + K を記録すると保存・監視反映され待機解除される
        let optionK = ShortcutPreference(keyCode: 40, modifiers: [.option], keyLabel: "K")
        viewModel.recordNormalShortcut(optionK)
        #expect(viewModel.shortcut == optionK)
        #expect(viewModel.shortcutValidationError == nil)
        #expect(viewModel.isRecordingNormalShortcut == false)
        #expect(hotKeyMonitor.isSuspendedForRecording == false)
        #expect(store.storedShortcut == optionK)
        #expect(hotKeyMonitor.updatedShortcuts.last == optionK)
    }

    /// 表示形式設定の初期値がリスト型であり、リスト型中は画面収録権限を一切確認・操作しないこと、
    /// およびキャプチャ表示型へ切り替えた場合のみオプトインで権限確認・リクエストできることを検証する
    @Test("表示形式の初期値はリスト型で画面収録権限を確認せず、キャプチャ型選択時のみ確認・要求する")
    @MainActor
    func displayStyleDefaultsToListAndOptInScreenRecording() {
        let store = MockPreferencesStore()
        let hotKeyMonitor = MockHotKeyMonitor()
        let launchService = MockLaunchAtLoginService()
        let permissionService = MockAccessibilityPermissionService()
        let screenRecordingService = MockScreenRecordingPermissionService()
        screenRecordingService.stubbedStatus = .denied

        let viewModel = SettingsViewModel(
            preferencesStore: store,
            hotKeyMonitor: hotKeyMonitor,
            launchAtLoginService: launchService,
            permissionService: permissionService,
            screenRecordingPermissionService: screenRecordingService
        )

        var notifiedStyles: [SwitcherDisplayStyle] = []
        viewModel.onNormalDisplayStyleChanged = { notifiedStyles.append($0) }

        // リスト型（初期値）では初期化時も refreshStatus 時も権限確認を一切呼ばない
        #expect(viewModel.normalDisplayStyle == .list)
        #expect(screenRecordingService.currentStatusCallCount == 0)

        viewModel.refreshStatus()
        viewModel.requestScreenRecordingPermission()
        viewModel.openScreenRecordingSettings()
        #expect(screenRecordingService.currentStatusCallCount == 0)
        #expect(screenRecordingService.requestPermissionCallCount == 0)
        #expect(screenRecordingService.openSystemSettingsCallCount == 0)

        // キャプチャ表示型へ切り替えると永続化・通知・権限確認が行われる
        viewModel.updateNormalDisplayStyle(.capture)
        #expect(viewModel.normalDisplayStyle == .capture)
        #expect(store.storedNormalDisplayStyle == .capture)
        #expect(store.saveNormalDisplayStyleCallCount == 1)
        #expect(notifiedStyles == [.capture])
        #expect(screenRecordingService.currentStatusCallCount == 1)
        #expect(viewModel.screenRecordingStatus == .denied)

        // キャプチャ表示型では権限リクエストおよびシステム設定遷移が可能
        screenRecordingService.requestPermissionResult = true
        screenRecordingService.stubbedStatus = .granted
        viewModel.requestScreenRecordingPermission()
        #expect(screenRecordingService.requestPermissionCallCount == 1)
        #expect(viewModel.screenRecordingStatus == .granted)

        viewModel.openScreenRecordingSettings()
        #expect(screenRecordingService.openSystemSettingsCallCount == 1)

        // リスト型へ戻すと設定が更新・通知され、以降の refreshStatus では再び画面収録権限を確認しない
        let countBeforeRevert = screenRecordingService.currentStatusCallCount
        viewModel.updateNormalDisplayStyle(.list)
        viewModel.refreshStatus()
        #expect(viewModel.normalDisplayStyle == .list)
        #expect(store.storedNormalDisplayStyle == .list)
        #expect(notifiedStyles == [.capture, .list])
        #expect(screenRecordingService.currentStatusCallCount == countBeforeRevert)
    }

    /// PreferencesStore が表示形式の初期値フォールバック・保存・読み込みを正しく行うことを検証する
    @Test("PreferencesStore で表示形式の保存と読み込み・不正値フォールバックが動作する")
    func preferencesStorePersistsNormalDisplayStyle() {
        let suiteName = "dev.wintch.tests.displayStyle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        defer { defaults?.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(suiteName: suiteName)
        #expect(store.loadNormalDisplayStyle() == .list)

        store.saveNormalDisplayStyle(.capture)
        #expect(store.loadNormalDisplayStyle() == .capture)

        // 不正値が入っている場合も安全にリスト型へフォールバックする
        defaults?.set("invalid-style", forKey: "dev.wintch.normalDisplayStyle")
        #expect(store.loadNormalDisplayStyle() == .list)
    }
}
