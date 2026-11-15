import AppKit
import Observation

/// スイッチャーパネルの現在の表示モード
public enum SwitcherMode: Equatable, Sendable {
    /// 非表示状態
    case inactive
    /// 従来の修飾キー保持式ウィンドウスイッチャーモード
    case normal
    /// 検索入力欄付きのトグル式ランチャーモード
    case launcher
}

/// パネルが閉じられた理由（フォーカス復元制御に利用）
public enum SwitcherDismissReason: Equatable, Sendable {
    /// ウィンドウ選択を確定して閉じた
    case confirmed
    /// Esc キーやトグル再押下などで明示的にキャンセルした
    case cancelled
    /// 外部クリック等でフォーカスを喪失した
    case resignedActive
}

/// スイッチャーパネルの表示状態・検索絞り込み・選択カーソル・確定/キャンセル操作を管理する ViewModel
@MainActor
@Observable
public final class SwitcherViewModel {
    /// 現在の表示モード
    public private(set) var mode: SwitcherMode = .inactive

    /// スイッチャーパネルが表示中かどうか
    public var isPresented: Bool { mode != .inactive }

    /// 現在の検索クエリ文字列（ランチャーモード専用）
    public private(set) var searchQuery: String = ""

    /// 画面に表示する検索・ソート済みウィンドウ結果一覧
    public private(set) var displayedResults: [WindowSearchResult] = []

    /// ランチャーモードでウィンドウ一覧の下に表示するアプリ起動候補一覧（表示中のウィンドウと同アプリは除外）
    public private(set) var displayedAppResults: [AppSearchResult] = []

    /// 現在アプリ起動候補を表示中かどうか（ランチャーモードかつアプリ起動候補が 1 件以上ある場合）
    public var isShowingLaunchCandidates: Bool {
        mode == .launcher && !displayedAppResults.isEmpty
    }

    /// 現在選択操作の対象となっている全候補（ウィンドウ＋ランチャー時はアプリ起動候補）の合計件数
    private var activeResultCount: Int {
        displayedResults.count + (mode == .launcher ? displayedAppResults.count : 0)
    }

    /// 表示対象のウィンドウ項目一覧（既存ビューおよびテスト互換プロパティ）
    public var entries: [WindowEntry] {
        displayedResults.map(\.entry)
    }

    /// 現在ハイライト選択中のインデックス
    public private(set) var selectedIndex: Int = 0

    /// パネル表示状態が変化した際に呼ばれる通知ハンドラ（互換用）
    public var onPresentationChanged: ((Bool) -> Void)?

    /// モードと終了理由付きでパネル表示状態の変化を通知するハンドラ
    public var onModePresentationChanged: ((SwitcherMode, SwitcherDismissReason?) -> Void)?

    /// 検索結果や候補件数が変化し、パネルリサイズが必要な際に呼ばれる通知ハンドラ
    public var onSearchResultsUpdated: (() -> Void)?

    /// 権限未許可の状態で起動操作が行われた際に呼ばれる通知ハンドラ
    public var onPermissionDenied: (() -> Void)?

    /// 自動 Space 移動等のクローズ操作完了後にパネルのフォーカス復元が必要な際に呼ばれる通知ハンドラ
    public var onPanelFocusRestoreNeeded: ((SwitcherMode) -> Void)?

    /// 起動時に取得した全有効ウィンドウ一覧（MRU ソート済み）
    private var allEntries: [WindowEntry] = []

    /// ウィンドウクローズ処理の多重実行を防止するロックフラグ
    private var isClosingWindow = false

    /// 表示セッションを識別する世代カウンタ（非同期クローズ復帰時のセッション跨ぎ防止用）
    private var presentationGeneration: Int = 0

    /// ウィンドウ取得・アクティブ化サービス
    private let windowService: any WindowServicing
    /// グローバルホットキー監視サービス
    private let hotKeyMonitor: any HotKeyMonitoring
    /// アクセシビリティ権限確認サービス
    private let permissionService: any AccessibilityPermissionServicing
    /// アプリアイコン取得サービス
    private let iconProvider: any IconProviding
    /// インストール済みアプリ取得・起動サービス
    private let installedAppService: (any InstalledAppServicing)?
    /// インストール済みアプリ一覧のバックグラウンド更新タスク
    private var installedAppsRefreshTask: Task<Void, Never>?

