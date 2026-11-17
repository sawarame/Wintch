import Foundation

/// グローバルショートカット起動トリガーの検知元経路
public enum HotKeyTriggerSource: Equatable, Sendable {
    /// 主経路である CGEventTap からの検知
    case cgEventTap
    /// 代替経路である Carbon RegisterEventHotKey からの検知
    case carbonHotKey
}

/// 重複排除および Carbon ホットキー識別対象となるトリガー種別
public enum HotKeyTriggerKind: Equatable, Sendable {
    /// 通常スイッチャー順方向
    case normalForward
    /// 通常スイッチャー逆方向（Shift 併用）
    case normalReverse
    /// 検索ランチャー起動またはトグル終了
    case launcher

    /// HotKeyEvent から対応する重複排除対象トリガー種別へ変換する
    /// - Parameter event: 判定対象の HotKeyEvent
    /// - Returns: 対象トリガー種別（移動・確定等の非トリガーイベントの場合は nil）
    public static func from(event: HotKeyEvent) -> HotKeyTriggerKind? {
        switch event {
        case let .triggerPressed(isShiftPressed):
            return isShiftPressed ? .normalReverse : .normalForward
        case .launcherTriggerPressed:
            return .launcher
        case .modifierReleased, .escapePressed, .arrowPressed, .closeSelectedWindowPressed:
            return nil
        }
    }

    /// トリガー種別に対応する HotKeyEvent を返す
    /// - Returns: 配送すべき HotKeyEvent
    public var hotKeyEvent: HotKeyEvent {
        switch self {
        case .normalForward:
            return .triggerPressed(isShiftPressed: false)
        case .normalReverse:
            return .triggerPressed(isShiftPressed: true)
        case .launcher:
            return .launcherTriggerPressed
        }
    }
}

/// CGEventTap と Carbon RegisterEventHotKey の双方から同一キー操作が二重通知されるのを防ぐ状態トラッカー
public struct HotKeyTriggerDeduplicator: Sendable {
    /// 異種経路間の同一トリガーを重複とみなす最大時間窓（秒）
    public let deduplicationWindowSeconds: TimeInterval

    /// 直前に受理したトリガー記録
    private struct AcceptedTrigger: Equatable, Sendable {
        let source: HotKeyTriggerSource
        let kind: HotKeyTriggerKind
        let timestamp: TimeInterval
    }

    /// 直前に受理したトリガーの経路・種別・単調増加時刻
    private var lastAcceptedTrigger: AcceptedTrigger?

    /// 重複排除トラッカーを初期化する
    /// - Parameter deduplicationWindowSeconds: 異種経路間の重複判定ウィンドウ幅（既定 0.15 秒）
    public init(deduplicationWindowSeconds: TimeInterval = 0.15) {
        self.deduplicationWindowSeconds = deduplicationWindowSeconds
    }

    /// 記録済みの直前トリガー状態を初期化する
    public mutating func reset() {
        lastAcceptedTrigger = nil
    }

    /// 指定経路・種別のトリガーを受理すべきか判定し、受理時は履歴を更新する
    /// - Parameters:
    ///   - source: 検知元の入力経路
    ///   - kind: 検知されたトリガー種別
    ///   - timestamp: 発生時の単調増加時刻（秒）
    /// - Returns: 重複でなく処理すべき場合は true、異種経路からの二重発火として破棄する場合は false
    public mutating func shouldAccept(
        source: HotKeyTriggerSource,
        kind: HotKeyTriggerKind,
        at timestamp: TimeInterval
    ) -> Bool {
        if let last = lastAcceptedTrigger,
           last.source != source,
           last.kind == kind {
            let elapsed = timestamp - last.timestamp
            if elapsed >= 0, elapsed < deduplicationWindowSeconds {
                return false
            }
        }

        lastAcceptedTrigger = AcceptedTrigger(source: source, kind: kind, timestamp: timestamp)
        return true
    }
}

/// Carbon RegisterEventHotKey へ登録する 1 件分のホットキー定義
public struct CarbonHotKeySpec: Equatable, Sendable {
    /// ホットキー識別 ID
    public let id: UInt32
    /// macOS 仮想キーコード
    public let keyCode: UInt32
    /// Carbon 修飾キーマスク（cmdKey / shiftKey / optionKey / controlKey のビット和）
    public let carbonModifiers: UInt32
    /// このホットキー発火時に対応するトリガー種別
    public let triggerKind: HotKeyTriggerKind

    /// Carbon ホットキー定義を初期化する
    /// - Parameters:
    ///   - id: 登録識別 ID
    ///   - keyCode: 仮想キーコード
    ///   - carbonModifiers: Carbon 修飾キーマスク
    ///   - triggerKind: 対応するトリガー種別
    public init(
        id: UInt32,
        keyCode: UInt32,
        carbonModifiers: UInt32,
        triggerKind: HotKeyTriggerKind
    ) {
        self.id = id
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.triggerKind = triggerKind
    }
}

/// 現在のショートカット設定と記録状態から Carbon ホットキー登録一覧を生成する純粋ビルダー
public enum CarbonHotKeyRegistrationPlan {
    /// 通常スイッチャー順方向の識別 ID
    public static let normalForwardID: UInt32 = 1
    /// 通常スイッチャー逆方向（Shift 併用）の識別 ID
    public static let normalReverseID: UInt32 = 2
    /// 検索ランチャーの識別 ID
    public static let launcherID: UInt32 = 3

