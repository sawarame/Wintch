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

    /// 画面に表示する検索・ソート済み結果一覧
    public private(set) var displayedResults: [WindowSearchResult] = []

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

    /// 起動時に取得した全有効ウィンドウ一覧（MRU ソート済み）
    private var allEntries: [WindowEntry] = []

    /// ウィンドウ取得・アクティブ化サービス
    private let windowService: any WindowServicing
    /// グローバルホットキー監視サービス
    private let hotKeyMonitor: any HotKeyMonitoring
    /// アクセシビリティ権限確認サービス
    private let permissionService: any AccessibilityPermissionServicing
    /// アプリアイコン取得サービス
    private let iconProvider: any IconProviding

    /// スイッチャー ViewModel を初期化する
    /// - Parameters:
    ///   - windowService: ウィンドウ情報サービス
    ///   - hotKeyMonitor: ホットキー監視サービス
    ///   - permissionService: 権限確認サービス
    ///   - iconProvider: アイコン取得サービス
    public init(
        windowService: any WindowServicing,
        hotKeyMonitor: any HotKeyMonitoring,
        permissionService: any AccessibilityPermissionServicing,
        iconProvider: any IconProviding
    ) {
        self.windowService = windowService
        self.hotKeyMonitor = hotKeyMonitor
        self.permissionService = permissionService
        self.iconProvider = iconProvider
    }

    /// 指定されたプロセス ID のアプリアイコンを取得する
    /// - Parameter pid: アプリケーションのプロセス ID
    /// - Returns: アプリアイコン画像（取得できない場合は nil）
    public func icon(for pid: Int32) -> NSImage? {
        iconProvider.icon(for: pid)
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
        }
    }

    /// ランチャーモードの検索文字列を更新し、ファジー検索結果と選択位置を再計算する
    /// - Parameter query: 新しい検索文字列
    public func updateSearchQuery(_ query: String) {
        guard mode == .launcher, searchQuery != query else { return }
        searchQuery = query
        displayedResults = WindowSearchEngine.search(query: query, in: allEntries)
        // 検索入力が変化したら先頭候補へ選択カーソルを戻す
        selectedIndex = 0
        onSearchResultsUpdated?()
    }

    /// 選択カーソルを上下に移動する（リストが空の場合は何もしない）
    /// - Parameter direction: 移動方向
    public func moveSelection(_ direction: ArrowDirection) {
        guard mode != .inactive, !displayedResults.isEmpty else { return }
        switch direction {
        case .up:
            selectedIndex = SwitcherSelection.previousIndex(current: selectedIndex, count: displayedResults.count)
        case .down:
            selectedIndex = SwitcherSelection.nextIndex(current: selectedIndex, count: displayedResults.count)
        }
    }

    /// 指定インデックスの項目をクリック等で直接選択して即座にアクティブ化する
    /// - Parameter index: 選択された項目のインデックス
    public func selectAndActivate(at index: Int) {
        guard mode != .inactive, displayedResults.indices.contains(index) else { return }
        selectedIndex = index
        confirmSelection()
    }

    /// 現在選択中のウィンドウで確定し、パネルを閉じてアクティブ化する
    public func confirmSelection() {
        guard mode != .inactive else { return }
        // ランチャーで一致 0 件のときに Enter が押されても誤操作せず開いたまま維持する
        guard displayedResults.indices.contains(selectedIndex) else { return }

        let target = displayedResults[selectedIndex].entry
        dismiss(reason: .confirmed)
        windowService.activateWindow(target)
    }

    /// 切り替えを実行せずにパネルを閉じる（Esc や外部フォーカス喪失時）
    /// - Parameter reason: パネル終了の理由（デフォルトは明示的キャンセル）
    public func cancel(reason: SwitcherDismissReason = .cancelled) {
        guard mode != .inactive else { return }
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
        selectedIndex = initial
        mode = targetMode
        hotKeyMonitor.activeMode = targetMode == .launcher ? .launcher : .normal

        onPresentationChanged?(true)
        onModePresentationChanged?(targetMode, nil)
    }

    /// パネル表示状態をリセットして閉じる
    /// - Parameter reason: パネル終了の理由
    private func dismiss(reason: SwitcherDismissReason) {
        mode = .inactive
        hotKeyMonitor.activeMode = .inactive
        allEntries = []
        searchQuery = ""
        displayedResults = []
        selectedIndex = 0
        onPresentationChanged?(false)
        onModePresentationChanged?(.inactive, reason)
    }
}
