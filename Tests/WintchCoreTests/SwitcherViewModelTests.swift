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

        // ランチャー表示中に通常ショートカットが押されてもランチャーを維持したまま「次へ」「前へ」移動する
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

        // 2. ランチャーモードで最後の1件を閉じてもアプリ終了の上で自動的にパネル終了する
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.mode == .launcher)
        await viewModel.closeSelectedWindow()
        #expect(windowService.terminatedPIDs == [10, 10])
        #expect(viewModel.isPresented == false)
        #expect(hotKeyMonitor.activeMode == .inactive)

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
        let closeTask1 = Task { @MainActor in
            await viewModel.closeSelectedWindow()
        }
        // 1件目が待機中に入るまで譲歩し、その間に2回目を呼んでも無視されることを確認する
        await Task.yield()
        let closeTask2 = Task { @MainActor in
            await viewModel.closeSelectedWindow()
        }
        await closeTask2.value
        #expect(windowService.closedWindows.map(\.id) == ["w2"])

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

    /// ランチャー検索で既存ウィンドウが 0 件の場合にアプリ起動候補を表示し、選択移動・確定で新規起動できることを検証する
    @Test("ランチャー検索で既存ウィンドウが0件のときアプリ起動候補を表示し選択・起動できる")
    @MainActor
    func launcherZeroWindowMatchesShowsAndLaunchesAppCandidates() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let installedAppService = MockInstalledAppService()

        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", pid: 10, applicationName: "Safari", title: "Apple")
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
        #expect(viewModel.isShowingLaunchCandidates == false)
        #expect(viewModel.displayedAppResults.isEmpty)

        // 既存ウィンドウに一致する場合はアプリ候補を出さない
        viewModel.updateSearchQuery("saf")
        #expect(viewModel.displayedResults.map(\.id) == ["w1"])
        #expect(viewModel.isShowingLaunchCandidates == false)
        #expect(viewModel.displayedAppResults.isEmpty)

        // 既存ウィンドウに一致しない "cal" を入力すると Calculator / Calendar がアプリ候補に出る
        viewModel.updateSearchQuery("cal")
        #expect(viewModel.displayedResults.isEmpty)
        #expect(viewModel.isShowingLaunchCandidates == true)
        #expect(viewModel.displayedAppResults.map(\.app.displayName) == ["Calculator", "Calendar"])
        #expect(viewModel.selectedIndex == 0)

        // 上下キーおよび通常スイッチャーショートカットでアプリ候補内を循環移動できる
        viewModel.moveSelection(.down)
        #expect(viewModel.selectedIndex == 1)
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.selectedIndex == 0)
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: true))
        #expect(viewModel.selectedIndex == 1)

        // 検索語を空に戻すと既存ウィンドウ一覧に戻る
        viewModel.updateSearchQuery("")
        #expect(viewModel.isShowingLaunchCandidates == false)
        #expect(viewModel.displayedAppResults.isEmpty)
        #expect(viewModel.displayedResults.map(\.id) == ["w1"])

        // 再び "cal" で絞り込み、2番目の Calendar をクリック相当で確定するとアプリが起動しパネルが閉じる
        viewModel.updateSearchQuery("cal")
        viewModel.selectAndActivate(at: 1)
        #expect(viewModel.isPresented == false)
        #expect(viewModel.mode == .inactive)
        #expect(hotKeyMonitor.activeMode == .inactive)
        #expect(windowService.activatedWindows.isEmpty)
        #expect(installedAppService.launchedApps.map(\.displayName) == ["Calendar"])
    }

    /// アプリ候補表示中のウィンドウクローズ無視、クローズによる 0 件化時のアプリ候補遷移、および非同期更新反映を検証する
    @Test("ウィンドウクローズで0件になった場合のアプリ候補表示と非同期更新が安全に動作する")
    @MainActor
    func closeToZeroShowsAppCandidatesAndBackgroundRefreshUpdatesSafely() async {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        let iconProvider = MockIconProvider()
        let installedAppService = MockInstalledAppService()

        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(id: "w1", pid: 10, applicationName: "Slack", title: "General", lastActivatedAt: now),
            RawWindowCandidate(id: "w2", pid: 20, applicationName: "Safari", title: "Docs", lastActivatedAt: now.addingTimeInterval(-10))
        ]
        installedAppService.stubbedApps = [
            LaunchableApp(
                displayName: "Slack",
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                bundleURL: URL(fileURLWithPath: "/Applications/Slack.app")
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

        // バックグラウンド更新が待機状態に入るのを確実に待ってからテストを進める
        await withCheckedContinuation { cont in
            refreshHandlerEnteredContinuation = cont
            viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        }
        viewModel.updateSearchQuery("sla")
        #expect(viewModel.displayedResults.map(\.id) == ["w1"])

        await viewModel.closeSelectedWindow()
        #expect(windowService.terminatedPIDs == [10])
        #expect(viewModel.displayedResults.isEmpty)
        #expect(viewModel.isShowingLaunchCandidates == true)
        #expect(viewModel.displayedAppResults.map(\.app.displayName) == ["Slack"])

        // アプリ候補表示中の closeSelectedWindow は対象ウィンドウが無いため安全に無視される
        await viewModel.closeSelectedWindow()
        #expect(windowService.closedWindows.isEmpty)
        #expect(windowService.terminatedPIDs == [10])

        // ランチャー表示中に裏のアプリ一覧リフレッシュが完了し新アプリが増えた場合、候補が再評価される
        await withCheckedContinuation { updateWaitCont in
            viewModel.onSearchResultsUpdated = {
                updateWaitCont.resume()
            }
            refreshContinuation?.resume(returning: [
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
            ])
        }
        #expect(viewModel.displayedAppResults.map(\.app.displayName) == ["Slack", "Slack Helper App"])

        // Enter（confirmSelection）で先頭の Slack を起動する
        viewModel.confirmSelection()
        #expect(viewModel.isPresented == false)
        #expect(installedAppService.launchedApps.map(\.displayName) == ["Slack"])
    }
}
