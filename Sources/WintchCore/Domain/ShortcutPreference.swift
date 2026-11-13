import Foundation

/// スイッチャーの起動および保持に使用する修飾キーの選択肢（後方互換およびプリセット定義用）
public enum ModifierKeyOption: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
    /// Option キー (⌥)
    case option
    /// Control キー (⌃)
    case control
    /// Command キー (⌘)
    case command

    /// Identifiable 準拠のための一意識別子
    public var id: String { rawValue }

    /// 設定画面に表示する日本語ラベル
    /// - Returns: 修飾キーの表示名
    public var displayName: String {
        switch self {
        case .option:
            return "Option (⌥)"
        case .control:
            return "Control (⌃)"
        case .command:
            return "Command (⌘)"
        }
    }

    /// 短縮表記用の記号文字
    /// - Returns: 修飾キー記号
    public var symbol: String {
        switch self {
        case .option:
            return "⌥"
        case .control:
            return "⌃"
        case .command:
            return "⌘"
        }
    }

    /// 共通修飾キーフラグ（ShortcutModifiers）への変換値
    /// - Returns: 対応する ShortcutModifiers
    public var shortcutModifierFlag: ShortcutModifiers {
        switch self {
        case .option:
            return .option
        case .control:
            return .control
        case .command:
            return .command
        }
    }

    /// 単一の ShortcutModifiers フラグから逆変換する
    /// - Parameter modifiers: 対象の修飾キー集合
    /// - Returns: 単一の主要修飾キーのみを含む場合は対応する ModifierKeyOption、それ以外は nil
    public static func from(_ modifiers: ShortcutModifiers) -> ModifierKeyOption? {
        switch modifiers {
        case [.option]:
            return .option
        case [.control]:
            return .control
        case [.command]:
            return .command
        default:
            return nil
        }
    }
}

/// 修飾キーと組み合わせてウィンドウ選択を送るトリガーキーの選択肢（後方互換およびプリセット定義用）
public enum TriggerKeyOption: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
    /// Tab キー (仮想キーコード: 48)
    case tab
    /// Space キー (仮想キーコード: 49)
    case space
    /// バッククォートキー (仮想キーコード: 50)
    case grave
    /// バックスラッシュキー (仮想キーコード: 42)
    case backslash

    /// Identifiable 準拠のための一意識別子
    public var id: String { rawValue }

    /// macOS 仮想キーコード (CGKeyCode 互換の UInt16 値)
    /// - Returns: 対応する仮想キーコード
    public var keyCode: UInt16 {
        switch self {
        case .tab:
            return 48
        case .space:
            return 49
        case .grave:
            return 50
        case .backslash:
            return 42
        }
    }

    /// 設定画面に表示するキー名
    /// - Returns: トリガーキーの表示名
    public var displayName: String {
        switch self {
        case .tab:
            return "Tab (⇥)"
        case .space:
            return "Space"
        case .grave:
            return "` (バッククォート)"
        case .backslash:
            return "\\ (バックスラッシュ)"
        }
    }

    /// 短縮表記用の記号文字
    /// - Returns: トリガーキー記号
    public var symbol: String {
        switch self {
        case .tab:
            return "⇥"
        case .space:
            return "Space"
        case .grave:
            return "`"
        case .backslash:
            return "\\"
        }
    }

    /// 仮想キーコードからプリセット列挙値へ逆変換する
    /// - Parameter keyCode: 仮想キーコード
    /// - Returns: 既知のプリセットに一致する場合は TriggerKeyOption、それ以外は nil
    public static func from(keyCode: UInt16) -> TriggerKeyOption? {
        TriggerKeyOption.allCases.first { $0.keyCode == keyCode }
    }
}

/// ユーザーが設定した通常スイッチャー起動ショートカット設定（ホールド式・任意キーキャプチャ対応）
public struct ShortcutPreference: Codable, Equatable, Sendable {
    /// デフォルト設定 (Option + Tab)
    public static let `default` = ShortcutPreference(modifier: .option, trigger: .tab)

    /// 仮想キーコード (CGKeyCode 互換の UInt16)
    public var keyCode: UInt16

    /// 保持する必須修飾キー集合（Shift は逆順予約のため除外）
    public var modifiers: ShortcutModifiers

    /// UI 表示用のキー名
    public var keyLabel: String

    /// 任意のキーコード・修飾キー・表示名からショートカット設定を初期化する
    /// - Parameters:
    ///   - keyCode: 仮想キーコード
    ///   - modifiers: 修飾キー集合
    ///   - keyLabel: UI 表示用のキー名
    public init(keyCode: UInt16, modifiers: ShortcutModifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// 従来のプリセット列挙型からショートカット設定を初期化する
    /// - Parameters:
    ///   - modifier: 修飾キー（Option / Control / Command）
    ///   - trigger: トリガーキー（Tab / Space / バッククォート / バックスラッシュ）
    public init(modifier: ModifierKeyOption, trigger: TriggerKeyOption) {
        self.keyCode = trigger.keyCode
        self.modifiers = [modifier.shortcutModifierFlag]
        self.keyLabel = trigger.symbol
    }

    /// 単一の主要修飾キーのみで構成されている場合に後方互換用の列挙値を返す
    /// - Returns: 一致する ModifierKeyOption、複数修飾キー等の場合は nil
    public var modifier: ModifierKeyOption? {
        ModifierKeyOption.from(modifiers)
    }

    /// 従来プリセットのトリガーキーに一致する場合に後方互換用の列挙値を返す
    /// - Returns: 一致する TriggerKeyOption、その他のキーの場合は nil
    public var trigger: TriggerKeyOption? {
        TriggerKeyOption.from(keyCode: keyCode)
    }

    /// macOS 標準のアプリケーションスイッチャー（Command + Tab）と競合するかどうか
    /// - Returns: 競合する場合は true
    public var conflictsWithSystemSwitcher: Bool {
        keyCode == TriggerKeyOption.tab.keyCode && modifiers == [.command]
    }

    /// 順方向操作の文字列表記（例: "⌥ + ⇥"）
    /// - Returns: 人間が読めるショートカット表記
    public var displayString: String {
        (modifiers.displaySymbols + [keyLabel]).joined(separator: " + ")
    }

    /// 逆方向操作の文字列表記（例: "⌥ + ⇧ + ⇥"）
    /// - Returns: Shift 併用時のショートカット表記
    public var reverseDisplayString: String {
        (modifiers.union(.shift).displaySymbols + [keyLabel]).joined(separator: " + ")
    }

    // MARK: - Codable（旧形式・新形式の両方からの安全なデコード対応）

    /// JSON エンコード・デコード用キー
    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
        case keyLabel
        case modifier
        case trigger
    }

    /// 新形式および従来の `{modifier, trigger}` 形式の双方からデコードする
    /// - Parameter decoder: デコーダ
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode),
           let modifiers = try container.decodeIfPresent(ShortcutModifiers.self, forKey: .modifiers),
           let keyLabel = try container.decodeIfPresent(String.self, forKey: .keyLabel) {
            self.init(keyCode: keyCode, modifiers: modifiers, keyLabel: keyLabel)
            return
        }

        // 旧バージョンの保存形式からのマイグレーション読み取り
        let legacyModifier = try container.decode(ModifierKeyOption.self, forKey: .modifier)
        let legacyTrigger = try container.decode(TriggerKeyOption.self, forKey: .trigger)
        self.init(modifier: legacyModifier, trigger: legacyTrigger)
    }

    /// 新形式で JSON エンコードする
    /// - Parameter encoder: エンコーダ
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encode(keyLabel, forKey: .keyLabel)
    }
}
