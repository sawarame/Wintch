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
}