    /// Carbon cmdKey ビット定数 (HIToolbox Events.h)
    public static let cmdKeyMask: UInt32 = 0x0100
    /// Carbon shiftKey ビット定数 (HIToolbox Events.h)
    public static let shiftKeyMask: UInt32 = 0x0200
    /// Carbon optionKey ビット定数 (HIToolbox Events.h)
    public static let optionKeyMask: UInt32 = 0x0800
    /// Carbon controlKey ビット定数 (HIToolbox Events.h)
    public static let controlKeyMask: UInt32 = 0x1000

    /// 共通修飾キー集合を Carbon RegisterEventHotKey 用のビットマスクへ変換する
    /// - Parameter modifiers: 変換対象の ShortcutModifiers
    /// - Returns: Carbon 修飾キービットマスク
    public static func carbonModifierFlags(from modifiers: ShortcutModifiers) -> UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.command) { mask |= cmdKeyMask }
        if modifiers.contains(.shift) { mask |= shiftKeyMask }
        if modifiers.contains(.option) { mask |= optionKeyMask }
        if modifiers.contains(.control) { mask |= controlKeyMask }
        return mask
    }

    /// 通常・ランチャー設定および記録サスペンド状態から登録すべきホットキー一覧を構築する
    /// - Parameters:
    ///   - shortcut: 通常スイッチャーのショートカット設定
    ///   - launcherShortcut: 検索ランチャーのショートカット設定
    ///   - isSuspendedForRecording: 設定画面でショートカット記録待機中か
    /// - Returns: 登録対象となる CarbonHotKeySpec の配列（記録中は空配列）
    public static func build(
        shortcut: ShortcutPreference,
        launcherShortcut: LauncherShortcutPreference,
        isSuspendedForRecording: Bool
    ) -> [CarbonHotKeySpec] {
        guard !isSuspendedForRecording else {
            return []
        }

        var specs: [CarbonHotKeySpec] = []

        // 通常スイッチャーは順方向および Shift 併用逆方向の 2 件を登録する
        if shortcut.modifiers.hasPrimaryModifier {
            specs.append(
                CarbonHotKeySpec(
                    id: normalForwardID,
                    keyCode: UInt32(shortcut.keyCode),
                    carbonModifiers: carbonModifierFlags(from: shortcut.modifiers),
                    triggerKind: .normalForward
                )
            )
            specs.append(
                CarbonHotKeySpec(
                    id: normalReverseID,
                    keyCode: UInt32(shortcut.keyCode),
                    carbonModifiers: carbonModifierFlags(from: shortcut.modifiers.union(.shift)),
                    triggerKind: .normalReverse
                )
            )
        }

        // 検索ランチャーはトグル用の 1 件を登録する
        if launcherShortcut.modifiers.hasPrimaryModifier {
            specs.append(
                CarbonHotKeySpec(
                    id: launcherID,
                    keyCode: UInt32(launcherShortcut.keyCode),
                    carbonModifiers: carbonModifierFlags(from: launcherShortcut.modifiers),
                    triggerKind: .launcher
                )
            )
        }

        return specs
    }
}

/// セキュア入力保護中の修飾キー状態誤検知を防ぎつつ高速解放を取りこぼさないための安全判定ヘルパー
public enum HotKeySecureInputGuard {
    /// セキュア入力が他プロセスに残留したまま自アプリがアクティブ化された場合の最短猶予時間（秒）
    public static let defaultActiveGraceSeconds: TimeInterval = 0.05

    /// 観測された修飾キー状態から「必須修飾キーが離された」と確定してよいか判定する
    /// - Parameters:
    ///   - requiredModifiers: 通常スイッチャー維持に必要な修飾キー集合
    ///   - observedModifiers: 現在観測された修飾キー集合
    ///   - isSecureInputEnabled: システムのセキュア入力保護が現在有効かどうか
    ///   - isAppActive: 自アプリがすでに最前面アクティブ状態か
    ///   - elapsedSincePresentation: フォールバック通常表示開始からの経過時間（秒）
    ///   - fallbackActiveGraceSeconds: セキュア入力残存時にアクティブ後判定を許可するまでの猶予時間（秒）
    /// - Returns: 確定処理へ進んでよい場合は true、誤検知の可能性があるため待機すべき場合は false
    public static func shouldTreatModifiersAsReleased(
        requiredModifiers: ShortcutModifiers,
        observedModifiers: ShortcutModifiers,
        isSecureInputEnabled: Bool,
        isAppActive: Bool,
        elapsedSincePresentation: TimeInterval,
        fallbackActiveGraceSeconds: TimeInterval = defaultActiveGraceSeconds
    ) -> Bool {
        guard !requiredModifiers.isSubset(of: observedModifiers) else {
            return false
        }

        // セキュア入力解除後は CGEventSource 等から正確な修飾キー状態を読めるため即時解放扱いとする
        if !isSecureInputEnabled {
            return true
        }

        // 他アプリ側でセキュア入力が残留していても、自アプリ前面化後の猶予経過後であればローカル修飾状態を採用する
        return isAppActive && elapsedSincePresentation >= fallbackActiveGraceSeconds
    }
}
