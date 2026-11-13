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
        var isSwitcherActive: Bool = false
    }

    /// イベント発生時の通知ハンドラ
    public var onEvent: ((HotKeyEvent) -> Void)?

    /// スイッチャーが現在表示中かどうか
    public var isSwitcherActive: Bool {
        get { sharedState.withLock { $0.isSwitcherActive } }
        set { sharedState.withLock { $0.isSwitcherActive = newValue } }
    }

    /// 非同期イベントタップコールバックと同期的に共有するロック付き状態
    private nonisolated let sharedState = OSAllocatedUnfairLock(initialState: TapState())

    /// アクティブな CGEventTap ポート
    private var eventTap: CFMachPort?

    /// メイン RunLoop へ登録したソース
    private var runLoopSource: CFRunLoopSource?

    /// HotKeyMonitorService を初期化する
    public init() {}

    /// 監視対象のショートカット設定を更新する
    /// - Parameter preference: 新しいショートカット設定
    public func updateShortcut(_ preference: ShortcutPreference) {
        sharedState.withLock { state in
            state.shortcut = preference
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
        isSwitcherActive = false
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
        let flags = event.flags

        if type == .flagsChanged {
            // スイッチャー表示中に必須修飾キーが離されたら確定イベントを送信する
            if snapshot.isSwitcherActive && !isModifierPressed(snapshot.shortcut.modifier, in: flags) {
                dispatchEvent(.modifierReleased)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // スイッチャー表示中は Esc および上下矢印キーを横取り消費する
        if snapshot.isSwitcherActive {
            switch keyCode {
            case 53: // Esc
                dispatchEvent(.escapePressed)
                return nil
            case 126: // 上矢印
                dispatchEvent(.arrowPressed(direction: .up))
                return nil
            case 125: // 下矢印
                dispatchEvent(.arrowPressed(direction: .down))
                return nil
            default:
                break
            }
        }

        // トリガーキーと必須修飾キーの一致判定
        if keyCode == snapshot.shortcut.trigger.keyCode,
           matchesRequiredModifierOnly(snapshot.shortcut.modifier, in: flags) {
            let isShift = flags.contains(.maskShift)
            dispatchEvent(.triggerPressed(isShiftPressed: isShift))
            // 他アプリへの文字入力や OS 標準スイッチャーの起動を防ぐためイベントを消費する
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    /// 検出されたキーイベントを MainActor 上のハンドラへ非同期配送する
    /// - Parameter event: 配送する HotKeyEvent
    private nonisolated func dispatchEvent(_ event: HotKeyEvent) {
        Task { @MainActor [weak self] in
            self?.onEvent?(event)
        }
    }

    /// 指定された修飾キーが現在のフラグに含まれているか判定する
    /// - Parameters:
    ///   - modifier: 判定対象の修飾キー
    ///   - flags: 現在の CGEventFlags
    /// - Returns: 押下中であれば true
    private nonisolated func isModifierPressed(_ modifier: ModifierKeyOption, in flags: CGEventFlags) -> Bool {
        switch modifier {
        case .option:
            return flags.contains(.maskAlternate)
        case .control:
            return flags.contains(.maskControl)
        case .command:
            return flags.contains(.maskCommand)
        }
    }

    /// 対象の修飾キーのみ（Shift の併用は許可）が押されているか判定する
    /// - Parameters:
    ///   - modifier: 必須の修飾キー
    ///   - flags: 現在の CGEventFlags
    /// - Returns: 一致する場合は true
    private nonisolated func matchesRequiredModifierOnly(
        _ modifier: ModifierKeyOption,
        in flags: CGEventFlags
    ) -> Bool {
        let hasOption = flags.contains(.maskAlternate)
        let hasControl = flags.contains(.maskControl)
        let hasCommand = flags.contains(.maskCommand)

        switch modifier {
        case .option:
            return hasOption && !hasControl && !hasCommand
        case .control:
            return hasControl && !hasOption && !hasCommand
        case .command:
            return hasCommand && !hasOption && !hasControl
        }
    }
}