    /// スイッチャー ViewModel を初期化する
    /// - Parameters:
    ///   - windowService: ウィンドウ情報サービス
    ///   - hotKeyMonitor: ホットキー監視サービス
    ///   - permissionService: 権限確認サービス
    ///   - iconProvider: アイコン取得サービス
    ///   - installedAppService: インストール済みアプリ取得・起動サービス（省略時はアプリ起動候補なし）
    public init(
        windowService: any WindowServicing,
        hotKeyMonitor: any HotKeyMonitoring,
        permissionService: any AccessibilityPermissionServicing,
        iconProvider: any IconProviding,
        installedAppService: (any InstalledAppServicing)? = nil
    ) {
        self.windowService = windowService
        self.hotKeyMonitor = hotKeyMonitor
        self.permissionService = permissionService
        self.iconProvider = iconProvider
        self.installedAppService = installedAppService
    }

    /// 指定されたプロセス ID のアプリアイコンを取得する
    /// - Parameter pid: アプリケーションのプロセス ID
    /// - Returns: アプリアイコン画像（取得できない場合は nil）
    public func icon(for pid: Int32) -> NSImage? {
        iconProvider.icon(for: pid)
    }

    /// 指定されたアプリケーションバンドル URL のアプリアイコンを取得する
    /// - Parameter url: アプリケーションバンドルの URL
    /// - Returns: アプリアイコン画像（取得できない場合は nil）
    public func icon(forAppURL url: URL) -> NSImage? {
        iconProvider.icon(forAppURL: url)
    }

    /// ランチャー検索用にインストール済みアプリ一覧をバックグラウンドで事前取得する
    public func preloadInstalledApps() {
        scheduleInstalledAppsRefresh()
    }

    /// サービス層から通知されたキーイベントを処理する
    /// - Parameter event: 受信したキーイベント
    public func handleHotKeyEvent(_ event: HotKeyEvent) {
        switch event {
        case let .triggerPressed(isShiftPressed):
            handleTriggerPressed(isShiftPressed: isShiftPressed)
        case .launcherTriggerPressed:
            handleLauncherTriggerPressed()
        case .modifierReleased:
            // トグル式のランチャーモード中は修飾キー解放で確定しない
            if mode == .normal {
                confirmSelection()
            }
        case .escapePressed:
            cancel()
        case let .arrowPressed(direction):
            moveSelection(direction)
        case .closeSelectedWindowPressed:
            Task { @MainActor [weak self] in
                await self?.closeSelectedWindow()
            }
        }
    }

    /// 現在選択中の対象を閉じる（同アプリに複数ウィンドウがあれば1枚のみ閉じ、最後の1枚ならアプリごと終了する）
    public func closeSelectedWindow() async {
        // 非表示中・クローズ処理中・選択候補なし（0件等）の場合は安全に無視する
        guard mode != .inactive,
              !isClosingWindow,
              displayedResults.indices.contains(selectedIndex) else {
            return
        }

        isClosingWindow = true
        defer { isClosingWindow = false }

        let targetMode = mode
        let capturedGeneration = presentationGeneration
        let target = displayedResults[selectedIndex].entry
        let previousIndex = selectedIndex
        // ランチャー検索による絞り込みに左右されないよう、全候補一覧を基準に同アプリの残余ウィンドウ数を判定する
        let isSingleWindowForApp = allEntries.filter { $0.pid == target.pid }.count <= 1

        let didSucceed: Bool
        if isSingleWindowForApp {
            didSucceed = await windowService.terminateApplication(pid: target.pid)
        } else {
            didSucceed = await windowService.closeWindow(target)
        }

        // 待機中に別セッションへ遷移・終了済みの場合は状態を変更せず抜ける
        guard mode == targetMode, presentationGeneration == capturedGeneration else { return }

        guard didSucceed else {
            // 自動 Space 移動等が発生した失敗ケースでもパネルの前面・フォーカスを維持する
            onPanelFocusRestoreNeeded?(targetMode)
            return
        }

        if isSingleWindowForApp {
            allEntries.removeAll { $0.pid == target.pid || $0.id == target.id }
        } else {
            allEntries.removeAll { $0.id == target.id }
        }

        if allEntries.isEmpty {
            // 開いている通常ウィンドウが全件0件になった場合はパネルを自動的に閉じる
            dismiss(reason: .cancelled)
            return
        }

        switch targetMode {
        case .normal:
            displayedResults = allEntries.map { WindowSearchResult(entry: $0) }
            displayedAppResults = []
        case .launcher:
            // 検索キーワードを維持したまま最新の残余ウィンドウおよびアプリ起動候補を再評価する
            updateLauncherSearchResults(for: searchQuery)
        case .inactive:
            return
        }

        selectedIndex = SwitcherSelection.indexAfterRemoval(
            current: previousIndex,
            remainingCount: activeResultCount
        )
        onSearchResultsUpdated?()
        onPanelFocusRestoreNeeded?(targetMode)
    }

