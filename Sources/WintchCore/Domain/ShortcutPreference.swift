import Foundation

/// スイッチャーの起動および保持に使用する修飾キーの選択肢
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
}

/// 修飾キーと組み合わせてウィンドウ選択を送るトリガーキーの選択肢
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
}

/// ユーザーが選択したスイッチャー起動ショートカット設定
public struct ShortcutPreference: Codable, Equatable, Sendable {
    /// デフォルト設定 (Option + Tab)
    public static let `default` = ShortcutPreference(modifier: .option, trigger: .tab)

    /// 保持する修飾キー
    public var modifier: ModifierKeyOption

    /// 選択移動を行うトリガーキー
    public var trigger: TriggerKeyOption

    /// ショートカット設定を初期化する
    /// - Parameters:
    ///   - modifier: 修飾キー（Option / Control / Command）
    ///   - trigger: トリガーキー（Tab / Space / バッククォート / バックスラッシュ）
    public init(modifier: ModifierKeyOption, trigger: TriggerKeyOption) {
        self.modifier = modifier
        self.trigger = trigger
    }

    /// macOS 標準のアプリケーションスイッチャー（Command + Tab）と競合するかどうか
    /// - Returns: 競合する場合は true
    public var conflictsWithSystemSwitcher: Bool {
        modifier == .command && trigger == .tab
    }

    /// 順方向操作の文字列表記（例: "⌥ + ⇥"）
    /// - Returns: 人間が読めるショートカット表記
    public var displayString: String {
        "\(modifier.symbol) + \(trigger.symbol)"
    }

    /// 逆方向操作の文字列表記（例: "⌥ + ⇧ + ⇥"）
    /// - Returns: Shift 併用時のショートカット表記
    public var reverseDisplayString: String {
        "\(modifier.symbol) + ⇧ + \(trigger.symbol)"
    }
}
