import ApplicationServices
import CoreGraphics
import Foundation
import os

/// keyDown イベントに対する判定結果（通知イベント有無とイベント消費有無）
public struct HotKeyKeyDownDecision: Equatable, Sendable {
    /// MainActor のイベントハンドラへ通知するイベント（無視または素通しの場合は nil）
    public let event: HotKeyEvent?
    /// OS および背面/キーウィンドウへのイベント伝播を遮断して消費する場合は true
    public let shouldConsume: Bool

    /// キー押下判定結果を初期化する
    /// - Parameters:
    ///   - event: 通知する HotKeyEvent（通知しない場合は nil）
    ///   - shouldConsume: イベントを消費して伝播を止める場合は true
    public init(event: HotKeyEvent?, shouldConsume: Bool) {
        self.event = event
        self.shouldConsume = shouldConsume
    }
}

/// CGEventTap のタイムアウト等で無効化された際の復帰アクション
public enum TapRecoveryAction: Equatable, Sendable {
    /// 即座にタップを再有効化する
    case reenableImmediately
    /// 指定秒数のクールダウン後に再有効化を試行する
    case reenableAfterCooldown(seconds: TimeInterval)
    /// 上限超過のため自動再有効化を停止する（サーキットブレーカー）
    case stopAutoReenable
}

/// CGEventTap の無効化通知に対する対処方針
public enum TapDisableDisposition: Equatable, Sendable {
    /// 一時的なタイムアウトであり、指定のリカバリーアクションに従って再有効化を試行する
    case attemptRecovery(TapRecoveryAction)
    /// 権限剥奪・ユーザー／システムによる無効化・上限超過のため即座にタップを破棄し監視を停止する
    case terminateAndNotify
}

/// CGEventTap のタイムアウト／システム無効化回数を監視し、無限再有効化ループを防ぐ状態トラッカー
public struct TapTimeoutRecoveryTracker: Sendable {
    /// 短時間バースト判定のウィンドウ幅（秒）
    public let burstWindowSeconds: TimeInterval
    /// バーストウィンドウ内で即時再有効化を許可する最大回数
    public let maxImmediateRetriesInWindow: Int
    /// バースト超過時のクールダウン待機時間（秒）
    public let cooldownSeconds: TimeInterval
    /// 長期サーキットブレーカー判定のウィンドウ幅（秒）
    public let longWindowSeconds: TimeInterval
    /// 長期ウィンドウ内で自動再有効化を許可する最大合計回数
    public let maxTotalRetriesInLongWindow: Int

    /// 記録された無効化イベントの単調増加タイムスタンプ履歴（秒）
    private var disableTimestamps: [TimeInterval] = []

    /// 復帰トラッカーを初期化する
    /// - Parameters:
    ///   - burstWindowSeconds: 短時間バースト判定ウィンドウ（秒）
    ///   - maxImmediateRetriesInWindow: 即時再有効化の上限回数
    ///   - cooldownSeconds: バースト超過時のクールダウン秒数
    ///   - longWindowSeconds: 長期判定ウィンドウ（秒）
    ///   - maxTotalRetriesInLongWindow: 長期ウィンドウ内の再有効化上限回数
    public init(
        burstWindowSeconds: TimeInterval = 10.0,
        maxImmediateRetriesInWindow: Int = 3,
        cooldownSeconds: TimeInterval = 5.0,
        longWindowSeconds: TimeInterval = 60.0,
        maxTotalRetriesInLongWindow: Int = 6
    ) {
        self.burstWindowSeconds = burstWindowSeconds
        self.maxImmediateRetriesInWindow = maxImmediateRetriesInWindow
        self.cooldownSeconds = cooldownSeconds
        self.longWindowSeconds = longWindowSeconds
        self.maxTotalRetriesInLongWindow = maxTotalRetriesInLongWindow
    }

    /// 記録済みの無効化履歴をすべてリセットする
    public mutating func reset() {
        disableTimestamps.removeAll()
    }

