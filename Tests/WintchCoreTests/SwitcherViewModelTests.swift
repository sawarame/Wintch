import AppKit
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

        // ランチャー起動: 2件以上でも1番目（インデックス0）が初期選択される
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.isPresented == true)
        #expect(viewModel.mode == .launcher)
        #expect(hotKeyMonitor.activeMode == .launcher)
        #expect(viewModel.selectedIndex == 0)

        // トグル式のため修飾キーを離しても閉じない
        viewModel.handleHotKeyEvent(.modifierReleased)
        #expect(viewModel.isPresented == true)

        // ランチャー表示中に通常ショートカットが押されてもランチャーを維持したまま「次へ」「前へ」移動する
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.mode == .launcher)
        #expect(viewModel.selectedIndex == 1)

        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.mode == .launcher)
        #expect(viewModel.selectedIndex == 2)

        // 末尾から順方向で先頭（0）へ循環する
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.mode == .launcher)
        #expect(viewModel.selectedIndex == 0)

        // 先頭から Shift 併用（前へ）で末尾（2）へ循環し、その後の修飾キー解放でも閉じない
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: true))
        #expect(viewModel.mode == .launcher)
        #expect(viewModel.selectedIndex == 2)
        viewModel.handleHotKeyEvent(.modifierReleased)
        #expect(viewModel.mode == .launcher)
        #expect(viewModel.isPresented == true)

        // 検索入力で絞り込みされ、先頭（インデックス0）に自動移動し、全削除しても先頭（0）を維持する
        viewModel.updateSearchQuery("vsc")
        #expect(viewModel.displayedResults.map(\.id) == ["w2"])
        #expect(viewModel.selectedIndex == 0)
        viewModel.updateSearchQuery("")
        #expect(viewModel.displayedResults.map(\.id) == ["w1", "w2", "w3"])
        #expect(viewModel.selectedIndex == 0)
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

        // 通常モード起動中にランチャーショートカットを押しても無視され、選択位置も維持される
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.mode == .normal)
        #expect(viewModel.selectedIndex == 1)
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.mode == .normal)
        #expect(viewModel.selectedIndex == 1)
        #expect(windowService.activatedWindows.isEmpty)
    }

    /// ランチャー検索で 0 件となった状態での Enter 確定や上下移動・通常ショートカットが無視されパネルが閉じないことを検証する
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
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: true))
        viewModel.confirmSelection()

        #expect(viewModel.isPresented == true)
        #expect(viewModel.mode == .launcher)
        #expect(windowService.activatedWindows.isEmpty)
    }

    /// ランチャー絞り込み中および候補1件時に通常スイッチャーショートカットで移動・維持できることを検証する
    @Test("ランチャー絞り込み中と候補1件時に通常ショートカットで安全に候補移動できる")
    @MainActor
    func launcherFilteredAndSingleResultNormalShortcutNavigation() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", pid: 10, applicationName: "Google Chrome", title: "Docs", lastActivatedAt: now),
            RawWindowCandidate(id: "w2", pid: 20, applicationName: "Google Chrome", title: "GitHub", lastActivatedAt: now.addingTimeInterval(-10)),
            RawWindowCandidate(id: "w3", pid: 30, applicationName: "Finder", title: "Home", lastActivatedAt: now.addingTimeInterval(-20))
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )

        // ランチャー起動後に "chr" で 2 件に絞り込む（先頭 w1 が選択状態）
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        viewModel.updateSearchQuery("chr")
        #expect(viewModel.displayedResults.map(\.id) == ["w1", "w2"])
        #expect(viewModel.selectedIndex == 0)

        // 順方向で w2 へ移動（検索クエリと絞り込み結果は保持される）
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.searchQuery == "chr")
        #expect(viewModel.displayedResults.map(\.id) == ["w1", "w2"])
        #expect(viewModel.selectedIndex == 1)

        // 逆方向で w1 へ戻る
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: true))
        #expect(viewModel.selectedIndex == 0)

        // 1件のみ一致する条件へ絞り込んだ場合は順・逆どちらでも先頭（0）を維持する
        viewModel.updateSearchQuery("finder")
        #expect(viewModel.displayedResults.map(\.id) == ["w3"])
        #expect(viewModel.selectedIndex == 0)
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.selectedIndex == 0)
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: true))
        #expect(viewModel.selectedIndex == 0)
        viewModel.handleHotKeyEvent(.modifierReleased)
        #expect(viewModel.mode == .launcher)

        // Enter で w3 を確定アクティブ化
        viewModel.confirmSelection()
        #expect(viewModel.mode == .inactive)
        #expect(windowService.activatedWindows.map(\.id) == ["w3"])
    }

    /// 通常スイッチャー表示中に選択中ウィンドウを閉じ、パネル維持・選択位置補正・連続クローズ後の確定が行えることを検証する
    @Test("通常スイッチャー表示中に選択ウィンドウを閉じて一覧と選択位置を更新維持し確定できる")
    @MainActor
    func normalModeCloseWindowMaintainsPanelAndSelection() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", pid: 10, applicationName: "Safari", title: "Page 1", lastActivatedAt: now),
            RawWindowCandidate(id: "w2", pid: 10, applicationName: "Safari", title: "Page 2", lastActivatedAt: now.addingTimeInterval(-10)),
            RawWindowCandidate(id: "w3", pid: 20, applicationName: "Finder", title: "Docs", lastActivatedAt: now.addingTimeInterval(-20))
        ]

        var resultsUpdateCount = 0
        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )
        viewModel.onSearchResultsUpdated = {
            resultsUpdateCount += 1
        }

        // 通常モード起動: 2番目（w2、インデックス1）が選択状態
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.mode == .normal)
        #expect(viewModel.selectedIndex == 1)

        // 中間項目 w2 を閉じる: w2 のみ除外されパネルは開いたまま、新しい2番目 w3（インデックス1）が選択される
        await viewModel.closeSelectedWindow()
        #expect(windowService.closedWindows.map(\.id) == ["w2"])
        #expect(viewModel.isPresented == true)
        #expect(viewModel.mode == .normal)
        #expect(viewModel.entries.map(\.id) == ["w1", "w3"])
        #expect(viewModel.selectedIndex == 1)
        #expect(resultsUpdateCount == 1)

        // 末尾となった w3（pid 20 で唯一のウィンドウ、インデックス1）を連続で閉じる: アプリ終了が呼ばれ w1（インデックス0）へ補正される
        await viewModel.closeSelectedWindow()
        #expect(windowService.closedWindows.map(\.id) == ["w2"])
        #expect(windowService.terminatedPIDs == [20])
        #expect(viewModel.isPresented == true)
        #expect(viewModel.entries.map(\.id) == ["w1"])
        #expect(viewModel.selectedIndex == 0)
        #expect(resultsUpdateCount == 2)

        // 修飾キーを離すと残った w1 がアクティブ化される
        viewModel.handleHotKeyEvent(.modifierReleased)
        #expect(viewModel.isPresented == false)
        #expect(windowService.activatedWindows.map(\.id) == ["w1"])
    }

    /// 検索ランチャー表示中に選択中ウィンドウを閉じた際、検索キーワードを維持したまま一覧から除外され、絞り込み0件時や検索語クリア後も整合することを検証する
    @Test("検索ランチャー表示中に検索語を維持したまま選択ウィンドウを閉じられる")
    @MainActor
    func launcherModeCloseWindowPreservesQueryAndUpdatesFilteredList() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", pid: 10, applicationName: "QuickTime Player", title: "Clip 1", lastActivatedAt: now),
            RawWindowCandidate(id: "w2", pid: 10, applicationName: "QuickTime Player", title: "Clip 2", lastActivatedAt: now.addingTimeInterval(-10)),
            RawWindowCandidate(id: "w3", pid: 20, applicationName: "Safari", title: "Apple", lastActivatedAt: now.addingTimeInterval(-20))
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )

        // ランチャー起動し "quick" で2件に絞り込む（先頭 w1 が選択状態）
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        viewModel.updateSearchQuery("quick")
        #expect(viewModel.displayedResults.map(\.id) == ["w1", "w2"])
        #expect(viewModel.selectedIndex == 0)

        // w1 を閉じる: 同アプリ2枚中の1枚目なのでウィンドウ単体クローズが呼ばれ w2 のみが残る
        await viewModel.closeSelectedWindow()
        #expect(windowService.closedWindows.map(\.id) == ["w1"])
        #expect(windowService.terminatedPIDs.isEmpty)
        #expect(viewModel.mode == .launcher)
        #expect(viewModel.searchQuery == "quick")
        #expect(viewModel.displayedResults.map(\.id) == ["w2"])
        #expect(viewModel.selectedIndex == 0)

        // さらに w2 を閉じる: 同アプリ最後の1枚なのでアプリ終了が呼ばれ、絞り込み結果は0件になるが w3 が残っているためパネルと検索語は維持される
        await viewModel.closeSelectedWindow()
        #expect(windowService.terminatedPIDs == [10])
        #expect(viewModel.mode == .launcher)
        #expect(viewModel.isPresented == true)
        #expect(viewModel.searchQuery == "quick")
        #expect(viewModel.displayedResults.isEmpty)
        #expect(viewModel.selectedIndex == 0)

        // 検索語を消去すると閉じた w1・w2 は復活せず、残った w3 のみが表示される
        viewModel.updateSearchQuery("")
        #expect(viewModel.displayedResults.map(\.id) == ["w3"])
        #expect(viewModel.selectedIndex == 0)
    }

    /// クローズ不可または未保存ダイアログ等でウィンドウやアプリが残存した場合、一覧とパネルが安全に維持されることを検証する
    @Test("クローズ失敗や確認ダイアログ残存時は一覧と選択状態を維持する")
    @MainActor
    func closeWindowFailureOrConfirmationPreservesState() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", pid: 10, applicationName: "TextEdit", title: "Draft.txt", lastActivatedAt: now),
            RawWindowCandidate(id: "w2", pid: 10, applicationName: "TextEdit", title: "Notes.txt", lastActivatedAt: now.addingTimeInterval(-10)),
            RawWindowCandidate(id: "w3", pid: 20, applicationName: "Finder", title: "Home", lastActivatedAt: now.addingTimeInterval(-20))
        ]
        windowService.stubbedCloseWindowResults["w2"] = false
        windowService.stubbedTerminateResults[20] = false

        var restoredModes: [SwitcherMode] = []
        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )
        viewModel.onPanelFocusRestoreNeeded = { mode in
            restoredModes.append(mode)
        }

        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.selectedIndex == 1)

        // 複数ウィンドウ時のクローズ失敗で一覧・選択を維持しフォーカス復元も呼ばれる
        await viewModel.closeSelectedWindow()
        #expect(windowService.closedWindows.map(\.id) == ["w2"])
        #expect(viewModel.isPresented == true)
        #expect(viewModel.entries.map(\.id) == ["w1", "w2", "w3"])
        #expect(viewModel.selectedIndex == 1)
        #expect(restoredModes == [.normal])

        // 単一ウィンドウアプリの終了失敗でも一覧・選択を維持しフォーカス復元が呼ばれる
        viewModel.moveSelection(.down)
        #expect(viewModel.selectedIndex == 2)
        await viewModel.closeSelectedWindow()
        #expect(windowService.terminatedPIDs == [20])
        #expect(viewModel.isPresented == true)
        #expect(viewModel.entries.map(\.id) == ["w1", "w2", "w3"])
        #expect(viewModel.selectedIndex == 2)
        #expect(restoredModes == [.normal, .normal])
    }

    /// 最後の1件を閉じた際の自動終了、検索0件時の無視、および待機中の連打・途中キャンセル安全性を検証する
    @Test("最後の1件終了で自動クローズし検索0件・再入・途中キャンセルを安全に処理する")
    @MainActor
    func lastWindowCloseDismissesAndBoundaryStatesAreSafe() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()

        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "only-1", pid: 10, applicationName: "Safari", title: "Tab")
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )

        // 1. 通常モードで最後の1件を閉じるとアプリ終了の上で自動的にパネル終了する
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.isPresented == true)
        await viewModel.closeSelectedWindow()
        #expect(windowService.terminatedPIDs == [10])
        #expect(viewModel.isPresented == false)
        #expect(viewModel.mode == .inactive)
        #expect(hotKeyMonitor.activeMode == .inactive)

        // 2. ランチャーモードで最後の1件を閉じた場合はパネルを維持し、ウィンドウ0件状態へ遷移する
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.mode == .launcher)
        await viewModel.closeSelectedWindow()
        #expect(windowService.terminatedPIDs == [10, 10])
        #expect(viewModel.isPresented == true)
        #expect(viewModel.mode == .launcher)
        #expect(viewModel.hasOpenWindows == false)
        #expect(viewModel.emptyState == .noOpenWindows)
        #expect(hotKeyMonitor.activeMode == .launcher)
        viewModel.cancel()

        // 3. ランチャーで検索結果0件のときにクローズ操作してもサービスを呼ばず維持される
        let closeCountBeforeZeroSearch = windowService.closedWindows.count
        let terminateCountBeforeZeroSearch = windowService.terminatedPIDs.count
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        viewModel.updateSearchQuery("no-match")
        #expect(viewModel.displayedResults.isEmpty)
        await viewModel.closeSelectedWindow()
        #expect(windowService.closedWindows.count == closeCountBeforeZeroSearch)
        #expect(windowService.terminatedPIDs.count == terminateCountBeforeZeroSearch)
        #expect(viewModel.isPresented == true)
        viewModel.cancel()

        // 4. クローズ待機中の二重実行防止と途中キャンセル後の安全な無視
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", pid: 10, applicationName: "App1", title: "Win1"),
            RawWindowCandidate(id: "w2", pid: 10, applicationName: "App1", title: "Win2")
        ]
        var continuation: CheckedContinuation<Bool, Never>?
        windowService.closeWindowHandler = { _ in
            await withCheckedContinuation { cont in
                continuation = cont
            }
        }

        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.selectedIndex == 0)
        let closeTask1 = Task { @MainActor in
            await viewModel.closeSelectedWindow()
        }
        // 1件目が待機中に入るまで譲歩し、その間に2回目を呼んでも無視されることを確認する
        await Task.yield()
        let closeTask2 = Task { @MainActor in
            await viewModel.closeSelectedWindow()
        }
        await closeTask2.value
        #expect(windowService.closedWindows.map(\.id) == ["w1"])

        // 待機中にユーザーがキャンセルして即座に再起動した場合でも、古い完了で新セッションが破壊されない
        viewModel.cancel()
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        continuation?.resume(returning: true)
        await closeTask1.value
        #expect(viewModel.mode == .launcher)
        #expect(viewModel.entries.map(\.id) == ["w1", "w2"])
    }

    /// ランチャー検索で1件に絞られても同アプリが全候補中に2枚以上開いていればウィンドウ単体クローズが選ばれること、
    /// および自動 Space 移動に伴うクローズ中の resignedActive 無視とフォーカス復元を検証する
    @Test("検索絞り込み時も全候補基準でウィンドウ数判定しクローズ中のフォーカス喪失を無視する")
    @MainActor
    func fullCandidateCountAndResignedActiveGuardWorkCorrectly() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", pid: 10, applicationName: "WezTerm", title: "Main Shell", lastActivatedAt: now),
            RawWindowCandidate(id: "w2", pid: 10, applicationName: "WezTerm", title: "Remote Logs", lastActivatedAt: now.addingTimeInterval(-10))
        ]

        var continuation: CheckedContinuation<Bool, Never>?
        windowService.closeWindowHandler = { _ in
            await withCheckedContinuation { cont in
                continuation = cont
            }
        }

        var restoredModes: [SwitcherMode] = []
        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )
        viewModel.onPanelFocusRestoreNeeded = { mode in
            restoredModes.append(mode)
        }

        // ランチャーで "Remote" の1件だけに絞り込む（allEntries には pid 10 が2枚ある）
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        viewModel.updateSearchQuery("Remote")
        #expect(viewModel.displayedResults.map(\.id) == ["w2"])

        let closeTask = Task { @MainActor in
            await viewModel.closeSelectedWindow()
        }
        await Task.yield()

        // 自動 Space 移動等によりクローズ待機中に resignedActive が来てもパネルは閉じない
        viewModel.cancel(reason: .resignedActive)
        #expect(viewModel.isPresented == true)
        #expect(viewModel.mode == .launcher)

        continuation?.resume(returning: true)
        await closeTask.value

        // 単一ウィンドウ誤認して terminateApplication せず closeWindow が呼ばれ、完了後にフォーカス復元される
        #expect(windowService.closedWindows.map(\.id) == ["w2"])
        #expect(windowService.terminatedPIDs.isEmpty)
        #expect(viewModel.isPresented == true)
        #expect(restoredModes == [.launcher])

        // クローズ処理完了後の通常の resignedActive は従来通りパネルを閉じる
        viewModel.cancel(reason: .resignedActive)
        #expect(viewModel.isPresented == false)
        #expect(viewModel.mode == .inactive)
    }

    /// ランチャー検索で既存ウィンドウ候補の下に重複除外されたアプリ起動候補が表示され、単一カーソルで横断選択・起動できることを検証する
    @Test("ランチャー検索でウィンドウ候補の下に未重複アプリ起動候補を表示し横断移動・起動できる")
    @MainActor
    func launcherShowsWindowsAndDeduplicatedAppsWithUnifiedNavigation() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let installedAppService = MockInstalledAppService()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(
                id: "w1",
                pid: 10,
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                title: "Docs",
                lastActivatedAt: now
            ),
            RawWindowCandidate(
                id: "w2",
                pid: 20,
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                applicationName: "Slack",
                title: "General",
                lastActivatedAt: now.addingTimeInterval(-10)
            )
        ]
        installedAppService.stubbedApps = [
            LaunchableApp(
                displayName: "Calculator",
                bundleIdentifier: "com.apple.calculator",
                bundleURL: URL(fileURLWithPath: "/System/Applications/Calculator.app")
            ),
            LaunchableApp(
                displayName: "Calendar",
                bundleIdentifier: "com.apple.iCal",
                bundleURL: URL(fileURLWithPath: "/System/Applications/Calendar.app")
            ),
            LaunchableApp(
                displayName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")
            ),
            LaunchableApp(
                displayName: "Simulator",
                bundleIdentifier: "com.apple.iphonesimulator",
                bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app")
            ),
            LaunchableApp(
                displayName: "Sublime Text",
                bundleIdentifier: "com.sublimetext.4",
                bundleURL: URL(fileURLWithPath: "/Applications/Sublime Text.app")
            )
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            installedAppService: installedAppService
        )

        // 初期状態（空検索語）および空白のみの場合はアプリ起動候補を出さない
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.isShowingLaunchCandidates == false)
        #expect(viewModel.displayedAppResults.isEmpty)

        viewModel.updateSearchQuery("   ")
        #expect(viewModel.displayedResults.map(\.id) == ["w1", "w2"])
        #expect(viewModel.isShowingLaunchCandidates == false)
        #expect(viewModel.displayedAppResults.isEmpty)

        // "s" で検索すると上部ウィンドウ (Safari, Slack) の下に Safari を除外した Simulator / Sublime Text が出る
        viewModel.updateSearchQuery("s")
        #expect(viewModel.displayedResults.map(\.entry.applicationName) == ["Safari", "Slack"])
        #expect(viewModel.isShowingLaunchCandidates == true)
        #expect(viewModel.displayedAppResults.map(\.app.displayName) == ["Simulator", "Sublime Text"])
        #expect(viewModel.selectedIndex == 0)

        // 上部ウィンドウ (0, 1) と下部アプリ候補 (2, 3) の間を単一カーソルで貫通・循環移動できる
        viewModel.moveSelection(.down)
        #expect(viewModel.selectedIndex == 1)
        viewModel.moveSelection(.down)
        #expect(viewModel.selectedIndex == 2)
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.selectedIndex == 3)
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.selectedIndex == 0)
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: true))
        #expect(viewModel.selectedIndex == 3)
        viewModel.moveSelection(.up)
        #expect(viewModel.selectedIndex == 2)

        // ランチャーモード中は修飾キー解放で確定せず開いたまま維持される
        viewModel.handleHotKeyEvent(.modifierReleased)
        #expect(viewModel.isPresented == true)
        #expect(installedAppService.launchedApps.isEmpty)

        // 検索語を空に戻すと既存ウィンドウ一覧のみに戻る
        viewModel.updateSearchQuery("")
        #expect(viewModel.isShowingLaunchCandidates == false)
        #expect(viewModel.displayedAppResults.isEmpty)
        #expect(viewModel.displayedResults.map(\.id) == ["w1", "w2"])

        // 既存ウィンドウ 0 件の一致 ("cal") では下部セクション相当のアプリ候補 (index 0, 1) がそのまま選択・起動できる
        viewModel.updateSearchQuery("cal")
        #expect(viewModel.displayedResults.isEmpty)
        #expect(viewModel.displayedAppResults.map(\.app.displayName) == ["Calculator", "Calendar"])
        viewModel.selectAndActivate(at: 1)
        #expect(viewModel.isPresented == false)
        #expect(viewModel.mode == .inactive)
        #expect(hotKeyMonitor.activeMode == .inactive)
        #expect(windowService.activatedWindows.isEmpty)
        #expect(installedAppService.launchedApps.map(\.displayName) == ["Calendar"])

        // 再度ランチャーを開き、混在結果の既存ウィンドウ (w2: Slack) を確定した場合はウィンドウ切り替えのみ行う
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        viewModel.updateSearchQuery("s")
        viewModel.selectAndActivate(at: 1)
        #expect(viewModel.isPresented == false)
        #expect(windowService.activatedWindows.map(\.id) == ["w2"])
        #expect(installedAppService.launchedApps.map(\.displayName) == ["Calendar"])
    }

    /// 混在表示中のアプリ候補選択時におけるウィンドウクローズ無視と、ウィンドウクローズ後の重複除外再評価を検証する
    @Test("アプリ候補選択中のクローズ無視とウィンドウクローズ後の再評価が安全に動作する")
    @MainActor
    func closeWindowAndAppCandidateCoexistence() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let installedAppService = MockInstalledAppService()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(
                id: "w1",
                pid: 10,
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                applicationName: "Slack",
                title: "General",
                lastActivatedAt: now
            ),
            RawWindowCandidate(
                id: "w2",
                pid: 20,
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                title: "Docs",
                lastActivatedAt: now.addingTimeInterval(-10)
            )
        ]
        installedAppService.stubbedApps = [
            LaunchableApp(
                displayName: "Slack",
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                bundleURL: URL(fileURLWithPath: "/Applications/Slack.app")
            ),
            LaunchableApp(
                displayName: "Slack Helper App",
                bundleIdentifier: "com.example.slackhelper",
                bundleURL: URL(fileURLWithPath: "/Applications/Slack Helper App.app")
            )
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            installedAppService: installedAppService
        )

        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        viewModel.updateSearchQuery("sla")
        #expect(viewModel.displayedResults.map(\.id) == ["w1"])
        #expect(viewModel.displayedAppResults.map(\.app.displayName) == ["Slack Helper App"])

        // 下部のアプリ起動候補 (index 1) にカーソルがある状態での closeSelectedWindow は安全に無視される
        viewModel.moveSelection(.down)
        #expect(viewModel.selectedIndex == 1)
        await viewModel.closeSelectedWindow()
        #expect(windowService.closedWindows.isEmpty)
        #expect(windowService.terminatedPIDs.isEmpty)
        #expect(viewModel.isPresented == true)
        #expect(viewModel.selectedIndex == 1)

        // 上部のウィンドウ (index 0) を閉じると、重複除外が外れて下部に Slack が再び現れる
        viewModel.moveSelection(.up)
        #expect(viewModel.selectedIndex == 0)
        await viewModel.closeSelectedWindow()
        #expect(windowService.terminatedPIDs == [10])
        #expect(viewModel.displayedResults.isEmpty)
        #expect(viewModel.isShowingLaunchCandidates == true)
        #expect(viewModel.displayedAppResults.map(\.app.displayName) == ["Slack", "Slack Helper App"])

        // Enter（confirmSelection）で先頭の Slack を起動する
        viewModel.confirmSelection()
        #expect(viewModel.isPresented == false)
        #expect(installedAppService.launchedApps.map(\.displayName) == ["Slack"])
    }

    /// 既存ウィンドウ候補がある混在表示中でもバックグラウンドのアプリ更新が反映され、ウィンドウ側の選択位置が維持されることを検証する
    @Test("混在表示中にバックグラウンド更新が完了してもウィンドウ選択を維持しつつアプリ候補を更新する")
    @MainActor
    func backgroundRefreshUpdatesCombinedAppResultsSafely() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let installedAppService = MockInstalledAppService()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(
                id: "w1",
                pid: 10,
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                title: "Docs",
                lastActivatedAt: now
            ),
            RawWindowCandidate(
                id: "w2",
                pid: 20,
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                applicationName: "Slack",
                title: "General",
                lastActivatedAt: now.addingTimeInterval(-10)
            )
        ]
        installedAppService.stubbedApps = [
            LaunchableApp(
                displayName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")
            ),
            LaunchableApp(
                displayName: "Simulator",
                bundleIdentifier: "com.apple.iphonesimulator",
                bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app")
            )
        ]

        var refreshContinuation: CheckedContinuation<[LaunchableApp], Never>?
        var refreshHandlerEnteredContinuation: CheckedContinuation<Void, Never>?
        installedAppService.refreshHandler = {
            refreshHandlerEnteredContinuation?.resume()
            refreshHandlerEnteredContinuation = nil
            return await withCheckedContinuation { cont in
                refreshContinuation = cont
            }
        }

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            installedAppService: installedAppService
        )

        await withCheckedContinuation { cont in
            refreshHandlerEnteredContinuation = cont
            viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        }

        viewModel.updateSearchQuery("s")
        viewModel.moveSelection(.down)
        #expect(viewModel.displayedResults.map(\.id) == ["w1", "w2"])
        #expect(viewModel.displayedAppResults.map(\.app.displayName) == ["Simulator"])
        #expect(viewModel.selectedIndex == 1)

        // 既存ウィンドウが表示されている混在状態でも、裏リフレッシュ完了により新規アプリが下部に追加される（Safari は除外）
        await withCheckedContinuation { updateWaitCont in
            viewModel.onSearchResultsUpdated = {
                updateWaitCont.resume()
            }
            refreshContinuation?.resume(returning: [
                LaunchableApp(
                    displayName: "Safari",
                    bundleIdentifier: "com.apple.Safari",
                    bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")
                ),
                LaunchableApp(
                    displayName: "Simulator",
                    bundleIdentifier: "com.apple.iphonesimulator",
                    bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app")
                ),
                LaunchableApp(
                    displayName: "Sublime Text",
                    bundleIdentifier: "com.sublimetext.4",
                    bundleURL: URL(fileURLWithPath: "/Applications/Sublime Text.app")
                )
            ])
        }

        #expect(viewModel.displayedAppResults.map(\.app.displayName) == ["Simulator", "Sublime Text"])
        // 上部ウィンドウ (w2: Slack) の選択カーソル位置は乱されない
        #expect(viewModel.selectedIndex == 1)

        // 末尾の Sublime Text へ移動して起動できる
        viewModel.moveSelection(.down)
        viewModel.moveSelection(.down)
        #expect(viewModel.selectedIndex == 3)
        viewModel.confirmSelection()
        #expect(installedAppService.launchedApps.map(\.displayName) == ["Sublime Text"])
    }

    /// キャプチャ表示型での即時表示（既存キャッシュ反映・未キャッシュ時は nil）、非同期キャプチャ差し替え、
    /// 4 方向グリッド移動、およびウィンドウクローズ時のキャッシュ破棄を検証する
    @Test("キャプチャ表示型で即時表示後に非同期サムネイルが反映され4方向移動とクローズ削除が行える")
    @MainActor
    func captureStyleImmediateDisplayAsyncUpdateAndFourWayNavigation() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let screenRecordingService = MockScreenRecordingPermissionService()
        let captureService = MockWindowCaptureService()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", cgWindowID: 101, pid: 10, applicationName: "App1", title: "Win1", lastActivatedAt: now),
            RawWindowCandidate(id: "w2", cgWindowID: 102, pid: 20, applicationName: "App2", title: "Win2", lastActivatedAt: now.addingTimeInterval(-10)),
            RawWindowCandidate(id: "w3", cgWindowID: 103, pid: 30, applicationName: "App3", title: "Win3", lastActivatedAt: now.addingTimeInterval(-20)),
            RawWindowCandidate(id: "w4", cgWindowID: 104, pid: 40, applicationName: "App4", title: "Win4", lastActivatedAt: now.addingTimeInterval(-30))
        ]

        // w1 のみ既存キャッシュを事前に保持し、w2〜w4 は非同期取得で後から到着させる
        let cachedImage1 = NSImage(size: NSSize(width: 100, height: 80))
        let freshImage2 = NSImage(size: NSSize(width: 120, height: 90))
        captureService.cachedThumbnails[101] = cachedImage1

        var captureStartedContinuation: CheckedContinuation<Void, Never>?
        var captureResumeContinuation: CheckedContinuation<Void, Never>?
        captureService.captureHandler = { _, onCaptured in
            captureStartedContinuation?.resume()
            await withCheckedContinuation { cont in
                captureResumeContinuation = cont
            }
            onCaptured(102, freshImage2)
        }

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: captureService,
            normalDisplayStyle: .capture
        )
        // 横幅 820pt の画面（3 列グリッド相当）としてレイアウト条件を設定する
        viewModel.updateAvailableScreenSize(CGSize(width: 820, height: 800))

        // 起動直後は非同期キャプチャ完了前でも即座に表示され、キャッシュ済みの w1 のみ画像があり w2 は nil（プレースホルダー）
        await withCheckedContinuation { cont in
            captureStartedContinuation = cont
            viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        }
        #expect(viewModel.isPresented == true)
        #expect(viewModel.mode == .normal)
        #expect(viewModel.isScreenRecordingGranted == true)
        #expect(viewModel.selectedIndex == 1)
        #expect(viewModel.thumbnail(for: viewModel.entries[0]) === cachedImage1)
        #expect(viewModel.thumbnail(for: viewModel.entries[1]) == nil)

        // 非同期キャプチャ完了で w2 のサムネイルが反映される
        captureResumeContinuation?.resume()
        await Task.yield()
        await Task.yield()
        #expect(viewModel.thumbnail(for: viewModel.entries[1]) === freshImage2)

        // 3列×4件グリッドで4方向移動を検証（現在 index 1 -> 右:2 -> 下:3(最終行末尾) -> 上:0 -> 左:3）
        viewModel.handleHotKeyEvent(.arrowPressed(direction: .right))
        #expect(viewModel.selectedIndex == 2)
        viewModel.handleHotKeyEvent(.arrowPressed(direction: .down))
        #expect(viewModel.selectedIndex == 3)
        viewModel.handleHotKeyEvent(.arrowPressed(direction: .up))
        #expect(viewModel.selectedIndex == 0)
        viewModel.handleHotKeyEvent(.arrowPressed(direction: .left))
        #expect(viewModel.selectedIndex == 3)

        // index 1 (w2, cgWindowID 102) を選択してクローズすると、キャッシュからも破棄され一覧が更新される
        viewModel.moveSelection(.right) // 3 -> 0
        viewModel.moveSelection(.right) // 0 -> 1 (w2)
        #expect(viewModel.selectedIndex == 1)
        await viewModel.closeSelectedWindow()
        #expect(captureService.invalidatedWindowIDs.contains(102))
        #expect(viewModel.entries.map(\.id) == ["w1", "w3", "w4"])
        #expect(viewModel.capturedThumbnails[102] == nil)
        #expect(viewModel.selectedIndex == 1)
    }

    /// 画面収録権限が未許可の状態でキャプチャ表示型を起動してもクラッシュせず、
    /// 権限未許可フラグとプレースホルダーで切り替え継続でき、設定画面自動遷移を行わずランチャー非介入・セッション保護・リスト復帰が動作することを検証する
    @Test("権限未許可フォールバック・設定非遷移・ランチャー非介入・セッション跨ぎ破棄・リスト復帰キャッシュ消去")
    @MainActor
    func captureStyleFallbackSessionSafetyAndOptInIsolation() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let screenRecordingService = MockScreenRecordingPermissionService()
        screenRecordingService.stubbedStatus = .denied
        let captureService = MockWindowCaptureService()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", cgWindowID: 201, pid: 10, applicationName: "App1", title: "Win1", lastActivatedAt: now),
            RawWindowCandidate(id: "w2", cgWindowID: 202, pid: 20, applicationName: "App2", title: "Win2", lastActivatedAt: now.addingTimeInterval(-10))
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: captureService,
            normalDisplayStyle: .capture
        )

        // 1. 画面収録権限が未許可のとき、キャプチャ取得は呼ばずプレースホルダーのまま切り替え可能
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.isPresented == true)
        #expect(viewModel.isScreenRecordingGranted == false)
        #expect(captureService.capturedRequestWindowIDs.isEmpty)
        #expect(viewModel.thumbnail(for: viewModel.entries[1]) == nil)

        viewModel.handleHotKeyEvent(.modifierReleased)
        #expect(viewModel.isPresented == false)
        #expect(windowService.activatedWindows.map(\.id) == ["w2"])

        // 2. 権限未許可でキャプチャ表示型を開いて Esc キャンセルしても、システム設定遷移や権限要求は行われない
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.isPresented == true)
        #expect(viewModel.isScreenRecordingGranted == false)
        viewModel.handleHotKeyEvent(.escapePressed)
        #expect(viewModel.isPresented == false)
        #expect(screenRecordingService.openSystemSettingsCallCount == 0)
        #expect(screenRecordingService.requestPermissionCallCount == 0)

        // 3. キャプチャ表示型設定中でも、検索ランチャー起動時は画面収録権限の確認もキャプチャ取得も行わない
        let statusCountBeforeLauncher = screenRecordingService.currentStatusCallCount
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.mode == .launcher)
        #expect(viewModel.isScreenRecordingGranted == true)
        #expect(screenRecordingService.currentStatusCallCount == statusCountBeforeLauncher)
        #expect(captureService.capturedRequestWindowIDs.isEmpty)
        viewModel.cancel()

        // 4. セッション跨ぎ: 1回目の非同期キャプチャ完了前にキャンセル→再起動しても古い結果が混入しない
        screenRecordingService.stubbedStatus = .granted
        var session1Continuation: CheckedContinuation<Void, Never>?
        var session1Started: CheckedContinuation<Void, Never>?
        var callIndex = 0
        let staleImage = NSImage(size: NSSize(width: 50, height: 50))
        let freshImage = NSImage(size: NSSize(width: 80, height: 80))

        captureService.captureHandler = { _, onCaptured in
            callIndex += 1
            if callIndex == 1 {
                session1Started?.resume()
                await withCheckedContinuation { cont in
                    session1Continuation = cont
                }
                // 古いセッション側の遅延結果として別画像を通知する
                onCaptured(201, staleImage)
            } else {
                onCaptured(202, freshImage)
            }
        }

        await withCheckedContinuation { cont in
            session1Started = cont
            viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        }
        viewModel.cancel()
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        await Task.yield()

        // 古いセッションを完了させても世代不一致により 201 には誤反映されない
        session1Continuation?.resume()
        await Task.yield()
        #expect(viewModel.capturedThumbnails[201] == nil)
        #expect(viewModel.capturedThumbnails[202] === freshImage)

        // 5. リスト型へ戻すと全キャッシュ破棄が呼ばれ、以降の通常起動でもキャプチャは実行されない
        let captureCallsBeforeList = captureService.capturedRequestWindowIDs.count
        let statusCallsBeforeList = screenRecordingService.currentStatusCallCount
        viewModel.updateNormalDisplayStyle(.list)
        #expect(captureService.clearCacheCallCount == 1)
        #expect(viewModel.capturedThumbnails.isEmpty)

        viewModel.cancel()
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.isPresented == true)
        #expect(captureService.capturedRequestWindowIDs.count == captureCallsBeforeList)
        #expect(screenRecordingService.currentStatusCallCount == statusCallsBeforeList)
    }

    /// 起動時は許可キャッシュが残っていても、非同期キャプチャ中に権限拒否（失効）が検知された場合は
    /// 即座に未許可バナー＆プレースホルダーへ切り替え、2回目以降の起動でキャプチャを再試行しないことを検証する
    @Test("非同期キャプチャ中の権限失効検知で即座に未許可表示へ切り替え次回以降の再要求ループを防ぐ")
    @MainActor
    func runtimePermissionRevocationSwitchesToDeniedAndStopsRepeatedCapture() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let screenRecordingService = MockScreenRecordingPermissionService()
        screenRecordingService.stubbedStatus = .granted
        let captureService = MockWindowCaptureService()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", cgWindowID: 301, pid: 10, applicationName: "App1", title: "Win1", lastActivatedAt: now),
            RawWindowCandidate(id: "w2", cgWindowID: 302, pid: 20, applicationName: "App2", title: "Win2", lastActivatedAt: now.addingTimeInterval(-10))
        ]
        // 旧キャッシュが残っていても、権限失効後はクリア・非表示になる
        captureService.cachedThumbnails[301] = NSImage(size: NSSize(width: 80, height: 60))

        // ScreenCaptureKit 呼び出しで権限拒否を検知したケースを再現する
        captureService.captureHandler = { _, _ in
            captureService.clearCache()
            screenRecordingService.markAccessRevoked()
        }

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: captureService,
            normalDisplayStyle: .capture
        )

        // 1回目の起動: 初回チェック時は許可扱いで開始し、非同期キャプチャ内で失効を検知して未許可へ切り替わる
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        await Task.yield()
        await Task.yield()

        #expect(viewModel.isPresented == true)
        #expect(viewModel.isScreenRecordingGranted == false)
        #expect(viewModel.capturedThumbnails.isEmpty)
        #expect(captureService.capturedRequestWindowIDs.count == 1)
        #expect(screenRecordingService.markAccessRevokedCallCount == 1)

        // 2回目の起動: 既に未許可状態が維持されているためキャプチャ API を二度と呼ばない
        viewModel.cancel()
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        await Task.yield()

        #expect(viewModel.isPresented == true)
        #expect(viewModel.isScreenRecordingGranted == false)
        #expect(viewModel.capturedThumbnails.isEmpty)
        #expect(captureService.capturedRequestWindowIDs.count == 1)
    }

    /// メモアプリで 1 枚のみ実ウィンドウを開き裏方ゴースト候補が混在する場合でも、
    /// スイッチャー（リスト型／キャプチャ表示型）および検索ランチャー双方で 1 件のみ表示され、
    /// 閉じる操作で単一ウィンドウ終了（terminateApplication）が実行されることを検証する
    @Test("メモアプリのゴースト候補が混在してもスイッチャーとランチャー双方で1件のみ表示し単一終了判定できる")
    @MainActor
    func notesGhostCandidatesDeduplicatedInBothSwitcherAndLauncherWithSingleWindowClose() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let screenRecordingService = MockScreenRecordingPermissionService()
        let captureService = MockWindowCaptureService()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(
                id: "ax-vscode-1",
                cgWindowID: 55,
                pid: 1081,
                bundleIdentifier: "com.microsoft.VSCode",
                applicationName: "Code",
                title: "Wintch",
                bounds: WindowBounds(x: 0, y: 0, width: 1920, height: 1080),
                axRole: "AXWindow",
                axSubrole: "AXStandardWindow",
                hasAXInfo: true,
                isOnScreen: true,
                lastActivatedAt: now,
                zOrderIndex: 0
            ),
            RawWindowCandidate(
                id: "ax-notes-main",
                cgWindowID: 7248,
                pid: 71905,
                bundleIdentifier: "com.apple.Notes",
                applicationName: "メモ",
                title: "eco検定 – 14件のメモ",
                bounds: WindowBounds(x: 487, y: 30, width: 1157, height: 1046),
                axRole: "AXWindow",
                axSubrole: "AXStandardWindow",
                hasAXInfo: true,
                isOnScreen: false,
                lastActivatedAt: now.addingTimeInterval(-10),
                zOrderIndex: 1
            ),
            RawWindowCandidate(
                id: "cg-notes-aux-475",
                cgWindowID: 7247,
                pid: 71905,
                bundleIdentifier: "com.apple.Notes",
                applicationName: "メモ",
                title: nil,
                bounds: WindowBounds(x: 828, y: 253, width: 475, height: 600),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false,
                zOrderIndex: 2
            ),
            RawWindowCandidate(
                id: "cg-notes-backing-500",
                cgWindowID: 7249,
                pid: 71905,
                bundleIdentifier: "com.apple.Notes",
                applicationName: "メモ",
                title: nil,
                bounds: WindowBounds(x: 0, y: 580, width: 500, height: 500),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false,
                zOrderIndex: 3
            )
        ]

        // 1. 通常スイッチャー（リスト型）でメモが 1 件のみ表示される
        let listSwitcherVM = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            normalDisplayStyle: .list
        )
        listSwitcherVM.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(listSwitcherVM.entries.map(\.id) == ["ax-vscode-1", "ax-notes-main"])
        listSwitcherVM.cancel()

        // 2. 通常スイッチャー（キャプチャ表示型）でもメモが 1 件のみ表示される
        let captureSwitcherVM = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: captureService,
            normalDisplayStyle: .capture
        )
        captureSwitcherVM.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        await Task.yield()
        #expect(captureSwitcherVM.entries.map(\.id) == ["ax-vscode-1", "ax-notes-main"])
        captureSwitcherVM.cancel()

        // 3. 検索ランチャーでもメモは 1 件のみ表示され、クローズ操作で単一ウィンドウとしてアプリ終了が呼ばれる
        let launcherVM = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )
        launcherVM.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(launcherVM.entries.map(\.id) == ["ax-vscode-1", "ax-notes-main"])

        launcherVM.updateSearchQuery("メモ")
        #expect(launcherVM.entries.map(\.id) == ["ax-notes-main"])
        #expect(launcherVM.selectedIndex == 0)

        await launcherVM.closeSelectedWindow()
        #expect(windowService.terminatedPIDs == [71905])
        #expect(windowService.closedWindows.isEmpty)
    }

    /// 500x500 の未表示バックキングウィンドウのみ保持する待機中アプリ（Gemini 等）は
    /// ウィンドウ候補に含まれず、検索ランチャーではアプリ起動候補として扱われることを検証する
    @Test("500x500裏方窓のみの待機中アプリはウィンドウ除外されランチャーでアプリ起動候補となる")
    @MainActor
    func idleAppWithOnlyHiddenBackingWindowShowsAsLaunchCandidateInLauncher() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let installedAppService = MockInstalledAppService()

        windowService.stubbedCandidates = [
            RawWindowCandidate(
                id: "ax-vscode-1",
                cgWindowID: 55,
                pid: 1081,
                bundleIdentifier: "com.microsoft.VSCode",
                applicationName: "Code",
                title: "Wintch",
                bounds: WindowBounds(x: 0, y: 0, width: 1920, height: 1080),
                axRole: "AXWindow",
                axSubrole: "AXStandardWindow",
                hasAXInfo: true,
                isOnScreen: true,
                lastActivatedAt: Date(),
                zOrderIndex: 0
            ),
            RawWindowCandidate(
                id: "cg-gemini-backing",
                cgWindowID: 7261,
                pid: 72152,
                bundleIdentifier: "com.google.GeminiMacOS",
                applicationName: "Gemini",
                title: nil,
                bounds: WindowBounds(x: 0, y: 580, width: 500, height: 500),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false,
                zOrderIndex: 1
            )
        ]
        installedAppService.stubbedApps = [
            LaunchableApp(
                displayName: "Gemini",
                bundleIdentifier: "com.google.GeminiMacOS",
                bundleURL: URL(fileURLWithPath: "/Applications/Gemini.app")
            )
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            installedAppService: installedAppService
        )

        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.entries.map(\.id) == ["ax-vscode-1"])

        viewModel.updateSearchQuery("gemini")
        #expect(viewModel.displayedResults.isEmpty)
        #expect(viewModel.displayedAppResults.map(\.app.displayName) == ["Gemini"])
    }

    /// ウィンドウ0件の状態でも検索ランチャーを起動でき、アプリ検索・起動・キャンセル・権限未許可フォールバックが機能することを検証する
    @Test("ウィンドウ0件状態でも検索ランチャーを起動してアプリを検索・起動およびキャンセルできる")
    @MainActor
    func launcherPresentsAndLaunchesAppsWhenNoWindowsExist() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let installedAppService = MockInstalledAppService()

        windowService.stubbedCandidates = []
        installedAppService.stubbedApps = [
            LaunchableApp(
                displayName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")
            ),
            LaunchableApp(
                displayName: "メモ",
                alternateName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                bundleURL: URL(fileURLWithPath: "/System/Applications/Notes.app")
            )
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            installedAppService: installedAppService
        )

        // 1. ウィンドウ0件で検索ランチャーを起動すると未入力案内状態で開く
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        await Task.yield()
        #expect(viewModel.isPresented == true)
        #expect(viewModel.mode == .launcher)
        #expect(viewModel.hasOpenWindows == false)
        #expect(viewModel.displayedResults.isEmpty)
        #expect(viewModel.displayedAppResults.isEmpty)
        #expect(viewModel.selectedIndex == 0)
        #expect(viewModel.emptyState == .noOpenWindows)
        #expect(viewModel.launchSectionHeaderTitle == "アプリを起動")
        #expect(hotKeyMonitor.activeMode == .launcher)
        #expect(installedAppService.refreshCallCount == 1)

        // 空白のみの入力ではアプリ一覧を展開せず、未入力案内状態を維持する
        viewModel.updateSearchQuery("   ")
        #expect(viewModel.displayedAppResults.isEmpty)
        #expect(viewModel.emptyState == .noOpenWindows)

        // 2. 英語・日本語別名キーワードでアプリを起動候補として検索・確定起動できる
        viewModel.updateSearchQuery("note")
        #expect(viewModel.emptyState == nil)
        #expect(viewModel.displayedAppResults.map(\.app.displayName) == ["メモ"])
        #expect(viewModel.selectedIndex == 0)
        viewModel.confirmSelection()
        #expect(installedAppService.launchedApps.map(\.displayName) == ["メモ"])
        #expect(viewModel.isPresented == false)
        #expect(hotKeyMonitor.activeMode == .inactive)

        // 3. クリック選択（selectAndActivate）でも起動でき、Esc/トグル再押下では起動せず閉じる
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        viewModel.updateSearchQuery("saf")
        #expect(viewModel.displayedAppResults.map(\.app.displayName) == ["Safari"])
        viewModel.handleHotKeyEvent(.escapePressed)
        #expect(viewModel.isPresented == false)
        #expect(installedAppService.launchedApps.count == 1)

        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        viewModel.updateSearchQuery("saf")
        viewModel.selectAndActivate(at: 0)
        #expect(installedAppService.launchedApps.map(\.displayName) == ["メモ", "Safari"])
        #expect(viewModel.isPresented == false)

        // 4. 権限未許可時はウィンドウ0件でもランチャーを開かず権限誘導通知を呼ぶ
        var deniedNotified = false
        viewModel.onPermissionDenied = { deniedNotified = true }
        permissionService.stubbedStatus = .denied
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.isPresented == false)
        #expect(deniedNotified == true)
    }

    /// ウィンドウ0件時の通常スイッチャー非起動維持・最後のウィンドウ終了時のランチャー継続・検索0件およびクリア遷移を検証する
    @Test("ウィンドウ0件の通常スイッチャー非起動とランチャーでの最後1枚クローズ維持および境界状態が安全に動作する")
    @MainActor
    func zeroWindowRoleSeparationAndLastWindowCloseInLauncher() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let installedAppService = MockInstalledAppService()

        installedAppService.stubbedApps = [
            LaunchableApp(
                displayName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")
            ),
            LaunchableApp(
                displayName: "Slack",
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                bundleURL: URL(fileURLWithPath: "/Applications/Slack.app")
            )
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            installedAppService: installedAppService
        )

        // 1. ウィンドウ0件のときは通常スイッチャー（順方向・逆方向とも）を開かない
        windowService.stubbedCandidates = []
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.isPresented == false)
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: true))
        #expect(viewModel.isPresented == false)

        // 2. 検索語入力中に最後の1枚のウィンドウを閉じてもパネルが維持され、アプリ起動候補が再評価される
        windowService.stubbedCandidates = [
            RawWindowCandidate(
                id: "only-safari",
                pid: 42,
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                title: "Start Page"
            )
        ]
        var focusRestoredModes: [SwitcherMode] = []
        var searchResultsUpdatedCount = 0
        viewModel.onPanelFocusRestoreNeeded = { focusRestoredModes.append($0) }
        viewModel.onSearchResultsUpdated = { searchResultsUpdatedCount += 1 }

        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        viewModel.updateSearchQuery("s")
        #expect(viewModel.displayedResults.map(\.entry.applicationName) == ["Safari"])
        // 上に Safari ウィンドウがあるため下のアプリ起動候補には Slack のみが出ている
        #expect(viewModel.displayedAppResults.map(\.app.displayName) == ["Slack"])

        let updatesBeforeClose = searchResultsUpdatedCount
        await viewModel.closeSelectedWindow()
        #expect(windowService.terminatedPIDs == [42])
        #expect(viewModel.isPresented == true)
        #expect(viewModel.mode == .launcher)
        #expect(viewModel.hasOpenWindows == false)
        #expect(viewModel.displayedResults.isEmpty)
        // Safari のウィンドウが閉じたため、検索語 "s" に対するアプリ起動候補へ Safari も再出現する
        #expect(viewModel.displayedAppResults.map(\.app.displayName) == ["Safari", "Slack"])
        #expect(viewModel.selectedIndex == 0)
        #expect(viewModel.emptyState == nil)
        #expect(viewModel.launchSectionHeaderTitle == "アプリを起動")
        #expect(searchResultsUpdatedCount > updatesBeforeClose)
        #expect(focusRestoredModes.last == .launcher)

        // 3. 検索語をすべて削除するとウィンドウ0件時の案内状態へ戻る
        viewModel.updateSearchQuery("")
        #expect(viewModel.displayedResults.isEmpty)
        #expect(viewModel.displayedAppResults.isEmpty)
        #expect(viewModel.emptyState == .noOpenWindows)

        // 4. 一致するアプリもない検索時は .noMatchingApps となり、Enter・移動・クローズが無視される
        viewModel.updateSearchQuery("zzzz-not-found")
        #expect(viewModel.emptyState == .noMatchingApps)
        viewModel.moveSelection(.down)
        viewModel.confirmSelection()
        await viewModel.closeSelectedWindow()
        #expect(viewModel.isPresented == true)
        #expect(installedAppService.launchedApps.isEmpty)
        #expect(windowService.closedWindows.isEmpty)
    }

    /// セキュア入力等のフォールバック起動時のみ通常スイッチャーで一時アクティブ化フラグが有効化され、終了時にリセットされることを検証する
    @Test("通常スイッチャーの一時アクティブ化フラグが監視サービス要求に連動し終了時にリセットされる")
    @MainActor
    func normalModeTemporaryActivationFlagTracksHotKeyMonitorRequirement() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        windowService.stubbedCandidates = [
            RawWindowCandidate(
                id: "win-1",
                pid: 101,
                bundleIdentifier: "com.google.Chrome",
                applicationName: "Google Chrome",
                title: "Sign In"
            ),
            RawWindowCandidate(
                id: "win-2",
                pid: 102,
                bundleIdentifier: "com.apple.TextEdit",
                applicationName: "TextEdit",
                title: "Notes.txt"
            )
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )

        // 通常経路（requiresAppActivationOnPresentation == false）では非アクティブ表示のまま維持する
        hotKeyMonitor.requiresAppActivationOnPresentation = false
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.isPresented == true)
        #expect(viewModel.shouldActivateAppForCurrentSession == false)
        viewModel.handleHotKeyEvent(.escapePressed)
        #expect(viewModel.shouldActivateAppForCurrentSession == false)

        // フォールバック経路（requiresAppActivationOnPresentation == true）では一時アクティブ化を要求する
        hotKeyMonitor.requiresAppActivationOnPresentation = true
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.isPresented == true)
        #expect(viewModel.shouldActivateAppForCurrentSession == true)

        // 確定（修飾キー解放）およびキャンセルのいずれでも終了後にフラグがリセットされる
        viewModel.handleHotKeyEvent(.modifierReleased)
        #expect(viewModel.isPresented == false)
        #expect(viewModel.shouldActivateAppForCurrentSession == false)

        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.shouldActivateAppForCurrentSession == true)
        viewModel.handleHotKeyEvent(.escapePressed)
        #expect(viewModel.isPresented == false)
        #expect(viewModel.shouldActivateAppForCurrentSession == false)
    }

    /// スイッチャー外で多数のウィンドウが開閉された後でも、起動時に閉じ済みキャッシュが整理され、
    /// MRU 最古→最新の逆順参照によって直近アクティブウィンドウのキャッシュが追い出されないことを検証する
    @Test("大量開閉後の生存ウィンドウ保持とMRU逆順読み込みによる直近キャッシュ保護が動作する")
    @MainActor
    func captureSwitcherPrunesClosedWindowsAndPreservesRecentThumbnailsInMRUOrder() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let screenRecordingService = MockScreenRecordingPermissionService()
        screenRecordingService.stubbedStatus = .granted

        // 1. MockWindowCaptureService で pruneCache 対象・参照順（MRU 最古→最新）を検証する
        let mockCapture = MockWindowCaptureService()
        let staleIDs: [UInt32] = Array(1000..<1120)
        for staleID in staleIDs {
            mockCapture.cachedThumbnails[staleID] = NSImage(size: NSSize(width: 40, height: 30))
        }
        let imgRecent = NSImage(size: NSSize(width: 80, height: 60))
        let imgMiddle = NSImage(size: NSSize(width: 80, height: 60))
        let imgOld = NSImage(size: NSSize(width: 80, height: 60))
        mockCapture.cachedThumbnails[1] = imgRecent
        mockCapture.cachedThumbnails[2] = imgMiddle
        mockCapture.cachedThumbnails[3] = imgOld

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w-recent", cgWindowID: 1, pid: 10, applicationName: "App1", title: "Recent", lastActivatedAt: now),
            RawWindowCandidate(id: "w-middle", cgWindowID: 2, pid: 20, applicationName: "App2", title: "Middle", lastActivatedAt: now.addingTimeInterval(-10)),
            RawWindowCandidate(id: "w-old", cgWindowID: 3, pid: 30, applicationName: "App3", title: "Old", lastActivatedAt: now.addingTimeInterval(-20))
        ]

        let mockVM = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: mockCapture,
            normalDisplayStyle: .capture
        )
        mockVM.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))

        // 閉じ済み 120 件が整理され、生存 3 件がすべて維持され、参照順が MRU 最古→最新 [3, 2, 1] となる
        #expect(mockCapture.prunedKeepingWindowIDsHistory == [Set([1, 2, 3])])
        #expect(mockCapture.cachedThumbnails.count == 3)
        #expect(mockCapture.cachedThumbnailLookupOrder == [3, 2, 1])
        #expect(mockVM.thumbnail(for: mockVM.entries[0]) === imgRecent)
        #expect(mockVM.thumbnail(for: mockVM.entries[1]) === imgMiddle)
        #expect(mockVM.thumbnail(for: mockVM.entries[2]) === imgOld)
        mockVM.cancel()

        // 2. 実 WindowCaptureService(maxCacheCount: 3) でも直近アクティブウィンドウが末尾保護され追い出されないことを検証する
        let realCapture = WindowCaptureService(
            screenRecordingPermissionService: screenRecordingService,
            maxCacheCount: 3
        )
        // 先に 1(最新), 2(中間), 3(最古) が逆の順で入っていても、present() により正しい MRU 順に整列される
        realCapture.storeInCache(imgRecent, for: 1)
        realCapture.storeInCache(imgMiddle, for: 2)
        realCapture.storeInCache(imgOld, for: 3)
        #expect(realCapture.cacheOrder == [1, 2, 3])

        let realVM = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: realCapture,
            normalDisplayStyle: .capture
        )
        realVM.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        // present() の逆順読み込みにより cacheOrder が [3, 2, 1]（最古が先頭、最直近が末尾）へ補正される
        #expect(realCapture.cacheOrder == [3, 2, 1])
        realVM.cancel()

        // 新規ウィンドウ 4 が追加されて上限 3 を超えても、追い出されるのは最古の 3 であり直近の 1 は保持される
        let imgNew = NSImage(size: NSSize(width: 80, height: 60))
        realCapture.storeInCache(imgNew, for: 4)
        #expect(realCapture.cacheOrder == [2, 1, 4])
        #expect(realCapture.cachedThumbnail(for: 3) == nil)
        #expect(realCapture.cachedThumbnail(for: 1) === imgRecent)
    }

    /// リスト型・検索ランチャー・権限未許可時は pruneCache を含めキャプチャサービスを呼ばず、
    /// 再取得失敗時にも既存サムネイルが消去されず維持されることを検証する
    @Test("非オプトイン時はpruneCacheも呼ばず再取得失敗時も既存サムネイルを維持する")
    @MainActor
    func nonOptInModesDoNotPruneAndFailedRefreshPreservesExistingThumbnail() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let screenRecordingService = MockScreenRecordingPermissionService()
        screenRecordingService.stubbedStatus = .granted
        let captureService = MockWindowCaptureService()

        let existingImage = NSImage(size: NSSize(width: 120, height: 80))
        captureService.cachedThumbnails[501] = existingImage
        captureService.cachedThumbnails[999] = NSImage(size: NSSize(width: 40, height: 40))

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", cgWindowID: 501, pid: 10, applicationName: "App1", title: "Win1", isOnScreen: true, lastActivatedAt: now),
            RawWindowCandidate(id: "w2", cgWindowID: 502, pid: 20, applicationName: "App2", title: "Win2", isOnScreen: true, lastActivatedAt: now.addingTimeInterval(-10))
        ]

        // 1. リスト型では pruneCache も含めキャプチャサービスを一切呼ばない
        let listVM = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: captureService,
            normalDisplayStyle: .list
        )
        listVM.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(captureService.prunedKeepingWindowIDsHistory.isEmpty)
        #expect(captureService.cachedThumbnailLookupOrder.isEmpty)
        listVM.cancel()

        // 2. キャプチャ設定中でもランチャー起動時および権限未許可時は pruneCache を呼ばない
        let captureVM = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: captureService,
            normalDisplayStyle: .capture
        )
        captureVM.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(captureService.prunedKeepingWindowIDsHistory.isEmpty)
        captureVM.cancel()

        screenRecordingService.stubbedStatus = .denied
        captureVM.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(captureService.prunedKeepingWindowIDsHistory.isEmpty)
        captureVM.cancel()

        // 3. 権限ありで再キャプチャに失敗（何も通知されない）場合も、既存の 501 サムネイルは維持される
        screenRecordingService.stubbedStatus = .granted
        captureService.captureHandler = { _, _ in
            // 取得失敗を模擬して onCaptured を呼ばず終了する
        }
        captureVM.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        await Task.yield()
        await Task.yield()
        #expect(captureService.prunedKeepingWindowIDsHistory == [Set([501, 502])])
        #expect(captureVM.thumbnail(for: captureVM.entries[0]) === existingImage)
        #expect(captureVM.thumbnail(for: captureVM.entries[1]) == nil)
    }

    /// Google Chrome のタブ・ウィンドウをすべて閉じて画面外の無名空き殻 CGWindow のみが残っている状態では、
    /// 通常スイッチャーおよび検索ランチャーの双方で Chrome の空ウィンドウが表示されず、ランチャーでは起動候補になることを検証する
    @Test("Chromeの全ウィンドウ閉鎖後は空の表示が残らずランチャーではアプリ起動候補として扱われる")
    @MainActor
    func chromeWithAllWindowsClosedDoesNotShowEmptyGhostInSwitcherOrLauncher() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let installedAppService = MockInstalledAppService()

        installedAppService.stubbedApps = [
            LaunchableApp(
                displayName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
            )
        ]

        // Chrome のウィンドウ全閉後に残る無名空き殻 CGWindow と、別アプリの有効ウィンドウ 1 件
        windowService.stubbedCandidates = [
            RawWindowCandidate(
                id: "ax-vscode-1",
                cgWindowID: 101,
                pid: 1465,
                bundleIdentifier: "com.microsoft.VSCode",
                applicationName: "Code",
                title: "README.md — Wintch",
                isOnScreen: true
            ),
            RawWindowCandidate(
                id: "cg-377",
                cgWindowID: 377,
                pid: 1109,
                bundleIdentifier: "com.google.Chrome",
                applicationName: "Google Chrome",
                title: nil,
                cgWindowName: "",
                bounds: WindowBounds(x: 0, y: 38, width: 1920, height: 1042),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false
            )
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            installedAppService: installedAppService,
            normalDisplayStyle: .capture
        )

        // 1. 通常スイッチャー起動時：Chrome の空表示は含まれず VS Code の 1 件のみ
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.entries.map(\.id) == ["ax-vscode-1"])
        viewModel.cancel()

        // 2. 検索ランチャー起動時：ウィンドウ一覧に Chrome はなく、検索するとアプリ起動候補に Google Chrome が現れる
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.entries.map(\.id) == ["ax-vscode-1"])
        viewModel.updateSearchQuery("chrome")
        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.displayedAppResults.map(\.app.bundleIdentifier) == ["com.google.Chrome"])
        viewModel.cancel()
    }

    /// アイコン型スイッチャーにおける 1 ウィンドウ = 1 アイコン表示、画面幅 85% 折り返しによる 4 方向矢印移動、
    /// Tab / Shift+Tab 移動、クリック確定、Esc キャンセル、修飾キー+Q クローズ、画面収録権限非参照、
    /// およびキャプチャ表示型からアイコン型への切り替え時のキャッシュ破棄を検証する
    @Test("アイコン型で画面収録権限を使わず4方向移動・クローズ・確定・キャプチャキャッシュ破棄が動作する")
    @MainActor
    func iconStyleFourWayNavigationCloseWindowAndZeroScreenRecordingAccess() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let screenRecordingService = MockScreenRecordingPermissionService()
        screenRecordingService.stubbedStatus = .denied
        let captureService = MockWindowCaptureService()

        let now = Date()
        // 同一アプリの複数ウィンドウを含む 5 件の有効ウィンドウ
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", cgWindowID: 401, pid: 10, applicationName: "Safari", title: "Tab 1", lastActivatedAt: now),
            RawWindowCandidate(id: "w2", cgWindowID: 402, pid: 10, applicationName: "Safari", title: "Tab 2", lastActivatedAt: now.addingTimeInterval(-10)),
            RawWindowCandidate(id: "w3", cgWindowID: 403, pid: 20, applicationName: "Finder", title: "Desktop", lastActivatedAt: now.addingTimeInterval(-20)),
            RawWindowCandidate(id: "w4", cgWindowID: 404, pid: 30, applicationName: "Code", title: "Wintch", lastActivatedAt: now.addingTimeInterval(-30)),
            RawWindowCandidate(id: "w5", cgWindowID: 405, pid: 40, applicationName: "Notes", title: "Ideas", lastActivatedAt: now.addingTimeInterval(-40))
        ]

        // 先にキャプチャ表示型でサムネイルを保持した状態からアイコン型へ切り替えた際、即座にキャッシュが破棄されることを確認する
        screenRecordingService.stubbedStatus = .granted
        captureService.cachedThumbnails[401] = NSImage(size: NSSize(width: 80, height: 60))

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: captureService,
            normalDisplayStyle: .capture
        )
        // 500pt 幅画面: アイコン型では 3 列（1 行目: [0, 1, 2]、2 行目: [3, 4]）に折り返される
        viewModel.updateAvailableScreenSize(CGSize(width: 500, height: 800))
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.capturedThumbnails[401] != nil)
        viewModel.cancel()

        // キャプチャ表示型 -> アイコン型へ変更するとキャプチャキャッシュが全破棄される
        let statusCallsBeforeIcon = screenRecordingService.currentStatusCallCount
        let captureCallsBeforeIcon = captureService.capturedRequestWindowIDs.count
        viewModel.updateNormalDisplayStyle(.icon)
        #expect(viewModel.normalDisplayStyle == .icon)
        #expect(viewModel.capturedThumbnails.isEmpty)
        #expect(captureService.clearCacheCallCount == 1)

        // アイコン型で起動: 同一アプリの複数ウィンドウも集約せず 5 件すべて並び、初期選択は 2 番目（index 1）
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.isPresented == true)
        #expect(viewModel.mode == .normal)
        #expect(viewModel.entries.map(\.id) == ["w1", "w2", "w3", "w4", "w5"])
        #expect(viewModel.selectedIndex == 1)
        #expect(viewModel.gridColumnCount == 3)
        // 画面収録権限の確認・キャプチャ要求・キャッシュpruneは一切実行されない
        #expect(screenRecordingService.currentStatusCallCount == statusCallsBeforeIcon)
        #expect(captureService.capturedRequestWindowIDs.count == captureCallsBeforeIcon)
        #expect(viewModel.capturedThumbnails.isEmpty)

        // 3 列 × 5 件グリッドでの上下左右矢印移動（index 1 -> 下:4 -> 上:1 -> 右:2 -> 下:4(最終行末尾丸め) -> 左:3）
        viewModel.handleHotKeyEvent(.arrowPressed(direction: .down))
        #expect(viewModel.selectedIndex == 4)
        viewModel.handleHotKeyEvent(.arrowPressed(direction: .up))
        #expect(viewModel.selectedIndex == 1)
        viewModel.handleHotKeyEvent(.arrowPressed(direction: .right))
        #expect(viewModel.selectedIndex == 2)
        viewModel.handleHotKeyEvent(.arrowPressed(direction: .down))
        #expect(viewModel.selectedIndex == 4)
        viewModel.handleHotKeyEvent(.arrowPressed(direction: .left))
        #expect(viewModel.selectedIndex == 3)

        // Tab / Shift + Tab による前後移動
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.selectedIndex == 4)
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: true))
        #expect(viewModel.selectedIndex == 3)

        // 修飾キー + Q で index 3 (w4) を閉じ、続いてさらに2件閉じて残り 2 件になると gridColumnCount も 2 列へ再計算される
        await viewModel.closeSelectedWindow()
        #expect(windowService.terminatedPIDs == [30])
        #expect(viewModel.entries.map(\.id) == ["w1", "w2", "w3", "w5"])
        #expect(viewModel.gridColumnCount == 3)

        await viewModel.closeSelectedWindow() // index 3 (w5) を閉じる -> 残り 3 件
        viewModel.moveSelection(.left) // index 2 -> 1 (w2: Safari 2枚のうち1枚)
        await viewModel.closeSelectedWindow() // w2 を単体クローズ -> 残り 2 件 (w1, w3)
        #expect(windowService.closedWindows.map(\.id) == ["w2"])
        #expect(viewModel.entries.map(\.id) == ["w1", "w3"])
        #expect(viewModel.gridColumnCount == 2)

        // タイルクリック（selectAndActivate）で直接確定・アクティブ化できる
        viewModel.selectAndActivate(at: 0)
        #expect(viewModel.isPresented == false)
        #expect(windowService.activatedWindows.map(\.id) == ["w1"])

        // 再起動して Esc キャンセルするとアクティブ化せず閉じる
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.isPresented == true)
        viewModel.handleHotKeyEvent(.escapePressed)
        #expect(viewModel.isPresented == false)
        #expect(windowService.activatedWindows.map(\.id) == ["w1"])
    }
}
