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

    /// アプリグルーピング有効時に画面へ表示するアプリグループ一覧（グルーピング無効時は空配列）
    public private(set) var displayedGroups: [WindowAppGroup] = []

    /// ランチャーモードでウィンドウ一覧の下に表示するアプリ起動候補一覧（表示中のウィンドウと同アプリは除外）
    public private(set) var displayedAppResults: [AppSearchResult] = []

    /// 通常スイッチャーの現在の表示形式（リスト型／アイコン型／キャプチャ表示型）
    public private(set) var normalDisplayStyle: SwitcherDisplayStyle

    /// 検索ランチャーの現在の表示形式（リスト型／キャプチャ表示型）
    public private(set) var launcherDisplayStyle: LauncherDisplayStyle

    /// 通常スイッチャーでウィンドウをアプリごとにグルーピングするかどうか
    public private(set) var isNormalSwitcherGroupedByApp: Bool

    /// 検索ランチャーでウィンドウをアプリごとにグルーピングするかどうか
    public private(set) var isLauncherGroupedByApp: Bool

    /// パネル表示に使用する解決済み言語
    public private(set) var resolvedLanguage: ResolvedAppLanguage

    /// 現在の解決済み言語に対応するローカライズ文言テーブル
    public var strings: AppStrings {
        AppStrings(language: resolvedLanguage)
    }

    /// 現在の表示モードでアプリグルーピング表示が有効かどうか
    public var isGroupingActiveForCurrentMode: Bool {
        switch mode {
        case .normal:
            isNormalSwitcherGroupedByApp
        case .launcher:
            isLauncherGroupedByApp
        case .inactive:
            false
        }
    }

    /// 現在の表示モード・表示形式・グルーピング設定でグリッドレイアウト（複数列表示）を使用中かどうか
    /// アイコン型・キャプチャ表示型でもグルーピング ON 時は縦型リスト表示（1 列）となる
    public var usesGridLayoutForCurrentMode: Bool {
        mode == .normal && normalDisplayStyle.usesGridLayout && !isNormalSwitcherGroupedByApp
    }

    /// 現在の表示モード・表示形式・グルーピング設定に応じたパネルの垂直配置スタイル
    /// 通常スイッチャーのグルーピング OFF かつキャプチャ表示型のみ従来通り画面中央に配置し、それ以外は上寄せ配置とする
    public var panelVerticalPlacement: SwitcherPanelVerticalPlacement {
        SwitcherPanelLayout.verticalPlacement(
            mode: mode,
            normalDisplayStyle: normalDisplayStyle,
            isNormalSwitcherGroupedByApp: isNormalSwitcherGroupedByApp
        )
    }

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
            return strings.launcherLaunchAppFallbackSectionTitle
        }
        return strings.launcherLaunchAppSectionTitle
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

    /// 現在クローズ／終了処理の完了待ち（ローディング表示中）となっているウィンドウ項目 ID 集合
    public private(set) var closingWindowIDs: Set<String> = []

    /// 互換用：処理中のウィンドウが 1 件以上ある場合にその代表 ID を返す（処理中でない場合は nil）
    public var closingWindowID: String? {
        closingWindowIDs.first
    }

    /// 現在いずれかのウィンドウでクローズ／終了処理のローディング表示を実行中かどうか
    public var isClosingWindow: Bool {
        !closingWindowIDs.isEmpty
    }

    /// 表示セッションを識別する世代カウンタ（非同期クローズ復帰時のセッション跨ぎ防止用）
    private var presentationGeneration: Int = 0

    /// 別操作スペース一時遷移を伴い得る単一ウィンドウ終了要求の送出中カウンタ（この間のみ `.resignedActive` を抑止する）
    private var activeCloseRequestCount: Int = 0

    /// 単一ウィンドウ終了要求の送出中に `.resignedActive` による閉鎖を抑止したかどうか
    private var didSuppressResignActiveDuringCloseRequest: Bool = false

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
    /// サムネイルキャプチャ時の上限ピクセルサイズ
    private static let captureMaxPixelSize = CGSize(width: 432, height: 270)

    /// 1 ウィンドウ項目あたりのローディングスピナー表示上限時間（既定値は 5 秒）
    private let closeLoadingTimeout: Duration
    /// スピナー表示中のフォールバック生存確認ポーリング間隔（既定値は 80ms）
    private let closePollInterval: Duration
    /// スピナー上限到達後にパネル表示中の遅延完了を検知するための低頻度確認間隔（既定値は 500ms）
    private let postTimeoutPollInterval: Duration
    /// バックグラウンド事前キャプチャの連続イベント集約用デバウンス待機時間（既定値は 300ms）
    private let capturePrefetchDebounceDuration: Duration
    /// バックグラウンド更新で既キャッシュウィンドウを再取得する最小間隔（既定値は 5 秒）
    private let captureRefreshCooldown: TimeInterval
    /// 定期バックグラウンド更新ループの実行間隔（既定値は 15 秒）
    private let periodicCaptureRefreshInterval: Duration
    /// 鮮度判定に使用する現在時刻プロバイダ（テスト用に注入可能）
    private let nowProvider: @Sendable () -> Date
    /// インストール済みアプリ一覧のバックグラウンド更新タスク
    private var installedAppsRefreshTask: Task<Void, Never>?
    /// ウィンドウサムネイルのバックグラウンド取得タスク（パネル表示契機・閉鎖後もキャッシュ格納まで継続）
    private var captureRefreshTask: Task<Void, Never>?
    /// パネル由来キャプチャタスクの世代カウンタ（旧タスク完了時の状態上書き防止用）
    private var captureRefreshGeneration: Int = 0
    /// パネル由来キャプチャタスクが現在実行中かどうか
    private var isCaptureRefreshInFlight: Bool = false
    /// イベント駆動・起動時一括のバックグラウンド事前キャプチャタスク
    private var capturePrefetchTask: Task<Void, Never>?
    /// バックグラウンド事前キャプチャタスクの世代カウンタ
    private var capturePrefetchGeneration: Int = 0
    /// バックグラウンド事前キャプチャが現在 ScreenCaptureKit 取得処理を実行中かどうか
    private var isCapturePrefetchInFlight: Bool = false
    /// デバウンス待機中に保持している事前取得契機（全ウィンドウ一括取得の優先維持用）
    private var pendingPrefetchReasonInDebounce: WindowCapturePrefetchReason?
    /// パネル由来継続取得や他のバックグラウンド取得の完了後に繰り越し実行する事前取得契機
    private var pendingPrefetchReasonAfterInFlight: WindowCapturePrefetchReason?
    /// 15 秒間隔の定期バックグラウンド更新ループタスク
    private var periodicCaptureRefreshTask: Task<Void, Never>?
    /// 定期バックグラウンド更新ループの世代カウンタ
    private var periodicCaptureRefreshGeneration: Int = 0
    /// 定期バックグラウンド更新の 1 回分のキャプチャが現在実行中かどうか
    private var isPeriodicCaptureInFlight: Bool = false
    /// スリープ／ディスプレイオフ／セッション非アクティブ化により一時停止している要因集合
    private var activeSystemCapturePauseReasons: Set<SystemCapturePauseReason> = []
    /// 省電力・セッション状態によりバックグラウンド更新を一時停止中かどうか
    private var isSystemCapturePaused: Bool {
        !activeSystemCapturePauseReasons.isEmpty
    }
    /// ウィンドウ監視イベントに基づくバックグラウンド事前キャプチャおよび定期更新が有効化されているかどうか
    private var isBackgroundCapturePrefetchEnabled: Bool
    /// 終了要求送出済みウィンドウ ID ごとの非同期完了監視タスク
    private var closeMonitorTasksByWindowID: [String: Task<Void, Never>] = [:]

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
    ///   - isNormalSwitcherGroupedByApp: 通常スイッチャーの初期アプリグルーピング設定（既定値は true）
    ///   - isLauncherGroupedByApp: 検索ランチャーの初期アプリグルーピング設定（既定値は true）
    ///   - resolvedLanguage: パネル表示に使用する解決済み言語（既定値は日本語）
    ///   - closeLoadingTimeout: 1 項目あたりのローディングスピナー表示上限時間（既定値は 5 秒）
    ///   - closePollInterval: スピナー表示中のフォールバック生存確認間隔（既定値は 80ms）
    ///   - postTimeoutPollInterval: スピナー上限到達後の低頻度フォールバック確認間隔（既定値は 500ms）
    ///   - capturePrefetchDebounceDuration: バックグラウンド事前キャプチャのデバウンス待機時間（既定値は 300ms）
    ///   - captureRefreshCooldown: バックグラウンド更新で既キャッシュを再取得する最小間隔（既定値は 5 秒）
    ///   - periodicCaptureRefreshInterval: 定期バックグラウンド更新の間隔（既定値は 15 秒）
    ///   - nowProvider: 鮮度判定に用いる現在時刻プロバイダ（既定値は `Date.init`）
    ///   - isBackgroundCapturePrefetchEnabled: 初期化時点でバックグラウンド事前キャプチャを有効化するか（既定値は false）
    public init(
        windowService: any WindowServicing,
        hotKeyMonitor: any HotKeyMonitoring,
        permissionService: any AccessibilityPermissionServicing,
        iconProvider: any IconProviding,
        installedAppService: (any InstalledAppServicing)? = nil,
        screenRecordingPermissionService: (any ScreenRecordingPermissionServicing)? = nil,
        windowCaptureService: (any WindowCaptureServicing)? = nil,
        normalDisplayStyle: SwitcherDisplayStyle = .default,
        launcherDisplayStyle: LauncherDisplayStyle = .default,
        isNormalSwitcherGroupedByApp: Bool = true,
        isLauncherGroupedByApp: Bool = true,
        resolvedLanguage: ResolvedAppLanguage = .japanese,
        closeLoadingTimeout: Duration = .seconds(5),
        closePollInterval: Duration = .milliseconds(80),
        postTimeoutPollInterval: Duration = .milliseconds(500),
        capturePrefetchDebounceDuration: Duration = .milliseconds(300),
        captureRefreshCooldown: TimeInterval = WindowCaptureRefreshPolicy.defaultRefreshCooldown,
        periodicCaptureRefreshInterval: Duration = WindowCaptureRefreshPolicy.defaultPeriodicRefreshInterval,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        isBackgroundCapturePrefetchEnabled: Bool = false
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
        self.isNormalSwitcherGroupedByApp = isNormalSwitcherGroupedByApp
        self.isLauncherGroupedByApp = isLauncherGroupedByApp
        self.resolvedLanguage = resolvedLanguage
        self.closeLoadingTimeout = closeLoadingTimeout
        self.closePollInterval = closePollInterval
        self.postTimeoutPollInterval = postTimeoutPollInterval
        self.capturePrefetchDebounceDuration = capturePrefetchDebounceDuration
        self.captureRefreshCooldown = max(captureRefreshCooldown, 0)
        self.periodicCaptureRefreshInterval = periodicCaptureRefreshInterval
        self.nowProvider = nowProvider
        self.isBackgroundCapturePrefetchEnabled = isBackgroundCapturePrefetchEnabled

        // パネル表示中に OS 通知で検知したウィンドウ破棄・アプリ終了をリアルタイムに一覧へ反映する
        self.windowService.onWindowLifecycleEvent = { [weak self] event in
            self?.handleWindowLifecycleEvent(event)
        }
        // スペース切替・起動スキャン・フォーカス/タイトル変更等の完了時にバックグラウンド取得・更新を行う
        self.windowService.onCapturePrefetchNeeded = { [weak self] reason in
            self?.scheduleBackgroundCapturePrefetch(reason: reason)
        }
        // スリープ／ディスプレイオフ／セッション非アクティブ化と復帰に応じて定期バックグラウンド更新を一時停止・再開する
        self.windowService.onSystemCaptureAvailabilityEvent = { [weak self] event in
            self?.handleSystemCaptureAvailabilityEvent(event)
        }

        if isBackgroundCapturePrefetchEnabled && usesCaptureDisplayStyle {
            syncPeriodicCaptureRefreshLoop()
        }
    }

    /// パネル表示に使用する解決済み言語を即時更新する
    /// - Parameter language: 新しい解決済み言語
    public func updateLanguage(_ language: ResolvedAppLanguage) {
        guard resolvedLanguage != language else { return }
        resolvedLanguage = language
        if mode != .inactive {
            onSearchResultsUpdated?()
        }
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

    /// ウィンドウ監視イベントに応じたバックグラウンド事前キャプチャおよび定期更新を有効化する
    public func enableBackgroundCapturePrefetch() {
        isBackgroundCapturePrefetchEnabled = true
        activeSystemCapturePauseReasons.removeAll()
        syncPeriodicCaptureRefreshLoop()
    }

    /// 権限剥奪・監視停止・アプリ終了時に進行中のバックグラウンド事前取得・継続キャプチャ・定期更新を即座に停止しキャッシュを全破棄する
    public func stopBackgroundCaptureWork() {
        isBackgroundCapturePrefetchEnabled = false
        activeSystemCapturePauseReasons.removeAll()
        clearCaptureState(clearServiceCache: true)
    }

    /// 通常スイッチャーの表示形式を更新し、通常・ランチャーの双方が非キャプチャとなった場合は一時キャプチャキャッシュを即時破棄する
    /// - Parameter style: 新しい表示形式
    public func updateNormalDisplayStyle(_ style: SwitcherDisplayStyle) {
        let wasUsingCapture = usesCaptureDisplayStyle
        normalDisplayStyle = style
        if !usesCaptureDisplayStyle {
            clearCaptureState(clearServiceCache: true)
        } else {
            if style != .capture && mode == .normal {
                clearCaptureState(clearServiceCache: false)
            }
            if !wasUsingCapture && isBackgroundCapturePrefetchEnabled {
                syncPeriodicCaptureRefreshLoop()
                scheduleBackgroundCapturePrefetch(reason: .displayStyleEnabled)
            }
        }
        if style.usesGridLayout && !displayedResults.isEmpty {
            recalculateGridColumnCount()
        }
    }

    /// 検索ランチャーの表示形式を更新し、通常・ランチャーの双方が非キャプチャとなった場合は一時キャプチャキャッシュを即時破棄する
    /// - Parameter style: 新しい検索ランチャー表示形式
    public func updateLauncherDisplayStyle(_ style: LauncherDisplayStyle) {
        let wasUsingCapture = usesCaptureDisplayStyle
        launcherDisplayStyle = style
        if !usesCaptureDisplayStyle {
            clearCaptureState(clearServiceCache: true)
        } else {
            if style != .capture && mode == .launcher {
                clearCaptureState(clearServiceCache: false)
            }
            if !wasUsingCapture && isBackgroundCapturePrefetchEnabled {
                syncPeriodicCaptureRefreshLoop()
                scheduleBackgroundCapturePrefetch(reason: .displayStyleEnabled)
            }
        }
    }

    /// 通常スイッチャーのアプリグルーピング設定を更新し、通常モード表示中であれば表示順とグループ構造を即時再構築する
    /// - Parameter enabled: アプリごとにグルーピングする場合は true
    public func updateNormalSwitcherGrouping(_ enabled: Bool) {
        guard isNormalSwitcherGroupedByApp != enabled else { return }
        isNormalSwitcherGroupedByApp = enabled
        guard mode == .normal else { return }

        let selectedWindowID = displayedResults.indices.contains(selectedIndex)
            ? displayedResults[selectedIndex].entry.id
            : nil
        rebuildNormalDisplayedResults()
        if let selectedWindowID,
           let nextIndex = displayedResults.firstIndex(where: { $0.entry.id == selectedWindowID }) {
            selectedIndex = nextIndex
        } else {
            selectedIndex = SwitcherSelection.indexAfterRemoval(
                current: selectedIndex,
                remainingCount: activeResultCount
            )
        }
        if normalDisplayStyle.usesGridLayout {
            recalculateGridColumnCount()
        }
        onSearchResultsUpdated?()
    }

    /// 検索ランチャーのアプリグルーピング設定を更新し、ランチャーモード表示中であれば表示順とグループ構造を即時再構築する
    /// - Parameter enabled: アプリごとにグルーピングする場合は true
    public func updateLauncherGrouping(_ enabled: Bool) {
        guard isLauncherGroupedByApp != enabled else { return }
        isLauncherGroupedByApp = enabled
        guard mode == .launcher else { return }

        let selectedWindowID = displayedResults.indices.contains(selectedIndex)
            ? displayedResults[selectedIndex].entry.id
            : nil
        let selectedAppID: String?
        if selectedWindowID == nil {
            let appIndex = selectedIndex - displayedResults.count
            selectedAppID = displayedAppResults.indices.contains(appIndex) ? displayedAppResults[appIndex].id : nil
        } else {
            selectedAppID = nil
        }

        updateLauncherSearchResults(for: searchQuery)
        if let selectedWindowID,
           let nextIndex = displayedResults.firstIndex(where: { $0.entry.id == selectedWindowID }) {
            selectedIndex = nextIndex
        } else if let selectedAppID,
                  let appIndex = displayedAppResults.firstIndex(where: { $0.id == selectedAppID }) {
            selectedIndex = displayedResults.count + appIndex
        } else {
            selectedIndex = SwitcherSelection.indexAfterRemoval(
                current: selectedIndex,
                remainingCount: activeResultCount
            )
        }
        onSearchResultsUpdated?()
    }

    /// 進行中のキャプチャ取得タスクと画面保持サムネイルを破棄する
    /// - Parameter clearServiceCache: キャプチャサービス側の共有メモリキャッシュも全破棄する場合は true
    private func clearCaptureState(clearServiceCache: Bool) {
        if clearServiceCache {
            cancelAllBackgroundCaptureTasks()
        } else {
            captureRefreshGeneration += 1
            captureRefreshTask?.cancel()
            captureRefreshTask = nil
            isCaptureRefreshInFlight = false
        }
        capturedThumbnails.removeAll()
        isScreenRecordingGranted = true
        if clearServiceCache {
            windowCaptureService?.clearCache()
        }
    }

    /// 進行中のパネル由来キャプチャ、バックグラウンド事前取得、および定期更新ループをすべてキャンセルし状態を初期化する
    private func cancelAllBackgroundCaptureTasks() {
        captureRefreshGeneration += 1
        captureRefreshTask?.cancel()
        captureRefreshTask = nil
        isCaptureRefreshInFlight = false

        cancelBackgroundCapturePrefetchTask()
        stopPeriodicCaptureRefreshLoop()
        pendingPrefetchReasonAfterInFlight = nil
    }

    /// 進行中またはデバウンス待機中のバックグラウンド事前取得タスクをキャンセルして初期化する
    private func cancelBackgroundCapturePrefetchTask() {
        capturePrefetchGeneration += 1
        capturePrefetchTask?.cancel()
        capturePrefetchTask = nil
        isCapturePrefetchInFlight = false
        pendingPrefetchReasonInDebounce = nil
    }

    /// 稼働中の定期バックグラウンド更新ループを即座に停止する
    private func stopPeriodicCaptureRefreshLoop() {
        periodicCaptureRefreshGeneration += 1
        periodicCaptureRefreshTask?.cancel()
        periodicCaptureRefreshTask = nil
        isPeriodicCaptureInFlight = false
    }

    /// 画面収録権限の実行時拒否・失効を検知した際、進行中の全バックグラウンド取得および定期更新ループを即座に停止しキャッシュを全破棄する
    private func handleRuntimeScreenRecordingRevoked() {
        cancelAllBackgroundCaptureTasks()
        windowCaptureService?.clearCache()
    }

    /// OS のスリープ／ディスプレイオフ／セッション非アクティブ化と復帰に応じてバックグラウンド更新を一時停止・再開する
    /// - Parameter event: 受信したシステム状態変化イベント
    public func handleSystemCaptureAvailabilityEvent(_ event: SystemCaptureAvailabilityEvent) {
        switch event {
        case let .paused(reason):
            activeSystemCapturePauseReasons.insert(reason)
            cancelBackgroundCapturePrefetchTask()
            stopPeriodicCaptureRefreshLoop()
            pendingPrefetchReasonAfterInFlight = nil
        case let .resumed(reason):
            activeSystemCapturePauseReasons.remove(reason)
            if !isSystemCapturePaused {
                syncPeriodicCaptureRefreshLoop()
            }
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
            recalculateGridColumnCount()
        }
    }

    /// 現在の表示形式・グルーピング設定・画面幅に応じてグリッド列数を再算出する
    private func recalculateGridColumnCount() {
        // グルーピング ON 時はアイコン型・キャプチャ表示型も縦型リスト表示（1 列）となる
        if isNormalSwitcherGroupedByApp || !normalDisplayStyle.usesGridLayout {
            gridColumnCount = 1
        } else {
            gridColumnCount = SwitcherGridLayout.columnsCount(
                itemCount: displayedResults.count,
                availableScreenWidth: availableScreenSize.width,
                style: normalDisplayStyle
            )
        }
    }

    /// 通常スイッチャー用の表示候補一覧とアプリグループ一覧を現在の全有効ウィンドウから構築する
    private func rebuildNormalDisplayedResults() {
        let baseResults = allEntries.map { WindowSearchResult(entry: $0) }
        if isNormalSwitcherGroupedByApp {
            let groups = WindowAppGrouping.group(baseResults)
            displayedGroups = groups
            displayedResults = WindowAppGrouping.flatten(groups)
        } else {
            displayedGroups = []
            displayedResults = baseResults
        }
    }

    /// 指定ウィンドウに対応するサムネイル画像（未取得時は nil）を返す
    /// - Parameter entry: 対象のウィンドウ項目
    /// - Returns: メモリ上に保持しているキャプチャサムネイル（未取得・対象外時は nil）
    public func thumbnail(for entry: WindowEntry) -> NSImage? {
        guard let cgWindowID = entry.cgWindowID else { return nil }
        return capturedThumbnails[cgWindowID]
    }

    /// 指定されたウィンドウ項目が現在クローズ／終了処理中かどうかを返す
    /// - Parameter entryID: 判定対象のウィンドウ項目 ID
    /// - Returns: 対象ウィンドウを閉じている最中であれば true
    public func isClosingWindow(id entryID: String) -> Bool {
        closingWindowIDs.contains(entryID)
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

    /// 現在選択中の対象へ終了要求を送出し、完了待機中は項目ごとに非同期追跡する
    /// （同アプリに複数ウィンドウがあれば 1 枚のみ閉じ、最後の 1 枚ならアプリごと通常終了する）
    public func closeSelectedWindow() async {
        // 非表示中・選択候補なし（0 件やアプリ起動候補選択中）の場合は安全に無視する
        guard mode != .inactive,
              displayedResults.indices.contains(selectedIndex) else {
            return
        }

        let target = displayedResults[selectedIndex].entry
        // すでに終了処理中（スピナー表示中）の同一ウィンドウに対する重複 Q 押下は無視する
        guard !closingWindowIDs.contains(target.id) else {
            return
        }

        let targetMode = mode
        let capturedGeneration = presentationGeneration
        // UI へ処理中スピナーを即時反映し、前回タイムアウト後の監視タスクがあれば差し替える
        closingWindowIDs.insert(target.id)
        closeMonitorTasksByWindowID.removeValue(forKey: target.id)?.cancel()

        // ランチャー検索による絞り込みに左右されないよう、全候補一覧を基準に同アプリの残余ウィンドウ数を判定する
        let isSingleWindowForApp = allEntries.filter { $0.pid == target.pid }.count <= 1

        let requestResult: WindowCloseRequestResult
        if isSingleWindowForApp {
            requestResult = await windowService.requestTerminateApplication(pid: target.pid)
        } else {
            // 別スペース一時遷移を伴い得る単一ウィンドウ終了要求の送出中のみ .resignedActive 閉鎖を抑止する
            activeCloseRequestCount += 1
            defer {
                if presentationGeneration == capturedGeneration {
                    activeCloseRequestCount = max(activeCloseRequestCount - 1, 0)
                }
            }
            requestResult = await windowService.requestCloseWindow(target)
        }

        // 要求送出中に別セッションへ遷移・終了済みの場合は状態を変更せず抜ける
        guard mode == targetMode, presentationGeneration == capturedGeneration else { return }

        let shouldRestoreFocus = !isSingleWindowForApp
            && (requestResult.didSwitchSpace || didSuppressResignActiveDuringCloseRequest)
        if activeCloseRequestCount == 0 {
            didSuppressResignActiveDuringCloseRequest = false
        }

        switch requestResult {
        case .failed:
            closingWindowIDs.remove(target.id)
            if shouldRestoreFocus {
                onPanelFocusRestoreNeeded?(targetMode)
            }

        case .alreadyClosed:
            closingWindowIDs.remove(target.id)
            if isSingleWindowForApp {
                removeEntries(matchingPID: target.pid, fallbackWindowID: target.id)
            } else {
                removeEntry(matchingWindowID: target.id, cgWindowID: target.cgWindowID)
            }

        case .requested:
            if shouldRestoreFocus {
                onPanelFocusRestoreNeeded?(targetMode)
            }
            // 要求送出中に OS 通知で既に一覧から除外済みであればスピナーのみ解除して終了する
            guard allEntries.contains(where: { $0.id == target.id }) else {
                closingWindowIDs.remove(target.id)
                return
            }
            startCloseMonitoring(
                for: target,
                isSingleWindowForApp: isSingleWindowForApp,
                targetMode: targetMode,
                generation: capturedGeneration
            )
        }
    }

    /// WindowService から通知されたリアルタイムのウィンドウ破棄／アプリ終了イベントを処理する
    /// - Parameter event: 受信したライフサイクルイベント
    public func handleWindowLifecycleEvent(_ event: WindowLifecycleEvent) {
        guard mode != .inactive else { return }
        switch event {
        case let .windowClosed(windowID, cgWindowID, _):
            removeEntry(matchingWindowID: windowID, cgWindowID: cgWindowID)
        case let .applicationTerminated(pid):
            removeEntries(matchingPID: pid, fallbackWindowID: nil)
        }
    }

    /// 終了要求を送出した対象について、フォールバック生存確認およびスピナー表示上限タイムアウトを非同期で監視する
    /// - Parameters:
    ///   - target: 監視対象のウィンドウ項目
    ///   - isSingleWindowForApp: アプリ通常終了として PID 単位で監視する場合は true
    ///   - targetMode: 開始時の表示モード
    ///   - generation: 開始時の表示セッション世代
    private func startCloseMonitoring(
        for target: WindowEntry,
        isSingleWindowForApp: Bool,
        targetMode: SwitcherMode,
        generation: Int
    ) {
        closeMonitorTasksByWindowID[target.id]?.cancel()
        let loadingDeadline = ContinuousClock.now + closeLoadingTimeout
        let pollInterval = closePollInterval
        let postTimeoutInterval = postTimeoutPollInterval

        closeMonitorTasksByWindowID[target.id] = Task { @MainActor [weak self] in
            var didReachLoadingTimeout = false

            while !Task.isCancelled {
                let sleepDuration: Duration
                if didReachLoadingTimeout {
                    sleepDuration = postTimeoutInterval
                } else {
                    let now = ContinuousClock.now
                    if now >= loadingDeadline {
                        sleepDuration = .zero
                    } else {
                        let remaining = now.duration(to: loadingDeadline)
                        sleepDuration = remaining < pollInterval ? remaining : pollInterval
                    }
                }

                if sleepDuration > .zero {
                    try? await Task.sleep(for: sleepDuration)
                }

                guard let self,
                      !Task.isCancelled,
                      self.mode == targetMode,
                      self.presentationGeneration == generation else {
                    return
                }

                // OS 通知等により既に一覧から除外済みであれば監視を終了する
                guard self.allEntries.contains(where: { $0.id == target.id }) else {
                    self.closingWindowIDs.remove(target.id)
                    self.closeMonitorTasksByWindowID.removeValue(forKey: target.id)
                    return
                }

                let isAlive: Bool
                if isSingleWindowForApp {
                    isAlive = await self.windowService.isApplicationRunning(pid: target.pid)
                } else {
                    isAlive = await self.windowService.isWindowAlive(target)
                }

                guard !Task.isCancelled,
                      self.mode == targetMode,
                      self.presentationGeneration == generation else {
                    return
                }

                if !isAlive {
                    self.closeMonitorTasksByWindowID.removeValue(forKey: target.id)
                    self.closingWindowIDs.remove(target.id)
                    if isSingleWindowForApp {
                        self.removeEntries(matchingPID: target.pid, fallbackWindowID: target.id)
                    } else {
                        self.removeEntry(matchingWindowID: target.id, cgWindowID: target.cgWindowID)
                    }
                    return
                }

                // ローディング上限時間経過後はスピナーのみ解除し、パネルが開いている間は低頻度監視＋OS 通知を継続する
                if !didReachLoadingTimeout && ContinuousClock.now >= loadingDeadline {
                    didReachLoadingTimeout = true
                    self.closingWindowIDs.remove(target.id)
                }
            }
        }
    }

    /// 指定ウィンドウに一致する項目を一覧・キャッシュから除外して表示と選択カーソルを更新する
    /// - Parameters:
    ///   - windowID: 除外対象のウィンドウ項目 ID
    ///   - cgWindowID: 補助照合用の CoreGraphics ウィンドウ ID（不明時は nil）
    private func removeEntry(matchingWindowID windowID: String, cgWindowID: UInt32?) {
        applyEntriesRemoval { entry in
            if entry.id == windowID {
                return true
            }
            if let cgWindowID, entry.cgWindowID == cgWindowID {
                return true
            }
            return false
        }
    }

    /// 指定 PID（および必要ならフォールバック ID）に一致する全ウィンドウ項目を一覧・キャッシュから除外して表示を更新する
    /// - Parameters:
    ///   - pid: 終了したアプリケーションのプロセス ID
    ///   - fallbackWindowID: PID 一致に加えて確実に除外する対象ウィンドウ ID（任意）
    private func removeEntries(matchingPID pid: Int32, fallbackWindowID: String?) {
        applyEntriesRemoval { entry in
            entry.pid == pid || (fallbackWindowID != nil && entry.id == fallbackWindowID)
        }
    }

    /// 条件に一致するウィンドウ項目を一覧・キャッシュ・監視タスクから除外し、選択カーソル維持とリサイズ通知を行う
    /// - Parameter predicate: 除外対象とみなすウィンドウ項目の判定クロージャ
    private func applyEntriesRemoval(where predicate: (WindowEntry) -> Bool) {
        guard mode != .inactive else { return }
        let removedEntries = allEntries.filter(predicate)
        guard !removedEntries.isEmpty else { return }

        let currentMode = mode
        let previousIndex = selectedIndex
        let previousTarget = currentSelectionTarget()

        for entry in removedEntries {
            closingWindowIDs.remove(entry.id)
            closeMonitorTasksByWindowID.removeValue(forKey: entry.id)?.cancel()
            if let windowID = entry.cgWindowID {
                capturedThumbnails.removeValue(forKey: windowID)
                windowCaptureService?.invalidateThumbnail(for: windowID)
            }
        }

        let removedIDs = Set(removedEntries.map(\.id))
        allEntries.removeAll { removedIDs.contains($0.id) }

        if allEntries.isEmpty && currentMode == .normal {
            // 通常スイッチャーでは開いている通常ウィンドウが 0 件になった時点でパネルを自動的に閉じる
            dismiss(reason: .cancelled)
            return
        }

        switch currentMode {
        case .normal:
            rebuildNormalDisplayedResults()
            displayedAppResults = []
            if normalDisplayStyle.usesGridLayout {
                recalculateGridColumnCount()
            }
        case .launcher:
            // 検索キーワードを維持したまま最新の残余ウィンドウおよびアプリ起動候補を再評価する
            updateLauncherSearchResults(for: searchQuery)
        case .inactive:
            return
        }

        selectedIndex = SwitcherSelection.indexAfterExternalRemoval(
            previousIndex: previousIndex,
            previousTarget: previousTarget,
            remainingWindowIDs: displayedResults.map(\.entry.id),
            remainingAppIDs: currentMode == .launcher ? displayedAppResults.map(\.id) : []
        )
        onSearchResultsUpdated?()
        onPanelFocusRestoreNeeded?(currentMode)
    }

    /// 現在選択中のウィンドウ項目またはアプリ起動候補の識別子を返す
    /// - Returns: 選択中の対象識別子（候補 0 件等で範囲外の場合は nil）
    private func currentSelectionTarget() -> SwitcherSelection.SelectionTarget? {
        if displayedResults.indices.contains(selectedIndex) {
            return .window(id: displayedResults[selectedIndex].entry.id)
        }
        if mode == .launcher {
            let appIndex = selectedIndex - displayedResults.count
            if displayedAppResults.indices.contains(appIndex) {
                return .app(id: displayedAppResults[appIndex].id)
            }
        }
        return nil
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

        if usesGridLayoutForCurrentMode {
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
        // 別スペース一時遷移を伴い得る単一ウィンドウ終了要求の送出中のみ非アクティブ化による閉鎖を抑止する
        // （終了待ちモニタリング中は確認ダイアログ操作を妨げないようブロックしない）
        if reason == .resignedActive && activeCloseRequestCount > 0 {
            didSuppressResignActiveDuringCloseRequest = true
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
        if sorted.isEmpty && targetMode != .launcher {
            return
        }

        allEntries = sorted
        searchQuery = ""
        let baseResults = sorted.map { WindowSearchResult(entry: $0) }
        let shouldGroup = targetMode == .launcher ? isLauncherGroupedByApp : isNormalSwitcherGroupedByApp
        if shouldGroup {
            let groups = WindowAppGrouping.group(baseResults)
            displayedGroups = groups
            displayedResults = WindowAppGrouping.flatten(groups)
        } else {
            displayedGroups = []
            displayedResults = baseResults
        }
        displayedAppResults = []
        if targetMode == .launcher {
            selectedIndex = 0
        } else {
            selectedIndex = WindowAppGrouping.resolveInitialIndexForNormalSwitcher(
                mruSortedEntries: sorted,
                displayedResults: displayedResults,
                isGrouped: isNormalSwitcherGroupedByApp
            ) ?? 0
        }
        presentationGeneration += 1
        shouldActivateAppForCurrentSession = targetMode == .launcher || hotKeyMonitor.requiresAppActivationOnPresentation
        mode = targetMode
        hotKeyMonitor.activeMode = targetMode == .launcher ? .launcher : .normal

        let shouldUseCapture = (targetMode == .normal && normalDisplayStyle == .capture)
            || (targetMode == .launcher && launcherDisplayStyle == .capture)
        if targetMode == .normal && normalDisplayStyle.usesGridLayout {
            recalculateGridColumnCount()
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
            if isBackgroundCapturePrefetchEnabled {
                syncPeriodicCaptureRefreshLoop(knownScreenRecordingGranted: true)
            }
            scheduleWindowCaptureRefresh(for: sorted)
        } else if shouldUseCapture && !isScreenRecordingGranted {
            stopPeriodicCaptureRefreshLoop()
        }
    }

    /// パネル表示状態をリセットして閉じる
    /// - Parameter reason: パネル終了の理由
    private func dismiss(reason: SwitcherDismissReason) {
        presentationGeneration += 1
        closingWindowIDs.removeAll()
        activeCloseRequestCount = 0
        didSuppressResignActiveDuringCloseRequest = false
        for task in closeMonitorTasksByWindowID.values {
            task.cancel()
        }
        closeMonitorTasksByWindowID.removeAll()
        installedAppsRefreshTask?.cancel()
        installedAppsRefreshTask = nil
        // パネル閉鎖後も進行中のキャプチャはメモリキャッシュ格納完了までバックグラウンドで継続する
        // （閉鎖済みパネルの UI 状態への誤反映は presentationGeneration / mode ガードで防止する）
        shouldActivateAppForCurrentSession = false
        mode = .inactive
        hotKeyMonitor.activeMode = .inactive
        allEntries = []
        searchQuery = ""
        displayedResults = []
        displayedGroups = []
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
        // パネル表示中の優先度順キャプチャを最優先するため、進行中の事前取得および前回の継続タスクを差し替える
        cancelBackgroundCapturePrefetchTask()
        pendingPrefetchReasonAfterInFlight = nil
        // 定期更新のキャプチャが実行中であれば一時停止してパネル側取得へ譲り、完了後に安全再開する
        let shouldRestartPeriodicAfterRefresh = isPeriodicCaptureInFlight
        if shouldRestartPeriodicAfterRefresh {
            stopPeriodicCaptureRefreshLoop()
        }

        captureRefreshGeneration += 1
        captureRefreshTask?.cancel()
        captureRefreshTask = nil
        isCaptureRefreshInFlight = false
        guard let windowCaptureService else { return }

        let targetIDs = Self.prioritizedCaptureWindowIDs(
            from: entries,
            cachedThumbnails: capturedThumbnails
        )
        guard !targetIDs.isEmpty else {
            if shouldRestartPeriodicAfterRefresh {
                syncPeriodicCaptureRefreshLoop()
            }
            return
        }

        let capturedMode = mode
        let capturedGeneration = presentationGeneration
        let refreshGeneration = captureRefreshGeneration
        let maxPixelSize = Self.captureMaxPixelSize
        isCaptureRefreshInFlight = true

        captureRefreshTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.captureRefreshGeneration == refreshGeneration {
                    self.isCaptureRefreshInFlight = false
                    self.captureRefreshTask = nil
                    let needsFollowUp = shouldRestartPeriodicAfterRefresh || self.pendingPrefetchReasonAfterInFlight != nil
                    if needsFollowUp {
                        let isPermissionStillGranted = self.screenRecordingPermissionService?.currentStatus() == .granted
                        if shouldRestartPeriodicAfterRefresh && isPermissionStillGranted {
                            self.syncPeriodicCaptureRefreshLoop(knownScreenRecordingGranted: true)
                        }
                        if isPermissionStillGranted,
                           let pendingReason = self.pendingPrefetchReasonAfterInFlight {
                            self.pendingPrefetchReasonAfterInFlight = nil
                            if self.mode == .inactive {
                                self.scheduleBackgroundCapturePrefetch(reason: pendingReason)
                            }
                        } else if !isPermissionStillGranted {
                            self.pendingPrefetchReasonAfterInFlight = nil
                        }
                    }
                }
            }

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

            // 非同期キャプチャ中に権限拒否・失効を検知した場合は、定期更新ループを即座に停止し表示中のパネルも未許可バナーへ切り替える
            guard let self,
                  !Task.isCancelled,
                  let screenRecordingPermissionService = self.screenRecordingPermissionService,
                  screenRecordingPermissionService.currentStatus() != .granted else {
                return
            }
            self.handleRuntimeScreenRecordingRevoked()
            guard self.mode == capturedMode,
                  self.isCaptureActiveForCurrentMode,
                  self.presentationGeneration == capturedGeneration else {
                return
            }
            self.isScreenRecordingGranted = false
            self.capturedThumbnails.removeAll()
            if capturedMode == .launcher {
                self.onSearchResultsUpdated?()
            }
        }
    }

    /// 起動時・キャプチャ表示型有効化時・操作スペース切替・フォーカス／タイトル変更などの契機で、
    /// バックグラウンドのサムネイル取得・鮮度更新をスケジュールする
    /// - Parameter reason: 事前取得を要求する契機種別
    public func scheduleBackgroundCapturePrefetch(reason: WindowCapturePrefetchReason) {
        // オプトイン原則: 通常・ランチャー双方が非キャプチャ時は権限確認含め一切実行しない
        guard isBackgroundCapturePrefetchEnabled,
              usesCaptureDisplayStyle,
              !isSystemCapturePaused,
              windowCaptureService != nil else {
            return
        }
        // パネル表示中はパネル側の MRU 優先キャプチャを妨げない
        guard mode == .inactive else {
            return
        }
        // パネル閉鎖後の継続取得や他のバックグラウンド取得が進行中の場合は多重起動せず、完了後に繰り越し実行する
        if isCaptureRefreshInFlight || isCapturePrefetchInFlight || isPeriodicCaptureInFlight {
            pendingPrefetchReasonAfterInFlight = WindowCaptureRefreshPolicy.mergePendingPrefetchReason(
                existing: pendingPrefetchReasonAfterInFlight,
                incoming: reason
            )
            return
        }

        let mergedReason = WindowCaptureRefreshPolicy.mergePendingPrefetchReason(
            existing: pendingPrefetchReasonInDebounce,
            incoming: reason
        )
        let shouldRunImmediately = WindowCaptureRefreshPolicy.isImmediateBulkPrefetch(reason: mergedReason)

        capturePrefetchGeneration += 1
        let prefetchGeneration = capturePrefetchGeneration
        capturePrefetchTask?.cancel()
        pendingPrefetchReasonInDebounce = mergedReason
        let debounceDuration: Duration = shouldRunImmediately ? .zero : capturePrefetchDebounceDuration

        capturePrefetchTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.capturePrefetchGeneration == prefetchGeneration {
                    self.capturePrefetchTask = nil
                    self.pendingPrefetchReasonInDebounce = nil
                }
            }

            if debounceDuration > .zero {
                try? await Task.sleep(for: debounceDuration)
            }
            guard let self,
                  !Task.isCancelled,
                  self.capturePrefetchGeneration == prefetchGeneration else {
                return
            }
            self.pendingPrefetchReasonInDebounce = nil
            await self.performBackgroundCapturePrefetch(reason: mergedReason)
        }
    }

    /// 契機種別に応じた対象ウィンドウ（起動時一括取得またはイベント駆動の現在スペース鮮度更新）をバックグラウンドでキャプチャする
    /// - Parameter reason: 実行契機種別
    private func performBackgroundCapturePrefetch(reason: WindowCapturePrefetchReason) async {
        guard isBackgroundCapturePrefetchEnabled,
              usesCaptureDisplayStyle,
              !isSystemCapturePaused,
              let windowCaptureService else {
            return
        }
        // パネル表示中はパネル側の MRU 優先キャプチャを妨げない
        guard mode == .inactive else {
            return
        }
        // パネル閉鎖後の継続キャプチャや他バックグラウンド取得が進行中の場合は重複実行を避け、完了後に繰り越し実行する
        if isCaptureRefreshInFlight || isCapturePrefetchInFlight || isPeriodicCaptureInFlight {
            pendingPrefetchReasonAfterInFlight = WindowCaptureRefreshPolicy.mergePendingPrefetchReason(
                existing: pendingPrefetchReasonAfterInFlight,
                incoming: reason
            )
            return
        }
        // アクセシビリティ権限および画面収録権限が許可済みの場合のみ実行し、OS ダイアログを誘発しない
        guard permissionService.currentStatus() == .granted else {
            return
        }
        guard let screenRecordingPermissionService,
              screenRecordingPermissionService.currentStatus() == .granted else {
            stopPeriodicCaptureRefreshLoop()
            return
        }

        // 権限許可済みが確認できたため、未稼働であれば定期バックグラウンド更新ループを開始する
        syncPeriodicCaptureRefreshLoop(knownScreenRecordingGranted: true)

        let rawCandidates = windowService.fetchRawWindowCandidates()
        let screenBounds = windowService.currentDisplayBounds()
        let filtered = WindowFilter.filterAndMap(rawCandidates, screenBounds: screenBounds)
        let sorted = WindowSorter.sortByMRU(filtered)

        // 全操作スペースの生存ウィンドウ ID 集合で閉じ済み分のキャッシュのみ整理し、別スペースのキャッシュは保持する
        let activeCGWindowIDs = Set(sorted.compactMap(\.cgWindowID))
        windowCaptureService.pruneCache(keeping: activeCGWindowIDs)

        let now = nowProvider()
        let targetIDs: [UInt32]
        if WindowCaptureRefreshPolicy.isImmediateBulkPrefetch(reason: reason) {
            targetIDs = WindowCaptureRefreshPolicy.startupBulkPrefetchWindowIDs(
                from: sorted,
                isCached: { windowCaptureService.hasCachedThumbnail(for: $0) },
                lastCapturedAt: { windowCaptureService.lastCapturedAt(for: $0) },
                now: now,
                cooldown: captureRefreshCooldown
            )
        } else {
            targetIDs = WindowCaptureRefreshPolicy.eventPrefetchWindowIDs(
                from: sorted,
                isCached: { windowCaptureService.hasCachedThumbnail(for: $0) },
                lastCapturedAt: { windowCaptureService.lastCapturedAt(for: $0) },
                now: now,
                cooldown: captureRefreshCooldown
            )
        }
        guard !targetIDs.isEmpty else { return }

        isCapturePrefetchInFlight = true
        defer {
            isCapturePrefetchInFlight = false
            dispatchDeferredPrefetchIfNeeded()
        }

        await windowCaptureService.captureThumbnails(
            for: targetIDs,
            maxPixelSize: Self.captureMaxPixelSize
        ) { _, _ in
            // 事前取得では WindowCaptureService 内のメモリキャッシュ格納のみ行い、UI 状態は更新しない
        }

        // 実行中に画面収録権限の拒否・失効を検知した場合は進行中タスクおよび定期更新ループを即座に停止する
        if !Task.isCancelled, screenRecordingPermissionService.currentStatus() != .granted {
            handleRuntimeScreenRecordingRevoked()
        }
    }

    /// 現在のオプトイン設定・監視状態・省電力状態・権限に応じて定期バックグラウンド更新ループを開始または停止する
    /// - Parameter knownScreenRecordingGranted: 呼び出し元で画面収録権限許可済みを確認済みの場合は true（重複照会回避用）
    private func syncPeriodicCaptureRefreshLoop(knownScreenRecordingGranted: Bool? = nil) {
        // オプトイン原則: 双方非キャプチャまたは監視停止中・一時停止中は画面収録権限確認すら行わず停止する
        guard isBackgroundCapturePrefetchEnabled,
              usesCaptureDisplayStyle,
              !isSystemCapturePaused,
              windowCaptureService != nil else {
            stopPeriodicCaptureRefreshLoop()
            return
        }

        guard periodicCaptureRefreshTask == nil else {
            return
        }

        guard permissionService.currentStatus() == .granted else {
            stopPeriodicCaptureRefreshLoop()
            return
        }

        let isGranted: Bool
        if let knownScreenRecordingGranted {
            isGranted = knownScreenRecordingGranted
        } else {
            isGranted = screenRecordingPermissionService?.currentStatus() == .granted
        }
        guard isGranted else {
            stopPeriodicCaptureRefreshLoop()
            return
        }

        periodicCaptureRefreshGeneration += 1
        let loopGeneration = periodicCaptureRefreshGeneration
        let interval = periodicCaptureRefreshInterval

        periodicCaptureRefreshTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.periodicCaptureRefreshGeneration == loopGeneration {
                    self.periodicCaptureRefreshTask = nil
                    self.isPeriodicCaptureInFlight = false
                }
            }

            while !Task.isCancelled {
                if interval > .zero {
                    try? await Task.sleep(for: interval)
                } else {
                    await Task.yield()
                }
                guard let self,
                      !Task.isCancelled,
                      self.periodicCaptureRefreshGeneration == loopGeneration else {
                    return
                }
                let shouldContinue = await self.performPeriodicCaptureRefreshTick(loopGeneration: loopGeneration)
                if !shouldContinue {
                    return
                }
            }
        }
    }

    /// 定期バックグラウンド更新ループの 1 周期分の処理を実行する
    /// - Parameter loopGeneration: 実行中ループの世代カウンタ
    /// - Returns: 次周期へ継続すべき場合は true、権限失効や条件喪失で即停止すべき場合は false
    private func performPeriodicCaptureRefreshTick(loopGeneration: Int) async -> Bool {
        guard isBackgroundCapturePrefetchEnabled,
              usesCaptureDisplayStyle,
              !isSystemCapturePaused,
              let windowCaptureService else {
            return false
        }

        // パネル表示中または他のキャプチャタスク実行中は多重起動せず、この回をスキップして次周期へ回す
        if mode != .inactive || isCaptureRefreshInFlight || isCapturePrefetchInFlight || isPeriodicCaptureInFlight {
            return true
        }

        guard permissionService.currentStatus() == .granted else {
            return false
        }
        guard let screenRecordingPermissionService,
              screenRecordingPermissionService.currentStatus() == .granted else {
            handleRuntimeScreenRecordingRevoked()
            return false
        }

        let rawCandidates = windowService.fetchRawWindowCandidates()
        let screenBounds = windowService.currentDisplayBounds()
        let filtered = WindowFilter.filterAndMap(rawCandidates, screenBounds: screenBounds)
        let sorted = WindowSorter.sortByMRU(filtered)

        let activeCGWindowIDs = Set(sorted.compactMap(\.cgWindowID))
        windowCaptureService.pruneCache(keeping: activeCGWindowIDs)

        let targetIDs = WindowCaptureRefreshPolicy.periodicRefreshWindowIDs(
            from: sorted,
            isCached: { windowCaptureService.hasCachedThumbnail(for: $0) },
            lastCapturedAt: { windowCaptureService.lastCapturedAt(for: $0) },
            now: nowProvider(),
            cooldown: captureRefreshCooldown
        )
        guard !targetIDs.isEmpty else {
            return true
        }

        isPeriodicCaptureInFlight = true
        defer {
            if periodicCaptureRefreshGeneration == loopGeneration {
                isPeriodicCaptureInFlight = false
            }
            dispatchDeferredPrefetchIfNeeded()
        }

        await windowCaptureService.captureThumbnails(
            for: targetIDs,
            maxPixelSize: Self.captureMaxPixelSize
        ) { _, _ in
            // 定期更新では WindowCaptureService 内のメモリキャッシュ格納のみ行い、UI 状態は更新しない
        }

        guard !Task.isCancelled, periodicCaptureRefreshGeneration == loopGeneration else {
            return false
        }

        if screenRecordingPermissionService.currentStatus() != .granted {
            handleRuntimeScreenRecordingRevoked()
            return false
        }
        return true
    }

    /// 進行中タスクの完了時に繰り越されていたイベント事前取得契機があれば再スケジュールする
    private func dispatchDeferredPrefetchIfNeeded() {
        guard !isCaptureRefreshInFlight,
              !isCapturePrefetchInFlight,
              !isPeriodicCaptureInFlight,
              mode == .inactive,
              isBackgroundCapturePrefetchEnabled,
              usesCaptureDisplayStyle,
              !isSystemCapturePaused,
              let pendingReason = pendingPrefetchReasonAfterInFlight else {
            return
        }
        pendingPrefetchReasonAfterInFlight = nil
        scheduleBackgroundCapturePrefetch(reason: pendingReason)
    }

    /// 現在操作スペース上で画面表示中（isOnScreen == true かつ非最小化）のうち、
    /// メモリキャッシュ未保持の CGWindow ID のみを MRU 順で抽出する
    /// - Parameters:
    ///   - entries: 全操作スペースの有効ウィンドウ項目一覧（MRU 順）
    ///   - isCached: 指定 CGWindow ID がキャッシュ済みかを判定する副作用なしクロージャ
    /// - Returns: 事前取得対象となる未キャッシュ CGWindow ID 配列（重複除外済み）
    static func uncachedOnScreenPrefetchWindowIDs(
        from entries: [WindowEntry],
        isCached: (UInt32) -> Bool
    ) -> [UInt32] {
        var seen: Set<UInt32> = []
        var result: [UInt32] = []
        for entry in entries {
            guard let windowID = entry.cgWindowID,
                  entry.isOnScreen == true,
                  !entry.isMinimized,
                  !isCached(windowID),
                  seen.insert(windowID).inserted else {
                continue
            }
            result.append(windowID)
        }
        return result
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
        let rawResults = WindowSearchEngine.search(query: query, in: allEntries)
        if isLauncherGroupedByApp {
            let groups = WindowAppGrouping.group(rawResults)
            displayedGroups = groups
            displayedResults = WindowAppGrouping.flatten(groups)
        } else {
            displayedGroups = []
            displayedResults = rawResults
        }
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
