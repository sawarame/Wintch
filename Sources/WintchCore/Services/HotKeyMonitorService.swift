import ApplicationServices
import CoreGraphics
import Foundation
import os

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
        // 通常スイッチャーは Shift の併用を逆順移動として許容するため Shift 以外の修飾キー一致で判定する
        let isNormalMatch = keyCode == snapshot.shortcut.keyCode
            && currentModifiers.subtracting(.shift) == snapshot.shortcut.modifiers
        let isLauncherMatch = keyCode == snapshot.launcherShortcut.keyCode
            && currentModifiers == snapshot.launcherShortcut.modifiers

        switch snapshot.activeMode {
        case .inactive:
            if isNormalMatch {
                let isShift = flags.contains(.maskShift)
                dispatchEvent(.triggerPressed(isShiftPressed: isShift))
                return nil
            }
            if isLauncherMatch {
                dispatchEvent(.launcherTriggerPressed)
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .normal:
            // 通常モード表示中は Esc および上下矢印キーを横取り消費する
            switch keyCode {
            case 53: // Esc キー
                dispatchEvent(.escapePressed)
                return nil
            case 126: // 上矢印キー
                dispatchEvent(.arrowPressed(direction: .up))
                return nil
            case 125: // 下矢印キー
                dispatchEvent(.arrowPressed(direction: .down))
                return nil
            default:
                break
            }

            if isNormalMatch {
                let isShift = flags.contains(.maskShift)
                dispatchEvent(.triggerPressed(isShiftPressed: isShift))
                return nil
            }
            // 通常モード表示中のランチャーショートカットは無視し、裏アプリへ漏らさないよう消費する
            if isLauncherMatch {
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .launcher:
            // ランチャー再押下はトグル終了として検知・消費する
            if isLauncherMatch {
                dispatchEvent(.launcherTriggerPressed)
                return nil
            }
            // ランチャー表示中の通常ショートカットは無視する
            if isNormalMatch {
                return nil
            }
            // Esc / 上下矢印 / 文字入力 / IME 変換操作はキーウィンドウへ通過させる
            return Unmanaged.passUnretained(event)
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