    /// ランチャーモードの検索文字列を更新し、ファジー検索結果と選択位置を再計算する
    /// - Parameter query: 新しい検索文字列
    public func updateSearchQuery(_ query: String) {
        guard mode == .launcher, searchQuery != query else { return }
        searchQuery = query
        updateLauncherSearchResults(for: query)
        // 検索入力が変化したら先頭候補へ選択カーソルを戻す
        selectedIndex = 0
        onSearchResultsUpdated?()
    }

    /// 選択カーソルを上下に移動する（リストが空の場合は何もしない）
    /// - Parameter direction: 移動方向
    public func moveSelection(_ direction: ArrowDirection) {
        let count = activeResultCount
        guard mode != .inactive, count > 0 else { return }
        switch direction {
        case .up:
            selectedIndex = SwitcherSelection.previousIndex(current: selectedIndex, count: count)
        case .down:
            selectedIndex = SwitcherSelection.nextIndex(current: selectedIndex, count: count)
        }
    }

    /// 指定インデックスの項目をクリック等で直接選択して即座にアクティブ化または起動する
    /// - Parameter index: 選択された項目のインデックス
    public func selectAndActivate(at index: Int) {
        guard mode != .inactive, (0..<activeResultCount).contains(index) else { return }
        selectedIndex = index
        confirmSelection()
    }

    /// 現在選択中のウィンドウまたはアプリ起動候補で確定し、パネルを閉じて実行する
    public func confirmSelection() {
        guard mode != .inactive else { return }

        if displayedResults.indices.contains(selectedIndex) {
            let target = displayedResults[selectedIndex].entry
            dismiss(reason: .confirmed)
            windowService.activateWindow(target)
            return
        }

        if mode == .launcher {
            let appIndex = selectedIndex - displayedResults.count
            guard displayedAppResults.indices.contains(appIndex) else { return }
            let targetApp = displayedAppResults[appIndex].app
            dismiss(reason: .confirmed)
            installedAppService?.launchApplication(targetApp)
        }
    }

    /// 切り替えを実行せずにパネルを閉じる（Esc や外部フォーカス喪失時）
    /// - Parameter reason: パネル終了の理由（デフォルトは明示的キャンセル）
    public func cancel(reason: SwitcherDismissReason = .cancelled) {
        guard mode != .inactive else { return }
        // クローズ処理中の自動 Space 移動に伴う一時的な非アクティブ化ではパネルを閉じない
        if reason == .resignedActive && isClosingWindow {
            return
        }
        dismiss(reason: reason)
    }

    /// 通常スイッチャーのトリガーキー押下を処理する
    /// - Parameter isShiftPressed: Shift キーが併用されているか
    private func handleTriggerPressed(isShiftPressed: Bool) {
        switch mode {
        case .inactive:
            present(targetMode: .normal)
        case .normal, .launcher:
            // 通常モードおよびランチャーモード表示中は、現在の表示リスト内で選択インデックスを移動する
            moveSelection(isShiftPressed ? .up : .down)
        }
    }