    /// 無効化イベントを記録し、今回の試行で行うべき復帰アクションを返す
    /// - Parameter timestamp: イベント発生時の単調増加時刻（秒）
    /// - Returns: 実行すべき TapRecoveryAction
    public mutating func recordDisableEvent(at timestamp: TimeInterval) -> TapRecoveryAction {
        let longCutoff = timestamp - longWindowSeconds
        disableTimestamps.removeAll { $0 < longCutoff }

        if disableTimestamps.count >= maxTotalRetriesInLongWindow {
            return .stopAutoReenable
        }

        disableTimestamps.append(timestamp)

        let burstCutoff = timestamp - burstWindowSeconds
        let burstCount = disableTimestamps.count { $0 >= burstCutoff }
        if burstCount <= maxImmediateRetriesInWindow {
            return .reenableImmediately
        }

        return .reenableAfterCooldown(seconds: cooldownSeconds)
    }
}

/// CGEventTap を用いてグローバルショートカットおよびスイッチャー表示中のキー操作を監視・横取りするサービス
@MainActor
public final class HotKeyMonitorService: HotKeyMonitoring {
    /// 非 Sendable な CoreFoundation / Foundation 参照をロック境界外へ安全に受け渡すラッパー
    private struct UncheckedSendable<Value>: @unchecked Sendable {
        let value: Value
    }

    /// スレッドセーフに共有する監視状態（C コールバックからの同期判定用）
    private struct TapState: Sendable {
        var shortcut: ShortcutPreference = .default
        var launcherShortcut: LauncherShortcutPreference = .default
        var activeMode: HotKeyMonitorMode = .inactive
        var isSuspendedForRecording: Bool = false
        /// 非同期ディスパッチ待ちの通常モード起動トリガーが存在するかどうか
        var pendingNormalTrigger: Bool = false
    }

    /// バックグラウンド監視スレッドおよびイベントタップのランタイム参照
    private struct TapRuntime: @unchecked Sendable {
        var eventTap: CFMachPort?
        var runLoopSource: CFRunLoopSource?
        var runLoop: CFRunLoop?
        var thread: Thread?
        var isMonitoring: Bool = false
        var pendingCooldownWorkItem: DispatchWorkItem?
    }

    /// 専用 RunLoop でのタップ生存・権限定期ヘルスチェック間隔（秒）
    private nonisolated static let healthCheckIntervalSeconds: TimeInterval = 0.2

