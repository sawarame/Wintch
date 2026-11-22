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

    /// 通常スイッチャーの現在の表示形式（リスト型／アイコン型／キャプチャ表示型）
    public private(set) var normalDisplayStyle: SwitcherDisplayStyle

    /// 検索ランチャーの現在の表示形式（リスト型／キャプチャ表示型）
    public private(set) var launcherDisplayStyle: LauncherDisplayStyle

    /// 通常スイッチャーまたは検索ランチャーのいずれかでキャプチャ表示型が選択されているか
    public var usesCaptureDisplayStyle: Bool {
        normalDisplayStyle == .capture || launcherDisplayStyle == .capture
    }

    /// 現在の表示モードでキャプチャ表示が有効かどうか
    public var isCaptureActiveForCurrentMode: Bool {
        switch mode {
        case .normal:
            normalDisplayStyle == .capture
        case .launcher:
            launcherDisplayStyle == .capture
        case .inactive:
            false
        }
    }

    /// キャプチャ表示型で使用するウィンドウごとのサムネイル画像（cgWindowID キー、メモリ限定）
    public private(set) var capturedThumbnails: [UInt32: NSImage] = [:]

    /// キャプチャ表示型における画面収録権限の許可状態（未許可時はバナー案内とプレースホルダー表示へフォールバック）
    public private(set) var isScreenRecordingGranted: Bool = true

    /// アイコン型・キャプチャ表示型グリッドで現在適用中の 1 行あたり列数（上下矢印の行間移動計算に使用）
    public private(set) var gridColumnCount: Int = 1

    /// アクティブディスプレイの利用可能サイズ（グリッド列数および最大高さ算出用）
    public private(set) var availableScreenSize: CGSize = CGSize(width: 1280, height: 800)

    /// 現在アプリ起動候補を表示中かどうか（ランチャーモードかつアプリ起動候補が 1 件以上ある場合）
    public var isShowingLaunchCandidates: Bool {
        mode == .launcher && !displayedAppResults.isEmpty
    }

    /// 現在の表示セッションで保持している有効な通常ウィンドウが 1 件以上存在するか
    public var hasOpenWindows: Bool {
        !allEntries.isEmpty
    }

    /// ランチャー表示中に候補が 0 件の場合の空状態種別（非表示時・通常モード・候補あり時は nil）
    public var emptyState: LauncherEmptyState? {
        guard mode == .launcher else { return nil }
        return LauncherEmptyState.resolve(
            hasOpenWindows: hasOpenWindows,
            searchQuery: searchQuery,
            displayedWindowCount: displayedResults.count,
            displayedAppCount: displayedAppResults.count
        )
    }

    /// アプリ起動候補セクションに表示する見出し文言
    public var launchSectionHeaderTitle: String {
        if hasOpenWindows && displayedResults.isEmpty {
            return "一致するウィンドウがないため、アプリを起動"
        }
        return "アプリを起動"
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

    /// 現在の表示セッションで自アプリの一時アクティブ化を行うべきかどうか
    public private(set) var shouldActivateAppForCurrentSession: Bool = false

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
    /// 画面収録権限確認・遷移サービス（キャプチャ表示型選択時のみ使用）
    private let screenRecordingPermissionService: (any ScreenRecordingPermissionServicing)?
    /// ウィンドウサムネイルキャプチャサービス（キャプチャ表示型選択時のみ使用）
    private let windowCaptureService: (any WindowCaptureServicing)?
    /// インストール済みアプリ一覧のバックグラウンド更新タスク
    private var installedAppsRefreshTask: Task<Void, Never>?
    /// ウィンドウサムネイルのバックグラウンド取得タスク
    private var captureRefreshTask: Task<Void, Never>?

    /// スイッチャー ViewModel を初期化する
    /// - Parameters:
    ///   - windowService: ウィンドウ情報サービス
    ///   - hotKeyMonitor: ホットキー監視サービス
    ///   - permissionService: 権限確認サービス
    ///   - iconProvider: アイコン取得サービス
    ///   - installedAppService: インストール済みアプリ取得・起動サービス（省略時はアプリ起動候補なし）
    ///   - screenRecordingPermissionService: 画面収録権限サービス（省略時は未設定）
    ///   - windowCaptureService: ウィンドウキャプチャサービス（省略時は未設定）
    ///   - normalDisplayStyle: 通常スイッチャーの初期表示形式
    ///   - launcherDisplayStyle: 検索ランチャーの初期表示形式
    public init(
        windowService: any WindowServicing,
        hotKeyMonitor: any HotKeyMonitoring,
        permissionService: any AccessibilityPermissionServicing,
        iconProvider: any IconProviding,
        installedAppService: (any InstalledAppServicing)? = nil,
        screenRecordingPermissionService: (any ScreenRecordingPermissionServicing)? = nil,
        windowCaptureService: (any WindowCaptureServicing)? = nil,
        normalDisplayStyle: SwitcherDisplayStyle = .default,
        launcherDisplayStyle: LauncherDisplayStyle = .default
    ) {
        self.windowService = windowService
        self.hotKeyMonitor = hotKeyMonitor
        self.permissionService = permissionService
        self.iconProvider = iconProvider
        self.installedAppService = installedAppService
        self.screenRecordingPermissionService = screenRecordingPermissionService
        self.windowCaptureService = windowCaptureService
        self.normalDisplayStyle = normalDisplayStyle
        self.launcherDisplayStyle = launcherDisplayStyle
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

    /// 通常スイッチャーの表示形式を更新し、通常・ランチャーの双方が非キャプチャとなった場合は一時キャプチャキャッシュを即時破棄する
    /// - Parameter style: 新しい表示形式
    public func updateNormalDisplayStyle(_ style: SwitcherDisplayStyle) {
        normalDisplayStyle = style
        if !usesCaptureDisplayStyle {
            clearCaptureState(clearServiceCache: true)
        } else if style != .capture && mode == .normal {
            clearCaptureState(clearServiceCache: false)
        }
        if style.usesGridLayout && !displayedResults.isEmpty {
            gridColumnCount = SwitcherGridLayout.columnsCount(
                itemCount: displayedResults.count,
                availableScreenWidth: availableScreenSize.width,
                style: style
            )
        }
    }

    /// 検索ランチャーの表示形式を更新し、通常・ランチャーの双方が非キャプチャとなった場合は一時キャプチャキャッシュを即時破棄する
    /// - Parameter style: 新しい検索ランチャー表示形式
    public func updateLauncherDisplayStyle(_ style: LauncherDisplayStyle) {
        launcherDisplayStyle = style
        if !usesCaptureDisplayStyle {
            clearCaptureState(clearServiceCache: true)
        } else if style != .capture && mode == .launcher {
            clearCaptureState(clearServiceCache: false)
        }
    }

    /// 進行中のキャプチャ取得タスクと画面保持サムネイルを破棄する
    /// - Parameter clearServiceCache: キャプチャサービス側の共有メモリキャッシュも全破棄する場合は true
    private func clearCaptureState(clearServiceCache: Bool) {
        captureRefreshTask?.cancel()
        captureRefreshTask = nil
        capturedThumbnails.removeAll()
        isScreenRecordingGranted = true
        if clearServiceCache {
            windowCaptureService?.clearCache()
        }
    }

    /// グリッド表示（アイコン型・キャプチャ表示型）で現在適用されている列数を更新する
    /// - Parameter columns: 1 以上の列数
    public func updateGridColumnCount(_ columns: Int) {
        gridColumnCount = max(columns, 1)
    }

    /// 表示対象ディスプレイの利用可能サイズを更新し、必要ならグリッド列数も再計算する
    /// - Parameter size: 利用可能なディスプレイ領域サイズ
    public func updateAvailableScreenSize(_ size: CGSize) {
        availableScreenSize = size
        if !displayedResults.isEmpty {
            gridColumnCount = SwitcherGridLayout.columnsCount(
                itemCount: displayedResults.count,
                availableScreenWidth: size.width,
                style: normalDisplayStyle
            )
        }
    }

    /// 指定ウィンドウに対応するサムネイル画像（未取得時は nil）を返す
    /// - Parameter entry: 対象のウィンドウ項目
    /// - Returns: メモリ上に保持しているキャプチャサムネイル（未取得・対象外時は nil）
    public func thumbnail(for entry: WindowEntry) -> NSImage? {
        guard let cgWindowID = entry.cgWindowID else { return nil }
        return capturedThumbnails[cgWindowID]
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
            let removedIDs = allEntries.filter { $0.pid == target.pid || $0.id == target.id }.compactMap(\.cgWindowID)
            for windowID in removedIDs {
                capturedThumbnails.removeValue(forKey: windowID)
                windowCaptureService?.invalidateThumbnail(for: windowID)
            }
            allEntries.removeAll { $0.pid == target.pid || $0.id == target.id }
        } else {
            if let windowID = target.cgWindowID {
                capturedThumbnails.removeValue(forKey: windowID)
                windowCaptureService?.invalidateThumbnail(for: windowID)
            }
            allEntries.removeAll { $0.id == target.id }
        }

        if allEntries.isEmpty && targetMode == .normal {
            // 通常スイッチャーでは開いている通常ウィンドウが 0 件になった時点でパネルを自動的に閉じる
            dismiss(reason: .cancelled)
            return
        }

        switch targetMode {
        case .normal:
            displayedResults = allEntries.map { WindowSearchResult(entry: $0) }
            displayedAppResults = []
            if normalDisplayStyle.usesGridLayout {
                gridColumnCount = SwitcherGridLayout.columnsCount(
                    itemCount: displayedResults.count,
                    availableScreenWidth: availableScreenSize.width,
                    style: normalDisplayStyle
                )
            }
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

    /// 選択カーソルを指定方向へ移動する（リストが空の場合は何もしない）
    /// - Parameter direction: 移動方向
    public func moveSelection(_ direction: ArrowDirection) {
        let count = activeResultCount
        guard mode != .inactive, count > 0 else { return }

        if mode == .normal && normalDisplayStyle.usesGridLayout {
            selectedIndex = SwitcherGridLayout.moveIndex(
                current: selectedIndex,
                direction: direction,
                count: count,
                columns: gridColumnCount
            )
            return
        }

        switch direction {
        case .up, .left:
            selectedIndex = SwitcherSelection.previousIndex(current: selectedIndex, count: count)
        case .down, .right:
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
            // 通常モードおよびランチャーモード表示中は、現在の表示候補の MRU 順に沿って前後へ移動する
            moveSelection(isShiftPressed ? .left : .right)
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
        let screenBounds = windowService.currentDisplayBounds()
        let filtered = WindowFilter.filterAndMap(rawCandidates, screenBounds: screenBounds)
        let sorted = WindowSorter.sortByMRU(filtered)

        // 通常スイッチャーは有効ウィンドウ 0 件時は起動せず、検索ランチャーは 0 件でもアプリ起動用に開く
        let initial = SwitcherSelection.initialIndex(
            count: sorted.count,
            preferSecondItem: targetMode != .launcher
        )
        if initial == nil && targetMode != .launcher {
            return
        }

        allEntries = sorted
        searchQuery = ""
        displayedResults = sorted.map { WindowSearchResult(entry: $0) }
        displayedAppResults = []
        selectedIndex = initial ?? 0
        presentationGeneration += 1
        shouldActivateAppForCurrentSession = targetMode == .launcher || hotKeyMonitor.requiresAppActivationOnPresentation
        mode = targetMode
        hotKeyMonitor.activeMode = targetMode == .launcher ? .launcher : .normal

        let shouldUseCapture = (targetMode == .normal && normalDisplayStyle == .capture)
            || (targetMode == .launcher && launcherDisplayStyle == .capture)
        if targetMode == .normal && normalDisplayStyle.usesGridLayout {
            gridColumnCount = SwitcherGridLayout.columnsCount(
                itemCount: sorted.count,
                availableScreenWidth: availableScreenSize.width,
                style: normalDisplayStyle
            )
        }
        if shouldUseCapture {
            let granted: Bool
            if let screenRecordingPermissionService {
                granted = screenRecordingPermissionService.currentStatus() == .granted
            } else {
                granted = false
            }
            isScreenRecordingGranted = granted

            // キャプチャ表示型では起動直後にキャッシュ済みサムネイルのみ即時反映し、表示遅延を起こさない
            var initialThumbnails: [UInt32: NSImage] = [:]
            if granted, let windowCaptureService {
                // 閉じ済みウィンドウのキャッシュを先に破棄し、MRU 最古→最新の順で参照して
                // 直近アクティブウィンドウが LRU 追い出し優先位置へ押し出されないようにする
                let activeCGWindowIDs = Set(sorted.compactMap(\.cgWindowID))
                windowCaptureService.pruneCache(keeping: activeCGWindowIDs)
                for entry in sorted.reversed() {
                    if let windowID = entry.cgWindowID,
                       let cached = windowCaptureService.cachedThumbnail(for: windowID) {
                        initialThumbnails[windowID] = cached
                    }
                }
            }
            capturedThumbnails = initialThumbnails
        } else {
            capturedThumbnails = [:]
            isScreenRecordingGranted = true
        }

        if targetMode == .launcher {
            // 新規インストール済みアプリを反映するためバックグラウンドでキャッシュを最新化する
            scheduleInstalledAppsRefresh()
        }

        onPresentationChanged?(true)
        onModePresentationChanged?(targetMode, nil)

        if shouldUseCapture && isScreenRecordingGranted {
            scheduleWindowCaptureRefresh(for: sorted)
        }
    }

    /// パネル表示状態をリセットして閉じる
    /// - Parameter reason: パネル終了の理由
    private func dismiss(reason: SwitcherDismissReason) {
        presentationGeneration += 1
        installedAppsRefreshTask?.cancel()
        installedAppsRefreshTask = nil
        captureRefreshTask?.cancel()
        captureRefreshTask = nil
        shouldActivateAppForCurrentSession = false
        mode = .inactive
        hotKeyMonitor.activeMode = .inactive
        allEntries = []
        searchQuery = ""
        displayedResults = []
        displayedAppResults = []
        capturedThumbnails = [:]
        isScreenRecordingGranted = true
        selectedIndex = 0
        onPresentationChanged?(false)
        onModePresentationChanged?(.inactive, reason)
    }

    /// バックグラウンドでウィンドウの最新サムネイルを非同期取得し、同一セッションかつ表示中項目にのみ反映する
    /// - Parameter entries: キャプチャ対象のウィンドウ項目一覧
    private func scheduleWindowCaptureRefresh(for entries: [WindowEntry]) {
        captureRefreshTask?.cancel()
        guard let windowCaptureService else { return }

        let targetIDs = Self.prioritizedCaptureWindowIDs(
            from: entries,
            cachedThumbnails: capturedThumbnails
        )
        guard !targetIDs.isEmpty else { return }

        let capturedMode = mode
        let capturedGeneration = presentationGeneration
        let maxPixelSize = CGSize(width: 432, height: 270)

        captureRefreshTask = Task { @MainActor [weak self] in
            await windowCaptureService.captureThumbnails(
                for: targetIDs,
                maxPixelSize: maxPixelSize
            ) { [weak self] windowID, image in
                guard let self,
                      !Task.isCancelled,
                      self.mode == capturedMode,
                      self.isCaptureActiveForCurrentMode,
                      self.presentationGeneration == capturedGeneration,
                      self.allEntries.contains(where: { $0.cgWindowID == windowID }) else {
                    return
                }
                self.capturedThumbnails[windowID] = image
            }

            // 非同期キャプチャ中に権限拒否・失効を検知した場合は、現在表示中のパネルにも即座に未許可バナーへ切り替える
            guard let self,
                  !Task.isCancelled,
                  self.mode == capturedMode,
                  self.isCaptureActiveForCurrentMode,
                  self.presentationGeneration == capturedGeneration,
                  let screenRecordingPermissionService = self.screenRecordingPermissionService,
                  screenRecordingPermissionService.currentStatus() != .granted else {
                return
            }
            self.isScreenRecordingGranted = false
            self.capturedThumbnails.removeAll()
            if capturedMode == .launcher {
                self.onSearchResultsUpdated?()
            }
        }
    }

    /// 画面表示中かつ未キャッシュのウィンドウを最優先し、取得不要な別スペース/最小化キャッシュ済みを省いたキャプチャ対象 ID 順を返す
    /// - Parameters:
    ///   - entries: 表示対象ウィンドウ項目一覧（MRU 順）
    ///   - cachedThumbnails: 既にメモリ上に保持しているサムネイルマップ
    /// - Returns: キャプチャ優先度順に並べた CGWindow ID 配列
    static func prioritizedCaptureWindowIDs(
        from entries: [WindowEntry],
        cachedThumbnails: [UInt32: NSImage]
    ) -> [UInt32] {
        var uncachedOnScreen: [UInt32] = []
        var cachedOnScreen: [UInt32] = []
        var uncachedOffScreen: [UInt32] = []
        var uncachedMinimized: [UInt32] = []

        for entry in entries {
            guard let windowID = entry.cgWindowID else { continue }
            let isCached = cachedThumbnails[windowID] != nil
            let isOnScreen = (entry.isOnScreen != false) && !entry.isMinimized

            if isOnScreen {
                if isCached {
                    cachedOnScreen.append(windowID)
                } else {
                    uncachedOnScreen.append(windowID)
                }
            } else if !isCached {
                // 別スペース・最小化済みでも既にキャッシュがある場合は最終フレームを維持し、未取得分のみ後方優先で試行する
                if entry.isMinimized {
                    uncachedMinimized.append(windowID)
                } else {
                    uncachedOffScreen.append(windowID)
                }
            }
        }

        return uncachedOnScreen + cachedOnScreen + uncachedOffScreen + uncachedMinimized
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
