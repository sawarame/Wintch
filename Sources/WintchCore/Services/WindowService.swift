import AppKit
import ApplicationServices
import CoreGraphics

/// CGWindowListCopyWindowInfo と AXUIElement / AXObserver を組み合わせて
/// 画面収録権限および非公開 API なしで全操作スペースのウィンドウ管理を行うサービス
@MainActor
public final class WindowService: WindowServicing {
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
        var lastActivatedAt: Date?
    }

    /// PID ごとのキャッシュされたウィンドウ一覧
    private var cachedWindowsByPID: [Int32: [CachedAXWindow]] = [:]

    /// PID ごとの AXObserver インスタンス
    private var observersByPID: [Int32: AXObserver] = [:]

    /// Workspace 通知監視トークン群
    private var workspaceObservers: [NSObjectProtocol] = []

    /// 監視中フラグ
    private var isObserving = false

    /// 照合および補完候補として許可する CoreGraphics ウィンドウレイヤー（通常・フローティング）
    private static let allowedCGWindowLayers: Set<Int> = [
        Int(CGWindowLevelForKey(.normalWindow)),
        Int(CGWindowLevelForKey(.floatingWindow))
    ]

    /// WindowService を初期化する
    public init() {}

    /// ウィンドウ監視（AXObserver およびワークスペース通知）を開始する
    public func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        // 起動済みの通常アプリを初期登録する
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard pid != ProcessInfo.processInfo.processIdentifier else { continue }
            registerObserver(for: pid)
            refreshAXWindows(for: pid, markFrontmostAsActive: app.isActive)
        }

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
                Task { @MainActor [weak self] in
                    self?.registerObserver(for: pid)
                    self?.refreshAXWindows(for: pid, markFrontmostAsActive: app.isActive)
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
                }
            }
        )

        // アプリ切り替え時に最前面ウィンドウの MRU 時刻を更新
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
                    self?.markFocusedWindowActivated(for: pid)
                }
            }
        )

        // 操作スペース切り替え時に新スペースのウィンドウをキャッシュへ取り込む
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scanAllRegularApps()
                }
            }
        )
    }

    /// ウィンドウ監視を停止し、監視リソースとキャッシュを解放する
    public func stopObserving() {
        guard isObserving else { return }
        isObserving = false

        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers {
            center.removeObserver(token)
        }
        workspaceObservers.removeAll()

        for pid in Array(observersByPID.keys) {
            unregisterObserver(for: pid)
        }
        cachedWindowsByPID.removeAll()
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

            for index in updatedList.indices {
                let cached = updatedList[index]
                // 位置・サイズまたはフルスクリーン領域で最も一致する CGWindow を探す
                let matchedCG = findMatchingCGWindow(
                    for: cached,
                    in: pidCGEntries,
                    excluding: matchedCGWindowIDs
                )
                if let matchedCG {
                    matchedCGWindowIDs.insert(matchedCG.info.windowID)
                    updatedList[index].cgWindowID = matchedCG.info.windowID
                }

                // 座標が取得できない不可視・非ウィンドウ要素はダミーサイズで補完せず除外する
                guard let rect = cached.bounds ?? matchedCG?.info.bounds else { continue }

                candidates.append(
                    RawWindowCandidate(
                        id: cached.id,
                        cgWindowID: matchedCG?.info.windowID ?? cached.cgWindowID,
                        pid: pid,
                        bundleIdentifier: app.bundleIdentifier,
                        applicationName: appName,
                        title: cached.title,
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

        return candidates
    }

    /// 指定されたウィンドウを最前面にアクティブ化する（必要なら操作スペース移動・最小化解除を行う）
    /// - Parameter entry: アクティブ化対象のウィンドウ項目
    public func activateWindow(_ entry: WindowEntry) {
        let now = Date()
        let app = NSRunningApplication(processIdentifier: entry.pid)

        // キャッシュ上の AXUIElement を探して MRU 時刻を更新する
        var targetAX: AXUIElement?
        if var list = cachedWindowsByPID[entry.pid],
           let idx = list.firstIndex(where: { $0.id == entry.id }) {
            list[idx].lastActivatedAt = now
            targetAX = list[idx].axElement
            cachedWindowsByPID[entry.pid] = list
        }

        // macOS 14+ 標準のアプリアクティブ化（別スペースにある場合 OS がスペース移動を誘発）
        app?.activate(options: [])

        if let targetAX {
            raiseAXWindow(targetAX, unminimize: entry.isMinimized)
        }

        // 別スペースへのアニメーション切り替え完了後に、対象ウィンドウのフォーカスを再確定する
        let targetPID = entry.pid
        let targetTitle = entry.windowTitle
        let targetID = entry.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self else { return }
            self.refreshAXWindows(for: targetPID, markFrontmostAsActive: false)
            if let resolved = self.findCachedWindow(pid: targetPID, preferredID: targetID, title: targetTitle) {
                self.raiseAXWindow(resolved.axElement, unminimize: entry.isMinimized)
                self.updateMRUTimestamp(pid: targetPID, windowID: resolved.id, date: Date())
            }
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
        if let isEnabled = copyBoolAttribute(closeButton, attribute: kAXEnabledAttribute as CFString), !isEnabled {
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
            unregisterObserver(for: pid)
            return true
        }
        if app.isTerminated {
            cachedWindowsByPID.removeValue(forKey: pid)
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
                unregisterObserver(for: pid)
                return true
            }
        }

        // 未保存変更のダイアログ等で終了がキャンセル・保留された場合は残存とみなす
        return false
    }

    // MARK: - 内部ヘルパー

    /// CGWindowListCopyWindowInfo の抽出用メタデータ構造体
    private struct CGWindowMeta {
        let windowID: UInt32
        let pid: Int32
        let layer: Int
        let bounds: CGRect
        let alpha: Double
        let isOnscreen: Bool
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
            return CGWindowMeta(
                windowID: windowID,
                pid: pid,
                layer: layer,
                bounds: bounds,
                alpha: alpha,
                isOnscreen: isOnscreen
            )
        }
    }

    /// 起動中の全通常アプリの AX ウィンドウをスキャンしてキャッシュを更新する
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

    /// 指定 PID のアプリから現在の AX ウィンドウ一覧を読み取りキャッシュを更新する
    /// - Parameters:
    ///   - pid: 対象プロセス ID
    ///   - markFrontmostAsActive: 最前面アプリの先頭ウィンドウをアクティブとして記録するか
    private func refreshAXWindows(for pid: Int32, markFrontmostAsActive: Bool) {
        let appElement = AXUIElementCreateApplication(pid)
        let axWindows = collectAXWindows(for: appElement)
        guard !axWindows.isEmpty else {
            return
        }

        var existing = cachedWindowsByPID[pid] ?? []
        let now = Date()

        for (index, axWin) in axWindows.enumerated() {
            let role = copyStringAttribute(axWin, attribute: kAXRoleAttribute as CFString)
            let title = copyStringAttribute(axWin, attribute: kAXTitleAttribute as CFString)
            let subrole = copyStringAttribute(axWin, attribute: kAXSubroleAttribute as CFString)
            let bounds = copyBounds(axWin)
            let isMinimized = copyBoolAttribute(axWin, attribute: kAXMinimizedAttribute as CFString) ?? false

            if let matchIdx = existing.firstIndex(where: { CFEqual($0.axElement, axWin) }) {
                existing[matchIdx].role = role
                existing[matchIdx].title = title
                existing[matchIdx].subrole = subrole
                existing[matchIdx].bounds = bounds
                existing[matchIdx].isMinimized = isMinimized
                if markFrontmostAsActive && index == 0 && existing[matchIdx].lastActivatedAt == nil {
                    existing[matchIdx].lastActivatedAt = now
                }
            } else {
                let uniqueID = "ax-\(pid)-\(CFHash(axWin))"
                existing.append(
                    CachedAXWindow(
                        id: uniqueID,
                        pid: pid,
                        axElement: axWin,
                        cgWindowID: nil,
                        role: role,
                        title: title,
                        subrole: subrole,
                        bounds: bounds,
                        isMinimized: isMinimized,
                        lastActivatedAt: (markFrontmostAsActive && index == 0) ? now : nil
                    )
                )
            }
        }

        cachedWindowsByPID[pid] = existing
    }

    /// 指定 PID のフォーカス中ウィンドウの MRU 時刻を更新する
    /// - Parameter pid: アクティブになったプロセス ID
    private func markFocusedWindowActivated(for pid: Int32) {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef)
        refreshAXWindows(for: pid, markFrontmostAsActive: true)

        guard status == .success, let focusedWin = focusedRef else { return }
        let axWin = focusedWin as! AXUIElement
        let now = Date()

        if var list = cachedWindowsByPID[pid],
           let idx = list.firstIndex(where: { CFEqual($0.axElement, axWin) }) {
            list[idx].lastActivatedAt = now
            cachedWindowsByPID[pid] = list
        }
    }

    /// 閉じられた・存在しなくなったウィンドウをキャッシュから整理する
    /// - Parameter cgEntriesByPID: 現在の CGWindow マップ
    private func cleanupClosedWindows(cgEntriesByPID: [Int32: [(zOrder: Int, info: CGWindowMeta)]]) {
        for (pid, list) in cachedWindowsByPID {
            let pidCGEntries = cgEntriesByPID[pid] ?? []
            let hasSubstantialCGWindow = pidCGEntries.contains { entry in
                Self.allowedCGWindowLayers.contains(entry.info.layer)
                    && entry.info.bounds.width >= 200
                    && entry.info.bounds.height >= 165
            }
            let filtered = list.filter { cached in
                // AX 属性にアクセスできれば生存している（または別スペースにある）
                var roleRef: CFTypeRef?
                let err = AXUIElementCopyAttributeValue(cached.axElement, kAXRoleAttribute as CFString, &roleRef)
                if err == .success {
                    return true
                }
                guard err == .cannotComplete else { return false }
                // AX が一時的に応答できない場合は、対応 CGWindow または通常サイズのウィンドウが残っている時だけ保持する
                if let knownID = cached.cgWindowID {
                    return pidCGEntries.contains { $0.info.windowID == knownID }
                }
                return hasSubstantialCGWindow
            }
            if filtered.isEmpty {
                cachedWindowsByPID.removeValue(forKey: pid)
            } else {
                cachedWindowsByPID[pid] = filtered
            }
        }
    }

    /// キャッシュ済み AX ウィンドウに対応する CGWindow を位置・サイズ・領域包含比較で特定する
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
        let available = entries.filter {
            !excludedIDs.contains($0.info.windowID)
                && Self.allowedCGWindowLayers.contains($0.info.layer)
        }
        guard let axBounds = cached.bounds else {
            return nil
        }

        // 1. 許容誤差 40pt 以内で最も位置・サイズが近い CGWindow を優先する（同距離なら通常レイヤー優先）
        if let exactMatch = available.min(by: { lhs, rhs in
            let lhsDist = boundsDistance(axBounds, lhs.info.bounds)
            let rhsDist = boundsDistance(axBounds, rhs.info.bounds)
            if lhsDist != rhsDist {
                return lhsDist < rhsDist
            }
            return lhs.info.layer < rhs.info.layer
        }), boundsDistance(axBounds, exactMatch.info.bounds) <= 40.0 {
            return exactMatch
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
            lhs.1 < rhs.1
        }

        return containmentMatch?.0
    }

    /// 2つの矩形間のマンハッタン距離を計算する
    /// - Parameters:
    ///   - a: 比較元の矩形
    ///   - b: 比較先の矩形
    /// - Returns: 座標とサイズの差分合計値
    private func boundsDistance(_ a: CGRect, _ b: CGRect) -> Double {
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
        if unminimize {
            AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(axWin, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
    }

    /// 再スキャン後のキャッシュから対象ウィンドウを探し出す
    /// - Parameters:
    ///   - pid: 所有プロセス ID
    ///   - preferredID: 優先して照合する識別子
    ///   - title: 補助照合用のウィンドウタイトル
    /// - Returns: 一致したキャッシュエントリ（存在しない場合は nil）
    private func findCachedWindow(pid: Int32, preferredID: String, title: String) -> CachedAXWindow? {
        guard let list = cachedWindowsByPID[pid] else { return nil }
        if let exact = list.first(where: { $0.id == preferredID }) {
            return exact
        }
        if !title.isEmpty, let byTitle = list.first(where: { $0.title == title }) {
            return byTitle
        }
        return list.first
    }

    /// キャッシュ内の MRU 時刻を更新する
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
        // CGWindow 補完識別子 (cg-*) のみ保持していた場合はタイトル一致で補助照合する
        if entry.id.hasPrefix("cg-"), !entry.windowTitle.isEmpty {
            return refreshed.first(where: { $0.title == entry.windowTitle })
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

        // 別 Space 上のウィンドウ（cg-* 等）で AXUIElement が未取得の場合、アプリをアクティブ化して自動遷移させる
        guard let app = NSRunningApplication(processIdentifier: entry.pid), !app.isTerminated else {
            return nil
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
        let axWindows = collectAXWindows(for: appElement)
        if !axWindows.isEmpty {
            return axWindows.contains { CFEqual($0, axElement) }
        }

        // ウィンドウ一覧取得に失敗した場合は対象要素のロール読み取り可否で生存確認する
        var roleRef: CFTypeRef?
        return AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleRef) == .success
    }

    /// アプリケーション要素から kAXWindowsAttribute に加え、フォーカス／メインウィンドウを重複排除して収集する
    /// - Parameter appElement: 対象アプリケーションの AXUIElement
    /// - Returns: 重複のないウィンドウ AXUIElement 配列
    private func collectAXWindows(for appElement: AXUIElement) -> [AXUIElement] {
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
            let retainedElement = element
            Task { @MainActor in
                service.handleAXNotification(element: retainedElement, notification: notifName)
            }
        }, &observerRef)

        guard err == .success, let observer = observerRef else { return }

        let appElement = AXUIElementCreateApplication(pid)
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

    /// 指定 PID の AXObserver を RunLoop から解除して破棄する
    /// - Parameter pid: 監視を解除するプロセスの PID
    private func unregisterObserver(for pid: Int32) {
        guard let observer = observersByPID.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    /// AXObserver コールバックを受信してキャッシュと MRU を更新する
    /// - Parameters:
    ///   - element: イベントが発生した AXUIElement
    ///   - notification: 通知名
    private func handleAXNotification(element: AXUIElement, notification: String) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != 0 else { return }

        if notification == kAXUIElementDestroyedNotification {
            if var list = cachedWindowsByPID[pid] {
                list.removeAll { CFEqual($0.axElement, element) }
                cachedWindowsByPID[pid] = list
            }
            return
        }

        refreshAXWindows(for: pid, markFrontmostAsActive: false)

        if notification == kAXFocusedWindowChangedNotification
            || notification == kAXMainWindowChangedNotification
            || notification == kAXWindowCreatedNotification {
            let now = Date()
            if var list = cachedWindowsByPID[pid],
               let idx = list.firstIndex(where: { CFEqual($0.axElement, element) }) {
                list[idx].lastActivatedAt = now
                cachedWindowsByPID[pid] = list
            }
        }
    }

    // MARK: - AX 属性読み取りユーティリティ

    /// 文字列属性を読み取る
    /// - Parameters:
    ///   - element: 対象の AXUIElement
    ///   - attribute: 読み取る属性名
    /// - Returns: 取得された文字列（失敗時は nil）
    private func copyStringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    /// 真偽値属性を読み取る
    /// - Parameters:
    ///   - element: 対象の AXUIElement
    ///   - attribute: 読み取る属性名
    /// - Returns: 取得された真偽値（失敗時は nil）
    private func copyBoolAttribute(_ element: AXUIElement, attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? Bool
    }

    /// 位置 (kAXPositionAttribute) とサイズ (kAXSizeAttribute) を組み合わせて CGRect を構築する
    /// - Parameter element: 対象の AXUIElement
    /// - Returns: 取得されたウィンドウ矩形（失敗時は nil）
    private func copyBounds(_ element: AXUIElement) -> CGRect? {
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
}
