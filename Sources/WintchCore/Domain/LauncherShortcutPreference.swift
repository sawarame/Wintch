import Foundation

/// ショートカットキーに組み合わせる修飾キーの集合
public struct ShortcutModifiers: OptionSet, Codable, Equatable, Hashable, Sendable {
    /// 生のビットマスク値
    public let rawValue: Int

    /// ビットマスク値から修飾キー集合を初期化する
    /// - Parameter rawValue: ビットマスク整数値
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Control キー (⌃)
    public static let control = ShortcutModifiers(rawValue: 1 << 0)
    /// Option キー (⌥)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    /// Shift キー (⇧)
    public static let shift = ShortcutModifiers(rawValue: 1 << 2)
    /// Command キー (⌘)
    public static let command = ShortcutModifiers(rawValue: 1 << 3)

    /// Command / Option / Control のいずれか1つ以上が含まれているか
    /// - Returns: 必須修飾キーを含む場合は true
    public var hasPrimaryModifier: Bool {
        contains(.command) || contains(.option) || contains(.control)
    }

    /// macOS 標準の表示順（⌃ → ⌥ → ⇧ → ⌘）で記号配列を返す
    /// - Returns: 含まれる修飾キー記号の配列
    public var displaySymbols: [String] {
        var symbols: [String] = []
        if contains(.control) { symbols.append("⌃") }
        if contains(.option) { symbols.append("⌥") }
        if contains(.shift) { symbols.append("⇧") }
        if contains(.command) { symbols.append("⌘") }
        return symbols
    }
}

/// ランチャー（検索モード）を起動・トグル終了するためのショートカット設定
public struct LauncherShortcutPreference: Codable, Equatable, Sendable {
    /// デフォルト設定 (Option + Space)
    public static let `default` = LauncherShortcutPreference(
        keyCode: 49,
        modifiers: [.option],
        keyLabel: "Space"
    )

    /// Esc キーの仮想キーコード
    public static let escapeKeyCode: UInt16 = 53

    /// 修飾キー単体の仮想キーコード集合（トリガーキーとして除外）
    private static let modifierOnlyKeyCodes: Set<UInt16> = [
        54, 55, // 右・左 Command キー
        56, 60, // 左・右 Shift キー
        57,     // Caps Lock キー
        58, 61, // 左・右 Option キー
        59, 62, // 左・右 Control キー
        63      // Fn キー
    ]

    /// 仮想キーコード (CGKeyCode 互換の UInt16)
    public var keyCode: UInt16

    /// 組み合わせる修飾キー
    public var modifiers: ShortcutModifiers

    /// UI 表示用のキー名
    public var keyLabel: String

    /// ランチャーショートカット設定を初期化する
    /// - Parameters:
    ///   - keyCode: 仮想キーコード
    ///   - modifiers: 修飾キー集合
    ///   - keyLabel: UI 表示用のキー名
    public init(keyCode: UInt16, modifiers: ShortcutModifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// 画面表示用のショートカット文字列（例: "⌥ + Space"）
    /// - Returns: 記号とキー名を結合した文字列
    public var displayString: String {
        let parts = modifiers.displaySymbols + [keyLabel]
        return parts.joined(separator: " + ")
    }

    /// 指定されたキーコードが修飾キー単体または Esc キー（トリガーとして無効）か判定する
    /// - Parameter keyCode: 判定対象の仮想キーコード
    /// - Returns: トリガーキーとして無視すべき場合は true
    public static func isNonTriggerKeyCode(_ keyCode: UInt16) -> Bool {
        keyCode == escapeKeyCode || modifierOnlyKeyCodes.contains(keyCode)
    }

    /// 仮想キーコードと文字情報から UI 表示用のキーラベルを生成する
    /// - Parameters:
    ///   - keyCode: macOS 仮想キーコード
    ///   - charactersIgnoringModifiers: 修飾キーを除いた入力文字（任意）
    /// - Returns: 人間が読めるキー名
    public static func resolveKeyLabel(
        for keyCode: UInt16,
        charactersIgnoringModifiers: String? = nil
    ) -> String {
        if let special = specialKeyLabels[keyCode] {
            return special
        }

        if let rawChars = charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawChars.isEmpty {
            return rawChars.uppercased()
        }

        if let ansiLabel = ansiKeyLabels[keyCode] {
            return ansiLabel
        }

        return "Key(\(keyCode))"
    }

    /// 特殊キーの仮想キーコードから表示ラベルへの対応表
    private static let specialKeyLabels: [UInt16: String] = [
        36: "↩",
        48: "⇥",
        49: "Space",
        51: "⌫",
        76: "⌤",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        117: "⌦",
        118: "F4",
        120: "F2",
        122: "F1",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑"
    ]

    /// ANSI キー配列における標準文字キーのフォールバック対応表
    private static let ansiKeyLabels: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`"
    ]
}
