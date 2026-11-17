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

    /// PID ごとのキャッシュされたウィンドウ一覧
    private var cachedWindowsByPID: [Int32: [CachedAXWindow]] = [:]

    /// PID ごとのキャッシュされた「ウィンドウ」メニュー項目一覧
    private var cachedWindowMenuByPID: [Int32: CachedWindowMenuState] = [:]

    /// PID ごとの AXObserver インスタンス
    private var observersByPID: [Int32: AXObserver] = [:]

    /// PID ごとのデバウンス付きバックグラウンド更新タスク
    private var pendingRefreshTasksByPID: [Int32: Task<Void, Never>] = [:]

    /// スペース切り替え／初期スキャン用のバックグラウンド走査タスク
    private var pendingSpaceScanTask: Task<Void, Never>?

    /// 別スペース遷移後のウィンドウフォーカス確定用フォローアップタスク
    private var pendingActivationFollowUpTask: Task<Void, Never>?

    /// Workspace 通知監視トークン群
    private var workspaceObservers: [NSObjectProtocol] = []

    /// 監視中フラグ
    private var isObserving = false

    /// 操作スペース切り替え後のバックグラウンド全体再走査が完了するまでフルスクリーン置換を抑制するフラグ
    private var hasPendingSpaceChange = false

    /// AX IPC 呼び出しをメインスレッド外で直列実行するためのワーカーキュー
    private nonisolated let axWorkerQueue = DispatchQueue(
        label: "dev.wintch.WindowService.AXWorker",
        qos: .utility
    )

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
        scheduleBackgroundScanAllRegularApps(debounce: nil)

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
                        debounce: nil
                    )
                }
            }
        )

        // アプリ終了時のキャッシュ解放
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                Task { @MainActor [weak self] in
                    self?.unregisterObserver(for: pid)
                    self?.cachedWindowsByPID.removeValue(forKey: pid)
                    self?.cachedWindowMenuByPID.removeValue(forKey: pid)
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
                    self?.scheduleBackgroundScanAllRegularApps(debounce: Self.spaceChangeDebounceDuration)
                }
            }
        )
    }

    /// ウィンドウ監視を停止し、監視リソースとキャッシュを解放する
    public func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        hasPendingSpaceChange = false

        pendingSpaceScanTask?.cancel()
        pendingSpaceScanTask = nil
        pendingActivationFollowUpTask?.cancel()
        pendingActivationFollowUpTask = nil
        for task in pendingRefreshTasksByPID.values {
            task.cancel()
        }
        pendingRefreshTasksByPID.removeAll()

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
    }

    /// 現在の全操作スペース上のウィンドウ候補を収集して返す
    /// - Returns: フィルタリング前の生ウィンドウ候補一覧
    public func fetchRawWindowCandidates() -> [RawWindowCandidate] {
        // 最新の AX ウィンドウ状態をスキャンする
        scanAllRegularApps()

        let selfPID = ProcessInfo.processInfo.processIdentifier
        let cgWindows = fetchCGWindowInfos()
        let appMap = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }
        )

        // CGWindow を PID ごとにグルーピングし、システム重なり順 (zOrderIndex) を付与する
        var cgEntriesByPID: [Int32: [(zOrder: Int, info: CGWindowMeta)]] = [:]
        for (index, info) in cgWindows.enumerated() {
            cgEntriesByPID[info.pid, default: []].append((zOrder: index, info: info))
        }

        // キャッシュの整合性整理：CGWindow にも現在の AX にも存在しない終了済みウィンドウを除去
        cleanupClosedWindows(cgEntriesByPID: cgEntriesByPID)

        var candidates: [RawWindowCandidate] = []
        var matchedCGWindowIDs = Set<UInt32>()

        // 1. キャッシュ済み AX ウィンドウを候補として構築し、対応する CGWindow メタデータを結合する
        for (pid, cachedList) in cachedWindowsByPID {
            guard let app = appMap[pid] else { continue }
            let isRegular = app.activationPolicy == .regular
            let appName = app.localizedName ?? "不明なアプリ"
            let pidCGEntries = cgEntriesByPID[pid] ?? []
            var updatedList = cachedList
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
                    in: pidCGEntries,
                    excluding: matchedCGWindowIDs
                )
                if let matchedCG {
                    matchedCGWindowIDs.insert(matchedCG.info.windowID)
                    updatedList[index].cgWindowID = matchedCG.info.windowID
                    matchedCGByIndex[index] = matchedCG
                }
            }

            for index in updatedList.indices {
                let cached = updatedList[index]
                let matchedCG = matchedCGByIndex[index]

                // 座標が取得できない不可視・非ウィンドウ要素はダミーサイズで補完せず除外する
                guard let rect = cached.bounds ?? matchedCG?.info.bounds else { continue }
                let resolvedCGID: UInt32?
                if let matchedID = matchedCG?.info.windowID {
                    resolvedCGID = matchedID
                } else if let oldID = cached.cgWindowID,
                          !matchedCGWindowIDs.contains(oldID),
                          pidCGEntries.contains(where: { $0.info.windowID == oldID }) {
                    matchedCGWindowIDs.insert(oldID)
                    resolvedCGID = oldID
                } else {
                    resolvedCGID = nil
                }

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
                        isOnScreen: matchedCG?.info.isOnscreen,
                        lastActivatedAt: cached.lastActivatedAt,
                        zOrderIndex: matchedCG?.zOrder ?? Int.max
                    )
                )
            }

            cachedWindowsByPID[pid] = updatedList
        }

        // 2. Wintch 起動前から別スペースに存在し AX 未キャッシュの CGWindow を補完追加する
        for (index, cgInfo) in cgWindows.enumerated() {
            guard !matchedCGWindowIDs.contains(cgInfo.windowID) else { continue }
            guard Self.allowedCGWindowLayers.contains(cgInfo.layer) else { continue }
            guard let app = appMap[cgInfo.pid],
                  app.activationPolicy == .regular else { continue }

            candidates.append(
                RawWindowCandidate(
                    id: "cg-\(cgInfo.windowID)",
                    cgWindowID: cgInfo.windowID,
                    pid: cgInfo.pid,
                    bundleIdentifier: app.bundleIdentifier,
                    applicationName: app.localizedName ?? "不明なアプリ",
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
        let targetID = entry.id
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

                if let resolved = self.findCachedWindow(pid: targetPID, preferredID: targetID, title: targetTitle),
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
                        preferUnchecked: true,
                        forceFresh: true
                    )
                } else if stepIndex == 2 {
                    _ = await self.performMenuNavigationViaMenuOpen(
                        pid: targetPID,
                        windowTitle: targetTitle,
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

    /// 指定されたウィンドウ1枚のみを閉じる操作を実行し、実際に消滅したかを確認して返す
    /// - Parameter entry: クローズ対象のウィンドウ項目
    /// - Returns: ウィンドウが閉じられたことを確認した場合は true、非対応や確認ダイアログ等で残存した場合は false
    public func closeWindow(_ entry: WindowEntry) async -> Bool {
        guard let target = await resolveCachedWindowWithSpaceFallback(entry) else {
            return false
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
            return false
        }

        let closeButton = closeButtonVal as! AXUIElement
        Self.applyMessagingTimeout(to: closeButton)
        if let isEnabled = Self.copyBoolAttribute(closeButton, attribute: kAXEnabledAttribute as CFString), !isEnabled {
            return false
        }

        let pressStatus = AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        guard pressStatus == .success else {
            return false
        }

        // 非同期のウィンドウ破棄に対応するため、短時間（最大約150ms）消滅をポーリング確認する
        let maxAttempts = 10
        for _ in 0..<maxAttempts {
            try? await Task.sleep(for: .milliseconds(15))
            if !isAXWindowAlive(target.axElement, pid: entry.pid) {
                removeCachedWindow(pid: entry.pid, windowID: entry.id, axElement: target.axElement)
                return true
            }
        }

        // 未保存変更の確認ダイアログ（シート）表示などで依然として開いている場合は残存とみなす
        return false
    }

    /// 指定された PID のアプリケーションに対して通常の終了要求を送信し、プロセス終了を確認して返す
    /// - Parameter pid: 終了対象のプロセス ID
    /// - Returns: アプリケーションが終了したことを確認できた場合は true、確認ダイアログ等で残存した場合は false
    public func terminateApplication(pid: Int32) async -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            cachedWindowsByPID.removeValue(forKey: pid)
            cachedWindowMenuByPID.removeValue(forKey: pid)
            unregisterObserver(for: pid)
            return true
        }
        if app.isTerminated {
            cachedWindowsByPID.removeValue(forKey: pid)
            cachedWindowMenuByPID.removeValue(forKey: pid)
            unregisterObserver(for: pid)
            return true
        }

        // 通常のアプリ終了要求（Command+Q 相当）を送信し、強制終了（forceTerminate）は行わない
        guard app.terminate() else {
            return false
        }

        // 非同期の終了処理（最大約500ms）をポーリングして終了を確認する
        let maxAttempts = 25
        for _ in 0..<maxAttempts {
            try? await Task.sleep(for: .milliseconds(20))
            if app.isTerminated {
                cachedWindowsByPID.removeValue(forKey: pid)
                cachedWindowMenuByPID.removeValue(forKey: pid)
                unregisterObserver(for: pid)
                return true
            }
        }

        // 未保存変更のダイアログ等で終了がキャンセル・保留された場合は残存とみなす
        return false
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

    /// 起動中の全通常アプリをバックグラウンドキューでスキャンし、結果をキャッシュへ反映する
    /// - Parameter debounce: 連続発生時のデバウンス待機時間（即時実行時は nil）
    private func scheduleBackgroundScanAllRegularApps(debounce: Duration?) {
        pendingSpaceScanTask?.cancel()
        pendingSpaceScanTask = Task { @MainActor [weak self] in
            if let debounce {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled, let self, self.isObserving else { return }

            let selfPID = ProcessInfo.processInfo.processIdentifier
            let scanTargets: [(pid: Int32, isActive: Bool)] = NSWorkspace.shared.runningApplications.compactMap { app in
                guard app.activationPolicy == .regular else { return nil }
                let pid = app.processIdentifier
                guard pid != selfPID else { return nil }
                if self.observersByPID[pid] == nil {
                    self.registerObserver(for: pid)
                }
                return (pid: pid, isActive: app.isActive)
            }

            let results = await withCheckedContinuation { continuation in
                self.axWorkerQueue.async {
                    let scanned = scanTargets.map { target in
                        (
                            pid: target.pid,
                            isActive: target.isActive,
                            snapshots: Self.fetchAXWindowSnapshots(for: target.pid),
                            menuItems: Self.fetchWindowMenuItems(for: target.pid)
                        )
                    }
                    continuation.resume(returning: scanned)
                }
            }

            guard !Task.isCancelled, self.isObserving else { return }
            let fetchedAt = Date()
            for item in results {
                self.applyAXWindowSnapshots(
                    item.snapshots,
                    for: item.pid,
                    markFrontmostAsActive: item.isActive,
                    allowDisplaySpanningReplacement: false
                )
                self.cachedWindowMenuByPID[item.pid] = CachedWindowMenuState(
                    items: item.menuItems,
                    fetchedAt: fetchedAt
                )
            }
            self.hasPendingSpaceChange = false
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
    private func scheduleBackgroundRefresh(
        for pid: Int32,
        markFrontmostAsActive: Bool,
        debounce: Duration?,
        activatedElement: SendableAXElement? = nil,
        activatedAt: Date? = nil,
        allowDisplaySpanningReplacement: Bool = false
    ) {
        pendingRefreshTasksByPID[pid]?.cancel()
        pendingRefreshTasksByPID[pid] = Task { @MainActor [weak self] in
            if let debounce {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled, let self, self.isObserving else { return }

            let result = await withCheckedContinuation { continuation in
                self.axWorkerQueue.async {
                    let snapshots = Self.fetchAXWindowSnapshots(for: pid)
                    let menuItems = Self.fetchWindowMenuItems(for: pid)
                    continuation.resume(returning: (snapshots, menuItems))
                }
            }
            guard !Task.isCancelled, self.isObserving else { return }
            self.pendingRefreshTasksByPID.removeValue(forKey: pid)

            self.applyAXWindowSnapshots(
                result.0,
                for: pid,
                markFrontmostAsActive: markFrontmostAsActive,
                allowDisplaySpanningReplacement: allowDisplaySpanningReplacement && !self.hasPendingSpaceChange
            )
            self.cachedWindowMenuByPID[pid] = CachedWindowMenuState(
                items: result.1,
                fetchedAt: Date()
            )

            if let activatedElement, let activatedAt {
                self.updateMRUTimestamp(
                    pid: pid,
                    axElement: activatedElement.value,
                    date: activatedAt
                )
            }
        }
    }

    /// バックグラウンドの直列ワーカーキューで指定 PID の AX ウィンドウ一覧を取得する
    /// - Parameter pid: 対象プロセス ID
    /// - Returns: 取得された AX ウィンドウスナップショット配列
    private func fetchAXWindowSnapshotsInBackground(for pid: Int32) async -> [ScannedAXWindowSnapshot] {
        await withCheckedContinuation { continuation in
            axWorkerQueue.async {
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
        let screenBounds = currentDisplayBounds()
        let activeWindowEntries = existing.filter {
            $0.isPresentInLatestAXScan && $0.role == "AXWindow" && $0.subrole != nil
        }

        if allowDisplaySpanningReplacement, hasDisappearedCandidates, !activeWindowEntries.isEmpty {
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
        pendingRefreshTasksByPID[pid] = Task { @MainActor [weak self] in
            guard let self, self.isObserving else { return }

            let result = await withCheckedContinuation { continuation in
                self.axWorkerQueue.async {
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
                    let menuItems = Self.fetchWindowMenuItems(for: pid)
                    continuation.resume(returning: (focusedElement, snapshots, menuItems))
                }
            }

            guard !Task.isCancelled, self.isObserving else { return }
            self.pendingRefreshTasksByPID.removeValue(forKey: pid)
            self.applyAXWindowSnapshots(result.1, for: pid, markFrontmostAsActive: true)
            self.cachedWindowMenuByPID[pid] = CachedWindowMenuState(
                items: result.2,
                fetchedAt: Date()
            )

            if let focusedElement = result.0 {
                self.updateMRUTimestamp(pid: pid, axElement: focusedElement.value, date: capturedNow)
            }
        }
    }

    /// 閉じられた・存在しなくなったウィンドウをキャッシュから整理する
    /// - Parameter cgEntriesByPID: 現在の CGWindow マップ
    private func cleanupClosedWindows(cgEntriesByPID: [Int32: [(zOrder: Int, info: CGWindowMeta)]]) {
        for (pid, list) in cachedWindowsByPID {
            let pidCGEntries = cgEntriesByPID[pid] ?? []
            let survivingCGWindowIDs = Set(pidCGEntries.map { $0.info.windowID })
            let hasSubstantialCGWindow = pidCGEntries.contains { entry in
                Self.allowedCGWindowLayers.contains(entry.info.layer)
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

    /// キャッシュ済み AX ウィンドウに対応する CGWindow を位置・サイズ・表示状態・履歴連続性・包含比較で特定する
    /// - Parameters:
    ///   - cached: キャッシュ済み AX ウィンドウ情報
    ///   - entries: 該当 PID の CGWindow 情報一覧
    ///   - excludedIDs: 既に照合済みのウィンドウ ID セット
    /// - Returns: 最も一致する CGWindow とその Z オーダー順（見つからない場合は nil）
    private func findMatchingCGWindow(
        for cached: CachedAXWindow,
        in entries: [(zOrder: Int, info: CGWindowMeta)],
        excluding excludedIDs: Set<UInt32>
    ) -> (zOrder: Int, info: CGWindowMeta)? {
        guard let axBounds = cached.bounds else {
            return nil
        }
        return Self.selectBestCGWindowMatch(
            axBounds: axBounds,
            axTitle: cached.title,
            isMinimized: cached.isMinimized,
            preferOnscreen: cached.isPresentInLatestAXScan && !cached.isMinimized,
            preferredCGWindowID: cached.cgWindowID,
            in: entries,
            excluding: excludedIDs
        )
    }

    /// AX 矩形に対して最も適合する CGWindow を純粋比較で選出する
    /// - Parameters:
    ///   - axBounds: AXUIElement のウィンドウ矩形
    ///   - axTitle: AXUIElement から取得したウィンドウタイトル（任意）
    ///   - isMinimized: AX 上の最小化状態
    ///   - preferOnscreen: 現在スペース上で捕捉済みであり画面表示中 CGWindow を優先するか
    ///   - preferredCGWindowID: 前回照合されていた CGWindow ID（任意）
    ///   - entries: 該当 PID の CGWindow 情報一覧
    ///   - excludedIDs: 既に照合済みのウィンドウ ID セット
    /// - Returns: 最も一致する CGWindow とその Z オーダー順（見つからない場合は nil）
    nonisolated static func selectBestCGWindowMatch(
        axBounds: CGRect,
        axTitle: String? = nil,
        isMinimized: Bool,
        preferOnscreen: Bool,
        preferredCGWindowID: UInt32?,
        in entries: [(zOrder: Int, info: CGWindowMeta)],
        excluding excludedIDs: Set<UInt32>
    ) -> (zOrder: Int, info: CGWindowMeta)? {
        let available = entries.filter {
            !excludedIDs.contains($0.info.windowID)
                && allowedCGWindowLayers.contains($0.info.layer)
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
                    isMinimized: isMinimized,
                    preferOnscreen: preferOnscreen,
                    preferredCGWindowID: preferredCGWindowID
                )
                let rhsRank = matchPriorityTuple(
                    for: rhs.entry,
                    dist: rhs.dist,
                    axTitle: axTitle,
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
                doesCGWindowNameMatchTitle(lhs.0.info.name, axTitle: axTitle) ? 1 : 0,
                (preferredCGWindowID != nil && lhs.0.info.windowID == preferredCGWindowID) ? 1 : 0,
                hasNonEmptyCGWindowName(lhs.0.info.name) ? 1 : 0,
                lhs.1
            )
            let rhsRank = (
                (preferOnscreen && rhs.0.info.isOnscreen) ? 1 : 0,
                doesCGWindowNameMatchTitle(rhs.0.info.name, axTitle: axTitle) ? 1 : 0,
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
    ///   - isMinimized: AX 上の最小化状態
    ///   - preferOnscreen: 画面表示中 CGWindow を優先するか
    ///   - preferredCGWindowID: 前回照合されていた CGWindow ID
    /// - Returns: 辞書順比較可能な優先度ランク
    private nonisolated static func matchPriorityTuple(
        for entry: (zOrder: Int, info: CGWindowMeta),
        dist: Double,
        axTitle: String?,
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
        let titleMatchPriority = doesCGWindowNameMatchTitle(entry.info.name, axTitle: axTitle) ? 0 : 1
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
    /// - Returns: 双方が非空かつ一致（省略一致含む）する場合に true
    private nonisolated static func doesCGWindowNameMatchTitle(_ cgName: String?, axTitle: String?) -> Bool {
        guard let cgName = cgName?.trimmingCharacters(in: .whitespacesAndNewlines),
              let axTitle = axTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cgName.isEmpty, !axTitle.isEmpty else {
            return false
        }
        return WindowMenuCandidatePairing.titlesMatch(axTitle, cgName)
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
    ///   - title: 補助照合用のウィンドウタイトル
    /// - Returns: 一致したキャッシュエントリ（存在しない場合は nil）
    private func findCachedWindow(pid: Int32, preferredID: String, title: String) -> CachedAXWindow? {
        guard let list = cachedWindowsByPID[pid],
              let idx = Self.matchWindowIndex(
                  preferredID: preferredID,
                  title: title,
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
    ///   - items: 検索対象要素列
    ///   - id: 各要素から識別子を取り出すクロージャ
    ///   - windowTitle: 各要素からタイトルを取り出すクロージャ
    /// - Returns: 一致した要素のインデックス（一致しない場合は nil。先頭要素への曖昧フォールバックは行わない）
    nonisolated static func matchWindowIndex<T>(
        preferredID: String,
        title: String,
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
            return WindowMenuCandidatePairing.titlesMatch(candidateTitle, trimmedTarget)
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
        // CGWindow 補完識別子 (cg-*) のみ保持していた場合はタイトル一致（省略表記含む）で補助照合する
        if entry.id.hasPrefix("cg-"), !entry.windowTitle.isEmpty {
            return refreshed.first(where: {
                guard let candidateTitle = $0.title else { return false }
                return WindowMenuCandidatePairing.titlesMatch(candidateTitle, entry.windowTitle)
            })
        }
        return nil
    }

    /// 別操作スペースに存在し未キャッシュのウィンドウに対し、必要に応じてスペース移動を行って AXUIElement を解決する
    /// - Parameter entry: クローズ対象のウィンドウ項目
    /// - Returns: 解決されたキャッシュエントリ（取得できない場合は nil）
    private func resolveCachedWindowWithSpaceFallback(_ entry: WindowEntry) async -> CachedAXWindow? {
        if let resolved = resolveCachedWindowForClose(entry) {
            return resolved
        }

        // 別 Space 上のウィンドウ（cg-* 等）で AXUIElement が未取得の場合、
        // 「ウィンドウ」メニュー経由（利用可能なら）＋アプリアクティブ化で対象 Space へ遷移させる
        guard let app = NSRunningApplication(processIdentifier: entry.pid), !app.isTerminated else {
            return nil
        }

        if !entry.windowTitle.isEmpty,
           let menuItem = resolveWindowMenuItemElement(pid: entry.pid, windowTitle: entry.windowTitle) {
            Self.applyMessagingTimeout(to: menuItem)
            AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
        }
        app.activate()
        // Space 切り替えアニメーションと AX ツリー反映を待ちつつ最大約600ms再試行する
        let maxAttempts = 15
        for _ in 0..<maxAttempts {
            try? await Task.sleep(for: .milliseconds(40))
            if let resolved = resolveCachedWindowForClose(entry) {
                return resolved
            }
        }
        return nil
    }

    /// 指定された AXUIElement ウィンドウが現在もアプリケーション上に存在しているかを判定する
    /// - Parameters:
    ///   - axElement: 確認対象の AXUIElement
    ///   - pid: 所有プロセスの PID
    /// - Returns: ウィンドウがまだ生存している場合は true、閉じられて消滅している場合は false
    private func isAXWindowAlive(_ axElement: AXUIElement, pid: Int32) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid), app.isTerminated {
            return false
        }

        let appElement = AXUIElementCreateApplication(pid)
        Self.applyMessagingTimeout(to: appElement)
        let axWindows = Self.collectAXWindows(for: appElement)
        if !axWindows.isEmpty {
            return axWindows.contains { CFEqual($0, axElement) }
        }

        // ウィンドウ一覧取得に失敗した場合は対象要素のロール読み取り可否で生存確認する
        Self.applyMessagingTimeout(to: axElement)
        var roleRef: CFTypeRef?
        return AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleRef) == .success
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
            // C コールバックからの通知を MainActor へディスパッチする
            let wrappedElement = SendableAXElement(value: element)
            Task { @MainActor in
                service.handleAXNotification(element: wrappedElement.value, notification: notifName)
            }
        }, &observerRef)

        guard err == .success, let observer = observerRef else { return }

        let appElement = AXUIElementCreateApplication(pid)
        Self.applyMessagingTimeout(to: appElement)
        let notifications = [
            kAXWindowCreatedNotification,
            kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification,
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
            if var list = cachedWindowsByPID[pid] {
                list.removeAll { CFEqual($0.axElement, element) }
                if list.isEmpty {
                    cachedWindowsByPID.removeValue(forKey: pid)
                } else {
                    cachedWindowsByPID[pid] = list
                }
            }
            // ウィンドウ破棄直後に古いメニュー項目キャッシュ（TTL 2.0秒）が裏方 CGWindow へ割り当てられるのを防ぐ
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

        let now = Date()
        if isActivationEvent {
            // キャッシュ済みウィンドウであれば MRU 時刻だけは即時反映する
            updateMRUTimestamp(pid: pid, axElement: element, date: now)
        }

        let debounce = isActivationEvent ? Self.focusChangeDebounceDuration : Self.titleChangeDebounceDuration
        scheduleBackgroundRefresh(
            for: pid,
            markFrontmostAsActive: false,
            debounce: debounce,
            activatedElement: isActivationEvent ? SendableAXElement(value: element) : nil,
            activatedAt: isActivationEvent ? now : nil,
            allowDisplaySpanningReplacement: true
        )
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

        return axWindows.map { axWin in
            applyMessagingTimeout(to: axWin)
            return ScannedAXWindowSnapshot(
                uniqueID: "ax-\(pid)-\(CFHash(axWin))",
                axElement: SendableAXElement(value: axWin),
                role: copyStringAttribute(axWin, attribute: kAXRoleAttribute as CFString),
                title: copyStringAttribute(axWin, attribute: kAXTitleAttribute as CFString),
                subrole: copyStringAttribute(axWin, attribute: kAXSubroleAttribute as CFString),
                bounds: copyBounds(axWin),
                isMinimized: copyBoolAttribute(axWin, attribute: kAXMinimizedAttribute as CFString) ?? false
            )
        }
    }

    /// アプリケーション要素から kAXWindowsAttribute に加え、フォーカス／メインウィンドウを重複排除して収集する
    /// - Parameter appElement: 対象アプリケーションの AXUIElement
    /// - Returns: 重複のないウィンドウ AXUIElement 配列
    private nonisolated static func collectAXWindows(for appElement: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let axWindows = windowsRef as? [AXUIElement] {
            result = axWindows
        }

        // kAXWindowsAttribute に含まれないフローティングパネルや別スペースの現在ウィンドウを補完する
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var extraRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, attribute as CFString, &extraRef) == .success,
                  let extraValue = extraRef,
                  CFGetTypeID(extraValue) == AXUIElementGetTypeID() else {
                continue
            }
            let extraWindow = extraValue as! AXUIElement
            if !result.contains(where: { CFEqual($0, extraWindow) }) {
                result.append(extraWindow)
            }
        }

        return result
    }

    /// 文字列属性を読み取る
    /// - Parameters:
    ///   - element: 対象の AXUIElement
    ///   - attribute: 読み取る属性名
    /// - Returns: 取得された文字列（失敗時は nil）
    private nonisolated static func copyStringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    /// 真偽値属性を読み取る
    /// - Parameters:
    ///   - element: 対象の AXUIElement
    ///   - attribute: 読み取る属性名
    /// - Returns: 取得された真偽値（失敗時は nil）
    private nonisolated static func copyBoolAttribute(_ element: AXUIElement, attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? Bool
    }

    /// 位置 (kAXPositionAttribute) とサイズ (kAXSizeAttribute) を組み合わせて CGRect を構築する
    /// - Parameter element: 対象の AXUIElement
    /// - Returns: 取得されたウィンドウ矩形（失敗時は nil）
    private nonisolated static func copyBounds(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef,
              let sizeVal = sizeRef else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - 「ウィンドウ」メニュー補完ヘルパー

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
        guard !targetPIDs.isEmpty else {
            return candidates
        }

        let now = Date()
        for pid in targetPIDs {
            if let existing = cachedWindowMenuByPID[pid],
               Self.isMenuCacheFresh(fetchedAt: existing.fetchedAt, now: now) {
                continue
            }
            let items = Self.fetchWindowMenuItems(for: pid)
            cachedWindowMenuByPID[pid] = CachedWindowMenuState(items: items, fetchedAt: now)
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
    ///   - preferUnchecked: チェックマーク無しの項目を優先するか
    ///   - forceFresh: 初回からキャッシュを無視して最新メニューを取得するか
    /// - Returns: メニュー項目の押下に成功した場合は true
    private func performMenuNavigationWithRetry(
        pid: Int32,
        windowTitle: String,
        preferUnchecked: Bool,
        forceFresh: Bool = false
    ) -> Bool {
        if !forceFresh,
           let cachedElement = resolveWindowMenuItemElement(
               pid: pid,
               windowTitle: windowTitle,
               preferUnchecked: preferUnchecked,
               forceRefresh: false
           ) {
            Self.applyMessagingTimeout(to: cachedElement)
            if AXUIElementPerformAction(cachedElement, kAXPressAction as CFString) == .success {
                return true
            }
        }

        // キャッシュ無効または押下失敗時は最新メニューを再取得して押下を試行する
        cachedWindowMenuByPID.removeValue(forKey: pid)
        guard let freshElement = resolveWindowMenuItemElement(
            pid: pid,
            windowTitle: windowTitle,
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
    ///   - preferUnchecked: チェックマーク無しの項目を優先するか
    /// - Returns: 対象メニュー項目の押下に成功した場合は true
    private func performMenuNavigationViaMenuOpen(
        pid: Int32,
        windowTitle: String,
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
    ///   - preferUnchecked: チェックマーク無しの項目を優先するか
    ///   - forceRefresh: キャッシュを無視して強制再取得するか
    /// - Returns: 一致したメニュー項目の AXUIElement（存在しない場合は nil）
    private func resolveWindowMenuItemElement(
        pid: Int32,
        windowTitle: String,
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
            preferUnchecked: preferUnchecked
        )?.axElement.value
    }

    /// スキャン済みメニュー項目一覧から指定タイトルに一致する項目を探す（完全一致優先・省略表現・未チェック優先対応）
    /// - Parameters:
    ///   - items: 抽出済みのメニュー項目一覧
    ///   - title: 照合対象のウィンドウタイトル
    ///   - preferUnchecked: チェックマーク無しの項目を優先するか
    /// - Returns: 一致したメニュー項目（見つからない場合は nil）
    private nonisolated static func findMatchingMenuItem(
        in items: [ScannedWindowMenuItem],
        title: String,
        preferUnchecked: Bool = false
    ) -> ScannedWindowMenuItem? {
        let snapshots = items.map(\.snapshot)
        guard let idx = WindowMenuCandidatePairing.matchingMenuItemIndex(
            for: title,
            in: snapshots,
            preferUnchecked: preferUnchecked
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
            if let barTitle = copyStringAttribute(barItem, attribute: kAXTitleAttribute as CFString),
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

        var snapshots: [WindowMenuItemSnapshot] = []
        snapshots.reserveCapacity(rawChildren.count)
        for (idx, item) in rawChildren.enumerated() {
            applyMessagingTimeout(to: item)
            let title = copyStringAttribute(item, attribute: kAXTitleAttribute as CFString) ?? ""
            let identifier = copyStringAttribute(item, attribute: kAXIdentifierAttribute as CFString)
            let mark = copyStringAttribute(item, attribute: kAXMenuItemMarkCharAttribute as CFString)
            let cmdChar = copyStringAttribute(item, attribute: kAXMenuItemCmdCharAttribute as CFString)
            let cmdVirtualKey = copyStringAttribute(item, attribute: kAXMenuItemCmdVirtualKeyAttribute as CFString)
            let hasCmdChar = !(cmdChar ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasCmdVKey = !(cmdVirtualKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let subChildren = copyAXChildren(item)
            let hasSubmenu = !(subChildren?.isEmpty ?? true)
            let isEnabled = copyBoolAttribute(item, attribute: kAXEnabledAttribute as CFString) ?? true

            snapshots.append(
                WindowMenuItemSnapshot(
                    title: title,
                    identifier: identifier,
                    mark: mark,
                    hasCommandKey: hasCmdChar || hasCmdVKey,
                    hasSubmenu: hasSubmenu,
                    isEnabled: isEnabled,
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