    /// CGEventTap の C コールバック関数（バックグラウンド RunLoop スレッドで非分離実行するため static nonisolated で定義）
    private nonisolated static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let monitor = Unmanaged<HotKeyMonitorService>.fromOpaque(refcon).takeUnretainedValue()
        return monitor.handleCGEvent(proxy: proxy, type: type, event: event)
    }

    /// サービス用ロガー
    private nonisolated static let logger = Logger(
        subsystem: "dev.wintch",
        category: "HotKeyMonitorService"
    )

    /// イベント発生時の通知ハンドラ
    public var onEvent: ((HotKeyEvent) -> Void)?

    /// 権限剥奪やシステム無効化等によりグローバル監視が意図せず中断された際の通知ハンドラ
    public var onMonitoringInterrupted: (() -> Void)?

    /// 現在のスイッチャー監視モード
    public var activeMode: HotKeyMonitorMode {
        get { sharedState.withLock { $0.activeMode } }
        set {
            sharedState.withLock { state in
                state.activeMode = newValue
                state.pendingNormalTrigger = false
            }
        }
    }

    /// スイッチャーが現在表示中かどうか（activeMode と同期）
    public var isSwitcherActive: Bool {
        get { sharedState.withLock { $0.activeMode != .inactive } }
        set {
            sharedState.withLock { state in
                if newValue {
                    if state.activeMode == .inactive {
                        state.activeMode = .normal
                    }
                } else {
                    state.activeMode = .inactive
                }
                state.pendingNormalTrigger = false
            }
        }
    }

    /// 設定画面でショートカット記録中のためグローバル監視を一時停止するか
    public var isSuspendedForRecording: Bool {
        get { sharedState.withLock { $0.isSuspendedForRecording } }
        set { sharedState.withLock { $0.isSuspendedForRecording = newValue } }
    }

    /// 非同期イベントタップコールバックと同期的に共有するロック付き状態
    private nonisolated let sharedState = OSAllocatedUnfairLock(initialState: TapState())

    /// バックグラウンド監視スレッドとイベントタップのライフサイクルを保護するロック
    private nonisolated let runtimeLock = OSAllocatedUnfairLock(initialState: TapRuntime())

    /// タイムアウト無効化からの復帰回数・クールダウンを管理するロック付きトラッカー
    private nonisolated let recoveryTracker = OSAllocatedUnfairLock(initialState: TapTimeoutRecoveryTracker())

    /// HotKeyMonitorService を初期化する
    public init() {}

    /// インスタンス破棄時にバックグラウンドのイベントタップと監視スレッドを確実に停止する
    deinit {
        cleanupTapRuntime()
    }

    /// 通常スイッチャーの監視対象ショートカット設定を更新する
    /// - Parameter preference: 新しいショートカット設定
    public func updateShortcut(_ preference: ShortcutPreference) {
        sharedState.withLock { state in
            state.shortcut = preference
        }
    }

    /// ランチャーモードの監視対象ショートカット設定を更新する
    /// - Parameter preference: 新しいランチャーショートカット設定
    public func updateLauncherShortcut(_ preference: LauncherShortcutPreference) {
        sharedState.withLock { state in
            state.launcherShortcut = preference
        }
    }

    /// グローバルイベント監視を専用バックグラウンドスレッドで開始する（アクセシビリティ権限が必要）
    /// - Returns: イベントタップの作成・有効化に成功した場合は true
    @discardableResult
    public func startMonitoring() -> Bool {
        if runtimeLock.withLock({ $0.isMonitoring }) {
            return true
        }

        // 未許可状態で CGEventTap を開始しないよう事前検証する
        guard AccessibilityPermissionService.isProcessTrusted() else {
            Self.logger.warning("アクセシビリティ権限が確認できないため CGEventTap の開始を見送りました")
            return false
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: Self.eventTapCallback,
            userInfo: selfPtr
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        recoveryTracker.withLock { $0.reset() }

        let boxedTap = UncheckedSendable(value: tap)
        let boxedSource = UncheckedSendable(value: source)
        let readySemaphore = DispatchSemaphore(value: 0)
        let startupLock = OSAllocatedUnfairLock(initialState: false)
        let thread = Thread { [weak self] in
            guard let self else {
                readySemaphore.signal()
                return
            }

            let currentRunLoop = UncheckedSendable(value: CFRunLoopGetCurrent())
            let initialShouldRun = self.runtimeLock.withLock { state -> Bool in
                guard state.isMonitoring else { return false }
                state.runLoop = currentRunLoop.value
                CFRunLoopAddSource(currentRunLoop.value, boxedSource.value, .commonModes)
                CGEvent.tapEnable(tap: boxedTap.value, enable: true)
                return CFMachPortIsValid(boxedTap.value)
                    && CGEvent.tapIsEnabled(tap: boxedTap.value)
                    && AccessibilityPermissionService.isProcessTrusted()
            }
            startupLock.withLock { $0 = initialShouldRun }
            readySemaphore.signal()

            var shouldRun = initialShouldRun

            // stopMonitoring() による停止指示またはヘルスチェック異常まで専用 RunLoop でイベントタップを処理する
            while shouldRun {
                let result = CFRunLoopRunInMode(.defaultMode, Self.healthCheckIntervalSeconds, false)
                if result == .stopped || result == .finished {
                    break
                }
                shouldRun = self.evaluateActiveTapHealthOnRunLoopThread()
            }
        }
        thread.name = "dev.wintch.HotKeyMonitor.EventTap"
        thread.qualityOfService = .userInteractive

        let boxedThread = UncheckedSendable(value: thread)
        runtimeLock.withLock { state in
            state.eventTap = boxedTap.value
            state.runLoopSource = boxedSource.value
            state.thread = boxedThread.value
            state.isMonitoring = true
        }

        thread.start()
        readySemaphore.wait()

        let didStartHealthy = startupLock.withLock { $0 }
        if !didStartHealthy {
            Self.logger.warning("CGEventTap の起動後健全性チェックに失敗したため即時破棄しました")
            cleanupTapRuntime()
            return false
        }
        Self.logger.notice("CGEventTap グローバルキーボード監視を開始しました")
        return true
    }

    /// グローバルイベント監視を停止し、専用スレッドとリソースを解放する
    public func stopMonitoring() {
        cleanupTapRuntime()
        resetSharedMonitoringState()
    }

    /// イベントタップ・RunLoop ソース・クールダウン予約をスレッドセーフに停止・破棄する
    /// - Returns: 実際に監視中だったランタイムを破棄した場合は true
    @discardableResult
    private nonisolated func cleanupTapRuntime() -> Bool {
        let extracted = runtimeLock.withLock { state -> TapRuntime in
            let snapshot = state
            state = TapRuntime()
            return snapshot
        }

        extracted.pendingCooldownWorkItem?.cancel()
        if let tap = extracted.eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop = extracted.runLoop {
            if let source = extracted.runLoopSource {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            CFRunLoopStop(runLoop)
        }
        return extracted.isMonitoring
    }

    /// 共有中のアクティブモードと保留トリガー状態を初期化する
    private nonisolated func resetSharedMonitoringState() {
        sharedState.withLock { state in
            state.activeMode = .inactive
            state.pendingNormalTrigger = false
        }
    }

    // MARK: - イベントコールバック処理（nonisolated）

    /// CGEventTap のコールバックから直接呼び出される軽量なイベント判定・消費処理
    /// - Parameters:
    ///   - proxy: イベントタッププロキシ
    ///   - type: イベント種別
    ///   - event: 受信した CGEvent
    /// - Returns: イベントをそのまま通過させる場合は非 nil、横取り消費する場合は nil
    private nonisolated func handleCGEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // OS のタイムアウト等でタップが無効化された場合は制限・クールダウン付きで再有効化する
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handleTapDisabled(reason: type)
            return Unmanaged.passUnretained(event)
        }

        let snapshot = sharedState.withLock { $0 }

        // 設定画面のショートカット記録待機中はすべてのキー入力を通過させる
        if snapshot.isSuspendedForRecording {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let currentModifiers = extractShortcutModifiers(from: flags)

        if type == .flagsChanged {
            // 通常モード表示中（または起動ディスパッチ待ち中）に必須修飾キーが離されたら確定イベントを送信する
            let shouldDispatchRelease = sharedState.withLock { state -> Bool in
                let isReleased = !state.shortcut.modifiers.isSubset(of: currentModifiers)
                guard isReleased else { return false }
                if state.activeMode == .normal {
                    return true
                }
                if state.pendingNormalTrigger {
                    state.pendingNormalTrigger = false
                    return true
                }
                return false
            }
            if shouldDispatchRelease {
                dispatchEvent(.modifierReleased)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let decision = Self.resolveKeyDown(
            mode: snapshot.activeMode,
            keyCode: keyCode,
            modifiers: currentModifiers,
            shortcut: snapshot.shortcut,
            launcherShortcut: snapshot.launcherShortcut
        )
        if let hotKeyEvent = decision.event {
            if case .triggerPressed = hotKeyEvent, snapshot.activeMode == .inactive {
                sharedState.withLock { state in
                    state.pendingNormalTrigger = true
                }
            }
            dispatchEvent(hotKeyEvent)
        }
        return decision.shouldConsume ? nil : Unmanaged.passUnretained(event)
    }

    /// 専用 RunLoop 上で現在のイベントタップと権限の健全性を検証し、異常時は即座に破棄する
    /// - Returns: 監視を継続可能な場合は true、停止または異常検知で終了すべき場合は false
    private nonisolated func evaluateActiveTapHealthOnRunLoopThread() -> Bool {
        let snapshot = runtimeLock.withLock { state -> (isMonitoring: Bool, tap: UncheckedSendable<CFMachPort>?, isCoolingDown: Bool) in
            (
                state.isMonitoring,
                state.eventTap.map { UncheckedSendable(value: $0) },
                state.pendingCooldownWorkItem != nil
            )
        }

        guard snapshot.isMonitoring, let tap = snapshot.tap?.value else {
            return false
        }

        let isPortValid = CFMachPortIsValid(tap)
        // クールダウン待機中は一時的に無効化されているため、ポート生存とライブ権限のみを検証する
        let isTapEnabled = snapshot.isCoolingDown ? true : CGEvent.tapIsEnabled(tap: tap)
        let isTrusted = AccessibilityPermissionService.isProcessTrusted()

        if !Self.isTapHealthy(
            isMachPortValid: isPortValid,
            isTapEnabled: isTapEnabled,
            isPermissionTrusted: isTrusted
        ) {
            terminateMonitoringFromSystem(
                reason: "ヘルスチェック失敗 (valid=\(isPortValid), enabled=\(isTapEnabled), trusted=\(isTrusted))"
            )
            return false
        }
        return true
    }

    /// 権限剥奪やシステム無効化により監視継続不能になった際、タップを安全破棄して MainActor へ通知する
    /// - Parameter reason: 停止理由の説明文字列
    private nonisolated func terminateMonitoringFromSystem(reason: String) {
        let didCleanup = cleanupTapRuntime()
        guard didCleanup else { return }
        resetSharedMonitoringState()
        Self.logger.warning("キーボード入力保護のため CGEventTap 監視を自動停止しました: \(reason, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.onMonitoringInterrupted?()
            }
        }
    }

    /// タイムアウト等でタップが無効化された際に理由と権限を確認し、復帰または即時破棄を行う
    /// - Parameter reason: 無効化理由の CGEventType
    private nonisolated func handleTapDisabled(reason: CGEventType) {
        let now = ProcessInfo.processInfo.systemUptime
        let isTrusted = AccessibilityPermissionService.isProcessTrusted()
        let disposition = recoveryTracker.withLock { tracker in
            Self.resolveTapDisableDisposition(
                reason: reason,
                isPermissionTrusted: isTrusted,
                tracker: &tracker,
                at: now
            )
        }

        switch disposition {
        case .terminateAndNotify:
            terminateMonitoringFromSystem(
                reason: "OS無効化通知 (reason=\(reason.rawValue), trusted=\(isTrusted))"
            )
        case let .attemptRecovery(action):
            switch action {
            case .reenableImmediately:
                scheduleImmediateTapReenable()
            case let .reenableAfterCooldown(seconds):
                Self.logger.warning(
                    "CGEventTap が短時間に繰り返し無効化されたため \(seconds, format: .fixed(precision: 1)) 秒後に再有効化します (reason: \(reason.rawValue))"
                )
                scheduleDelayedTapReenable(after: seconds)
            case .stopAutoReenable:
                terminateMonitoringFromSystem(reason: "自動再有効化上限に到達 (reason=\(reason.rawValue))")
            }
        }
    }

    /// 専用 RunLoop 上で即座にタップを再有効化し、健全性を検証する
    private nonisolated func scheduleImmediateTapReenable() {
        let snapshot = runtimeLock.withLock { state -> TapRuntime in
            let previous = state.pendingCooldownWorkItem
            state.pendingCooldownWorkItem = nil
            previous?.cancel()
            return state
        }

        guard snapshot.isMonitoring, let tap = snapshot.eventTap else { return }
        let boxedTap = UncheckedSendable(value: tap)
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
                self?.enableTapAndVerifyHealth(boxedTap.value, context: "即時再有効化")
            }
            CFRunLoopWakeUp(runLoop)
        } else {
            enableTapAndVerifyHealth(boxedTap.value, context: "即時再有効化")
        }
    }

    /// 指定秒数のクールダウン経過後にタップを再有効化し、健全性を検証する
    /// - Parameter seconds: 待機秒数
    private nonisolated func scheduleDelayedTapReenable(after seconds: TimeInterval) {
        let boxedWorkItem = UncheckedSendable(value: DispatchWorkItem { [weak self] in
            guard let self else { return }
            let boxedTap = self.runtimeLock.withLock { state -> UncheckedSendable<CFMachPort>? in
                state.pendingCooldownWorkItem = nil
                guard state.isMonitoring, let tap = state.eventTap else { return nil }
                return UncheckedSendable(value: tap)
            }
            if let tap = boxedTap?.value {
                self.enableTapAndVerifyHealth(tap, context: "クールダウン後再有効化")
            }
        })

        let previousWorkItem = runtimeLock.withLock { state -> UncheckedSendable<DispatchWorkItem>? in
            let prev = state.pendingCooldownWorkItem.map { UncheckedSendable(value: $0) }
            guard state.isMonitoring else {
                state.pendingCooldownWorkItem = nil
                return prev
            }
            state.pendingCooldownWorkItem = boxedWorkItem.value
            return prev
        }
        previousWorkItem?.value.cancel()

        DispatchQueue.global(qos: .userInteractive).asyncAfter(
            deadline: .now() + seconds,
            execute: boxedWorkItem.value
        )
    }

    /// タップを再有効化し、直後に権限およびポートの健全性を検証する（失敗時は即座に破棄して上位へ通知する）
    /// - Parameters:
    ///   - tap: 再有効化対象の CFMachPort
    ///   - context: ログ出力用のコンテキスト文字列
    private nonisolated func enableTapAndVerifyHealth(_ tap: CFMachPort, context: String) {
        let boxedTap = UncheckedSendable(value: tap)
        let isStillTargetTap = runtimeLock.withLock { state in
            state.isMonitoring && state.eventTap.map { CFEqual($0, boxedTap.value) } == true
        }
        guard isStillTargetTap else { return }

        guard AccessibilityPermissionService.isProcessTrusted() else {
            terminateMonitoringFromSystem(reason: "\(context): 権限喪失を検知")
            return
        }

        CGEvent.tapEnable(tap: tap, enable: true)

        let isHealthy = Self.isTapHealthy(
            isMachPortValid: CFMachPortIsValid(tap),
            isTapEnabled: CGEvent.tapIsEnabled(tap: tap),
            isPermissionTrusted: true
        )
        if !isHealthy {
            terminateMonitoringFromSystem(reason: "\(context): 再有効化後のタップ健全性確認に失敗")
        }
    }

    /// CGEventTap の無効化イベントに対する対処方針を決定する純粋判定関数
    /// - Parameters:
    ///   - reason: OS から受信した無効化理由の CGEventType
    ///   - isPermissionTrusted: 現在のアクセシビリティ権限が有効であるか
    ///   - tracker: タイムアウト復帰回数トラッカー
    ///   - timestamp: イベント発生時の単調増加時刻（秒）
    /// - Returns: 実行すべき TapDisableDisposition
    public nonisolated static func resolveTapDisableDisposition(
        reason: CGEventType,
        isPermissionTrusted: Bool,
        tracker: inout TapTimeoutRecoveryTracker,
        at timestamp: TimeInterval
    ) -> TapDisableDisposition {
        // ユーザー操作・権限剥奪・権限未許可状態での無効化は絶対に再有効化せず即座に破棄する
        guard reason == .tapDisabledByTimeout, isPermissionTrusted else {
            return .terminateAndNotify
        }
        let recoveryAction = tracker.recordDisableEvent(at: timestamp)
        switch recoveryAction {
        case .reenableImmediately, .reenableAfterCooldown:
            return .attemptRecovery(recoveryAction)
        case .stopAutoReenable:
            return .terminateAndNotify
        }
    }

    /// タップの生存状態と権限状態から監視を継続可能か判定する純粋判定関数
    /// - Parameters:
    ///   - isMachPortValid: CFMachPortIsValid の結果
    ///   - isTapEnabled: CGEvent.tapIsEnabled の結果
    ///   - isPermissionTrusted: 現在のライブアクセシビリティ権限状態
    /// - Returns: 継続可能な場合は true、即座にタップを破棄すべき場合は false
    public nonisolated static func isTapHealthy(
        isMachPortValid: Bool,
        isTapEnabled: Bool,
        isPermissionTrusted: Bool
    ) -> Bool {
        isMachPortValid && isTapEnabled && isPermissionTrusted
    }

    /// 選択中ウィンドウを閉じる操作に割り当てる Q キーの仮想キーコード (ANSI kVK_ANSI_Q)
    public nonisolated static let closeWindowKeyCode: UInt16 = 12

    /// 現在の監視モードとキー入力から通知イベントおよび消費有無を判定する純粋関数
    /// - Parameters:
    ///   - mode: 現在の監視モード
    ///   - keyCode: 押下されたキーの仮想キーコード
    ///   - modifiers: 現在押されている修飾キー集合
    ///   - shortcut: 通常スイッチャーのショートカット設定
    ///   - launcherShortcut: 検索ランチャーのショートカット設定
    /// - Returns: 通知イベントと消費判定を含む HotKeyKeyDownDecision
    public nonisolated static func resolveKeyDown(
        mode: HotKeyMonitorMode,
        keyCode: UInt16,
        modifiers: ShortcutModifiers,
        shortcut: ShortcutPreference,
        launcherShortcut: LauncherShortcutPreference
    ) -> HotKeyKeyDownDecision {
        // 通常スイッチャーは Shift の併用を逆順移動として許容するため Shift 以外の修飾キー一致で判定する
        let isNormalMatch = keyCode == shortcut.keyCode
            && modifiers.subtracting(.shift) == shortcut.modifiers
        let isLauncherMatch = keyCode == launcherShortcut.keyCode
            && modifiers == launcherShortcut.modifiers
        // ウィンドウ終了操作（修飾キー + Q）は逆順移動直後の Shift 残存も許容して判定する
        let isCloseWindowMatch = keyCode == closeWindowKeyCode
            && modifiers.subtracting(.shift) == shortcut.modifiers
        let isShiftPressed = modifiers.contains(.shift)

        switch mode {
        case .inactive:
            if isNormalMatch {
                return HotKeyKeyDownDecision(
                    event: .triggerPressed(isShiftPressed: isShiftPressed),
                    shouldConsume: true
                )
            }
            if isLauncherMatch {
                return HotKeyKeyDownDecision(
                    event: .launcherTriggerPressed,
                    shouldConsume: true
                )
            }
            return HotKeyKeyDownDecision(event: nil, shouldConsume: false)

        case .normal:
            // 通常モード表示中は Esc および上下左右矢印キーを横取り消費する
            switch keyCode {
            case 53: // Esc キー
                return HotKeyKeyDownDecision(event: .escapePressed, shouldConsume: true)
            case 126: // 上矢印キー
                return HotKeyKeyDownDecision(event: .arrowPressed(direction: .up), shouldConsume: true)
            case 125: // 下矢印キー
                return HotKeyKeyDownDecision(event: .arrowPressed(direction: .down), shouldConsume: true)
            case 123: // 左矢印キー
                return HotKeyKeyDownDecision(event: .arrowPressed(direction: .left), shouldConsume: true)
            case 124: // 右矢印キー
                return HotKeyKeyDownDecision(event: .arrowPressed(direction: .right), shouldConsume: true)
            default:
                break
            }

            if isNormalMatch {
                return HotKeyKeyDownDecision(
                    event: .triggerPressed(isShiftPressed: isShiftPressed),
                    shouldConsume: true
                )
            }
            // 通常モード表示中のランチャーショートカットは無視し、裏アプリへ漏らさないよう消費する
            if isLauncherMatch {
                return HotKeyKeyDownDecision(event: nil, shouldConsume: true)
            }
            // 通常スイッチャー必須修飾キー + Q で選択ウィンドウ終了イベントを通知して消費する
            if isCloseWindowMatch {
                return HotKeyKeyDownDecision(
                    event: .closeSelectedWindowPressed,
                    shouldConsume: true
                )
            }
            return HotKeyKeyDownDecision(event: nil, shouldConsume: false)

        case .launcher:
            // ランチャー再押下はトグル終了として検知・消費する（設定重複時も最優先）
            if isLauncherMatch {
                return HotKeyKeyDownDecision(
                    event: .launcherTriggerPressed,
                    shouldConsume: true
                )
            }
            // ランチャー表示中の通常ショートカットは候補移動（次へ/前へ）として通知し消費する
            if isNormalMatch {
                return HotKeyKeyDownDecision(
                    event: .triggerPressed(isShiftPressed: isShiftPressed),
                    shouldConsume: true
                )
            }
            // 通常スイッチャー必須修飾キー + Q は選択ウィンドウ終了として通知し、特殊文字入力等を防ぐため消費する
            if isCloseWindowMatch {
                return HotKeyKeyDownDecision(
                    event: .closeSelectedWindowPressed,
                    shouldConsume: true
                )
            }
            // Esc / 上下矢印 / 単体 Q や Shift + Q を含む文字入力 / IME 変換操作はキーウィンドウへ通過させる
            return HotKeyKeyDownDecision(event: nil, shouldConsume: false)
        }
    }

    /// 検出されたキーイベントを MainActor 上のハンドラへ発生順を保って非同期配送する
    /// - Parameter event: 配送する HotKeyEvent
    private nonisolated func dispatchEvent(_ event: HotKeyEvent) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.onEvent?(event)
            }
        }
    }

    /// CGEventFlags から比較用の 4 修飾キー集合を抽出する
    /// - Parameter flags: 現在の CGEventFlags
    /// - Returns: 抽出された ShortcutModifiers
    private nonisolated func extractShortcutModifiers(from flags: CGEventFlags) -> ShortcutModifiers {
        var result: ShortcutModifiers = []
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        return result
    }
}
