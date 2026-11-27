import AppKit
import ApplicationServices
import CoreGraphics

/// CGWindowListCopyWindowInfo と AXUIElement / AXObserver を組み合わせて
/// 画面収録権限および非公開 API なしで全操作スペースのウィンドウ管理を行うサービス
@MainActor
public final class WindowService: WindowServicing {
    /// AXUIElement 参照をスレッド境界を跨いで受け渡すための Sendable ラッパー
    private struct SendableAXElement: @unchecked Sendable {
        let value: AXUIElement
    }

    /// バックグラウンドキューで取得した 1 ウィンドウ分の AX スナップショット
    private struct ScannedAXWindowSnapshot: Sendable {
        let uniqueID: String
        let axElement: SendableAXElement
        let role: String?
        let title: String?
        let subrole: String?
        let bounds: CGRect?
        let isMinimized: Bool
    }

    /// バックグラウンド／オンデマンドで取得した Window メニュー項目と AXUIElement の組
    private struct ScannedWindowMenuItem: Sendable {
        let snapshot: WindowMenuItemSnapshot
        let axElement: SendableAXElement
    }

    /// PID ごとのキャッシュ済み Window メニュー状態
    private struct CachedWindowMenuState {
        var items: [ScannedWindowMenuItem]
        var fetchedAt: Date
    }

    /// ウィンドウアクティブ化時の実行戦略を表す値型
    struct ActivationPlan: Equatable, Sendable {
        /// 同期的にアプリ全体アクティブ化（`app.activate`）を即時実行するか
        let shouldActivateApplicationImmediately: Bool
        /// 同期的に対象 AXUIElement を前面化（`raiseAXWindow`）するか
        let shouldRaiseTargetAXImmediately: Bool
        /// 別スペース遷移やフォーカス定着を段階確認するフォローアップを実行するか
        let usesSteppedSpaceFollowUp: Bool
    }

    /// キャッシュされた AX ウィンドウ情報
    private struct CachedAXWindow {
        let id: String
        let pid: Int32
        let axElement: AXUIElement
        var cgWindowID: UInt32?
        var role: String?
        var title: String?
        var subrole: String?
        var bounds: CGRect?
        var isMinimized: Bool
        var isPresentInLatestAXScan: Bool
        var lastActivatedAt: Date?
    }

    /// 終了要求を送出したウィンドウの追跡情報（別スペース解決済み cg-* 要素の破棄通知・生存確認用）
    private struct TrackedCloseTarget {
        let entryID: String
        let pid: Int32
        let cgWindowID: UInt32?
        let axElement: AXUIElement
    }

    /// OS 通知等でウィンドウ破棄またはアプリ終了を検知した際に呼ばれるリアルタイム通知ハンドラ
    public var onWindowLifecycleEvent: ((WindowLifecycleEvent) -> Void)?

    /// 事前キャプチャ（未キャッシュサムネイルのバックグラウンド取得）が望ましいイベント完了時に呼ばれる通知ハンドラ
    public var onCapturePrefetchNeeded: ((WindowCapturePrefetchReason) -> Void)?

    /// 終了要求を送出済みのウィンドウ追跡マップ（WindowEntry.id キー）
    private var trackedCloseTargetsByEntryID: [String: TrackedCloseTarget] = [:]

    /// ウィンドウキャッシュ整理時の CGWindow 生存チェック方針
    enum CGCacheRetentionDecision: Equatable, Sendable {
        /// キャッシュをそのまま保持する
        case retain
        /// 閉鎖済みとしてキャッシュから即座に破棄する
        case evict
        /// CGWindowID の付け替わり等の可能性があるため、旧 ID を解除して再照合する
        case clearCGWindowIDAndRevalidate
    }

    /// メニューキャッシュ参照時の取得戦略
    enum MenuCacheLookupAction: Equatable, Sendable {
        /// 新鮮なキャッシュをそのまま利用する
        case useFresh
        /// 既存キャッシュを即時利用しつつバックグラウンドで最新化する（Stale-While-Revalidate）
        case useStaleAndRefreshInBackground
        /// キャッシュが存在しないため同期取得する
        case fetchSynchronously
    }

    /// PID ごとのキャッシュされたウィンドウ一覧
    private var cachedWindowsByPID: [Int32: [CachedAXWindow]] = [:]

    /// PID ごとのキャッシュされた「ウィンドウ」メニュー項目一覧
    private var cachedWindowMenuByPID: [Int32: CachedWindowMenuState] = [:]

    /// PID ごとの AXObserver インスタンス
    private var observersByPID: [Int32: AXObserver] = [:]

    /// PID ごとのデバウンス付きバックグラウンド更新タスク
    private var pendingRefreshTasksByPID: [Int32: Task<Void, Never>] = [:]

    /// PID ごとのバックグラウンドメニュー更新タスク（Stale-While-Revalidate 用）
    private var pendingMenuRefreshTasksByPID: [Int32: Task<Void, Never>] = [:]

    /// PID ごとの最新バックグラウンドスキャン世代カウンタ（古い結果による上書き防止用）
    private var scanGenerationByPID: [Int32: UInt64] = [:]

    /// PID ごとに後続リフレッシュへ引き継ぐ保留中の事前キャプチャ契機（連続 AX 通知による上書き消失防止用）
    private var pendingPrefetchReasonByPID: [Int32: WindowCapturePrefetchReason] = [:]

    /// メニュー補完（別スペース候補等）が必要と判定された PID 集合
    private var menuEnrichmentTargetPIDs: Set<Int32> = []

    /// スペース切り替え／初期スキャン用のバックグラウンド走査タスク
    private var pendingSpaceScanTask: Task<Void, Never>?

    /// 別スペース遷移後のウィンドウフォーカス確定用フォローアップタスク
    private var pendingActivationFollowUpTask: Task<Void, Never>?

    /// Workspace 通知監視トークン群
    private var workspaceObservers: [NSObjectProtocol] = []

    /// 監視中フラグ
    private var isObserving = false

    /// 起動直後の初期バックグラウンド全スキャンが完了したかどうか
    private var hasCompletedInitialBackgroundScan = false

    /// 操作スペース切り替え後のバックグラウンド全体再走査が完了するまでフルスクリーン置換を抑制するフラグ
    private var hasPendingSpaceChange = false

    /// バックグラウンド AX IPC 呼び出しを並列実行するためのコンカレントワーカーキュー
    private nonisolated let axWorkerQueue = DispatchQueue(
        label: "dev.wintch.WindowService.AXWorker",
        qos: .utility,
        attributes: .concurrent
    )

    /// 切り替え確定直後のフォーカス確認を他アプリのバックグラウンド走査に待たれず実行する高優先度キュー
    private nonisolated let axActivationQueue = DispatchQueue(
        label: "dev.wintch.WindowService.AXActivation",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// 全アプリ並列バックグラウンドスキャン時の最大同時実行数
    private static let maxConcurrentBackgroundScans = 6

    /// 応答しないアプリによる長時間ブロックを防ぐための AX IPC タイムアウト（秒）
    nonisolated static let axMessagingTimeoutSeconds: Float = 0.2

    /// 別スペース候補がある場合に使用する Window メニューキャッシュの有効期間（秒）
    nonisolated static let windowMenuCacheTTL: TimeInterval = 2.0

    /// 高頻度なタイトル変更通知（kAXTitleChangedNotification）のデバウンス間隔
    static let titleChangeDebounceDuration: Duration = .milliseconds(150)

    /// フォーカス／ウィンドウ作成通知のデバウンス間隔
    static let focusChangeDebounceDuration: Duration = .milliseconds(40)

    /// 操作スペース切り替え時の全体再走査デバウンス間隔
    static let spaceChangeDebounceDuration: Duration = .milliseconds(60)

    /// キャッシュ対象として許可する AX ロール
    private nonisolated static let allowedCachedRoles: Set<String> = ["AXWindow"]

    /// キャッシュ対象として許可する AX サブロール
    private nonisolated static let allowedCachedSubroles: Set<String> = [
        "AXStandardWindow",
        "AXDialog",
        "AXFloatingWindow",
        "AXSystemFloatingWindow"
    ]

    /// 照合および補完候補として許可する CoreGraphics ウィンドウレイヤー（通常・フローティング）
    private nonisolated static let allowedCGWindowLayers: Set<Int> = [
        Int(CGWindowLevelForKey(.normalWindow)),
        Int(CGWindowLevelForKey(.floatingWindow))
    ]

    /// WindowService を初期化する
    public init() {}

    /// 現在の全ディスプレイの矩形一覧（CoreGraphics 座標系）を返す
    /// - Returns: ディスプレイ矩形配列
    public func currentDisplayBounds() -> [WindowBounds] {
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return [] }
        return screens.map { screen in
            let frame = screen.frame
            let cgY = Double(primaryHeight - (frame.origin.y + frame.height))
            return WindowBounds(
                x: Double(frame.origin.x),
                y: cgY,
                width: Double(frame.width),
                height: Double(frame.height)
            )
        }
    }

    /// ウィンドウ監視（AXObserver およびワークスペース通知）を開始する
    public func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        // プロセス全体および個別 AXUIElement の IPC タイムアウトを短縮し、無応答アプリでの固着を防ぐ
        Self.applyMessagingTimeout(to: AXUIElementCreateSystemWide())