    /// ランチャーモードのショートカット押下（起動またはトグル終了）を処理する
    private func handleLauncherTriggerPressed() {
        switch mode {
        case .normal:
            // 通常モード表示中はランチャーショートカットを無視する
            return
        case .launcher:
            // ランチャー再押下で切り替えを行わずトグル終了する
            cancel(reason: .cancelled)
        case .inactive:
            present(targetMode: .launcher)
        }
    }

    /// 権限確認とウィンドウ一覧取得を行い、指定されたモードでパネルを開く
    /// - Parameter targetMode: 起動先モード（.normal または .launcher）
    private func present(targetMode: SwitcherMode) {
        guard permissionService.currentStatus() == .granted else {
            onPermissionDenied?()
            return
        }

        let rawCandidates = windowService.fetchRawWindowCandidates()
        let filtered = WindowFilter.filterAndMap(rawCandidates)
        let sorted = WindowSorter.sortByMRU(filtered)

        guard let initial = SwitcherSelection.initialIndex(count: sorted.count) else {
            // 有効なウィンドウが 0 件の場合はパネルを表示しない
            return
        }

        allEntries = sorted
        searchQuery = ""
        displayedResults = sorted.map { WindowSearchResult(entry: $0) }
        displayedAppResults = []
        selectedIndex = initial
        presentationGeneration += 1
        mode = targetMode
        hotKeyMonitor.activeMode = targetMode == .launcher ? .launcher : .normal

        if targetMode == .launcher {
            // 新規インストール済みアプリを反映するためバックグラウンドでキャッシュを最新化する
            scheduleInstalledAppsRefresh()
        }

        onPresentationChanged?(true)
        onModePresentationChanged?(targetMode, nil)
    }

    /// パネル表示状態をリセットして閉じる
    /// - Parameter reason: パネル終了の理由
    private func dismiss(reason: SwitcherDismissReason) {
        presentationGeneration += 1
        installedAppsRefreshTask?.cancel()
        installedAppsRefreshTask = nil
        mode = .inactive
        hotKeyMonitor.activeMode = .inactive
        allEntries = []
        searchQuery = ""
        displayedResults = []
        displayedAppResults = []
        selectedIndex = 0
        onPresentationChanged?(false)
        onModePresentationChanged?(.inactive, reason)
    }

    /// 検索クエリを用いてウィンドウ検索結果とアプリ起動候補（表示中ウィンドウと重複するアプリを除外）を更新する
    /// - Parameter query: 適用する検索クエリ文字列
    private func updateLauncherSearchResults(for query: String) {
        displayedResults = WindowSearchEngine.search(query: query, in: allEntries)
        if let installedAppService {
            displayedAppResults = AppSearchEngine.search(
                query: query,
                in: installedAppService.cachedInstalledApps(),
                excludingWindowEntries: displayedResults.map(\.entry)
            )
        } else {
            displayedAppResults = []
        }
    }

    /// バックグラウンドでアプリ一覧を更新し、ランチャー表示中ならアプリ起動候補を即時再評価する
    private func scheduleInstalledAppsRefresh() {
        guard let installedAppService else { return }
        installedAppsRefreshTask?.cancel()
        let capturedGeneration = presentationGeneration
        let capturedMode = mode

        installedAppsRefreshTask = Task { @MainActor [weak self] in
            let latestApps = await installedAppService.refreshInstalledApps()
            guard let self,
                  !Task.isCancelled,
                  self.mode == .launcher,
                  capturedMode == .launcher,
                  self.presentationGeneration == capturedGeneration else {
                return
            }

            let nextAppResults = AppSearchEngine.search(
                query: self.searchQuery,
                in: latestApps,
                excludingWindowEntries: self.displayedResults.map(\.entry)
            )
            guard nextAppResults != self.displayedAppResults else { return }
            self.displayedAppResults = nextAppResults
            self.selectedIndex = SwitcherSelection.indexAfterRemoval(
                current: self.selectedIndex,
                remainingCount: self.activeResultCount
            )
            self.onSearchResultsUpdated?()
        }
    }
}
