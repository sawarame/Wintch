import Foundation

/// ショートカット検証結果
public enum ShortcutValidationResult: Equatable, Sendable {
    /// 有効かつ競合なし
    case valid
    /// 必須修飾キーが不足している、または禁止された修飾キーが含まれている
    case invalidModifier(String)
    /// 通常スイッチャーのショートカットと重複している
    case conflictWithNormalSwitcher(String)
    /// ランチャーのショートカットと重複している
    case conflictWithLauncher(String)

    /// 検証エラーメッセージ（有効な場合は nil）
    /// - Returns: エラー説明文、または nil
    public var errorMessage: String? {
        switch self {
        case .valid:
            return nil
        case let .invalidModifier(message),
             let .conflictWithNormalSwitcher(message),
             let .conflictWithLauncher(message):
            return message
        }
    }

    /// 登録・適用可能な有効状態かどうか
    /// - Returns: 有効であれば true
    public var isValid: Bool {
        self == .valid
    }
}

/// ランチャーショートカットと通常スイッチャーショートカットの妥当性および双方向競合を検証する純粋ロジック
public enum ShortcutConflictValidator {
    /// ランチャー用ショートカット候補が登録可能か検証する
    /// - Parameters:
    ///   - candidate: 登録候補のランチャーショートカット
    ///   - normal: 現在設定されている通常スイッチャーショートカット
    /// - Returns: 検証結果
    public static func validateLauncherShortcut(
        _ candidate: LauncherShortcutPreference,
        against normal: ShortcutPreference
    ) -> ShortcutValidationResult {
        guard candidate.modifiers.hasPrimaryModifier else {
            return .invalidModifier("Command / Option / Control のいずれか1つ以上の修飾キーを含めてください。")
        }

        if conflicts(launcher: candidate, normal: normal) {
            return .conflictWithNormalSwitcher(
                "通常スイッチャー（\(normal.displayString) / \(normal.reverseDisplayString)）と重複するため登録できません。"
            )
        }

        return .valid
    }

    /// 通常スイッチャー用ショートカット候補が登録可能かつランチャーと競合しないか検証する
    /// - Parameters:
    ///   - candidate: 変更候補の通常スイッチャーショートカット
    ///   - launcher: 現在設定されているランチャーショートカット
    /// - Returns: 検証結果
    public static func validateNormalShortcut(
        _ candidate: ShortcutPreference,
        against launcher: LauncherShortcutPreference
    ) -> ShortcutValidationResult {
        guard candidate.modifiers.hasPrimaryModifier else {
            return .invalidModifier("Command / Option / Control のいずれか1つ以上の修飾キーを含めてください。")
        }

        // 通常スイッチャーでは Shift が逆順選択に予約されているため基本設定に含められない
        guard !candidate.modifiers.contains(.shift) else {
            return .invalidModifier("通常スイッチャーでは Shift は逆順移動に使用されるため、基本ショートカットに含められません。")
        }

        if conflicts(launcher: launcher, normal: candidate) {
            return .conflictWithLauncher(
                "検索ランチャー（\(launcher.displayString)）と重複するため設定できません。"
            )
        }
        return .valid
    }

    /// ランチャーショートカットと通常スイッチャー（順方向・逆方向）の衝突を判定する
    /// - Parameters:
    ///   - launcher: ランチャーショートカット設定
    ///   - normal: 通常スイッチャーショートカット設定
    /// - Returns: 順方向または逆方向のいずれかと重複していれば true
    public static func conflicts(
        launcher: LauncherShortcutPreference,
        normal: ShortcutPreference
    ) -> Bool {
        guard launcher.keyCode == normal.keyCode else {
            return false
        }
        let forwardModifiers = normal.modifiers
        let reverseModifiers = normal.modifiers.union(.shift)
        return launcher.modifiers == forwardModifiers || launcher.modifiers == reverseModifiers
    }
}