        // 起動済みの通常アプリにオブザーバを登録し、初期スキャンはバックグラウンドで実行する
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard pid != ProcessInfo.processInfo.processIdentifier else { continue }
            registerObserver(for: pid)
        }
        scheduleBackgroundScanAllRegularApps(debounce: nil, prefetchReasonOnCompletion: .initialScanCompleted)

        let center = NSWorkspace.shared.notificationCenter

        // 新規アプリ起動の監視
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.activationPolicy == .regular else { return }
                let pid = app.processIdentifier
                let isActive = app.isActive
                Task { @MainActor [weak self] in
                    guard let self, self.isObserving else { return }
                    self.registerObserver(for: pid)
                    self.scheduleBackgroundRefresh(
                        for: pid,
                        markFrontmostAsActive: isActive,
                        debounce: nil,
                        prefetchReasonOnCompletion: .applicationLaunched
                    )
                }
            }
        )

        // アプリ終了時のキャッシュ解放およびリアルタイム通知
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                Task { @MainActor [weak self] in
                    guard let self, self.isObserving else { return }
                    self.cleanupTerminatedPID(pid)
                    self.onWindowLifecycleEvent?(.applicationTerminated(pid: pid))
                }
            }
        )

        // アプリ切り替え時に最前面ウィンドウの MRU 時刻を更新（AX 問い合わせはバックグラウンド実行）
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.activationPolicy == .regular else { return }
                let pid = app.processIdentifier
                Task { @MainActor [weak self] in
                    self?.markFocusedWindowActivatedInBackground(for: pid)
                }
            }
        )

        // 操作スペース切り替え時に新スペースのウィンドウをデバウンス付きバックグラウンド走査で取り込む
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.hasPendingSpaceChange = true
                    self?.scheduleBackgroundScanAllRegularApps(
                        debounce: Self.spaceChangeDebounceDuration,
                        prefetchReasonOnCompletion: .activeSpaceChanged
                    )
                }
            }
        )
    }

    /// ウィンドウ監視を停止し、監視リソースとキャッシュを解放する
    public func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        hasCompletedInitialBackgroundScan = false
        hasPendingSpaceChange = false

        pendingSpaceScanTask?.cancel()
        pendingSpaceScanTask = nil
        pendingActivationFollowUpTask?.cancel()
        pendingActivationFollowUpTask = nil
        for task in pendingRefreshTasksByPID.values {
            task.cancel()
        }
        pendingRefreshTasksByPID.removeAll()
        for task in pendingMenuRefreshTasksByPID.values {
            task.cancel()
        }
        pendingMenuRefreshTasksByPID.removeAll()
        scanGenerationByPID.removeAll()
        pendingPrefetchReasonByPID.removeAll()
        menuEnrichmentTargetPIDs.removeAll()

        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers {
            center.removeObserver(token)
        }
        workspaceObservers.removeAll()

        for pid in Array(observersByPID.keys) {
            unregisterObserver(for: pid)
        }
        cachedWindowsByPID.removeAll()
        cachedWindowMenuByPID.removeAll()
        trackedCloseTargetsByEntryID.removeAll()
    }

    /// 現在の全操作スペース上のウィンドウ候補を収集して返す
    /// - Returns: フィルタリング前の生ウィンドウ候補一覧
    public func fetchRawWindowCandidates() -> [RawWindowCandidate] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSWorkspace.shared.runningApplications
        let appMap = Dictionary(
            uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, $0) }
        )

        // 非監視時または起動直後の初回スキャン未完了時のみ同期スキャンへフォールバックし、
        // 定常稼働時はバックグラウンド更新済みキャッシュを用いてメインスレッドの AX IPC 待ちを排除する
        let usesSyncFallback = Self.shouldPerformSyncScanOnFetch(
            isObserving: isObserving,
            hasCompletedInitialBackgroundScan: hasCompletedInitialBackgroundScan
        )
        if usesSyncFallback {
            scanAllRegularApps()
            if isObserving {
                hasCompletedInitialBackgroundScan = true
            }
        } else {
            // 通知漏れ等で監視未登録の新規通常アプリを検知した場合は非同期で監視・スキャンを予約する
            for app in runningApps where app.activationPolicy == .regular {
                let pid = app.processIdentifier
                guard pid != selfPID else { continue }
                if observersByPID[pid] == nil {
                    registerObserver(for: pid)
                    scheduleBackgroundRefresh(
                        for: pid,
                        markFrontmostAsActive: app.isActive,
                        debounce: nil
                    )
                }
            }
        }

        let cgWindows = fetchCGWindowInfos()

        // CGWindow を PID ごとにグルーピングし、システム重なり順 (zOrderIndex) を付与する
        var cgEntriesByPID: [Int32: [(zOrder: Int, info: CGWindowMeta)]] = [:]
        for (index, info) in cgWindows.enumerated() {
            cgEntriesByPID[info.pid, default: []].append((zOrder: index, info: info))
        }

        // 終了済みアプリおよび CGWindow 上から消滅した閉鎖済みウィンドウをキャッシュから整理する
        purgeTerminatedPIDs(activeAppPIDs: Set(appMap.keys))
        if usesSyncFallback {
            cleanupClosedWindows(cgEntriesByPID: cgEntriesByPID)
        } else {
            cleanupClosedWindowsUsingCGWindows(cgEntriesByPID: cgEntriesByPID)
        }

        var candidates: [RawWindowCandidate] = []
        var matchedCGWindowIDs = Set<UInt32>()

        // 1. キャッシュ済み AX ウィンドウを候補として構築し、対応する CGWindow メタデータを結合する
        for (pid, cachedList) in cachedWindowsByPID {
            guard let app = appMap[pid] else { continue }
            let isRegular = app.activationPolicy == .regular
            // アプリ名が取得できない場合は空文字とし、UI 描画時に現在の表示言語に応じた不明アプリ表記へフォールバックする
            let appName = app.localizedName ?? ""
            let profile = AppWindowProfileRegistry.profile(for: app.bundleIdentifier)
            let pidCGEntries = cgEntriesByPID[pid] ?? []
            var updatedList = cachedList

            // 閉鎖時に orderOut 等で CGWindow を残すアプリでは、画面外化した非最小化キャッシュの最新 AX 在籍を確認する
            if !usesSyncFallback,
               profile.requiresLiveVerificationWhenOffscreen,
               !app.isHidden,
               updatedList.contains(where: { cached in
                   guard cached.isPresentInLatestAXScan, !cached.isMinimized else { return false }
                   if let knownID = cached.cgWindowID,
                      let entry = pidCGEntries.first(where: { $0.info.windowID == knownID }) {
                       return !entry.info.isOnscreen
                   }
                   if let matched = findMatchingCGWindow(
                       for: cached,
                       applicationName: appName,
                       in: pidCGEntries,
                       excluding: matchedCGWindowIDs
                   ) {
                       return !matched.info.isOnscreen
                   }
                   return true
               }) {
                refreshAXWindows(for: pid, markFrontmostAsActive: app.isActive)
                updatedList = cachedWindowsByPID[pid] ?? []
            }

            var matchedCGByIndex: [Int: (zOrder: Int, info: CGWindowMeta)] = [:]

            // 現在スペース上でアクティブ捕捉された非最小化ウィンドウを優先して CGWindow と照合し、
            // 同一サイズの別スペース履歴ウィンドウによる on-screen CGWindow 奪取を防ぐ
            let activeIndices = updatedList.indices.filter {
                updatedList[$0].isPresentInLatestAXScan && !updatedList[$0].isMinimized
            }
            let remainingIndices = updatedList.indices.filter {
                !(updatedList[$0].isPresentInLatestAXScan && !updatedList[$0].isMinimized)
            }

            for index in activeIndices + remainingIndices {
                let cached = updatedList[index]
                let matchedCG = findMatchingCGWindow(
                    for: cached,
                    applicationName: appName,
                    in: pidCGEntries,
                    excluding: matchedCGWindowIDs
                )
                if let matchedCG {
                    matchedCGWindowIDs.insert(matchedCG.info.windowID)
                    updatedList[index].cgWindowID = matchedCG.info.windowID
                    matchedCGByIndex[index] = matchedCG
                }
            }

            // orderOut 閉鎖後のオフスクリーンキャッシュを判定するため、必要な場合のみ「ウィンドウ」メニューを参照する
            let needsOffscreenMenuVerification = profile.requiresLiveVerificationWhenOffscreen
                && !app.isHidden
                && updatedList.indices.contains { index in
                    let cached = updatedList[index]
                    guard !cached.isPresentInLatestAXScan, !cached.isMinimized else { return false }
                    if let matched = matchedCGByIndex[index] {
                        return !matched.info.isOnscreen
                    }
                    if let knownID = cached.cgWindowID,
                       let oldEntry = pidCGEntries.first(where: { $0.info.windowID == knownID }) {
                        return !oldEntry.info.isOnscreen
                    }
                    return true
                }
            let verificationMenuSnapshots: [WindowMenuItemSnapshot]
            if needsOffscreenMenuVerification {
                let now = Date()
                if let existingMenu = cachedWindowMenuByPID[pid],
                   Self.isMenuCacheFresh(fetchedAt: existingMenu.fetchedAt, now: now) {
                    verificationMenuSnapshots = existingMenu.items.map(\.snapshot)
                } else {
                    let freshMenuItems = Self.fetchWindowMenuItems(for: pid)
                    cachedWindowMenuByPID[pid] = CachedWindowMenuState(items: freshMenuItems, fetchedAt: now)
                    verificationMenuSnapshots = freshMenuItems.map(\.snapshot)
                }
            } else {
                verificationMenuSnapshots = []
            }

            var retainedList: [CachedAXWindow] = []
            retainedList.reserveCapacity(updatedList.count)

            for index in updatedList.indices {
                let cached = updatedList[index]
                let matchedCG = matchedCGByIndex[index]
                let isFloating = Self.isFloatingAXSubrole(cached.subrole)

                let resolvedCGID: UInt32?
                let resolvedCGIsOnscreen: Bool
                if let matchedCG {
                    resolvedCGID = matchedCG.info.windowID
                    resolvedCGIsOnscreen = matchedCG.info.isOnscreen
                } else if let oldID = cached.cgWindowID,
                          !matchedCGWindowIDs.contains(oldID),
                          let oldEntry = pidCGEntries.first(where: { entry in
                              entry.info.windowID == oldID
                                  && (isFloating || entry.info.layer == 0 || entry.info.isOnscreen)
                          }) {
                    matchedCGWindowIDs.insert(oldID)
                    resolvedCGID = oldID
                    resolvedCGIsOnscreen = oldEntry.info.isOnscreen
                } else {
                    resolvedCGID = nil
                    resolvedCGIsOnscreen = false
                }

                // 最新 AX スキャンに不在かつ WindowServer 上にも生存 CGWindow がない場合は閉鎖済みとみなし破棄する
                guard Self.shouldEmitCachedAXWindow(
                    isPresentInLatestAXScan: cached.isPresentInLatestAXScan,
                    resolvedCGWindowID: resolvedCGID
                ) else {
                    continue
                }

                // orderOut 等で CGWindow を残したまま閉じられたキャッシュ済み AX ウィンドウを破棄する
                guard Self.shouldRetainOffscreenCachedAXWindow(
                    requiresLiveVerificationWhenOffscreen: profile.requiresLiveVerificationWhenOffscreen,
                    isPresentInLatestAXScan: cached.isPresentInLatestAXScan,
                    isMinimized: cached.isMinimized,
                    isAppHidden: app.isHidden,
                    isCGOnScreen: resolvedCGIsOnscreen,
                    title: cached.title,
                    applicationName: appName,
                    menuItems: verificationMenuSnapshots
                ) else {
                    continue
                }

                retainedList.append(cached)

                // 座標が取得できない不可視・非ウィンドウ要素はダミーサイズで補完せず除外する
                guard let rect = cached.bounds ?? matchedCG?.info.bounds else { continue }

                candidates.append(
                    RawWindowCandidate(
                        id: cached.id,
                        cgWindowID: resolvedCGID,
                        pid: pid,
                        bundleIdentifier: app.bundleIdentifier,
                        applicationName: appName,
                        title: cached.title,
                        cgWindowName: matchedCG?.info.name,
                        layer: matchedCG?.info.layer ?? 0,
                        bounds: WindowBounds(
                            x: Double(rect.origin.x),
                            y: Double(rect.origin.y),
                            width: Double(rect.size.width),
                            height: Double(rect.size.height)
                        ),
                        alpha: matchedCG?.info.alpha ?? 1.0,
                        isRegularApplication: isRegular,
                        isSelf: pid == selfPID,
                        isMinimized: cached.isMinimized,
                        axRole: cached.role,
                        axSubrole: cached.subrole,
                        hasAXInfo: true,
                        isOnScreen: matchedCG?.info.isOnscreen ?? (resolvedCGID != nil ? resolvedCGIsOnscreen : nil),
                        lastActivatedAt: cached.lastActivatedAt,
                        zOrderIndex: matchedCG?.zOrder ?? Int.max
                    )
                )
            }

            if retainedList.isEmpty {
                cachedWindowsByPID.removeValue(forKey: pid)
            } else {
                cachedWindowsByPID[pid] = retainedList
            }
        }

        // 2. Wintch 起動前から別スペースに存在し AX 未キャッシュの CGWindow を補完追加する
        for (index, cgInfo) in cgWindows.enumerated() {
            guard !matchedCGWindowIDs.contains(cgInfo.windowID) else { continue }
            guard Self.allowedCGWindowLayers.contains(cgInfo.layer) else { continue }
            guard let app = appMap[cgInfo.pid],
                  app.activationPolicy == .regular else { continue }

            // 現在スペース上で表示中にもかかわらず AX キャッシュに一致しなかった場合は、次回に向けてバックグラウンド更新を予約する
            if !usesSyncFallback,
               cgInfo.pid != selfPID,
               cgInfo.isOnscreen,
               cgInfo.layer == 0,
               cgInfo.bounds.width >= 200,
               cgInfo.bounds.height >= 165,
               pendingRefreshTasksByPID[cgInfo.pid] == nil {
                scheduleBackgroundRefresh(
                    for: cgInfo.pid,
                    markFrontmostAsActive: app.isActive,
                    debounce: nil
                )
            }

            candidates.append(
                RawWindowCandidate(
                    id: "cg-\(cgInfo.windowID)",
                    cgWindowID: cgInfo.windowID,
                    pid: cgInfo.pid,
                    bundleIdentifier: app.bundleIdentifier,
                    applicationName: app.localizedName ?? "",
                    title: nil,
                    cgWindowName: cgInfo.name,
                    layer: cgInfo.layer,
                    bounds: WindowBounds(
                        x: Double(cgInfo.bounds.origin.x),
                        y: Double(cgInfo.bounds.origin.y),
                        width: Double(cgInfo.bounds.size.width),
                        height: Double(cgInfo.bounds.size.height)
                    ),
                    alpha: cgInfo.alpha,
                    isRegularApplication: true,
                    isSelf: cgInfo.pid == selfPID,
                    isMinimized: false,
                    axRole: nil,
                    axSubrole: nil,
                    hasAXInfo: false,
                    isOnScreen: cgInfo.isOnscreen,
                    lastActivatedAt: nil,
                    zOrderIndex: index
                )
            )
        }

        // 3. AX で捕捉できなかった別スペース等の cg-* 候補に対し、アプリの「ウィンドウ」メニューからタイトルを補完し余剰ゴーストを整理する
        return enrichCandidatesWithWindowMenu(candidates)
    }

    /// 指定されたウィンドウを最前面にアクティブ化する（必要なら操作スペース移動・最小化解除を行う）
    /// - Parameter entry: アクティブ化対象のウィンドウ項目
    public func activateWindow(_ entry: WindowEntry) {
        pendingActivationFollowUpTask?.cancel()
        pendingActivationFollowUpTask = nil

        let now = Date()
        let app = NSRunningApplication(processIdentifier: entry.pid)

        // キャッシュ上の AXUIElement と現在スペース在籍状況を確認し、MRU 時刻を更新する
        var targetAX: AXUIElement?
        var isPresentInLatestAXScan = false
        if var list = cachedWindowsByPID[entry.pid],
           let idx = list.firstIndex(where: { $0.id == entry.id }) {
            list[idx].lastActivatedAt = now
            targetAX = list[idx].axElement
            isPresentInLatestAXScan = list[idx].isPresentInLatestAXScan
            cachedWindowsByPID[entry.pid] = list
        }
        let isPresentInCurrentSpace = Self.isWindowInCurrentSpace(
            isPresentInLatestAXScan: isPresentInLatestAXScan,
            isOnScreen: entry.isOnScreen,
            isMinimized: entry.isMinimized
        )

        // AX 未取得（別スペースの cg-* 候補）または現在スペース不在時は「ウィンドウ」メニュー項目からの直接切り替えを実行する
        let needsMenuNavigation = (targetAX == nil) || !isPresentInCurrentSpace
        let menuNavigationSucceeded: Bool
        if needsMenuNavigation, !entry.windowTitle.isEmpty {
            menuNavigationSucceeded = performMenuNavigationWithRetry(
                pid: entry.pid,
                windowTitle: entry.windowTitle,
                applicationName: entry.applicationName,
                preferUnchecked: true
            )
        } else {
            menuNavigationSucceeded = false
        }

        let plan = Self.makeActivationPlan(
            hasTargetAX: targetAX != nil,
            isPresentInCurrentSpace: isPresentInCurrentSpace,
            menuNavigationSucceeded: menuNavigationSucceeded
        )

        if plan.shouldActivateApplicationImmediately {
            app?.activate(options: [])
        }
        if plan.shouldRaiseTargetAXImmediately, let targetAX {
            raiseAXWindow(targetAX, unminimize: entry.isMinimized)
        }

        guard plan.usesSteppedSpaceFollowUp else {
            return
        }

        // 別スペースへのアニメーション切り替え完了を段階的に確認しつつ、非アクティブ時のメニュー無視対策・フォーカス確定を行う
        let targetPID = entry.pid
        let targetTitle = entry.windowTitle
        let targetAppName = entry.applicationName
        let targetID = entry.id
        let targetCGWindowID = entry.cgWindowID
        let needsUnminimize = entry.isMinimized
        pendingActivationFollowUpTask = Task { @MainActor [weak self] in
            let stepDelaysMs: [UInt64] = [50, 110, 160, 180]
            var didActivateAndRaise = false

            for (stepIndex, delayMs) in stepDelaysMs.enumerated() {
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled, let self else { return }

                let snapshots = await self.fetchAXWindowSnapshotsInBackground(for: targetPID)
                guard !Task.isCancelled else { return }
                self.applyAXWindowSnapshots(snapshots, for: targetPID, markFrontmostAsActive: false)

                if let resolved = self.findCachedWindow(
                    pid: targetPID,
                    preferredID: targetID,
                    cgWindowID: targetCGWindowID,
                    title: targetTitle,
                    applicationName: targetAppName
                ),
                   resolved.isPresentInLatestAXScan {
                    if let runningApp = NSRunningApplication(processIdentifier: targetPID), !runningApp.isActive {
                        runningApp.activate(options: [])
                    }
                    self.raiseAXWindow(resolved.axElement, unminimize: needsUnminimize)
                    self.updateMRUTimestamp(pid: targetPID, windowID: resolved.id, date: Date())
                    didActivateAndRaise = true
                    break
                }

                // 対象ウィンドウが未到達の場合、アプリをアクティブ化した上で最新メニューから再押下（必要時は展開押下）する
                guard needsMenuNavigation, !targetTitle.isEmpty else { continue }
                if stepIndex == 0 {
                    if let runningApp = NSRunningApplication(processIdentifier: targetPID), !runningApp.isActive {
                        runningApp.activate(options: [])
                    }
                } else if stepIndex == 1 {
                    if let runningApp = NSRunningApplication(processIdentifier: targetPID), !runningApp.isActive {
                        runningApp.activate(options: [])
                    }
                    _ = self.performMenuNavigationWithRetry(
                        pid: targetPID,
                        windowTitle: targetTitle,
                        applicationName: targetAppName,
                        preferUnchecked: true,
                        forceFresh: true
                    )
                } else if stepIndex == 2 {
                    _ = await self.performMenuNavigationViaMenuOpen(
                        pid: targetPID,
                        windowTitle: targetTitle,
                        applicationName: targetAppName,
                        preferUnchecked: true
                    )
                }
            }

            guard !Task.isCancelled, let self else { return }
            // 規定時間内に遷移を捕捉できなかった場合も、別ウィンドウへの誤前面化を避けつつ未アクティブなら前面化のみ補完する
            if !didActivateAndRaise,
               let runningApp = NSRunningApplication(processIdentifier: targetPID),
               !runningApp.isActive {
                runningApp.activate(options: [])
            }
            self.pendingActivationFollowUpTask = nil
        }
    }

    /// 指定されたウィンドウ 1 枚に対してクローズ要求を送出し、要求フェーズの結果を返す
    /// - Parameter entry: クローズ対象のウィンドウ項目
    /// - Returns: 要求送出成功・すでに消滅済み・送出失敗のいずれかを表す結果
    public func requestCloseWindow(_ entry: WindowEntry) async -> WindowCloseRequestResult {
        guard let app = NSRunningApplication(processIdentifier: entry.pid), !app.isTerminated else {
            cleanupTerminatedPID(entry.pid)
            return .alreadyClosed()
        }

        let (resolvedTarget, didSwitchSpace) = await resolveCachedWindowWithSpaceFallback(entry)
        guard let target = resolvedTarget else {
            let isAppTerminated = NSRunningApplication(processIdentifier: entry.pid)?.isTerminated ?? true
            if isAppTerminated {
                cleanupTerminatedPID(entry.pid)
            }
            let survivingCGWindowIDs: Set<UInt32>
            if !isAppTerminated, entry.cgWindowID != nil {
                survivingCGWindowIDs = await fetchSurvivingCGWindowIDsInBackground(for: entry.pid)
            } else {
                survivingCGWindowIDs = []
            }
            return Self.resolveCloseRequestResultOnUnresolvedTarget(
                isAppTerminated: isAppTerminated,
                cgWindowID: entry.cgWindowID,
                survivingCGWindowIDs: survivingCGWindowIDs,
                didSwitchSpace: didSwitchSpace
            )
        }

        // クローズボタン押下前に既にウィンドウが消滅済みであれば即座に完了として返す
        let isAliveBeforePress = await checkAXWindowAliveInBackground(target.axElement, pid: entry.pid)
        guard isAliveBeforePress else {
            removeCachedWindow(pid: entry.pid, windowID: entry.id, axElement: target.axElement)
            cachedWindowMenuByPID.removeValue(forKey: entry.pid)
            trackedCloseTargetsByEntryID.removeValue(forKey: entry.id)
            return .alreadyClosed(didSwitchSpace: didSwitchSpace)
        }

        // クローズボタン属性が存在し、かつ無効化されていない場合のみ押下アクションを実行する
        Self.applyMessagingTimeout(to: target.axElement)
        var closeButtonRef: CFTypeRef?
        let buttonStatus = AXUIElementCopyAttributeValue(
            target.axElement,
            kAXCloseButtonAttribute as CFString,
            &closeButtonRef
        )
        guard buttonStatus == .success,
              let closeButtonVal = closeButtonRef,
              CFGetTypeID(closeButtonVal) == AXUIElementGetTypeID() else {
            return .failed(didSwitchSpace: didSwitchSpace)
        }

        let closeButton = closeButtonVal as! AXUIElement
        Self.applyMessagingTimeout(to: closeButton)
        if let isEnabled = Self.copyBoolAttribute(closeButton, attribute: kAXEnabledAttribute as CFString), !isEnabled {
            return .failed(didSwitchSpace: didSwitchSpace)
        }

        // 押下直後に同期的に届く破棄通知を取りこぼさないよう、押下前に追跡対象へ登録しておく
        let resolvedCGWindowID = target.cgWindowID ?? entry.cgWindowID
        trackedCloseTargetsByEntryID[entry.id] = TrackedCloseTarget(
            entryID: entry.id,
            pid: entry.pid,
            cgWindowID: resolvedCGWindowID,
            axElement: target.axElement
        )

        let pressStatus = AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        guard pressStatus == .success else {
            trackedCloseTargetsByEntryID.removeValue(forKey: entry.id)
            let isAliveAfterFailure = await checkAXWindowAliveInBackground(target.axElement, pid: entry.pid)
            if !isAliveAfterFailure {
                removeCachedWindow(pid: entry.pid, windowID: entry.id, axElement: target.axElement)
                cachedWindowMenuByPID.removeValue(forKey: entry.pid)
                return .alreadyClosed(didSwitchSpace: didSwitchSpace)
            }
            return .failed(didSwitchSpace: didSwitchSpace)
        }

        // 押下中に既に破棄通知が処理されて追跡対象から除去済みであれば即座に完了扱いとする
        if trackedCloseTargetsByEntryID[entry.id] == nil {
            return .alreadyClosed(didSwitchSpace: didSwitchSpace)
        }

        return .requested(didSwitchSpace: didSwitchSpace)
    }

    /// 指定された PID のアプリケーションに対して通常の終了要求（強制終了ではない）を送出し、要求フェーズの結果を返す
    /// - Parameter pid: 終了対象のプロセス ID
    /// - Returns: 要求送出成功・すでに終了済み・送出失敗のいずれかを表す結果
    public func requestTerminateApplication(pid: Int32) async -> WindowCloseRequestResult {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            cleanupTerminatedPID(pid)
            return Self.resolveTerminateRequestResult(
                hasRunningApp: false,
                isAlreadyTerminated: true,
                terminateAccepted: false,
                isTerminatedImmediately: true
            )
        }
        if app.isTerminated {
            cleanupTerminatedPID(pid)
            return Self.resolveTerminateRequestResult(
                hasRunningApp: true,
                isAlreadyTerminated: true,
                terminateAccepted: false,
                isTerminatedImmediately: true
            )
        }

        // 通常のアプリ終了要求（Command+Q 相当）を送信し、強制終了（forceTerminate）は行わない
        let accepted = app.terminate()
        let terminatedImmediately = accepted && app.isTerminated
        if terminatedImmediately {
            cleanupTerminatedPID(pid)
        }
        return Self.resolveTerminateRequestResult(
            hasRunningApp: true,
            isAlreadyTerminated: false,
            terminateAccepted: accepted,
            isTerminatedImmediately: terminatedImmediately
        )
    }

    /// 指定されたウィンドウが現在も生存しているかをバックグラウンドで非同期確認する（フォールバック生存確認用）
    /// - Parameter entry: 確認対象のウィンドウ項目
    /// - Returns: まだ生存している場合は true、閉じられて消滅している場合は false
    public func isWindowAlive(_ entry: WindowEntry) async -> Bool {
        guard let app = NSRunningApplication(processIdentifier: entry.pid), !app.isTerminated else {
            cleanupTerminatedPID(entry.pid)
            return false
        }

        let targetAXElement: AXUIElement?
        if let tracked = trackedCloseTargetsByEntryID[entry.id] {
            targetAXElement = tracked.axElement
        } else if let list = cachedWindowsByPID[entry.pid] {
            targetAXElement = list.first(where: { $0.id == entry.id })?.axElement
                ?? entry.cgWindowID.flatMap { cgID in list.first(where: { $0.cgWindowID == cgID })?.axElement }
        } else {
            targetAXElement = nil
        }

        if let targetAXElement {
            let isAlive = await checkAXWindowAliveInBackground(targetAXElement, pid: entry.pid)
            if !isAlive {
                removeCachedWindow(pid: entry.pid, windowID: entry.id, axElement: targetAXElement)
                cachedWindowMenuByPID.removeValue(forKey: entry.pid)
                trackedCloseTargetsByEntryID.removeValue(forKey: entry.id)
            }
            return isAlive
        }

        // キャッシュ・追跡対象に不在の場合は、対応 CGWindowID の生存有無で最終判定する
        if let cgWindowID = entry.cgWindowID {
            let surviving = await fetchSurvivingCGWindowIDsInBackground(for: entry.pid)
            if surviving.contains(cgWindowID) {
                return true
            }
        }
        trackedCloseTargetsByEntryID.removeValue(forKey: entry.id)
        return false
    }

    /// 指定された PID のアプリケーションが現在も稼働中かを確認する（フォールバック生存確認用）
    /// - Parameter pid: 確認対象のプロセス ID
    /// - Returns: 稼働中の場合は true、終了済みの場合は false
    public func isApplicationRunning(pid: Int32) async -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            cleanupTerminatedPID(pid)
            return false
        }
        return true
    }

    /// AX 対象が未解決だった場合のウィンドウ終了要求結果を純粋ロジックで決定する
    /// - Parameters:
    ///   - isAppTerminated: 所有アプリケーションが終了済みか
    ///   - cgWindowID: 対象ウィンドウに紐付いていた CoreGraphics ウィンドウ ID（不明時は nil）
    ///   - survivingCGWindowIDs: 現在 WindowServer 上に生存している該当 PID の CGWindowID 集合
    ///   - didSwitchSpace: 解決試行中に別スペース一時遷移を行ったか
    /// - Returns: すでに消滅済みと判定できれば `.alreadyClosed`、それ以外は `.failed`
    nonisolated static func resolveCloseRequestResultOnUnresolvedTarget(
        isAppTerminated: Bool,
        cgWindowID: UInt32?,
        survivingCGWindowIDs: Set<UInt32>,
        didSwitchSpace: Bool
    ) -> WindowCloseRequestResult {
        if isAppTerminated {
            return .alreadyClosed(didSwitchSpace: didSwitchSpace)
        }
        if let cgWindowID, !survivingCGWindowIDs.contains(cgWindowID) {
            return .alreadyClosed(didSwitchSpace: didSwitchSpace)
        }
        return .failed(didSwitchSpace: didSwitchSpace)
    }

    /// アプリ通常終了要求の結果を純粋ロジックで決定する
    /// - Parameters:
    ///   - hasRunningApp: 対象 PID に対応する稼働中アプリオブジェクトが存在したか
    ///   - isAlreadyTerminated: 終了要求前にすでに終了済みだったか
    ///   - terminateAccepted: `NSRunningApplication.terminate()` が要求を受理したか
    ///   - isTerminatedImmediately: 要求直後にすでに終了状態になったか
    /// - Returns: 要求フェーズの結果 (`WindowCloseRequestResult`)
    nonisolated static func resolveTerminateRequestResult(
        hasRunningApp: Bool,
        isAlreadyTerminated: Bool,
        terminateAccepted: Bool,
        isTerminatedImmediately: Bool
    ) -> WindowCloseRequestResult {
        if !hasRunningApp || isAlreadyTerminated {
            return .alreadyClosed()
        }
        guard terminateAccepted else {
            return .failed()
        }
        return isTerminatedImmediately ? .alreadyClosed() : .requested()
    }

    /// 終了済み PID に紐付くキャッシュ・オブザーバ・クローズ追跡情報を一括解放する
    /// - Parameter pid: 終了したプロセス ID
    private func cleanupTerminatedPID(_ pid: Int32) {
        unregisterObserver(for: pid)
        cachedWindowsByPID.removeValue(forKey: pid)
        cachedWindowMenuByPID.removeValue(forKey: pid)
        trackedCloseTargetsByEntryID = trackedCloseTargetsByEntryID.filter { $0.value.pid != pid }
    }

    // MARK: - 内部ヘルパー

    /// CGWindowListCopyWindowInfo の抽出用メタデータ構造体
    struct CGWindowMeta: Equatable {
        let windowID: UInt32
        let pid: Int32
        let layer: Int
        let bounds: CGRect
        let alpha: Double
        let isOnscreen: Bool
        let name: String?

        /// CGWindow メタデータを初期化する
        /// - Parameters:
        ///   - windowID: CoreGraphics ウィンドウ ID
        ///   - pid: 所有プロセス ID
        ///   - layer: レイヤー番号
        ///   - bounds: ウィンドウ矩形
        ///   - alpha: 不透明度
        ///   - isOnscreen: 画面表示中フラグ
        ///   - name: CGWindow 名メタデータ（取得可能な場合）
        init(
            windowID: UInt32,
            pid: Int32,
            layer: Int,
            bounds: CGRect,
            alpha: Double,
            isOnscreen: Bool,
            name: String? = nil
        ) {
            self.windowID = windowID
            self.pid = pid
            self.layer = layer
            self.bounds = bounds
            self.alpha = alpha
            self.isOnscreen = isOnscreen
            self.name = name
        }
    }

    /// 全操作スペースの CGWindow メタデータを Z オーダー順で取得する
    /// - Returns: CoreGraphics ウィンドウメタデータ配列
    private func fetchCGWindowInfos() -> [CGWindowMeta] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return rawList.compactMap { dict in
            guard let windowID = dict[kCGWindowNumber as String] as? UInt32,
                  let pid = dict[kCGWindowOwnerPID as String] as? Int32,
                  let layer = dict[kCGWindowLayer as String] as? Int,
                  let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                return nil
            }
            let alpha = (dict[kCGWindowAlpha as String] as? Double) ?? 1.0
            let isOnscreen = (dict[kCGWindowIsOnscreen as String] as? Bool) ?? false
            let name = dict[kCGWindowName as String] as? String
            return CGWindowMeta(
                windowID: windowID,
                pid: pid,
                layer: layer,
                bounds: bounds,
                alpha: alpha,
                isOnscreen: isOnscreen,
                name: name
            )
        }
    }

    /// 起動中の全通常アプリの AX ウィンドウをスキャンしてキャッシュを更新する（同期呼び出し用）
    private func scanAllRegularApps() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard pid != selfPID else { continue }
            if observersByPID[pid] == nil {
                registerObserver(for: pid)
            }
            refreshAXWindows(for: pid, markFrontmostAsActive: app.isActive)
        }
    }

    /// 起動中の全通常アプリを最大同時実行数付きで並列バックグラウンドスキャンし、結果を順次キャッシュへ反映する
    /// - Parameters:
    ///   - debounce: 連続発生時のデバウンス待機時間（即時実行時は nil）
    ///   - prefetchReasonOnCompletion: スキャン完了後にサムネイル事前取得を促す契機種別（不要時は nil）
    private func scheduleBackgroundScanAllRegularApps(
        debounce: Duration?,
        prefetchReasonOnCompletion: WindowCapturePrefetchReason? = nil
    ) {
        pendingSpaceScanTask?.cancel()
        pendingSpaceScanTask = Task { @MainActor [weak self] in
            if let debounce {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled, let self, self.isObserving else { return }

            let selfPID = ProcessInfo.processInfo.processIdentifier
            let cgWindows = self.fetchCGWindowInfos()
            let pidsNeedingMenu = Self.pidsRequiringMenuPreload(
                from: cgWindows,
                knownTargetPIDs: self.menuEnrichmentTargetPIDs
            )

            let scanTargets: [(pid: Int32, isActive: Bool, includeMenu: Bool, generation: UInt64)] = NSWorkspace.shared.runningApplications.compactMap { app in
                guard app.activationPolicy == .regular else { return nil }
                let pid = app.processIdentifier
                guard pid != selfPID else { return nil }
                if self.observersByPID[pid] == nil {
                    self.registerObserver(for: pid)
                }
                let generation = self.bumpScanGeneration(for: pid)
                let includeMenu = pidsNeedingMenu.contains(pid)
                return (pid: pid, isActive: app.isActive, includeMenu: includeMenu, generation: generation)
            }

            let workerQueue = self.axWorkerQueue
            let maxConcurrency = Self.maxConcurrentBackgroundScans

            await withTaskGroup(of: (pid: Int32, isActive: Bool, generation: UInt64, snapshots: [ScannedAXWindowSnapshot], menuItems: [ScannedWindowMenuItem]?).self) { group in
                var nextIndex = 0
                let initialBatch = min(maxConcurrency, scanTargets.count)

                for _ in 0..<initialBatch {
                    let target = scanTargets[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        let data = await Self.fetchAXDataInBackground(
                            for: target.pid,
                            includeMenuItems: target.includeMenu,
                            on: workerQueue
                        )
                        return (target.pid, target.isActive, target.generation, data.snapshots, data.menuItems)
                    }
                }

                while let result = await group.next() {
                    if Task.isCancelled || !self.isObserving {
                        group.cancelAll()
                        break
                    }
                    if nextIndex < scanTargets.count {
                        let target = scanTargets[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            let data = await Self.fetchAXDataInBackground(
                                for: target.pid,
                                includeMenuItems: target.includeMenu,
                                on: workerQueue
                            )
                            return (target.pid, target.isActive, target.generation, data.snapshots, data.menuItems)
                        }
                    }

                    // より新しい個別更新が先行完了していた場合は古いスキャン結果を破棄する
                    guard self.scanGenerationByPID[result.pid] == result.generation else { continue }
                    self.applyAXWindowSnapshots(
                        result.snapshots,
                        for: result.pid,
                        markFrontmostAsActive: result.isActive,
                        allowDisplaySpanningReplacement: false
                    )
                    if let menuItems = result.menuItems {
                        self.cachedWindowMenuByPID[result.pid] = CachedWindowMenuState(
                            items: menuItems,
                            fetchedAt: Date()
                        )
                    }
                }
            }

            guard !Task.isCancelled, self.isObserving else { return }
            self.hasPendingSpaceChange = false
            self.hasCompletedInitialBackgroundScan = true
            if let prefetchReasonOnCompletion {
                self.onCapturePrefetchNeeded?(prefetchReasonOnCompletion)
            }
        }
    }

    /// 指定 PID の AX ウィンドウスキャンをデバウンス付きでバックグラウンド実行する
    /// - Parameters:
    ///   - pid: 対象プロセス ID
    ///   - markFrontmostAsActive: 最前面アプリの先頭ウィンドウをアクティブとして記録するか
    ///   - debounce: デバウンス待機時間（即時実行時は nil）
    ///   - activatedElement: 更新後に MRU 時刻を更新する対象要素（任意）
    ///   - activatedAt: 記録するアクティブ時刻（任意）
    ///   - allowDisplaySpanningReplacement: 同一スペース内のタブ切り替えとしてディスプレイ占有級置換を許可するか
    ///   - includeMenuItems: ウィンドウメニュー項目の再取得も同時に行うか
    ///   - prefetchReasonOnCompletion: 更新完了後にサムネイル事前取得を促す契機種別（不要時は nil）
    private func scheduleBackgroundRefresh(
        for pid: Int32,
        markFrontmostAsActive: Bool,
        debounce: Duration?,
        activatedElement: SendableAXElement? = nil,
        activatedAt: Date? = nil,
        allowDisplaySpanningReplacement: Bool = false,
        includeMenuItems: Bool = false,
        prefetchReasonOnCompletion: WindowCapturePrefetchReason? = nil
    ) {
        pendingRefreshTasksByPID[pid]?.cancel()
        if let prefetchReasonOnCompletion {
            pendingPrefetchReasonByPID[pid] = prefetchReasonOnCompletion
        }
        let generation = bumpScanGeneration(for: pid)
        let workerQueue = axWorkerQueue
        let shouldFetchMenu = includeMenuItems || menuEnrichmentTargetPIDs.contains(pid)

        pendingRefreshTasksByPID[pid] = Task { @MainActor [weak self] in
            if let debounce {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled, let self, self.isObserving else { return }

            let result = await Self.fetchAXDataInBackground(
                for: pid,
                includeMenuItems: shouldFetchMenu,
                on: workerQueue
            )
            guard !Task.isCancelled, self.isObserving else { return }
            self.pendingRefreshTasksByPID.removeValue(forKey: pid)
            guard self.scanGenerationByPID[pid] == generation else { return }

            self.applyAXWindowSnapshots(
                result.snapshots,
                for: pid,
                markFrontmostAsActive: markFrontmostAsActive,
                allowDisplaySpanningReplacement: allowDisplaySpanningReplacement && !self.hasPendingSpaceChange
            )
            if let menuItems = result.menuItems {
                self.cachedWindowMenuByPID[pid] = CachedWindowMenuState(
                    items: menuItems,
                    fetchedAt: Date()
                )
            }

            if let activatedElement, let activatedAt {
                self.updateMRUTimestamp(
                    pid: pid,
                    axElement: activatedElement.value,
                    date: activatedAt
                )
            }
            if let pendingReason = self.pendingPrefetchReasonByPID.removeValue(forKey: pid) {
                self.onCapturePrefetchNeeded?(pendingReason)
            }
        }
    }

    /// 指定 PID の「ウィンドウ」メニュー項目のみをバックグラウンドで非同期更新する（Stale-While-Revalidate 用）
    /// - Parameter pid: 対象プロセス ID
    private func scheduleBackgroundMenuRefresh(for pid: Int32) {
        guard isObserving, pendingMenuRefreshTasksByPID[pid] == nil else { return }
        let workerQueue = axWorkerQueue
        pendingMenuRefreshTasksByPID[pid] = Task { @MainActor [weak self] in
            let menuItems = await withCheckedContinuation { continuation in
                workerQueue.async {
                    continuation.resume(returning: Self.fetchWindowMenuItems(for: pid))
                }
            }
            guard let self else { return }
            self.pendingMenuRefreshTasksByPID.removeValue(forKey: pid)
            guard !Task.isCancelled, self.isObserving else { return }
            self.cachedWindowMenuByPID[pid] = CachedWindowMenuState(
                items: menuItems,
                fetchedAt: Date()
            )
        }
    }

    /// 指定 PID のスキャン世代番号を進め、更新後の値を返す
    /// - Parameter pid: 対象プロセス ID
    /// - Returns: 更新された世代番号
    private func bumpScanGeneration(for pid: Int32) -> UInt64 {
        let next = (scanGenerationByPID[pid] ?? 0) &+ 1
        scanGenerationByPID[pid] = next
        return next
    }

    /// 指定ワーカーキュー上で対象 PID の AX ウィンドウ一覧と必要なメニュー項目を非同期取得する
    /// - Parameters:
    ///   - pid: 対象プロセス ID
    ///   - includeMenuItems: ウィンドウメニューも同時に取得するか
    ///   - queue: 実行先の DispatchQueue
    /// - Returns: スナップショット配列および（取得時のみ）メニュー項目配列
    private nonisolated static func fetchAXDataInBackground(
        for pid: Int32,
        includeMenuItems: Bool,
        on queue: DispatchQueue
    ) async -> (snapshots: [ScannedAXWindowSnapshot], menuItems: [ScannedWindowMenuItem]?) {
        await withCheckedContinuation { continuation in
            queue.async {
                let snapshots = fetchAXWindowSnapshots(for: pid)
                let menuItems = includeMenuItems ? fetchWindowMenuItems(for: pid) : nil
                continuation.resume(returning: (snapshots, menuItems))
            }
        }
    }

    /// 高優先度ワーカーキューで指定 PID の AX ウィンドウ一覧を取得する（切り替え確定フォローアップ用）
    /// - Parameter pid: 対象プロセス ID
    /// - Returns: 取得された AX ウィンドウスナップショット配列
    private func fetchAXWindowSnapshotsInBackground(for pid: Int32) async -> [ScannedAXWindowSnapshot] {
        let queue = axActivationQueue
        return await withCheckedContinuation { continuation in
            queue.async {
                let snapshots = Self.fetchAXWindowSnapshots(for: pid)
                continuation.resume(returning: snapshots)
            }
        }
    }

    /// 指定 PID のアプリから現在の AX ウィンドウ一覧を読み取りキャッシュを更新する（同期版）
    /// - Parameters:
    ///   - pid: 対象プロセス ID
    ///   - markFrontmostAsActive: 最前面アプリの先頭ウィンドウをアクティブとして記録するか
    private func refreshAXWindows(for pid: Int32, markFrontmostAsActive: Bool) {
        let snapshots = Self.fetchAXWindowSnapshots(for: pid)
        applyAXWindowSnapshots(snapshots, for: pid, markFrontmostAsActive: markFrontmostAsActive)
    }

    /// 取得済み AX スナップショット一覧を既存のキャッシュ・MRU 時刻を保持したままマージし、タブ切り替えで隠れた旧タブを除去する
    /// - Parameters:
    ///   - snapshots: バックグラウンドまたは同期で取得した AX ウィンドウスナップショット
    ///   - pid: 対象プロセス ID
    ///   - markFrontmostAsActive: 最前面アプリの先頭ウィンドウをアクティブとして記録するか
    ///   - allowDisplaySpanningReplacement: 同一スペース内のタブ切り替えとしてディスプレイ占有級置換を許可するか
    private func applyAXWindowSnapshots(
        _ snapshots: [ScannedAXWindowSnapshot],
        for pid: Int32,
        markFrontmostAsActive: Bool,
        allowDisplaySpanningReplacement: Bool = false
    ) {
        var existing = cachedWindowsByPID[pid] ?? []
        for idx in existing.indices {
            existing[idx].isPresentInLatestAXScan = false
        }

        guard !snapshots.isEmpty else {
            if !existing.isEmpty {
                cachedWindowsByPID[pid] = existing
                cachedWindowMenuByPID.removeValue(forKey: pid)
            }
            return
        }

        let now = Date()

        for (index, snapshot) in snapshots.enumerated() {
            if let matchIdx = existing.firstIndex(where: { CFEqual($0.axElement, snapshot.axElement.value) }) {
                existing[matchIdx].role = snapshot.role
                // 一時的な AX 読み取り失敗（nil）や遷移中の空タイトルで既知の非空タイトルを消去しない
                if let newTitle = snapshot.title,
                   !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    existing[matchIdx].title = newTitle
                } else if existing[matchIdx].title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                    existing[matchIdx].title = snapshot.title
                }
                existing[matchIdx].subrole = snapshot.subrole
                existing[matchIdx].bounds = snapshot.bounds
                existing[matchIdx].isMinimized = snapshot.isMinimized
                existing[matchIdx].isPresentInLatestAXScan = true
                if markFrontmostAsActive && index == 0 && existing[matchIdx].lastActivatedAt == nil {
                    existing[matchIdx].lastActivatedAt = now
                }
            } else {
                existing.append(
                    CachedAXWindow(
                        id: snapshot.uniqueID,
                        pid: pid,
                        axElement: snapshot.axElement.value,
                        cgWindowID: nil,
                        role: snapshot.role,
                        title: snapshot.title,
                        subrole: snapshot.subrole,
                        bounds: snapshot.bounds,
                        isMinimized: snapshot.isMinimized,
                        isPresentInLatestAXScan: true,
                        lastActivatedAt: (markFrontmostAsActive && index == 0) ? now : nil
                    )
                )
            }
        }

        // 同一スペースの AX 通知由来で姿を消した旧タブ候補がある場合のみ、独立 CGWindow の生存確認を伴って整理する
        let hasDisappearedCandidates = existing.contains { !$0.isPresentInLatestAXScan && $0.role == "AXWindow" }
        if hasDisappearedCandidates {
            cachedWindowMenuByPID.removeValue(forKey: pid)
        }
        let activeWindowEntries = existing.filter {
            $0.isPresentInLatestAXScan && $0.role == "AXWindow" && $0.subrole != nil
        }

        if allowDisplaySpanningReplacement, hasDisappearedCandidates, !activeWindowEntries.isEmpty {
            let screenBounds = currentDisplayBounds()
            let survivingCGWindowIDs = Self.fetchSurvivingCGWindowIDs(for: pid)
            var inheritedDateByReplacementID: [String: Date] = [:]
            existing.removeAll { candidate in
                guard !candidate.isPresentInLatestAXScan, candidate.role == "AXWindow" else {
                    return false
                }
                guard let replacement = activeWindowEntries.first(where: { active in
                    Self.shouldEvictCachedWindowAsReplacedTab(
                        oldBounds: candidate.bounds,
                        oldIsMinimized: candidate.isMinimized,
                        oldCGWindowID: candidate.cgWindowID,
                        newBounds: active.bounds,
                        newIsMinimized: active.isMinimized,
                        newCGWindowID: active.cgWindowID,
                        survivingCGWindowIDs: survivingCGWindowIDs,
                        allowDisplaySpanningReplacement: allowDisplaySpanningReplacement,
                        screenBounds: screenBounds
                    )
                }) else {
                    return false
                }
                if let oldDate = candidate.lastActivatedAt {
                    let prev = inheritedDateByReplacementID[replacement.id]
                    if prev == nil || oldDate > prev! {
                        inheritedDateByReplacementID[replacement.id] = oldDate
                    }
                }
                return true
            }
            for idx in existing.indices where existing[idx].lastActivatedAt == nil {
                if let inheritedDate = inheritedDateByReplacementID[existing[idx].id] {
                    existing[idx].lastActivatedAt = inheritedDate
                }
            }
        }

        cachedWindowsByPID[pid] = existing
    }

    /// 指定 PID のフォーカス中ウィンドウの MRU 時刻をバックグラウンドの AX 問い合わせを用いて更新する
    /// - Parameter pid: アクティブになったプロセス ID
    private func markFocusedWindowActivatedInBackground(for pid: Int32) {
        pendingRefreshTasksByPID[pid]?.cancel()
        let capturedNow = Date()
        let generation = bumpScanGeneration(for: pid)
        let workerQueue = axWorkerQueue

        pendingRefreshTasksByPID[pid] = Task { @MainActor [weak self] in
            guard let self, self.isObserving else { return }

            let result = await withCheckedContinuation { continuation in
                workerQueue.async {
                    let appElement = AXUIElementCreateApplication(pid)
                    Self.applyMessagingTimeout(to: appElement)
                    var focusedRef: CFTypeRef?
                    let status = AXUIElementCopyAttributeValue(
                        appElement,
                        kAXFocusedWindowAttribute as CFString,
                        &focusedRef
                    )
                    let focusedElement: SendableAXElement?
                    if status == .success,
                       let focusedWin = focusedRef,
                       CFGetTypeID(focusedWin) == AXUIElementGetTypeID() {
                        let axWin = focusedWin as! AXUIElement
                        Self.applyMessagingTimeout(to: axWin)
                        focusedElement = SendableAXElement(value: axWin)
                    } else {
                        focusedElement = nil
                    }
                    let snapshots = Self.fetchAXWindowSnapshots(for: pid)
                    continuation.resume(returning: (focusedElement, snapshots))
                }
            }

            guard !Task.isCancelled, self.isObserving else { return }
            self.pendingRefreshTasksByPID.removeValue(forKey: pid)
            guard self.scanGenerationByPID[pid] == generation else { return }
            self.applyAXWindowSnapshots(result.1, for: pid, markFrontmostAsActive: true)

            if let focusedElement = result.0 {
                self.updateMRUTimestamp(pid: pid, axElement: focusedElement.value, date: capturedNow)
            }
            if let pendingReason = self.pendingPrefetchReasonByPID.removeValue(forKey: pid) {
                self.onCapturePrefetchNeeded?(pendingReason)
            }
        }
    }

    /// 既に終了したプロセス ID に紐付くキャッシュと監視リソースを一括解放する
    /// - Parameter activeAppPIDs: 現在稼働中のアプリケーション PID 集合
    private func purgeTerminatedPIDs(activeAppPIDs: Set<Int32>) {
        let stalePIDs = Set(cachedWindowsByPID.keys)
            .union(cachedWindowMenuByPID.keys)
            .union(observersByPID.keys)
            .subtracting(activeAppPIDs)
        for pid in stalePIDs {
            cleanupTerminatedPID(pid)
            menuEnrichmentTargetPIDs.remove(pid)
            scanGenerationByPID.removeValue(forKey: pid)
        }
    }

    /// 同期 AX IPC を行わずに CGWindow 生存情報のみを用いて閉鎖済みキャッシュウィンドウを整理する
    /// - Parameter cgEntriesByPID: 現在の CGWindow マップ
    private func cleanupClosedWindowsUsingCGWindows(cgEntriesByPID: [Int32: [(zOrder: Int, info: CGWindowMeta)]]) {
        for (pid, list) in cachedWindowsByPID {
            let pidCGEntries = cgEntriesByPID[pid] ?? []
            let survivingCGWindowIDs = Set(pidCGEntries.map { $0.info.windowID })
            let hasSubstantialCGWindow = pidCGEntries.contains { entry in
                (entry.info.layer == 0 || entry.info.isOnscreen)
                    && entry.info.bounds.width >= 200
                    && entry.info.bounds.height >= 165
            }

            var needsBackgroundValidation = false
            var retained: [CachedAXWindow] = []
            retained.reserveCapacity(list.count)

            for var cached in list {
                let decision = Self.cgCacheRetentionDecision(
                    isPresentInLatestAXScan: cached.isPresentInLatestAXScan,
                    isMinimized: cached.isMinimized,
                    knownCGWindowID: cached.cgWindowID,
                    survivingCGWindowIDs: survivingCGWindowIDs,
                    hasSubstantialCGWindow: hasSubstantialCGWindow
                )
                switch decision {
                case .retain:
                    retained.append(cached)
                case .evict:
                    needsBackgroundValidation = true
                case .clearCGWindowIDAndRevalidate:
                    cached.cgWindowID = nil
                    retained.append(cached)
                    needsBackgroundValidation = true
                }
            }

            if retained.isEmpty {
                cachedWindowsByPID.removeValue(forKey: pid)
            } else {
                cachedWindowsByPID[pid] = retained
            }

            if needsBackgroundValidation, pendingRefreshTasksByPID[pid] == nil {
                scheduleBackgroundRefresh(for: pid, markFrontmostAsActive: false, debounce: nil)
            }
        }
    }

    /// ウィンドウ候補収集時にメインスレッドでの同期全アプリスキャンへフォールバックすべきか判定する純粋関数
    /// - Parameters:
    ///   - isObserving: AXObserver によるバックグラウンド監視が稼働中か
    ///   - hasCompletedInitialBackgroundScan: 初期バックグラウンド全スキャンが完了済みか
    /// - Returns: 同期スキャンが必要な場合は true、キャッシュベースで即時構築すべき場合は false
    nonisolated static func shouldPerformSyncScanOnFetch(
        isObserving: Bool,
        hasCompletedInitialBackgroundScan: Bool
    ) -> Bool {
        !isObserving || !hasCompletedInitialBackgroundScan
    }

    /// 全体バックグラウンドスキャン時に「ウィンドウ」メニュー先読みが必要な PID 集合を算出する純粋関数
    /// - Parameters:
    ///   - cgWindows: WindowServer から取得した CGWindow メタデータ一覧
    ///   - knownTargetPIDs: 直近の候補構築でメニュー補完対象と判定された PID 集合
    /// - Returns: バックグラウンドスキャン時にメニュー取得も併用すべき PID 集合
    nonisolated static func pidsRequiringMenuPreload(
        from cgWindows: [CGWindowMeta],
        knownTargetPIDs: Set<Int32>
    ) -> Set<Int32> {
        var result = knownTargetPIDs
        for cg in cgWindows where !cg.isOnscreen && cg.layer == 0 && cg.bounds.width >= 200 && cg.bounds.height >= 165 {
            result.insert(cg.pid)
        }
        return result
    }

    /// CGWindow の生存情報のみからキャッシュ済みウィンドウの保持／破棄／再照合を判定する純粋関数
    /// - Parameters:
    ///   - isPresentInLatestAXScan: 直近の AX スキャンで捕捉されたか
    ///   - isMinimized: 最小化状態かどうか
    ///   - knownCGWindowID: 前回までに確定していた CGWindowID（未確定時は nil）
    ///   - survivingCGWindowIDs: 現在 WindowServer 上に生存している該当 PID の CGWindowID 集合
    ///   - hasSubstantialCGWindow: 該当 PID に通常サイズ以上の有効レイヤー CGWindow が残存しているか
    /// - Returns: キャッシュに対する処置方針 (`CGCacheRetentionDecision`)
    nonisolated static func cgCacheRetentionDecision(
        isPresentInLatestAXScan: Bool,
        isMinimized: Bool,
        knownCGWindowID: UInt32?,
        survivingCGWindowIDs: Set<UInt32>,
        hasSubstantialCGWindow: Bool
    ) -> CGCacheRetentionDecision {
        guard let knownID = knownCGWindowID else {
            return .retain
        }
        if survivingCGWindowIDs.contains(knownID) {
            return .retain
        }
        // 直近の AX スキャンに不在かつ対応 CGWindowID も消滅している場合は閉鎖済みとして即破棄する
        if !isPresentInLatestAXScan {
            return .evict
        }
        // 非最小化かつ実サイズ CGWindow が完全に無くなっている場合は閉鎖済みとみなす
        if !isMinimized && !hasSubstantialCGWindow {
            return .evict
        }
        // フルスクリーン遷移等で CGWindowID のみ入れ替わった可能性を考慮し、旧 ID を外して再照合する
        return isMinimized ? .retain : .clearCGWindowIDAndRevalidate
    }

    /// 閉じられた・存在しなくなったウィンドウをキャッシュから整理する（非監視時の同期フォールバック用）
    /// - Parameter cgEntriesByPID: 現在の CGWindow マップ
    private func cleanupClosedWindows(cgEntriesByPID: [Int32: [(zOrder: Int, info: CGWindowMeta)]]) {
        for (pid, list) in cachedWindowsByPID {
            let pidCGEntries = cgEntriesByPID[pid] ?? []
            let survivingCGWindowIDs = Set(pidCGEntries.map { $0.info.windowID })
            let hasSubstantialCGWindow = pidCGEntries.contains { entry in
                (entry.info.layer == 0 || entry.info.isOnscreen)
                    && entry.info.bounds.width >= 200
                    && entry.info.bounds.height >= 165
            }
            let filtered = list.filter { cached in
                Self.applyMessagingTimeout(to: cached.axElement)
                var roleRef: CFTypeRef?
                let err = AXUIElementCopyAttributeValue(cached.axElement, kAXRoleAttribute as CFString, &roleRef)
                return Self.shouldRetainCachedAXWindow(
                    isPresentInLatestAXScan: cached.isPresentInLatestAXScan,
                    knownCGWindowID: cached.cgWindowID,
                    axRoleCheckResult: err,
                    survivingCGWindowIDs: survivingCGWindowIDs,
                    hasSubstantialCGWindow: hasSubstantialCGWindow
                )
            }
            if filtered.isEmpty {
                cachedWindowsByPID.removeValue(forKey: pid)
            } else {
                cachedWindowsByPID[pid] = filtered
            }
        }
    }

    /// キャッシュ済み AX ウィンドウが現在も生存しており保持すべきかを純粋ロジックで判定する
    /// - Parameters:
    ///   - isPresentInLatestAXScan: 直近の AX スキャン（現在スペースおよびフォーカス/メイン補完）で捕捉されたか
    ///   - knownCGWindowID: 前回までに照合・確定していた CGWindowID（未確定時は nil）
    ///   - axRoleCheckResult: 対象 AXUIElement の `kAXRoleAttribute` 読み取り結果
    ///   - survivingCGWindowIDs: 現在システム上に生存している該当 PID の CGWindowID 集合
    ///   - hasSubstantialCGWindow: 該当 PID に通常サイズ以上の有効レイヤー CGWindow が残存しているか
    /// - Returns: キャッシュに保持し続ける場合は true、閉鎖済みとして破棄する場合は false
    nonisolated static func shouldRetainCachedAXWindow(
        isPresentInLatestAXScan: Bool,
        knownCGWindowID: UInt32?,
        axRoleCheckResult: AXError,
        survivingCGWindowIDs: Set<UInt32>,
        hasSubstantialCGWindow: Bool
    ) -> Bool {
        // 直近の AX スキャンに存在せず、かつ前回確定していた対応 CGWindowID が WindowServer 上から消滅している場合は、
        // 閉じられたウィンドウが裏方の空き殻 CGWindow に乗り換えてゾンビ化するのを防ぐため即座に破棄する
        if !isPresentInLatestAXScan,
           let knownID = knownCGWindowID,
           !survivingCGWindowIDs.contains(knownID) {
            return false
        }
        if axRoleCheckResult == .success {
            return true
        }
        guard axRoleCheckResult == .cannotComplete else { return false }
        // AX が一時的に応答できない場合は、対応 CGWindow または（最新 AX スキャンで捕捉済みのときのみ）通常サイズのウィンドウが残っている時だけ保持する
        if let knownID = knownCGWindowID {
            return survivingCGWindowIDs.contains(knownID)
        }
        return isPresentInLatestAXScan && hasSubstantialCGWindow
    }

    /// 照合処理後のキャッシュ済み AX ウィンドウ候補が現在も実在し出力・保持すべきかを純粋ロジックで判定する
    /// - Parameters:
    ///   - isPresentInLatestAXScan: 直近の AX スキャンで捕捉されたか
    ///   - resolvedCGWindowID: WindowServer 上で生存が確認できた対応 CGWindowID（未一致時は nil）
    /// - Returns: 現在スペースの AX または WindowServer 上に実在し候補として出力すべき場合は true
    nonisolated static func shouldEmitCachedAXWindow(
        isPresentInLatestAXScan: Bool,
        resolvedCGWindowID: UInt32?
    ) -> Bool {
        isPresentInLatestAXScan || resolvedCGWindowID != nil
    }

    /// 閉鎖後に orderOut 等で CGWindow を残すアプリのオフスクリーンキャッシュを保持すべきか純粋ロジックで判定する
    /// - Parameters:
    ///   - requiresLiveVerificationWhenOffscreen: 対象アプリがオフスクリーン時の生存再検証を必要とするか
    ///   - isPresentInLatestAXScan: 直近の AX スキャンで捕捉されたか
    ///   - isMinimized: 最小化状態かどうか
    ///   - isAppHidden: アプリケーション自体が非表示（Cmd+H）状態か
    ///   - isCGOnScreen: 対応する CGWindow が画面表示中か
    ///   - title: キャッシュされていたウィンドウタイトル
    ///   - applicationName: 所有アプリケーションの表示名（アプリ名／プロファイル名サフィックス照合用。省略時は nil）
    ///   - menuItems: アプリの「ウィンドウ」メニューから抽出した開いているウィンドウ一覧
    /// - Returns: 実在するウィンドウとして保持すべき場合は true、閉鎖済みとみなして破棄する場合は false
    nonisolated static func shouldRetainOffscreenCachedAXWindow(
        requiresLiveVerificationWhenOffscreen: Bool,
        isPresentInLatestAXScan: Bool,
        isMinimized: Bool,
        isAppHidden: Bool,
        isCGOnScreen: Bool,
        title: String?,
        applicationName: String? = nil,
        menuItems: [WindowMenuItemSnapshot]
    ) -> Bool {
        guard requiresLiveVerificationWhenOffscreen else {
            return true
        }
        if isMinimized || isAppHidden || isCGOnScreen || isPresentInLatestAXScan {
            return true
        }
        guard let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedTitle.isEmpty else {
            return false
        }
        return WindowMenuCandidatePairing.matchingMenuItemIndex(
            for: trimmedTitle,
            in: menuItems,
            preferUnchecked: false,
            applicationName: applicationName
        ) != nil
    }

    /// 指定された AX サブロールがフローティングウィンドウ系かを判定する
    /// - Parameter subrole: 対象の AX サブロール文字列
    /// - Returns: フローティングウィンドウ系のサブロールであれば true
    private nonisolated static func isFloatingAXSubrole(_ subrole: String?) -> Bool {
        subrole == "AXFloatingWindow" || subrole == "AXSystemFloatingWindow"
    }

    /// キャッシュ済み AX ウィンドウに対応する CGWindow を位置・サイズ・表示状態・履歴連続性・包含比較で特定する
    /// - Parameters:
    ///   - cached: キャッシュ済み AX ウィンドウ情報
    ///   - applicationName: 所有アプリケーションの表示名（サフィックス付き AX タイトルと CGWindow 名の照合用）
    ///   - entries: 該当 PID の CGWindow 情報一覧
    ///   - excludedIDs: 既に照合済みのウィンドウ ID セット
    /// - Returns: 最も一致する CGWindow とその Z オーダー順（見つからない場合は nil）
    private func findMatchingCGWindow(
        for cached: CachedAXWindow,
        applicationName: String? = nil,
        in entries: [(zOrder: Int, info: CGWindowMeta)],
        excluding excludedIDs: Set<UInt32>
    ) -> (zOrder: Int, info: CGWindowMeta)? {
        guard let axBounds = cached.bounds else {
            return nil
        }
        return Self.selectBestCGWindowMatch(
            axBounds: axBounds,
            axTitle: cached.title,
            applicationName: applicationName,
            isMinimized: cached.isMinimized,
            preferOnscreen: cached.isPresentInLatestAXScan && !cached.isMinimized,
            preferredCGWindowID: cached.cgWindowID,
            allowOffscreenNonZeroLayer: Self.isFloatingAXSubrole(cached.subrole),
            in: entries,
            excluding: excludedIDs
        )
    }

    /// AX 矩形に対して最も適合する CGWindow を純粋比較で選出する
    /// - Parameters:
    ///   - axBounds: AXUIElement のウィンドウ矩形
    ///   - axTitle: AXUIElement から取得したウィンドウタイトル（任意）
    ///   - applicationName: 所有アプリケーションの表示名（サフィックス付き AX タイトルと CGWindow 名の照合用。任意）
    ///   - isMinimized: AX 上の最小化状態
    ///   - preferOnscreen: 現在スペース上で捕捉済みであり画面表示中 CGWindow を優先するか
    ///   - preferredCGWindowID: 前回照合されていた CGWindow ID（任意）
    ///   - allowOffscreenNonZeroLayer: オフスクリーンの非通常レイヤー（layer != 0）候補との照合を許可するか
    ///   - entries: 該当 PID の CGWindow 情報一覧
    ///   - excludedIDs: 既に照合済みのウィンドウ ID セット
    /// - Returns: 最も一致する CGWindow とその Z オーダー順（見つからない場合は nil）
    nonisolated static func selectBestCGWindowMatch(
        axBounds: CGRect,
        axTitle: String? = nil,
        applicationName: String? = nil,
        isMinimized: Bool,
        preferOnscreen: Bool,
        preferredCGWindowID: UInt32?,
        allowOffscreenNonZeroLayer: Bool = false,
        in entries: [(zOrder: Int, info: CGWindowMeta)],
        excluding excludedIDs: Set<UInt32>
    ) -> (zOrder: Int, info: CGWindowMeta)? {
        let available = entries.filter { entry in
            guard !excludedIDs.contains(entry.info.windowID),
                  allowedCGWindowLayers.contains(entry.info.layer),
                  entry.info.bounds.width >= 50,
                  entry.info.bounds.height >= 50 else {
                return false
            }
            // 通常ウィンドウに対してオフスクリーンのフローティング補助窓（Figma の 400x600 等）を誤照合しない
            if !allowOffscreenNonZeroLayer && entry.info.layer != 0 && !entry.info.isOnscreen {
                return false
            }
            return true
        }

        // 1. 許容誤差 40pt 以内で、最小距離 + 4pt 以内の候補から可視状態・タイトル一致・連続性・Z オーダーを含めて最良を選出する
        let distances = available.compactMap { entry -> (entry: (zOrder: Int, info: CGWindowMeta), dist: Double)? in
            let dist = boundsDistance(axBounds, entry.info.bounds)
            guard dist <= 40.0 else { return nil }
            return (entry: entry, dist: dist)
        }

        if let minDist = distances.map(\.dist).min() {
            let closeMatches = distances.filter { $0.dist <= minDist + 4.0 }
            if let best = closeMatches.min(by: { lhs, rhs in
                let lhsRank = matchPriorityTuple(
                    for: lhs.entry,
                    dist: lhs.dist,
                    axTitle: axTitle,
                    applicationName: applicationName,
                    isMinimized: isMinimized,
                    preferOnscreen: preferOnscreen,
                    preferredCGWindowID: preferredCGWindowID
                )
                let rhsRank = matchPriorityTuple(
                    for: rhs.entry,
                    dist: rhs.dist,
                    axTitle: axTitle,
                    applicationName: applicationName,
                    isMinimized: isMinimized,
                    preferOnscreen: preferOnscreen,
                    preferredCGWindowID: preferredCGWindowID
                )
                return lhsRank < rhsRank
            }) {
                return best.entry
            }
        }

        // 2. フルスクリーン等でツールバー分離により矩形が異なる場合、包含率の高い主コンテンツウィンドウを照合する
        let axArea = Double(axBounds.width * axBounds.height)
        guard axBounds.width >= 300, axBounds.height >= 300, axArea > 0 else {
            return nil
        }

        let containmentMatch = available.compactMap { entry -> ((zOrder: Int, info: CGWindowMeta), Double)? in
            if !allowOffscreenNonZeroLayer && entry.info.layer != 0 {
                return nil
            }
            let cgBounds = entry.info.bounds
            let cgArea = Double(cgBounds.width * cgBounds.height)
            guard cgArea > 0 else { return nil }
            let intersection = axBounds.intersection(cgBounds)
            guard !intersection.isNull else { return nil }
            let intersectionArea = Double(intersection.width * intersection.height)
            guard (intersectionArea / cgArea) >= 0.85,
                  (intersectionArea / axArea) >= 0.5 else {
                return nil
            }
            return (entry, intersectionArea)
        }.max { lhs, rhs in
            let lhsRank = (
                (preferOnscreen && lhs.0.info.isOnscreen) ? 1 : 0,
                doesCGWindowNameMatchTitle(lhs.0.info.name, axTitle: axTitle, applicationName: applicationName) ? 1 : 0,
                (preferredCGWindowID != nil && lhs.0.info.windowID == preferredCGWindowID) ? 1 : 0,
                hasNonEmptyCGWindowName(lhs.0.info.name) ? 1 : 0,
                lhs.1
            )
            let rhsRank = (
                (preferOnscreen && rhs.0.info.isOnscreen) ? 1 : 0,
                doesCGWindowNameMatchTitle(rhs.0.info.name, axTitle: axTitle, applicationName: applicationName) ? 1 : 0,
                (preferredCGWindowID != nil && rhs.0.info.windowID == preferredCGWindowID) ? 1 : 0,
                hasNonEmptyCGWindowName(rhs.0.info.name) ? 1 : 0,
                rhs.1
            )
            return lhsRank < rhsRank
        }

        return containmentMatch?.0
    }

    /// 近接一致の優先順位比較用値型（各フィールドが小さいほど優先）
    private struct ProximityMatchRank: Comparable {
        let layerPriority: Int
        let visibilityPriority: Int
        let titleMatchPriority: Int
        let continuityPriority: Int
        let nonEmptyNamePriority: Int
        let dist: Double
        let zOrder: Int

        /// 優先順位を比較する（小さいほど優先）
        /// - Parameters:
        ///   - lhs: 比較元のランク
        ///   - rhs: 比較先のランク
        /// - Returns: lhs を優先すべき場合は true
        static func < (lhs: ProximityMatchRank, rhs: ProximityMatchRank) -> Bool {
            let lhsPrimary = (lhs.layerPriority, lhs.visibilityPriority, lhs.titleMatchPriority, lhs.continuityPriority, lhs.nonEmptyNamePriority)
            let rhsPrimary = (rhs.layerPriority, rhs.visibilityPriority, rhs.titleMatchPriority, rhs.continuityPriority, rhs.nonEmptyNamePriority)
            if lhsPrimary != rhsPrimary {
                return lhsPrimary < rhsPrimary
            }
            if lhs.dist != rhs.dist {
                return lhs.dist < rhs.dist
            }
            return lhs.zOrder < rhs.zOrder
        }
    }

    /// 候補 CGWindow の優先順位比較用ランクを構築する（小さいほど優先）
    /// - Parameters:
    ///   - entry: 比較対象の CGWindow エントリ
    ///   - dist: AX 矩形とのマンハッタン距離
    ///   - axTitle: AXUIElement のウィンドウタイトル（任意）
    ///   - applicationName: 所有アプリケーションの表示名（任意）
    ///   - isMinimized: AX 上の最小化状態
    ///   - preferOnscreen: 画面表示中 CGWindow を優先するか
    ///   - preferredCGWindowID: 前回照合されていた CGWindow ID
    /// - Returns: 辞書順比較可能な優先度ランク
    private nonisolated static func matchPriorityTuple(
        for entry: (zOrder: Int, info: CGWindowMeta),
        dist: Double,
        axTitle: String?,
        applicationName: String?,
        isMinimized: Bool,
        preferOnscreen: Bool,
        preferredCGWindowID: UInt32?
    ) -> ProximityMatchRank {
        let layerPriority = entry.info.layer == 0 ? 0 : 1
        let visibilityPriority: Int
        if preferOnscreen && !isMinimized {
            visibilityPriority = entry.info.isOnscreen ? 0 : 1
        } else if isMinimized {
            visibilityPriority = !entry.info.isOnscreen ? 0 : 1
        } else {
            visibilityPriority = !entry.info.isOnscreen ? 0 : 1
        }
        let titleMatchPriority = doesCGWindowNameMatchTitle(
            entry.info.name,
            axTitle: axTitle,
            applicationName: applicationName
        ) ? 0 : 1
        let continuityPriority = (preferredCGWindowID != nil && entry.info.windowID == preferredCGWindowID) ? 0 : 1
        let nonEmptyNamePriority = hasNonEmptyCGWindowName(entry.info.name) ? 0 : 1
        return ProximityMatchRank(
            layerPriority: layerPriority,
            visibilityPriority: visibilityPriority,
            titleMatchPriority: titleMatchPriority,
            continuityPriority: continuityPriority,
            nonEmptyNamePriority: nonEmptyNamePriority,
            dist: dist,
            zOrder: entry.zOrder
        )
    }

    /// CGWindow の名前メタデータが空白以外の文字を含む非空文字列かを判定する
    /// - Parameter cgName: CGWindow の名前メタデータ
    /// - Returns: 非空の実名が付与されている場合は true
    private nonisolated static func hasNonEmptyCGWindowName(_ cgName: String?) -> Bool {
        guard let trimmed = cgName?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !trimmed.isEmpty
    }

    /// CGWindow の名前メタデータが AX タイトルと一致するか判定する
    /// - Parameters:
    ///   - cgName: CGWindow の名前メタデータ
    ///   - axTitle: AXUIElement のタイトル
    ///   - applicationName: 所有アプリケーションの表示名（サフィックス照合用。省略時は nil）
    /// - Returns: 双方が非空かつ一致（省略一致・アプリ名サフィックス一致含む）する場合に true
    private nonisolated static func doesCGWindowNameMatchTitle(
        _ cgName: String?,
        axTitle: String?,
        applicationName: String? = nil
    ) -> Bool {
        guard let cgName = cgName?.trimmingCharacters(in: .whitespacesAndNewlines),
              let axTitle = axTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cgName.isEmpty, !axTitle.isEmpty else {
            return false
        }
        return WindowMenuCandidatePairing.titlesMatch(
            axTitle,
            cgName,
            applicationName: applicationName
        )
    }

    /// 2つの矩形間のマンハッタン距離を計算する
    /// - Parameters:
    ///   - a: 比較元の矩形
    ///   - b: 比較先の矩形
    /// - Returns: 座標とサイズの差分合計値
    private nonisolated static func boundsDistance(_ a: CGRect, _ b: CGRect) -> Double {
        abs(Double(a.origin.x - b.origin.x))
            + abs(Double(a.origin.y - b.origin.y))
            + abs(Double(a.size.width - b.size.width))
            + abs(Double(a.size.height - b.size.height))
    }

    /// 指定の AXUIElement に対して最小化解除・メイン化・前面移動を実行する
    /// - Parameters:
    ///   - axWin: 対象の AXUIElement ウィンドウ参照
    ///   - unminimize: 最小化されている場合に解除を行うか
    private func raiseAXWindow(_ axWin: AXUIElement, unminimize: Bool) {
        Self.applyMessagingTimeout(to: axWin)
        if unminimize {
            AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(axWin, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
    }

    /// 再スキャン後のキャッシュから対象ウィンドウのみを厳密に探し出す（不一致時は別ウィンドウを返さない）
    /// - Parameters:
    ///   - pid: 所有プロセス ID
    ///   - preferredID: 優先して照合する識別子
    ///   - cgWindowID: 補助照合用の CoreGraphics ウィンドウ ID（任意）
    ///   - title: 補助照合用のウィンドウタイトル
    ///   - applicationName: 所有アプリケーションの表示名（サフィックス付き AX タイトル照合用。任意）
    /// - Returns: 一致したキャッシュエントリ（存在しない場合は nil）
    private func findCachedWindow(
        pid: Int32,
        preferredID: String,
        cgWindowID: UInt32? = nil,
        title: String,
        applicationName: String? = nil
    ) -> CachedAXWindow? {
        guard let list = cachedWindowsByPID[pid] else {
            return nil
        }
        if let cgWindowID,
           let cgIdx = list.firstIndex(where: { $0.cgWindowID == cgWindowID }) {
            return list[cgIdx]
        }
        guard let idx = Self.matchWindowIndex(
            preferredID: preferredID,
            title: title,
            applicationName: applicationName,
            items: list,
            id: { $0.id },
            windowTitle: { $0.title }
        ) else {
            return nil
        }
        return list[idx]
    }

    /// 任意の要素列から識別子またはウィンドウタイトルで対象インデックスを厳密照合する（純粋ヘルパー）
    /// - Parameters:
    ///   - preferredID: 優先して一致判定する識別子
    ///   - title: 補助照合用のウィンドウタイトル
    ///   - applicationName: 所有アプリケーションの表示名（アプリ名／プロファイル名サフィックス照合用。省略時は nil）
    ///   - items: 検索対象要素列
    ///   - id: 各要素から識別子を取り出すクロージャ
    ///   - windowTitle: 各要素からタイトルを取り出すクロージャ
    /// - Returns: 一致した要素のインデックス（一致しない場合は nil。先頭要素への曖昧フォールバックは行わない）
    nonisolated static func matchWindowIndex<T>(
        preferredID: String,
        title: String,
        applicationName: String? = nil,
        items: [T],
        id: (T) -> String,
        windowTitle: (T) -> String?
    ) -> Int? {
        if let exact = items.firstIndex(where: { id($0) == preferredID }) {
            return exact
        }
        let trimmedTarget = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty else {
            return nil
        }
        if let exactTitle = items.firstIndex(where: {
            windowTitle($0)?.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedTarget
        }) {
            return exactTitle
        }
        return items.firstIndex(where: {
            guard let candidateTitle = windowTitle($0) else { return false }
            return WindowMenuCandidatePairing.titlesMatch(
                candidateTitle,
                trimmedTarget,
                applicationName: applicationName
            )
        })
    }

    /// キャッシュ内の MRU 時刻を更新する（ウィンドウ識別子指定）
    /// - Parameters:
    ///   - pid: 所有プロセス ID
    ///   - windowID: 更新対象ウィンドウ識別子
    ///   - date: 記録するアクティブ日時
    private func updateMRUTimestamp(pid: Int32, windowID: String, date: Date) {
        guard var list = cachedWindowsByPID[pid],
              let idx = list.firstIndex(where: { $0.id == windowID }) else { return }
        list[idx].lastActivatedAt = date
        cachedWindowsByPID[pid] = list
    }

    /// キャッシュ内の MRU 時刻を更新する（AXUIElement 一致指定）
    /// - Parameters:
    ///   - pid: 所有プロセス ID
    ///   - axElement: 更新対象の AXUIElement
    ///   - date: 記録するアクティブ日時
    private func updateMRUTimestamp(pid: Int32, axElement: AXUIElement, date: Date) {
        guard var list = cachedWindowsByPID[pid],
              let idx = list.firstIndex(where: { CFEqual($0.axElement, axElement) }) else { return }
        list[idx].lastActivatedAt = date
        cachedWindowsByPID[pid] = list
    }

    /// クローズ対象ウィンドウに対応するキャッシュ済み AXUIElement を解決する
    /// - Parameter entry: クローズ対象のウィンドウ項目
    /// - Returns: 一致したキャッシュエントリ（解決できない場合は nil）
    private func resolveCachedWindowForClose(_ entry: WindowEntry) -> CachedAXWindow? {
        if let list = cachedWindowsByPID[entry.pid] {
            if let exact = list.first(where: { $0.id == entry.id }) {
                return exact
            }
            if let cgID = entry.cgWindowID,
               let byCG = list.first(where: { $0.cgWindowID == cgID }) {
                return byCG
            }
        }

        // 別スペース等で未キャッシュだった場合に備えて対象 PID の AX ウィンドウを再スキャンする
        refreshAXWindows(for: entry.pid, markFrontmostAsActive: false)
        guard let refreshed = cachedWindowsByPID[entry.pid] else { return nil }
        if let exact = refreshed.first(where: { $0.id == entry.id }) {
            return exact
        }
        if let cgID = entry.cgWindowID,
           let byCG = refreshed.first(where: { $0.cgWindowID == cgID }) {
            return byCG
        }
        // CGWindow 補完識別子 (cg-*) のみ保持していた場合はタイトル一致（省略表記・サフィックス差分含む）で補助照合する
        if entry.id.hasPrefix("cg-"), !entry.windowTitle.isEmpty {
            return refreshed.first(where: {
                guard let candidateTitle = $0.title else { return false }
                return WindowMenuCandidatePairing.titlesMatch(
                    candidateTitle,
                    entry.windowTitle,
                    applicationName: entry.applicationName
                )
            })
        }
        return nil
    }

    /// 別操作スペースに存在し未キャッシュのウィンドウに対し、必要に応じてスペース移動を行って AXUIElement を解決する
    /// - Parameter entry: クローズ対象のウィンドウ項目
    /// - Returns: 解決されたキャッシュエントリと、別スペース一時遷移を行ったかのタプル
    private func resolveCachedWindowWithSpaceFallback(_ entry: WindowEntry) async -> (window: CachedAXWindow?, didSwitchSpace: Bool) {
        if let resolved = resolveCachedWindowForClose(entry) {
            return (resolved, false)
        }

        // 別 Space 上のウィンドウ（cg-* 等）で AXUIElement が未取得の場合、
        // 「ウィンドウ」メニュー経由（利用可能なら）＋アプリアクティブ化で対象 Space へ遷移させる
        guard let app = NSRunningApplication(processIdentifier: entry.pid), !app.isTerminated else {
            return (nil, false)
        }

        if !entry.windowTitle.isEmpty,
           let menuItem = resolveWindowMenuItemElement(
               pid: entry.pid,
               windowTitle: entry.windowTitle,
               applicationName: entry.applicationName
           ) {
            Self.applyMessagingTimeout(to: menuItem)
            AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
        }
        app.activate()
        // Space 切り替えアニメーションと AX ツリー反映を待ちつつ最大約600ms再試行する
        let maxAttempts = 15
        for _ in 0..<maxAttempts {
            try? await Task.sleep(for: .milliseconds(40))
            if let resolved = resolveCachedWindowForClose(entry) {
                return (resolved, true)
            }
        }
        return (nil, true)
    }

    /// 指定された AXUIElement ウィンドウの生存確認をバックグラウンドワーカーキュー上で非同期実行する
    /// - Parameters:
    ///   - axElement: 確認対象の AXUIElement
    ///   - pid: 所有プロセスの PID
    /// - Returns: ウィンドウがまだ生存している場合は true、閉じられて消滅している場合は false
    private func checkAXWindowAliveInBackground(_ axElement: AXUIElement, pid: Int32) async -> Bool {
        let wrapped = SendableAXElement(value: axElement)
        let queue = axWorkerQueue
        return await withCheckedContinuation { continuation in
            queue.async {
                let alive = Self.isAXWindowAliveInProcess(wrapped.value, pid: pid)
                continuation.resume(returning: alive)
            }
        }
    }

    /// 指定 PID の生存中 CGWindowID 集合をバックグラウンドワーカーキュー上で非同期取得する
    /// - Parameter pid: 所有プロセスの PID
    /// - Returns: 生存中の CGWindowID 集合
    private func fetchSurvivingCGWindowIDsInBackground(for pid: Int32) async -> Set<UInt32> {
        let queue = axWorkerQueue
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.fetchSurvivingCGWindowIDs(for: pid))
            }
        }
    }

    /// 指定された AXUIElement ウィンドウが現在もアプリケーション上に存在しているかを判定する（バックグラウンド実行安全）
    /// - Parameters:
    ///   - axElement: 確認対象の AXUIElement
    ///   - pid: 所有プロセスの PID
    /// - Returns: ウィンドウがまだ生存している場合は true、閉じられて消滅している場合は false
    private nonisolated static func isAXWindowAliveInProcess(_ axElement: AXUIElement, pid: Int32) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        applyMessagingTimeout(to: appElement)
        let (axWindows, windowsAttributeSucceeded) = collectAXWindowsWithStatus(for: appElement)
        if let knownResult = evaluateAXWindowLivenessFromList(
            windowsAttributeSucceeded: windowsAttributeSucceeded,
            containsTarget: axWindows.contains { CFEqual($0, axElement) }
        ) {
            return knownResult
        }

        // ウィンドウ一覧取得に失敗した場合は対象要素のロール読み取り可否で生存確認する
        applyMessagingTimeout(to: axElement)
        var roleRef: CFTypeRef?
        return AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleRef) == .success
    }

    /// AX ウィンドウ一覧取得結果から対象ウィンドウの生存可否を判定する純粋ロジック
    /// - Parameters:
    ///   - windowsAttributeSucceeded: `kAXWindowsAttribute` の読み取り自体が成功したか
    ///   - containsTarget: 収集済み一覧に対象ウィンドウが含まれていたか
    /// - Returns: 生存判定が確定した場合は真偽値、一覧取得失敗時はフォールバック判定を促す nil
    nonisolated static func evaluateAXWindowLivenessFromList(
        windowsAttributeSucceeded: Bool,
        containsTarget: Bool
    ) -> Bool? {
        if containsTarget {
            return true
        }
        if windowsAttributeSucceeded {
            return false
        }
        return nil
    }

    /// クローズ確認済みのウィンドウを内部キャッシュから除去する
    /// - Parameters:
    ///   - pid: 所有プロセスの PID
    ///   - windowID: 除外するウィンドウ識別子
    ///   - axElement: 除外する AXUIElement 参照
    private func removeCachedWindow(pid: Int32, windowID: String, axElement: AXUIElement) {
        guard var list = cachedWindowsByPID[pid] else { return }
        list.removeAll { $0.id == windowID || CFEqual($0.axElement, axElement) }
        if list.isEmpty {
            cachedWindowsByPID.removeValue(forKey: pid)
        } else {
            cachedWindowsByPID[pid] = list
        }
    }

    // MARK: - AXObserver 管理

    /// 指定 PID に対して AXObserver を作成しウィンドウイベント通知を登録する
    /// - Parameter pid: 監視対象プロセスの PID
    private func registerObserver(for pid: Int32) {
        guard observersByPID[pid] == nil else { return }

        var observerRef: AXObserver?
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let err = AXObserverCreate(pid, { _, element, notification, refcon in
            guard let refcon else { return }
            let notifName = notification as String
            let service = Unmanaged<WindowService>.fromOpaque(refcon).takeUnretainedValue()
            // CFRunLoopGetMain に登録されたコールバックは既にメインスレッド上のため不要な Task 生成を回避する
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    service.handleAXNotification(element: element, notification: notifName)
                }
            } else {
                let wrappedElement = SendableAXElement(value: element)
                Task { @MainActor in
                    service.handleAXNotification(element: wrappedElement.value, notification: notifName)
                }
            }
        }, &observerRef)

        guard err == .success, let observer = observerRef else { return }

        let appElement = AXUIElementCreateApplication(pid)
        Self.applyMessagingTimeout(to: appElement)
        let notifications = [
            kAXWindowCreatedNotification,
            kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXTitleChangedNotification,
            kAXUIElementDestroyedNotification
        ]
        for notif in notifications {
            AXObserverAddNotification(observer, appElement, notif as CFString, selfPtr)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observersByPID[pid] = observer
    }

    /// 指定 PID の AXObserver と保留中のデバウンス更新タスクを解除して破棄する
    /// - Parameter pid: 監視を解除するプロセスの PID
    private func unregisterObserver(for pid: Int32) {
        pendingRefreshTasksByPID.removeValue(forKey: pid)?.cancel()
        pendingMenuRefreshTasksByPID.removeValue(forKey: pid)?.cancel()
        pendingPrefetchReasonByPID.removeValue(forKey: pid)
        guard let observer = observersByPID.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    /// AXObserver コールバックを受信し、高頻度通知をデバウンスしながらバックグラウンドでキャッシュと MRU を更新する
    /// - Parameters:
    ///   - element: イベントが発生した AXUIElement
    ///   - notification: 通知名
    private func handleAXNotification(element: AXUIElement, notification: String) {
        guard isObserving else { return }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != 0 else { return }

        if notification == kAXUIElementDestroyedNotification {
            var destroyedCandidates: [(windowID: String, cgWindowID: UInt32?)] = []

            if var list = cachedWindowsByPID[pid] {
                let matchedCached = list.filter { CFEqual($0.axElement, element) }
                for cached in matchedCached {
                    destroyedCandidates.append((windowID: cached.id, cgWindowID: cached.cgWindowID))
                }
                list.removeAll { CFEqual($0.axElement, element) }
                if list.isEmpty {
                    cachedWindowsByPID.removeValue(forKey: pid)
                } else {
                    cachedWindowsByPID[pid] = list
                }
            }

            let matchedTrackedKeys = trackedCloseTargetsByEntryID.compactMap { key, target -> String? in
                guard target.pid == pid, CFEqual(target.axElement, element) else { return nil }
                return key
            }
            for key in matchedTrackedKeys {
                if let tracked = trackedCloseTargetsByEntryID.removeValue(forKey: key) {
                    destroyedCandidates.append((windowID: tracked.entryID, cgWindowID: tracked.cgWindowID))
                }
            }

            let events = Self.makeDestroyedWindowLifecycleEvents(
                from: destroyedCandidates,
                pid: pid
            )
            for event in events {
                onWindowLifecycleEvent?(event)
            }

            // ウィンドウ破棄直後に古いメニュー項目キャッシュが裏方 CGWindow へ割り当てられるのを防ぐ
            cachedWindowMenuByPID.removeValue(forKey: pid)
            scheduleBackgroundRefresh(
                for: pid,
                markFrontmostAsActive: false,
                debounce: Self.focusChangeDebounceDuration,
                allowDisplaySpanningReplacement: true
            )
            return
        }

        let isActivationEvent = notification == kAXFocusedWindowChangedNotification
            || notification == kAXMainWindowChangedNotification
            || notification == kAXWindowCreatedNotification
        let isStructureOrStateEvent = isActivationEvent
            || notification == kAXWindowMiniaturizedNotification
            || notification == kAXWindowDeminiaturizedNotification

        let now = Date()
        if isActivationEvent {
            // キャッシュ済みウィンドウであれば MRU 時刻だけは即時反映する
            updateMRUTimestamp(pid: pid, axElement: element, date: now)
        }

        let debounce = isStructureOrStateEvent ? Self.focusChangeDebounceDuration : Self.titleChangeDebounceDuration
        let prefetchReason = Self.capturePrefetchReason(forAXNotification: notification)
        scheduleBackgroundRefresh(
            for: pid,
            markFrontmostAsActive: false,
            debounce: debounce,
            activatedElement: isActivationEvent ? SendableAXElement(value: element) : nil,
            activatedAt: isActivationEvent ? now : nil,
            allowDisplaySpanningReplacement: true,
            prefetchReasonOnCompletion: prefetchReason
        )
    }

    /// AXObserver 通知種別からバックグラウンド事前キャプチャを促すべき契機を判定する純粋関数
    /// - Parameter notification: 受信した AX 通知名
    /// - Returns: 事前キャプチャ対象となる契機種別（対象外通知は nil）
    nonisolated static func capturePrefetchReason(
        forAXNotification notification: String
    ) -> WindowCapturePrefetchReason? {
        if notification == kAXWindowCreatedNotification {
            return .windowCreated
        }
        if notification == kAXWindowDeminiaturizedNotification {
            return .windowDeminiaturized
        }
        return nil
    }

    /// 破棄されたキャッシュ・追跡対象ウィンドウ群から重複排除したリアルタイム通知イベント一覧を構築する
    /// - Parameters:
    ///   - candidates: 一致したウィンドウ ID と CGWindow ID の組一覧
    ///   - pid: 所有プロセスの PID
    /// - Returns: 通知すべき `WindowLifecycleEvent` 配列（対象ウィンドウに一致しない子要素破棄時は空配列）
    nonisolated static func makeDestroyedWindowLifecycleEvents(
        from candidates: [(windowID: String, cgWindowID: UInt32?)],
        pid: Int32
    ) -> [WindowLifecycleEvent] {
        var seenWindowIDs = Set<String>()
        var events: [WindowLifecycleEvent] = []
        for candidate in candidates {
            guard seenWindowIDs.insert(candidate.windowID).inserted else { continue }
            events.append(
                .windowClosed(
                    windowID: candidate.windowID,
                    cgWindowID: candidate.cgWindowID,
                    pid: pid
                )
            )
        }
        return events
    }

    /// 今回スキャンから消えたキャッシュ要素を「同一スペース内のタブ切り替えで消えた旧タブ」として削除すべきか判定する
    /// - Parameters:
    ///   - oldBounds: 今回スキャンから消えたキャッシュ要素の矩形
    ///   - oldIsMinimized: 今回スキャンから消えたキャッシュ要素の最小化状態
    ///   - oldCGWindowID: 今回スキャンから消えたキャッシュ要素に紐付いていた CGWindowID（任意）
    ///   - newBounds: 今回スキャンに存在する有効ウィンドウの矩形
    ///   - newIsMinimized: 今回スキャンに存在する有効ウィンドウの最小化状態
    ///   - newCGWindowID: 置換先候補ウィンドウに紐付く CGWindowID（任意）
    ///   - survivingCGWindowIDs: 現在システム上に生存している該当アプリの CGWindowID 集合
    ///   - allowDisplaySpanningReplacement: 同一スペース上の AX イベント由来でタブ置換を許可するか
    ///   - screenBounds: 接続中ディスプレイの矩形一覧
    /// - Returns: 旧タブとしてキャッシュから除去すべき場合は true
    nonisolated static func shouldEvictCachedWindowAsReplacedTab(
        oldBounds: CGRect?,
        oldIsMinimized: Bool,
        oldCGWindowID: UInt32?,
        newBounds: CGRect?,
        newIsMinimized: Bool,
        newCGWindowID: UInt32?,
        survivingCGWindowIDs: Set<UInt32>,
        allowDisplaySpanningReplacement: Bool,
        screenBounds: [WindowBounds]
    ) -> Bool {
        // 全体再スキャンやスペース移動時は別スペースの同矩形ウィンドウを誤削除しない
        guard allowDisplaySpanningReplacement else {
            return false
        }
        // 置換先とは異なる独立 CGWindowID が現在もシステム上に生存している場合は別スペース等の実ウィンドウとして保持する
        if let oldCGWindowID,
           oldCGWindowID != newCGWindowID,
           survivingCGWindowIDs.contains(oldCGWindowID) {
            return false
        }
        return isReplacedTabBounds(
            oldBounds: oldBounds,
            oldIsMinimized: oldIsMinimized,
            newBounds: newBounds,
            newIsMinimized: newIsMinimized,
            allowDisplaySpanningReplacement: allowDisplaySpanningReplacement,
            screenBounds: screenBounds
        )
    }

    /// 対象ウィンドウが現在の操作スペース上に在籍しているかを純粋ロジックで判定する
    /// - Parameters:
    ///   - isPresentInLatestAXScan: 直近の AX スキャン（`kAXFocusedWindow` 等の別スペース補完を含む）に含まれたか
    ///   - isOnScreen: CoreGraphics 照合上の画面表示状態（別スペース時は false）
    ///   - isMinimized: 最小化状態かどうか
    /// - Returns: 現在スペース上のウィンドウとして直接前面化できる場合は true、別スペース遷移が必要な場合は false
    nonisolated static func isWindowInCurrentSpace(
        isPresentInLatestAXScan: Bool,
        isOnScreen: Bool?,
        isMinimized: Bool
    ) -> Bool {
        guard isPresentInLatestAXScan else {
            return false
        }
        // kAXFocusedWindowAttribute 等で AX 捕捉されていても、非最小化かつ isOnScreen == false なら別スペースにある
        if isOnScreen == false && !isMinimized {
            return false
        }
        return true
    }

    /// ウィンドウアクティブ化時の実行計画を純粋ロジックで決定する
    /// - Parameters:
    ///   - hasTargetAX: 対象ウィンドウのキャッシュ済み AXUIElement が存在するか
    ///   - isPresentInCurrentSpace: 対象ウィンドウが直近の現在スペーススキャンに存在したか
    ///   - menuNavigationSucceeded: 「ウィンドウ」メニュー項目の押下に成功したか
    /// - Returns: 競合しないアクティブ化手順を表す `ActivationPlan`
    nonisolated static func makeActivationPlan(
        hasTargetAX: Bool,
        isPresentInCurrentSpace: Bool,
        menuNavigationSucceeded: Bool
    ) -> ActivationPlan {
        let needsMenuNavigation = !hasTargetAX || !isPresentInCurrentSpace
        if !needsMenuNavigation {
            return ActivationPlan(
                shouldActivateApplicationImmediately: true,
                shouldRaiseTargetAXImmediately: true,
                usesSteppedSpaceFollowUp: false
            )
        }
        if menuNavigationSucceeded {
            // メニュー押下が成功した場合は即時の app.activate() 並走による別ウィンドウ誤前面化を抑止し、フォローアップで確定する
            return ActivationPlan(
                shouldActivateApplicationImmediately: false,
                shouldRaiseTargetAXImmediately: false,
                usesSteppedSpaceFollowUp: true
            )
        }
        return ActivationPlan(
            shouldActivateApplicationImmediately: true,
            shouldRaiseTargetAXImmediately: hasTargetAX,
            usesSteppedSpaceFollowUp: true
        )
    }

    /// メニュー項目キャッシュが有効期限（TTL）内であるかを判定する
    /// - Parameters:
    ///   - fetchedAt: キャッシュを取得した日時
    ///   - now: 判定基準となる現在日時
    ///   - ttl: 有効期間（秒）
    /// - Returns: 経過時間が `0...ttl` の範囲内であれば true
    nonisolated static func isMenuCacheFresh(
        fetchedAt: Date,
        now: Date = Date(),
        ttl: TimeInterval = windowMenuCacheTTL
    ) -> Bool {
        let elapsed = now.timeIntervalSince(fetchedAt)
        return elapsed >= 0 && elapsed <= ttl
    }

    /// 指定された PID の現在生存中の CGWindowID 集合を取得する
    /// - Parameter pid: 対象アプリケーションのプロセス ID
    /// - Returns: システム上に存在する CGWindowID の集合
    private nonisolated static func fetchSurvivingCGWindowIDs(for pid: Int32) -> Set<UInt32> {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids = Set<UInt32>()
        for dict in rawList {
            guard (dict[kCGWindowOwnerPID as String] as? Int32) == pid,
                  let windowID = dict[kCGWindowNumber as String] as? UInt32 else {
                continue
            }
            ids.insert(windowID)
        }
        return ids
    }

    /// 今回スキャンから消えたキャッシュ要素が、タブ切り替え等により同一座標の新ウィンドウへ置き換わった旧タブかを判定する
    /// - Parameters:
    ///   - oldBounds: 今回スキャンから消えたキャッシュ要素の矩形
    ///   - oldIsMinimized: 今回スキャンから消えたキャッシュ要素の最小化状態
    ///   - newBounds: 今回スキャンに存在する有効ウィンドウの矩形
    ///   - newIsMinimized: 今回スキャンに存在する有効ウィンドウの最小化状態
    ///   - allowDisplaySpanningReplacement: フルスクリーン級ウィンドウでのタブ置換を許可するか（スペース移動直後は false）
    ///   - screenBounds: 接続中ディスプレイの矩形一覧
    /// - Returns: 旧タブとしてキャッシュから除去すべき場合は true
    nonisolated static func isReplacedTabBounds(
        oldBounds: CGRect?,
        oldIsMinimized: Bool,
        newBounds: CGRect?,
        newIsMinimized: Bool,
        allowDisplaySpanningReplacement: Bool,
        screenBounds: [WindowBounds]
    ) -> Bool {
        guard oldIsMinimized == newIsMinimized,
              let oRect = oldBounds,
              let nRect = newBounds else {
            return false
        }
        let oBounds = WindowBounds(
            x: Double(oRect.origin.x),
            y: Double(oRect.origin.y),
            width: Double(oRect.size.width),
            height: Double(oRect.size.height)
        )
        let nBounds = WindowBounds(
            x: Double(nRect.origin.x),
            y: Double(nRect.origin.y),
            width: Double(nRect.size.width),
            height: Double(nRect.size.height)
        )
        guard WindowFilter.areBoundsNearlyEqual(oBounds, nBounds) else {
            return false
        }
        if WindowFilter.isDisplaySpanningBounds(oBounds, screenBounds: screenBounds) {
            return allowDisplaySpanningReplacement
        }
        return true
    }

    // MARK: - AX スナップショット収集・属性読み取り（nonisolated）

    /// 指定された AXUIElement に短い IPC タイムアウトを設定する
    /// - Parameter element: タイムアウトを設定する AXUIElement
    private nonisolated static func applyMessagingTimeout(to element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, axMessagingTimeoutSeconds)
    }

    /// 読み取った AX ロール／サブロールがスイッチャー候補用キャッシュとして保持対象か判定する純粋関数
    /// - Parameters:
    ///   - role: 取得された `kAXRoleAttribute`
    ///   - subrole: 取得された `kAXSubroleAttribute`
    /// - Returns: キャッシュ対象となるウィンドウ要素であれば true
    nonisolated static func shouldCacheAXWindowAttributes(role: String?, subrole: String?) -> Bool {
        if let role, !allowedCachedRoles.contains(role) {
            return false
        }
        if let subrole, !allowedCachedSubroles.contains(subrole) {
            return false
        }
        return true
    }

    /// AXError がプロセス無応答・API 無効化等の通信打ち切り対象かを判定する
    /// - Parameter error: AXUIElement API の戻り値エラーコード
    /// - Returns: 同一対象への後続 IPC 呼び出しを即座に打ち切るべき場合は true
    private nonisolated static func isAXCommunicationAbortError(_ error: AXError) -> Bool {
        error == .cannotComplete || error == .apiDisabled || error == .notImplemented
    }

    /// 指定 PID のアプリから現在の AX ウィンドウ一覧と属性をバックグラウンド安全に収集する
    /// - Parameter pid: 対象プロセス ID
    /// - Returns: 収集された ScannedAXWindowSnapshot 配列
    private nonisolated static func fetchAXWindowSnapshots(for pid: Int32) -> [ScannedAXWindowSnapshot] {
        let appElement = AXUIElementCreateApplication(pid)
        applyMessagingTimeout(to: appElement)
        let axWindows = collectAXWindows(for: appElement)
        guard !axWindows.isEmpty else {
            return []
        }

        var snapshots: [ScannedAXWindowSnapshot] = []
        snapshots.reserveCapacity(axWindows.count)

        for axWin in axWindows {
            applyMessagingTimeout(to: axWin)

            let roleResult = copyStringAttributeWithError(axWin, attribute: kAXRoleAttribute as CFString)
            if isAXCommunicationAbortError(roleResult.error) {
                // アプリがハング・タイムアウトしている場合は残りの属性／ウィンドウへの連続タイムアウトを回避する
                break
            }
            if let role = roleResult.value, !allowedCachedRoles.contains(role) {
                continue
            }

            let subroleResult = copyStringAttributeWithError(axWin, attribute: kAXSubroleAttribute as CFString)
            if isAXCommunicationAbortError(subroleResult.error) {
                break
            }
            guard shouldCacheAXWindowAttributes(role: roleResult.value, subrole: subroleResult.value) else {
                continue
            }

            let titleResult = copyStringAttributeWithError(axWin, attribute: kAXTitleAttribute as CFString)
            if isAXCommunicationAbortError(titleResult.error) {
                break
            }
            let boundsResult = copyBoundsWithError(axWin)
            if isAXCommunicationAbortError(boundsResult.error) {
                break
            }
            let minimizedResult = copyBoolAttributeWithError(axWin, attribute: kAXMinimizedAttribute as CFString)
            if isAXCommunicationAbortError(minimizedResult.error) {
                break
            }

            snapshots.append(
                ScannedAXWindowSnapshot(
                    uniqueID: "ax-\(pid)-\(CFHash(axWin))",
                    axElement: SendableAXElement(value: axWin),
                    role: roleResult.value,
                    title: titleResult.value,
                    subrole: subroleResult.value,
                    bounds: boundsResult.value,
                    isMinimized: minimizedResult.value ?? false
                )
            )
        }
        return snapshots
    }

    /// アプリケーション要素から kAXWindowsAttribute に加え、フォーカス／メインウィンドウを重複排除して収集する
    /// - Parameter appElement: 対象アプリケーションの AXUIElement
    /// - Returns: 重複のないウィンドウ AXUIElement 配列
    private nonisolated static func collectAXWindows(for appElement: AXUIElement) -> [AXUIElement] {
        collectAXWindowsWithStatus(for: appElement).windows
    }

    /// アプリケーション要素からウィンドウ AXUIElement 配列と `kAXWindowsAttribute` 取得成否を併せて収集する
    /// - Parameter appElement: 対象アプリケーションの AXUIElement
    /// - Returns: 収集したウィンドウ配列と `kAXWindowsAttribute` が成功したかの組
    private nonisolated static func collectAXWindowsWithStatus(
        for appElement: AXUIElement
    ) -> (windows: [AXUIElement], windowsAttributeSucceeded: Bool) {
        var result: [AXUIElement] = []
        var windowsRef: CFTypeRef?
        let windowsStatus = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        if isAXCommunicationAbortError(windowsStatus) {
            // アプリがタイムアウト／API無効の場合はフォーカス・メイン補完での追加タイムアウト連鎖を防ぐ
            return (result, false)
        }
        let windowsAttributeSucceeded = (windowsStatus == .success)
        if windowsAttributeSucceeded,
           let axWindows = windowsRef as? [AXUIElement] {
            result = axWindows
        }

        // kAXWindowsAttribute に含まれないフローティングパネルや別スペースの現在ウィンドウを補完する
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var extraRef: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(appElement, attribute as CFString, &extraRef)
            if isAXCommunicationAbortError(status) {
                break
            }
            guard status == .success,
                  let extraValue = extraRef,
                  CFGetTypeID(extraValue) == AXUIElementGetTypeID() else {
                continue
            }
            let extraWindow = extraValue as! AXUIElement
            if !result.contains(where: { CFEqual($0, extraWindow) }) {
                result.append(extraWindow)
            }
        }

        return (result, windowsAttributeSucceeded)
    }

    /// 文字列属性を読み取る
    /// - Parameters:
    ///   - element: 対象の AXUIElement
    ///   - attribute: 読み取る属性名
    /// - Returns: 取得された文字列（失敗時は nil）
    private nonisolated static func copyStringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
        copyStringAttributeWithError(element, attribute: attribute).value
    }

    /// 文字列属性と AXError をあわせて読み取る
    /// - Parameters:
    ///   - element: 対象の AXUIElement
    ///   - attribute: 読み取る属性名
    /// - Returns: 取得された文字列と AXError のタプル
    private nonisolated static func copyStringAttributeWithError(
        _ element: AXUIElement,
        attribute: CFString
    ) -> (value: String?, error: AXError) {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return (nil, status) }
        return (value as? String, status)
    }

    /// 真偽値属性を読み取る
    /// - Parameters:
    ///   - element: 対象の AXUIElement
    ///   - attribute: 読み取る属性名
    /// - Returns: 取得された真偽値（失敗時は nil）
    private nonisolated static func copyBoolAttribute(_ element: AXUIElement, attribute: CFString) -> Bool? {
        copyBoolAttributeWithError(element, attribute: attribute).value
    }

    /// 真偽値属性と AXError をあわせて読み取る
    /// - Parameters:
    ///   - element: 対象の AXUIElement
    ///   - attribute: 読み取る属性名
    /// - Returns: 取得された真偽値と AXError のタプル
    private nonisolated static func copyBoolAttributeWithError(
        _ element: AXUIElement,
        attribute: CFString
    ) -> (value: Bool?, error: AXError) {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return (nil, status) }
        return (value as? Bool, status)
    }

    /// 位置 (kAXPositionAttribute) とサイズ (kAXSizeAttribute) を組み合わせて CGRect と AXError を返す
    /// - Parameter element: 対象の AXUIElement
    /// - Returns: 取得されたウィンドウ矩形と最終 AXError のタプル
    private nonisolated static func copyBoundsWithError(_ element: AXUIElement) -> (value: CGRect?, error: AXError) {
        var posRef: CFTypeRef?
        let posStatus = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        guard posStatus == .success, let posVal = posRef else {
            return (nil, posStatus)
        }

        var sizeRef: CFTypeRef?
        let sizeStatus = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        guard sizeStatus == .success, let sizeVal = sizeRef else {
            return (nil, sizeStatus)
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else {
            return (nil, .failure)
        }
        return (CGRect(origin: origin, size: size), .success)
    }

    // MARK: - 「ウィンドウ」メニュー補完ヘルパー

    /// メニューキャッシュの有無と鮮度から取得・利用方針を決定する純粋関数
    /// - Parameters:
    ///   - hasCachedState: キャッシュ済みメニュー状態が存在するか
    ///   - isFresh: キャッシュが TTL 以内か
    ///   - allowStaleWhileRevalidate: Stale-While-Revalidate を許可するか（通常監視中は true）
    /// - Returns: 実行すべき `MenuCacheLookupAction`
    nonisolated static func menuCacheLookupAction(
        hasCachedState: Bool,
        isFresh: Bool,
        allowStaleWhileRevalidate: Bool
    ) -> MenuCacheLookupAction {
        guard hasCachedState else {
            return .fetchSynchronously
        }
        if isFresh {
            return .useFresh
        }
        return allowStaleWhileRevalidate ? .useStaleAndRefreshInBackground : .fetchSynchronously
    }

    /// AX で未捕捉の CGWindow 補完候補（別スペース等）またはタイトル空の標準 AX 候補を含む PID に対して、アプリの「ウィンドウ」メニューからタイトルを補完する
    /// - Parameter candidates: 構築済みの生ウィンドウ候補一覧
    /// - Returns: タイトル補完および余剰ゴースト候補整理済みの候補一覧
    private func enrichCandidatesWithWindowMenu(_ candidates: [RawWindowCandidate]) -> [RawWindowCandidate] {
        // 実質サイズを持ちスイッチャー対象となり得る cg-* 候補、またはタイトル空の標準 AX 候補が存在する PID のみ対象とする
        let targetPIDs = Set(
            candidates.compactMap { candidate -> Int32? in
                guard WindowMenuCandidatePairing.needsMenuEnrichment(candidate) else { return nil }
                return candidate.pid
            }
        )
        menuEnrichmentTargetPIDs = targetPIDs
        guard !targetPIDs.isEmpty else {
            return candidates
        }

        let now = Date()
        for pid in targetPIDs {
            let existing = cachedWindowMenuByPID[pid]
            let isFresh = existing.map { Self.isMenuCacheFresh(fetchedAt: $0.fetchedAt, now: now) } ?? false
            let action = Self.menuCacheLookupAction(
                hasCachedState: existing != nil,
                isFresh: isFresh,
                allowStaleWhileRevalidate: isObserving
            )
            switch action {
            case .useFresh:
                continue
            case .useStaleAndRefreshInBackground:
                scheduleBackgroundMenuRefresh(for: pid)
            case .fetchSynchronously:
                let items = Self.fetchWindowMenuItems(for: pid)
                cachedWindowMenuByPID[pid] = CachedWindowMenuState(items: items, fetchedAt: now)
            }
        }

        let candidatesByPID = Dictionary(grouping: candidates, by: \.pid)
        var enriched: [RawWindowCandidate] = []
        enriched.reserveCapacity(candidates.count)
        var processedPIDs = Set<Int32>()

        for candidate in candidates {
            let pid = candidate.pid
            guard !processedPIDs.contains(pid) else { continue }
            processedPIDs.insert(pid)

            let group = candidatesByPID[pid] ?? []
            if targetPIDs.contains(pid) {
                let menuSnapshots = cachedWindowMenuByPID[pid]?.items.map(\.snapshot) ?? []
                enriched.append(
                    contentsOf: WindowMenuCandidatePairing.applyMenuTitles(
                        to: group,
                        menuItems: menuSnapshots
                    )
                )
            } else {
                enriched.append(contentsOf: group)
            }
        }
        return enriched
    }

    /// 「ウィンドウ」メニュー項目を押下し、キャッシュ参照が失効して失敗した場合は最新メニューを再取得して 1 回リトライする
    /// - Parameters:
    ///   - pid: 対象アプリケーションのプロセス ID
    ///   - windowTitle: 照合するウィンドウタイトル
    ///   - applicationName: 所有アプリケーションの表示名（サフィックス照合用。省略時は nil）
    ///   - preferUnchecked: チェックマーク無しの項目を優先するか
    ///   - forceFresh: 初回からキャッシュを無視して最新メニューを取得するか
    /// - Returns: メニュー項目の押下に成功した場合は true
    private func performMenuNavigationWithRetry(
        pid: Int32,
        windowTitle: String,
        applicationName: String? = nil,
        preferUnchecked: Bool,
        forceFresh: Bool = false
    ) -> Bool {
        // 既存キャッシュ要素が利用可能であれば TTL 超過時でもまず直接押下を試み、失敗時のみ最新メニューを再取得する
        if !forceFresh,
           let cached = cachedWindowMenuByPID[pid],
           let matchedCached = Self.findMatchingMenuItem(
               in: cached.items,
               title: windowTitle,
               applicationName: applicationName,
               preferUnchecked: preferUnchecked
           ) {
            let cachedElement = matchedCached.axElement.value
            Self.applyMessagingTimeout(to: cachedElement)
            if AXUIElementPerformAction(cachedElement, kAXPressAction as CFString) == .success {
                return true
            }
        }

        // キャッシュ未保持または押下失敗時は最新メニューを再取得して押下を試行する
        cachedWindowMenuByPID.removeValue(forKey: pid)
        guard let freshElement = resolveWindowMenuItemElement(
            pid: pid,
            windowTitle: windowTitle,
            applicationName: applicationName,
            preferUnchecked: preferUnchecked,
            forceRefresh: true
        ) else {
            return false
        }
        Self.applyMessagingTimeout(to: freshElement)
        return AXUIElementPerformAction(freshElement, kAXPressAction as CFString) == .success
    }

    /// 非アクティブ時や直接押下が無視されるアプリ向けに「ウィンドウ」メニューバー項目を展開してから対象項目を押下する
    /// - Parameters:
    ///   - pid: 対象アプリケーションのプロセス ID
    ///   - windowTitle: 照合するウィンドウタイトル
    ///   - applicationName: 所有アプリケーションの表示名（サフィックス照合用。省略時は nil）
    ///   - preferUnchecked: チェックマーク無しの項目を優先するか
    /// - Returns: 対象メニュー項目の押下に成功した場合は true
    private func performMenuNavigationViaMenuOpen(
        pid: Int32,
        windowTitle: String,
        applicationName: String? = nil,
        preferUnchecked: Bool
    ) async -> Bool {
        guard let barItem = Self.findWindowMenuBarItem(for: pid) else {
            return false
        }
        Self.applyMessagingTimeout(to: barItem)
        guard AXUIElementPerformAction(barItem, kAXPressAction as CFString) == .success else {
            return false
        }

        // メニュー項目の生成・検証が完了するまで短時間待機してから最新項目を押下する
        try? await Task.sleep(for: .milliseconds(30))
        guard !Task.isCancelled else {
            AXUIElementPerformAction(barItem, kAXCancelAction as CFString)
            return false
        }

        let freshItems = Self.fetchWindowMenuItems(fromMenuBarItem: barItem)
        cachedWindowMenuByPID[pid] = CachedWindowMenuState(items: freshItems, fetchedAt: Date())
        guard let matched = Self.findMatchingMenuItem(
            in: freshItems,
            title: windowTitle,
            applicationName: applicationName,
            preferUnchecked: preferUnchecked
        ) else {
            AXUIElementPerformAction(barItem, kAXCancelAction as CFString)
            return false
        }

        let targetElement = matched.axElement.value
        Self.applyMessagingTimeout(to: targetElement)
        let status = AXUIElementPerformAction(targetElement, kAXPressAction as CFString)
        if status != .success {
            AXUIElementPerformAction(barItem, kAXCancelAction as CFString)
            return false
        }
        return true
    }

    /// 指定された PID とウィンドウタイトルに対応する「ウィンドウ」メニュー項目の AXUIElement を解決する
    /// - Parameters:
    ///   - pid: 対象アプリケーションのプロセス ID
    ///   - windowTitle: 照合するウィンドウタイトル
    ///   - applicationName: 所有アプリケーションの表示名（サフィックス照合用。省略時は nil）
    ///   - preferUnchecked: チェックマーク無しの項目を優先するか
    ///   - forceRefresh: キャッシュを無視して強制再取得するか
    /// - Returns: 一致したメニュー項目の AXUIElement（存在しない場合は nil）
    private func resolveWindowMenuItemElement(
        pid: Int32,
        windowTitle: String,
        applicationName: String? = nil,
        preferUnchecked: Bool = false,
        forceRefresh: Bool = false
    ) -> AXUIElement? {
        let now = Date()
        if !forceRefresh,
           let cached = cachedWindowMenuByPID[pid],
           Self.isMenuCacheFresh(fetchedAt: cached.fetchedAt, now: now),
           let matched = Self.findMatchingMenuItem(
               in: cached.items,
               title: windowTitle,
               applicationName: applicationName,
               preferUnchecked: preferUnchecked
           ) {
            return matched.axElement.value
        }

        // キャッシュが存在しないか TTL 超過時は最新メニューを再取得して照合する
        let freshItems = Self.fetchWindowMenuItems(for: pid)
        cachedWindowMenuByPID[pid] = CachedWindowMenuState(items: freshItems, fetchedAt: Date())
        return Self.findMatchingMenuItem(
            in: freshItems,
            title: windowTitle,
            applicationName: applicationName,
            preferUnchecked: preferUnchecked
        )?.axElement.value
    }

    /// スキャン済みメニュー項目一覧から指定タイトルに一致する項目を探す（完全一致優先・省略表現・サフィックス・未チェック優先対応）
    /// - Parameters:
    ///   - items: 抽出済みのメニュー項目一覧
    ///   - title: 照合対象のウィンドウタイトル
    ///   - applicationName: 所有アプリケーションの表示名（サフィックス照合用。省略時は nil）
    ///   - preferUnchecked: チェックマーク無しの項目を優先するか
    /// - Returns: 一致したメニュー項目（見つからない場合は nil）
    private nonisolated static func findMatchingMenuItem(
        in items: [ScannedWindowMenuItem],
        title: String,
        applicationName: String? = nil,
        preferUnchecked: Bool = false
    ) -> ScannedWindowMenuItem? {
        let snapshots = items.map(\.snapshot)
        guard let idx = WindowMenuCandidatePairing.matchingMenuItemIndex(
            for: title,
            in: snapshots,
            preferUnchecked: preferUnchecked,
            applicationName: applicationName
        ), items.indices.contains(idx) else {
            return nil
        }
        return items[idx]
    }

    /// 指定 PID のアプリケーションから AXMenuBar 上の「ウィンドウ」メニューバー項目を探索する
    /// - Parameter pid: 対象アプリケーションのプロセス ID
    /// - Returns: 「ウィンドウ」メニューバー項目の AXUIElement（見つからない場合は nil）
    private nonisolated static func findWindowMenuBarItem(for pid: Int32) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        applyMessagingTimeout(to: appElement)

        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBarVal = menuBarRef,
              CFGetTypeID(menuBarVal) == AXUIElementGetTypeID() else {
            return nil
        }

        let menuBar = menuBarVal as! AXUIElement
        applyMessagingTimeout(to: menuBar)
        guard let barItems = copyAXChildren(menuBar) else { return nil }

        for barItem in barItems {
            applyMessagingTimeout(to: barItem)
            let titleResult = copyStringAttributeWithError(barItem, attribute: kAXTitleAttribute as CFString)
            if isAXCommunicationAbortError(titleResult.error) {
                break
            }
            if let barTitle = titleResult.value,
               WindowMenuExtractor.isWindowMenuBarTitle(barTitle) {
                return barItem
            }
        }
        return nil
    }

    /// 指定 PID のアプリケーションから AXMenuBar 経由で「ウィンドウ」メニュー内の実ウィンドウ項目群を収集する
    /// - Parameter pid: 対象アプリケーションのプロセス ID
    /// - Returns: 抽出されたウィンドウ項目と AXUIElement の配列
    private nonisolated static func fetchWindowMenuItems(for pid: Int32) -> [ScannedWindowMenuItem] {
        guard let barItem = findWindowMenuBarItem(for: pid) else {
            return []
        }
        return fetchWindowMenuItems(fromMenuBarItem: barItem)
    }

    /// 「ウィンドウ」メニューバー項目の配下メニューから実ウィンドウ項目群を収集する
    /// - Parameter barItem: 「ウィンドウ」メニューバー項目の AXUIElement
    /// - Returns: 抽出されたウィンドウ項目と AXUIElement の配列
    private nonisolated static func fetchWindowMenuItems(fromMenuBarItem barItem: AXUIElement) -> [ScannedWindowMenuItem] {
        applyMessagingTimeout(to: barItem)
        guard let subMenus = copyAXChildren(barItem),
              let windowMenu = subMenus.first else {
            return []
        }
        applyMessagingTimeout(to: windowMenu)
        guard let rawChildren = copyAXChildren(windowMenu) else {
            return []
        }

        // 第1パス：全項目で最小属性（title と identifier）のみ読み取り、空タイトル／セパレータの不要 IPC をスキップする
        var titlesByIndex = Array<String?>(repeating: nil, count: rawChildren.count)
        var identifiersByIndex = Array<String?>(repeating: nil, count: rawChildren.count)
        var hasStandardMakeKeyItems = false
        var nonEmptyIndices: [Int] = []
        nonEmptyIndices.reserveCapacity(rawChildren.count)

        for (idx, item) in rawChildren.enumerated() {
            applyMessagingTimeout(to: item)
            let titleResult = copyStringAttributeWithError(item, attribute: kAXTitleAttribute as CFString)
            if isAXCommunicationAbortError(titleResult.error) {
                return []
            }
            guard let rawTitle = titleResult.value,
                  !rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let identifierResult = copyStringAttributeWithError(item, attribute: kAXIdentifierAttribute as CFString)
            if isAXCommunicationAbortError(identifierResult.error) {
                return []
            }
            titlesByIndex[idx] = rawTitle
            identifiersByIndex[idx] = identifierResult.value
            if identifierResult.value == WindowMenuExtractor.standardWindowActionIdentifier {
                hasStandardMakeKeyItems = true
            }
            nonEmptyIndices.append(idx)
        }

        guard !nonEmptyIndices.isEmpty else { return [] }

        // 標準識別子 "makeKeyAndOrderFront:" が存在する場合、非標準項目の残属性およびサブメニュー/コマンドキー判定を完全にスキップする
        if hasStandardMakeKeyItems {
            var snapshots: [WindowMenuItemSnapshot] = []
            for idx in nonEmptyIndices where identifiersByIndex[idx] == WindowMenuExtractor.standardWindowActionIdentifier {
                let item = rawChildren[idx]
                let enabledResult = copyBoolAttributeWithError(item, attribute: kAXEnabledAttribute as CFString)
                if isAXCommunicationAbortError(enabledResult.error) {
                    return []
                }
                guard enabledResult.value ?? true else { continue }
                let markResult = copyStringAttributeWithError(item, attribute: kAXMenuItemMarkCharAttribute as CFString)
                if isAXCommunicationAbortError(markResult.error) {
                    return []
                }
                snapshots.append(
                    WindowMenuItemSnapshot(
                        title: titlesByIndex[idx] ?? "",
                        identifier: identifiersByIndex[idx],
                        mark: markResult.value,
                        hasCommandKey: false,
                        hasSubmenu: false,
                        isEnabled: true,
                        index: idx
                    )
                )
            }
            let extracted = WindowMenuExtractor.extractWindowListItems(from: snapshots)
            return extracted.compactMap { snapshot in
                guard snapshot.index >= 0, snapshot.index < rawChildren.count else { return nil }
                return ScannedWindowMenuItem(
                    snapshot: snapshot,
                    axElement: SendableAXElement(value: rawChildren[snapshot.index])
                )
            }
        }

        // フォールバック：セパレータ境界を保った全項目スナップショットを構築し、非空項目のみ必要属性を読み取る
        var snapshots: [WindowMenuItemSnapshot] = []
        snapshots.reserveCapacity(rawChildren.count)
        for (idx, item) in rawChildren.enumerated() {
            guard let title = titlesByIndex[idx] else {
                snapshots.append(WindowMenuItemSnapshot(title: "", index: idx))
                continue
            }
            let identifier = identifiersByIndex[idx]
            // 明らかにシステム項目と分かる識別子は残りの属性取得をスキップする
            if let identifier, identifier == "_toggleIPad:" || identifier.hasPrefix("_NS:") {
                snapshots.append(
                    WindowMenuItemSnapshot(title: title, identifier: identifier, index: idx)
                )
                continue
            }
            let isEnabled = copyBoolAttribute(item, attribute: kAXEnabledAttribute as CFString) ?? true
            guard isEnabled else {
                snapshots.append(
                    WindowMenuItemSnapshot(title: title, identifier: identifier, isEnabled: false, index: idx)
                )
                continue
            }
            let cmdChar = copyStringAttribute(item, attribute: kAXMenuItemCmdCharAttribute as CFString)
            let cmdVirtualKey = copyStringAttribute(item, attribute: kAXMenuItemCmdVirtualKeyAttribute as CFString)
            let hasCmdChar = !(cmdChar ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasCmdVKey = !(cmdVirtualKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasCmdChar || hasCmdVKey {
                snapshots.append(
                    WindowMenuItemSnapshot(
                        title: title,
                        identifier: identifier,
                        hasCommandKey: true,
                        isEnabled: true,
                        index: idx
                    )
                )
                continue
            }
            let subChildren = copyAXChildren(item)
            let hasSubmenu = !(subChildren?.isEmpty ?? true)
            let mark = hasSubmenu ? nil : copyStringAttribute(item, attribute: kAXMenuItemMarkCharAttribute as CFString)

            snapshots.append(
                WindowMenuItemSnapshot(
                    title: title,
                    identifier: identifier,
                    mark: mark,
                    hasCommandKey: false,
                    hasSubmenu: hasSubmenu,
                    isEnabled: true,
                    index: idx
                )
            )
        }

        let extracted = WindowMenuExtractor.extractWindowListItems(from: snapshots)
        return extracted.compactMap { snapshot in
            guard snapshot.index >= 0, snapshot.index < rawChildren.count else { return nil }
            return ScannedWindowMenuItem(
                snapshot: snapshot,
                axElement: SendableAXElement(value: rawChildren[snapshot.index])
            )
        }
    }

    /// 指定 AXUIElement の kAXChildrenAttribute 配列を読み取る
    /// - Parameter element: 親 AXUIElement
    /// - Returns: 子 AXUIElement 配列（取得失敗時は nil）
    private nonisolated static func copyAXChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success else {
            return nil
        }
        return childrenRef as? [AXUIElement]
    }
}
