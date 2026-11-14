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

/// CGEventTap を用いてグローバルショートカットおよびスイッチャー表示中のキー操作を監視・横取りするサービス
@MainActor
public final class HotKeyMonitorService: HotKeyMonitoring {
    /// スレッドセーフに共有する監視状態（C コールバックからの同期判定用）
    private struct TapState: Sendable {
        var shortcut: ShortcutPreference = .default
        var launcherShortcut: LauncherShortcutPreference = .default
        var activeMode: HotKeyMonitorMode = .inactive
        var isSuspendedForRecording: Bool = false
    }

    /// イベント発生時の通知ハンドラ
    public var onEvent: ((HotKeyEvent) -> Void)?

    /// 現在のスイッチャー監視モード
    public var activeMode: HotKeyMonitorMode {
        get { sharedState.withLock { $0.activeMode } }
        set { sharedState.withLock { $0.activeMode = newValue } }
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

    /// アクティブな CGEventTap ポート
    private var eventTap: CFMachPort?

    /// メイン RunLoop へ登録したソース
    private var runLoopSource: CFRunLoopSource?

    /// HotKeyMonitorService を初期化する
    public init() {}

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

    /// グローバルイベント監視を開始する（アクセシビリティ権限が必要）
    /// - Returns: イベントタップの作成・有効化に成功した場合は true
    @discardableResult
    public func startMonitoring() -> Bool {
        if eventTap != nil {
            return true
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<HotKeyMonitorService>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    /// グローバルイベント監視を停止し、リソースを解放する
    public func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        activeMode = .inactive
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
        // OS のタイムアウト等でタップが無効化された場合は即座に再有効化する
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor [weak self] in
                if let tap = self?.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
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
            // 通常モード表示中のみ必須修飾キーのいずれかが離されたら確定イベントを送信する
            if snapshot.activeMode == .normal && !snapshot.shortcut.modifiers.isSubset(of: currentModifiers) {
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
            dispatchEvent(hotKeyEvent)
        }
        return decision.shouldConsume ? nil : Unmanaged.passUnretained(event)
    }

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
            // 通常モード表示中は Esc および上下矢印キーを横取り消費する
            switch keyCode {
            case 53: // Esc キー
                return HotKeyKeyDownDecision(event: .escapePressed, shouldConsume: true)
            case 126: // 上矢印キー
                return HotKeyKeyDownDecision(event: .arrowPressed(direction: .up), shouldConsume: true)
            case 125: // 下矢印キー
                return HotKeyKeyDownDecision(event: .arrowPressed(direction: .down), shouldConsume: true)
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
            // Esc / 上下矢印 / 文字入力 / IME 変換操作はキーウィンドウへ通過させる
            return HotKeyKeyDownDecision(event: nil, shouldConsume: false)
        }
    }

    /// 検出されたキーイベントを MainActor 上のハンドラへ非同期配送する
    /// - Parameter event: 配送する HotKeyEvent
    private nonisolated func dispatchEvent(_ event: HotKeyEvent) {
        Task { @MainActor [weak self] in
            self?.onEvent?(event)
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
