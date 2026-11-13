import Foundation
import Testing
@testable import WintchCore

/// SwitcherViewModel の状態遷移および操作制御を検証するテストスイート
@Suite("SwitcherViewModel テスト")
struct SwitcherViewModelTests {
    /// 起動・次移動・逆順移動・修飾キー解放による確定の一連のフローを検証する
    @Test("起動から移動・修飾キー解放で対象ウィンドウがアクティブ化される")
    @MainActor
    func switcherLaunchMoveAndConfirm() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", pid: 10, applicationName: "App1", title: "Win1", lastActivatedAt: now),
            RawWindowCandidate(id: "w2", pid: 20, applicationName: "App2", title: "Win2", lastActivatedAt: now.addingTimeInterval(-10)),
            RawWindowCandidate(id: "w3", pid: 30, applicationName: "App3", title: "Win3", lastActivatedAt: now.addingTimeInterval(-20))
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )

        // 初回トリガー: 2番目（インデックス1 = w2）が選択状態で表示される
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.isPresented == true)
        #expect(hotKeyMonitor.isSwitcherActive == true)
        #expect(viewModel.entries.map(\.id) == ["w1", "w2", "w3"])
        #expect(viewModel.selectedIndex == 1)

        // さらにトリガー押下: 3番目（w3）へ移動
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.selectedIndex == 2)

        // Shift 併用で逆順移動: 2番目（w2）へ戻る
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: true))
        #expect(viewModel.selectedIndex == 1)

        // 修飾キー解放で確定: パネルが閉じ w2 がアクティブ化される
        viewModel.handleHotKeyEvent(.modifierReleased)
        #expect(viewModel.isPresented == false)
        #expect(hotKeyMonitor.isSwitcherActive == false)
        #expect(windowService.activatedWindows.map(\.id) == ["w2"])
    }

    /// Esc キーおよび外部フォーカス喪失時にウィンドウを切り替えずキャンセルすることを検証する
    @Test("Esc キーで切り替えを実行せずキャンセルされる")
    @MainActor
    func escapeCancelsWithoutActivating() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()

        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", pid: 10, applicationName: "App1", title: "Win1"),
            RawWindowCandidate(id: "w2", pid: 20, applicationName: "App2", title: "Win2")
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )

        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.isPresented == true)

        viewModel.handleHotKeyEvent(.escapePressed)
        #expect(viewModel.isPresented == false)
        #expect(hotKeyMonitor.isSwitcherActive == false)
        #expect(windowService.activatedWindows.isEmpty)
    }

    /// ウィンドウ0件のときはパネルを表示しないことを検証する
    @Test("有効ウィンドウが0件のときはパネルを表示しない")
    @MainActor
    func emptyWindowListDoesNotPresent() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()

        windowService.stubbedCandidates = []

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )

        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.isPresented == false)
        #expect(hotKeyMonitor.isSwitcherActive == false)
    }

    /// 権限未許可時はスイッチャーを起動せず権限不足通知コールバックを呼ぶことを検証する
    @Test("権限未許可時は起動をブロックしコールバックを通知する")
    @MainActor
    func deniedPermissionBlocksSwitcherAndNotifies() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        permissionService.stubbedStatus = .denied
        let iconProvider = MockIconProvider()

        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", pid: 10, applicationName: "App1", title: "Win1")
        ]

        var deniedNotified = false
        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )
        viewModel.onPermissionDenied = {
            deniedNotified = true
        }

        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.isPresented == false)
        #expect(deniedNotified == true)
    }

    /// ランチャーモードのトグル起動、検索による先頭選択リセット、修飾キー解放無視、モード排他、Enter 確定を検証する
    @Test("ランチャーモードで起動・検索・先頭選択・確定およびモード排他が正しく動作する")
    @MainActor
    func launcherModeSearchMoveConfirmAndMutualExclusion() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", pid: 10, applicationName: "Safari", title: "Docs", lastActivatedAt: now),
            RawWindowCandidate(id: "w2", pid: 20, applicationName: "Visual Studio Code", title: "Wintch", lastActivatedAt: now.addingTimeInterval(-10)),
            RawWindowCandidate(id: "w3", pid: 30, applicationName: "Finder", title: "Downloads", lastActivatedAt: now.addingTimeInterval(-20))
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )

        // ランチャー起動: 2番目（インデックス1）が初期選択される
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.isPresented == true)
        #expect(viewModel.mode == .launcher)
        #expect(hotKeyMonitor.activeMode == .launcher)
        #expect(viewModel.selectedIndex == 1)

        // トグル式のため修飾キーを離しても閉じない
        viewModel.handleHotKeyEvent(.modifierReleased)
        #expect(viewModel.isPresented == true)

        // ランチャー表示中に通常ショートカットが押されても無視する
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.mode == .launcher)
        #expect(viewModel.selectedIndex == 1)

        // 検索入力で絞り込みされ、先頭（インデックス0）に自動移動する
        viewModel.updateSearchQuery("vsc")
        #expect(viewModel.displayedResults.map(\.id) == ["w2"])
        #expect(viewModel.selectedIndex == 0)

        // Enter（confirmSelection）で確定し対象ウィンドウがアクティブ化される
        viewModel.confirmSelection()
        #expect(viewModel.isPresented == false)
        #expect(viewModel.mode == .inactive)
        #expect(hotKeyMonitor.activeMode == .inactive)
        #expect(windowService.activatedWindows.map(\.id) == ["w2"])
    }

    /// ランチャー再押下で切り替えせずにトグル終了し、通常モード中はランチャーショートカットを無視することを検証する
    @Test("ランチャー再押下でトグル終了し通常モード中のランチャー起動は無視される")
    @MainActor
    func launcherToggleCloseAndIgnoreDuringNormalMode() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()

        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", pid: 10, applicationName: "App1", title: "Win1"),
            RawWindowCandidate(id: "w2", pid: 20, applicationName: "App2", title: "Win2")
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )

        // ランチャー起動 → 再押下でキャンセルクローズ
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.mode == .launcher)
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.mode == .inactive)
        #expect(windowService.activatedWindows.isEmpty)

        // 通常モード起動中にランチャーショートカットを押しても無視される
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.mode == .normal)
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.mode == .normal)
    }

    /// ランチャー検索で 0 件となった状態での Enter 確定や上下移動が無視されパネルが閉じないことを検証する
    @Test("検索結果が0件の状態で確定や移動を行ってもパネルが維持される")
    @MainActor
    func zeroSearchResultsIgnoresConfirmAndMove() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()

        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", pid: 10, applicationName: "Safari", title: "Apple")
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )

        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        viewModel.updateSearchQuery("zzzzqqq")

        #expect(viewModel.displayedResults.isEmpty)
        #expect(viewModel.isPresented == true)

        viewModel.moveSelection(.down)
        viewModel.confirmSelection()

        #expect(viewModel.isPresented == true)
        #expect(viewModel.mode == .launcher)
        #expect(windowService.activatedWindows.isEmpty)
    }
}
