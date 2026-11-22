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

        // アイコン型へ切り替えた場合も永続化・通知が行われ、画面収録権限の確認・要求・設定遷移は一切行わない
        viewModel.updateNormalDisplayStyle(.icon)
        viewModel.refreshStatus()
        viewModel.requestScreenRecordingPermission()
        viewModel.openScreenRecordingSettings()
        #expect(viewModel.normalDisplayStyle == .icon)
        #expect(store.storedNormalDisplayStyle == .icon)
        #expect(notifiedStyles == [.capture, .list, .icon])
        #expect(viewModel.screenRecordingStatus == .denied)
        #expect(screenRecordingService.currentStatusCallCount == countBeforeRevert)
        #expect(screenRecordingService.requestPermissionCallCount == 1)
        #expect(screenRecordingService.openSystemSettingsCallCount == 1)
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

        store.saveNormalDisplayStyle(.icon)
        #expect(store.loadNormalDisplayStyle() == .icon)

        store.saveNormalDisplayStyle(.capture)
        #expect(store.loadNormalDisplayStyle() == .capture)

        // 不正値が入っている場合も安全にリスト型へフォールバックする
        defaults?.set("invalid-style", forKey: "dev.wintch.normalDisplayStyle")
        #expect(store.loadNormalDisplayStyle() == .list)
    }

    /// PreferencesStore が検索ランチャー表示形式の初期値・保存・読み込み・不正値フォールバックを通常設定と独立して行えることを検証する
    @Test("PreferencesStore で検索ランチャー表示形式の永続化と不正値フォールバックが通常設定と独立して動作する")
    func preferencesStorePersistsLauncherDisplayStyleIndependently() {
        let suiteName = "dev.wintch.tests.launcherDisplayStyle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        defer { defaults?.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(suiteName: suiteName)
        #expect(store.loadNormalDisplayStyle() == .list)
        #expect(store.loadLauncherDisplayStyle() == .list)

        // ランチャーのみキャプチャ表示型へ変更しても通常スイッチャー設定へ影響しない
        store.saveLauncherDisplayStyle(.capture)
        #expect(store.loadLauncherDisplayStyle() == .capture)
        #expect(store.loadNormalDisplayStyle() == .list)

        // 通常スイッチャーをアイコン型へ変更してもランチャー設定へ影響しない
        store.saveNormalDisplayStyle(.icon)
        #expect(store.loadNormalDisplayStyle() == .icon)
        #expect(store.loadLauncherDisplayStyle() == .capture)

        // ランチャー非対応の "icon" や不正値が入っている場合は安全にリスト型へフォールバックする
        defaults?.set("icon", forKey: "dev.wintch.launcherDisplayStyle")
        #expect(store.loadLauncherDisplayStyle() == .list)

        defaults?.set("unknown-style", forKey: "dev.wintch.launcherDisplayStyle")
        #expect(store.loadLauncherDisplayStyle() == .list)
    }

    /// 検索ランチャーの表示形式を通常スイッチャーと独立して切り替えられ、
    /// どちらか一方でもキャプチャ表示型の間のみオプトインで画面収録権限の確認・要求・設定遷移が可能になることを検証する
    @Test("検索ランチャー表示形式の個別切り替えと双方非キャプチャ時の画面収録権限非参照を検証する")
    @MainActor
    func launcherDisplayStyleOptInScreenRecordingAndIndependentSwitching() {
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

        var notifiedLauncherStyles: [LauncherDisplayStyle] = []
        viewModel.onLauncherDisplayStyleChanged = { notifiedLauncherStyles.append($0) }

        // 初期状態（通常=リスト型、ランチャー=リスト型）では画面収録権限を一切確認しない
        #expect(viewModel.normalDisplayStyle == .list)
        #expect(viewModel.launcherDisplayStyle == .list)
        #expect(viewModel.usesCaptureDisplayStyle == false)
        #expect(screenRecordingService.currentStatusCallCount == 0)

        // 検索ランチャーのみキャプチャ表示型へ変更すると永続化・通知・権限確認が行われる
        viewModel.updateLauncherDisplayStyle(.capture)
        #expect(viewModel.normalDisplayStyle == .list)
        #expect(viewModel.launcherDisplayStyle == .capture)
        #expect(viewModel.usesCaptureDisplayStyle == true)
        #expect(store.storedLauncherDisplayStyle == .capture)
        #expect(store.saveLauncherDisplayStyleCallCount == 1)
        #expect(notifiedLauncherStyles == [.capture])
        #expect(screenRecordingService.currentStatusCallCount == 1)
        #expect(viewModel.screenRecordingStatus == .denied)

        // ランチャーのみキャプチャ表示型の状態でも権限リクエスト・設定遷移・再確認が機能する
        screenRecordingService.requestPermissionResult = true
        screenRecordingService.stubbedStatus = .granted
        viewModel.requestScreenRecordingPermission()
        #expect(screenRecordingService.requestPermissionCallCount == 1)
        #expect(viewModel.screenRecordingStatus == .granted)

        viewModel.openScreenRecordingSettings()
        #expect(screenRecordingService.openSystemSettingsCallCount == 1)

        // 通常側をアイコン型へ変更してもランチャー側がキャプチャのままなので usesCaptureDisplayStyle は true を維持
        viewModel.updateNormalDisplayStyle(.icon)
        #expect(viewModel.usesCaptureDisplayStyle == true)
        #expect(viewModel.screenRecordingStatus == .granted)

        // ランチャー側もリスト型へ戻すと双方非キャプチャとなり、以後は画面収録権限の確認・要求・設定遷移を行わない
        let statusCallsBeforeBothNonCapture = screenRecordingService.currentStatusCallCount
        viewModel.updateLauncherDisplayStyle(.list)
        #expect(viewModel.usesCaptureDisplayStyle == false)
        #expect(viewModel.screenRecordingStatus == .denied)
        #expect(notifiedLauncherStyles == [.capture, .list])

        viewModel.refreshStatus()
        viewModel.requestScreenRecordingPermission()
        viewModel.openScreenRecordingSettings()
        #expect(screenRecordingService.currentStatusCallCount == statusCallsBeforeBothNonCapture)
        #expect(screenRecordingService.requestPermissionCallCount == 1)
        #expect(screenRecordingService.openSystemSettingsCallCount == 1)
    }

    /// ショートカット記録開始〜確定・キャンセルの前後で監視サスペンド状態と更新通知が正しく同期されることを検証する
    @Test("ショートカット記録の開始と確定で監視サスペンド解除およびショートカット更新が行われる")
    @MainActor
    func recordingLifecycleSuspendsAndResumesHotKeyMonitor() {
        let store = MockPreferencesStore()
        let hotKeyMonitor = MockHotKeyMonitor()
        let viewModel = SettingsViewModel(
            preferencesStore: store,
            hotKeyMonitor: hotKeyMonitor,
            launchAtLoginService: MockLaunchAtLoginService(),
            permissionService: MockAccessibilityPermissionService()
        )

        #expect(hotKeyMonitor.isSuspendedForRecording == false)
        viewModel.beginRecordingNormalShortcut()
        #expect(hotKeyMonitor.isSuspendedForRecording == true)

        let nextShortcut = ShortcutPreference(modifier: .control, trigger: .tab)
        viewModel.recordNormalShortcut(nextShortcut)
        #expect(hotKeyMonitor.isSuspendedForRecording == false)
        #expect(hotKeyMonitor.updatedShortcuts.last == nextShortcut)

        viewModel.beginRecordingLauncherShortcut()
        #expect(hotKeyMonitor.isSuspendedForRecording == true)
        viewModel.cancelRecordingLauncherShortcut()
        #expect(hotKeyMonitor.isSuspendedForRecording == false)
    }

    /// サイドバーの4メニュー定義の並び順・タイトル・SF Symbols アイコン名を検証する
    @Test("SettingsTab のメニュー順序と表示タイトル・アイコン名が規定どおりである")
    func settingsTabOrderAndMetadata() {
        #expect(SettingsTab.allCases == [.general, .switcher, .launcher, .system])
        #expect(SettingsTab.allCases.map(\.title) == ["一般", "スイッチャー", "ランチャー", "システム"])
        #expect(SettingsTab.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }

    /// サイドバーの初期選択、メニュー切り替え時の記録自動キャンセル・監視再開、およびエラークリアを検証する
    @Test("タブ初期値は一般で、別タブ切替時に進行中のショートカット記録と検証エラーが安全にクリアされる")
    @MainActor
    func tabSelectionCancelsActiveRecordingAndClearsValidationError() {
        let store = MockPreferencesStore()
        let hotKeyMonitor = MockHotKeyMonitor()
        let viewModel = SettingsViewModel(
            preferencesStore: store,
            hotKeyMonitor: hotKeyMonitor,
            launchAtLoginService: MockLaunchAtLoginService(),
            permissionService: MockAccessibilityPermissionService()
        )

        // アプリ起動時の初期選択は「一般」
        #expect(viewModel.selectedTab == .general)

        // 通常スイッチャーのショートカット記録待機と検証エラーを発生させた状態で別タブへ切り替える
        viewModel.selectTab(.switcher)
        #expect(viewModel.selectedTab == .switcher)
        viewModel.beginRecordingNormalShortcut()
        viewModel.recordNormalShortcut(ShortcutPreference(keyCode: 40, modifiers: [.option, .shift], keyLabel: "K"))
        #expect(viewModel.isRecordingNormalShortcut == true)
        #expect(hotKeyMonitor.isSuspendedForRecording == true)
        #expect(viewModel.shortcutValidationError != nil)
        #expect(viewModel.shortcutValidationTarget == .normal)

        // 同一タブの再選択では進行中の記録状態を不要に解除しない
        viewModel.selectTab(.switcher)
        #expect(viewModel.isRecordingNormalShortcut == true)
        #expect(hotKeyMonitor.isSuspendedForRecording == true)

        // 「ランチャー」へ切り替えると記録キャンセル・監視再開・エラークリアが行われる
        viewModel.selectTab(.launcher)
        #expect(viewModel.selectedTab == .launcher)
        #expect(viewModel.isRecordingNormalShortcut == false)
        #expect(hotKeyMonitor.isSuspendedForRecording == false)
        #expect(viewModel.shortcutValidationError == nil)
        #expect(viewModel.shortcutValidationTarget == nil)

        // ランチャーのショートカット記録待機と検証エラーを発生させた状態で「システム」へ切り替える
        viewModel.beginRecordingLauncherShortcut()
        viewModel.recordLauncherShortcut(LauncherShortcutPreference(keyCode: 48, modifiers: [.option, .shift], keyLabel: "⇥"))
        #expect(viewModel.isRecordingLauncherShortcut == true)
        #expect(hotKeyMonitor.isSuspendedForRecording == true)
        #expect(viewModel.shortcutValidationError != nil)
        #expect(viewModel.shortcutValidationTarget == .launcher)

        viewModel.selectTab(.system)
        #expect(viewModel.selectedTab == .system)
        #expect(viewModel.isRecordingLauncherShortcut == false)
        #expect(hotKeyMonitor.isSuspendedForRecording == false)
        #expect(viewModel.shortcutValidationError == nil)
        #expect(viewModel.shortcutValidationTarget == nil)
    }

    /// 非キャプチャ表示形式のままシステムタブへ遷移・状態更新しても画面収録権限を確認しないことを検証する
    @Test("リスト型・アイコン型選択中はシステムタブ表示時も画面収録権限を確認しない")
    @MainActor
    func systemTabDoesNotQueryScreenRecordingWhenNonCaptureSelected() {
        let screenRecordingService = MockScreenRecordingPermissionService()
        let viewModel = SettingsViewModel(
            preferencesStore: MockPreferencesStore(),
            hotKeyMonitor: MockHotKeyMonitor(),
            launchAtLoginService: MockLaunchAtLoginService(),
            permissionService: MockAccessibilityPermissionService(),
            screenRecordingPermissionService: screenRecordingService
        )

        viewModel.selectTab(.system)
        viewModel.refreshStatus()
        #expect(viewModel.usesCaptureDisplayStyle == false)
        #expect(screenRecordingService.currentStatusCallCount == 0)

        viewModel.updateNormalDisplayStyle(.icon)
        viewModel.refreshStatus()
        #expect(viewModel.usesCaptureDisplayStyle == false)
        #expect(screenRecordingService.currentStatusCallCount == 0)
    }

    /// PreferencesStore が通常スイッチャー・検索ランチャーのアプリグルーピング設定を独立して永続化し、未保存時はデフォルト true を返すことを検証する
    @Test("PreferencesStore でグルーピング設定が未保存時 true にフォールバックし個別に永続化される")
    func preferencesStorePersistsAppGroupingIndependentlyWithTrueDefault() {
        let suiteName = "dev.wintch.tests.appGrouping.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        defer { defaults?.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(suiteName: suiteName)
        // キー未保存時は UserDefaults.bool の false ではなくデフォルト true を返すこと
        #expect(store.loadGroupNormalSwitcherByApp() == true)
        #expect(store.loadGroupLauncherByApp() == true)

        // 通常スイッチャーのみ false にしてもランチャー側へ影響しない
        store.saveGroupNormalSwitcherByApp(false)
        #expect(store.loadGroupNormalSwitcherByApp() == false)
        #expect(store.loadGroupLauncherByApp() == true)

        // ランチャーのみ false にし、通常側を true へ戻せる
        store.saveGroupLauncherByApp(false)
        store.saveGroupNormalSwitcherByApp(true)
        #expect(store.loadGroupNormalSwitcherByApp() == true)
        #expect(store.loadGroupLauncherByApp() == false)
    }

    /// SettingsViewModel で通常スイッチャー・検索ランチャーのグルーピング設定を個別に変更・永続化・通知でき、画面収録権限を参照しないことを検証する
    @Test("SettingsViewModel でグルーピング設定がデフォルト ON・個別永続化・通知され画面収録権限を参照しない")
    @MainActor
    func appGroupingTogglePersistsAndNotifiesWithoutScreenRecordingQuery() {
        let store = MockPreferencesStore()
        let screenRecordingService = MockScreenRecordingPermissionService()
        let viewModel = SettingsViewModel(
            preferencesStore: store,
            hotKeyMonitor: MockHotKeyMonitor(),
            launchAtLoginService: MockLaunchAtLoginService(),
            permissionService: MockAccessibilityPermissionService(),
            screenRecordingPermissionService: screenRecordingService
        )

        var normalHistory: [Bool] = []
        var launcherHistory: [Bool] = []
        viewModel.onNormalSwitcherGroupingChanged = { normalHistory.append($0) }
        viewModel.onLauncherGroupingChanged = { launcherHistory.append($0) }

        #expect(viewModel.isNormalSwitcherGroupedByApp == true)
        #expect(viewModel.isLauncherGroupedByApp == true)

        // 同じ値を渡した場合は不要な保存・通知を行わない
        viewModel.updateNormalSwitcherGrouping(true)
        viewModel.updateLauncherGrouping(true)
        #expect(store.saveGroupNormalSwitcherByAppCallCount == 0)
        #expect(store.saveGroupLauncherByAppCallCount == 0)
        #expect(normalHistory.isEmpty)
        #expect(launcherHistory.isEmpty)

        // 個別に変更すると永続化・通知される
        viewModel.updateNormalSwitcherGrouping(false)
        #expect(viewModel.isNormalSwitcherGroupedByApp == false)
        #expect(viewModel.isLauncherGroupedByApp == true)
        #expect(store.storedGroupNormalSwitcherByApp == false)
        #expect(store.saveGroupNormalSwitcherByAppCallCount == 1)
        #expect(normalHistory == [false])

        viewModel.updateLauncherGrouping(false)
        #expect(viewModel.isLauncherGroupedByApp == false)
        #expect(store.storedGroupLauncherByApp == false)
        #expect(store.saveGroupLauncherByAppCallCount == 1)
        #expect(launcherHistory == [false])
        #expect(screenRecordingService.currentStatusCallCount == 0)
    }
}
