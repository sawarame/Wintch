import AppKit
import Observation

/// スイッチャーパネルの表示状態・選択カーソル・確定/キャンセル操作を管理する ViewModel
@MainActor
@Observable
public final class SwitcherViewModel {
    /// スイッチャーパネルが表示中かどうか
    public private(set) var isPresented: Bool = false

    /// 表示対象のウィンドウ項目一覧（MRU ソート済み）
    public private(set) var entries: [WindowEntry] = []

    /// 現在ハイライト選択中のインデックス
    public private(set) var selectedIndex: Int = 0

    /// パネル表示状態が変化した際に呼ばれる通知ハンドラ
    public var onPresentationChanged: ((Bool) -> Void)?

    /// 権限未許可の状態で起動操作が行われた際に呼ばれる通知ハンドラ
    public var onPermissionDenied: (() -> Void)?

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
        case .modifierReleased:
            confirmSelection()
        case .escapePressed:
            cancel()
        case let .arrowPressed(direction):
            handleArrowPressed(direction)
        }
    }

    /// 指定インデックスの項目をクリック等で直接選択して即座にアクティブ化する
    /// - Parameter index: 選択された項目のインデックス
    public func selectAndActivate(at index: Int) {
        guard isPresented, entries.indices.contains(index) else { return }
        selectedIndex = index
        confirmSelection()
    }

    /// 切り替えを実行せずにパネルを閉じる
    public func cancel() {
        guard isPresented else { return }
        dismiss()
    }

    /// トリガーキー押下時の起動または選択移動を処理する
    /// - Parameter isShiftPressed: Shift キーが併用されているか
    private func handleTriggerPressed(isShiftPressed: Bool) {
        if !isPresented {
            // 権限未許可の場合は起動をブロックし誘導画面表示を通知する
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

            entries = sorted
            selectedIndex = initial
            isPresented = true
            hotKeyMonitor.isSwitcherActive = true
            onPresentationChanged?(true)
            return
        }

        // すでに表示中の場合は選択インデックスを移動する
        if isShiftPressed {
            selectedIndex = SwitcherSelection.previousIndex(current: selectedIndex, count: entries.count)
        } else {
            selectedIndex = SwitcherSelection.nextIndex(current: selectedIndex, count: entries.count)
        }
    }

    /// 矢印キーによる上下移動を処理する
    /// - Parameter direction: 移動方向
    private func handleArrowPressed(_ direction: ArrowDirection) {
        guard isPresented, !entries.isEmpty else { return }
        switch direction {
        case .up:
            selectedIndex = SwitcherSelection.previousIndex(current: selectedIndex, count: entries.count)
        case .down:
            selectedIndex = SwitcherSelection.nextIndex(current: selectedIndex, count: entries.count)
        }
    }

    /// 現在選択中のウィンドウで確定し、パネルを閉じてアクティブ化する
    private func confirmSelection() {
        guard isPresented else { return }
        let target: WindowEntry? = entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
        dismiss()
        if let target {
            windowService.activateWindow(target)
        }
    }

    /// パネル表示状態をリセットして閉じる
    private func dismiss() {
        isPresented = false
        hotKeyMonitor.isSwitcherActive = false
        entries = []
        selectedIndex = 0
        onPresentationChanged?(false)
    }
}
