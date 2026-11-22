import Foundation

/// ショートカット検証失敗の言語非依存な理由モデル（表示時の動的ローカライズに使用）
public enum ShortcutValidationFailure: Equatable, Sendable {
    /// 必須修飾キー（Command / Option / Control）が 1 つも含まれていない
    case missingPrimaryModifier
    /// 通常スイッチャーの基本ショートカットに逆順移動予約の Shift が含まれている
    case shiftReservedForNormalSwitcher
    /// 通常スイッチャーのショートカット（順方向・逆方向）と重複している
    case conflictWithNormalSwitcher(forward: String, reverse: String)
    /// 検索ランチャーのショートカットと重複している
    case conflictWithLauncher(shortcut: String)

    /// 指定言語でユーザー向けの検証エラーメッセージを生成する
    /// - Parameter language: 表示対象の解決済み言語
    /// - Returns: ローカライズ済みのエラー説明文
    public func message(in language: ResolvedAppLanguage) -> String {
        let strings = AppStrings(language: language)
        switch self {
        case .missingPrimaryModifier:
            return strings.text(for: .shortcutValidationMissingPrimaryModifier)
        case .shiftReservedForNormalSwitcher:
            return strings.text(for: .shortcutValidationShiftReserved)
        case let .conflictWithNormalSwitcher(forward, reverse):
            return strings.shortcutConflictWithNormalSwitcher(forward: forward, reverse: reverse)
        case let .conflictWithLauncher(shortcut):
            return strings.shortcutConflictWithLauncher(shortcut: shortcut)
        }
    }

    /// 指定言語で対応する `ShortcutValidationResult` へ変換する
    /// - Parameter language: 表示対象の解決済み言語
    /// - Returns: ローカライズ済みエラーメッセージ付きの検証結果
    public func toValidationResult(in language: ResolvedAppLanguage) -> ShortcutValidationResult {
        let text = message(in: language)
        switch self {
        case .missingPrimaryModifier, .shiftReservedForNormalSwitcher:
            return .invalidModifier(text)
        case .conflictWithNormalSwitcher:
            return .conflictWithNormalSwitcher(text)
        case .conflictWithLauncher:
            return .conflictWithLauncher(text)
        }
    }
}

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
    /// ランチャー用ショートカット候補の検証失敗理由を評価する
    /// - Parameters:
    ///   - candidate: 登録候補のランチャーショートカット
    ///   - normal: 現在設定されている通常スイッチャーショートカット
    /// - Returns: 検証失敗時は理由モデル、有効なら nil
    public static func evaluateLauncherShortcut(
        _ candidate: LauncherShortcutPreference,
        against normal: ShortcutPreference
    ) -> ShortcutValidationFailure? {
        guard candidate.modifiers.hasPrimaryModifier else {
            return .missingPrimaryModifier
        }

        if conflicts(launcher: candidate, normal: normal) {
            return .conflictWithNormalSwitcher(
                forward: normal.displayString,
                reverse: normal.reverseDisplayString
            )
        }

        return nil
    }

    /// ランチャー用ショートカット候補が登録可能か検証する
    /// - Parameters:
    ///   - candidate: 登録候補のランチャーショートカット
    ///   - normal: 現在設定されている通常スイッチャーショートカット
    ///   - language: エラーメッセージの表示言語（既定値は日本語）
    /// - Returns: 検証結果
    public static func validateLauncherShortcut(
        _ candidate: LauncherShortcutPreference,
        against normal: ShortcutPreference,
        language: ResolvedAppLanguage = .japanese
    ) -> ShortcutValidationResult {
        guard let failure = evaluateLauncherShortcut(candidate, against: normal) else {
            return .valid
        }
        return failure.toValidationResult(in: language)
    }

    /// 通常スイッチャー用ショートカット候補の検証失敗理由を評価する
    /// - Parameters:
    ///   - candidate: 変更候補の通常スイッチャーショートカット
    ///   - launcher: 現在設定されているランチャーショートカット
    /// - Returns: 検証失敗時は理由モデル、有効なら nil
    public static func evaluateNormalShortcut(
        _ candidate: ShortcutPreference,
        against launcher: LauncherShortcutPreference
    ) -> ShortcutValidationFailure? {
        guard candidate.modifiers.hasPrimaryModifier else {
            return .missingPrimaryModifier
        }

        // 通常スイッチャーでは Shift が逆順選択に予約されているため基本設定に含められない
        guard !candidate.modifiers.contains(.shift) else {
            return .shiftReservedForNormalSwitcher
        }

        if conflicts(launcher: launcher, normal: candidate) {
            return .conflictWithLauncher(shortcut: launcher.displayString)
        }

        return nil
    }

    /// 通常スイッチャー用ショートカット候補が登録可能かつランチャーと競合しないか検証する
    /// - Parameters:
    ///   - candidate: 変更候補の通常スイッチャーショートカット
    ///   - launcher: 現在設定されているランチャーショートカット
    ///   - language: エラーメッセージの表示言語（既定値は日本語）
    /// - Returns: 検証結果
    public static func validateNormalShortcut(
        _ candidate: ShortcutPreference,
        against launcher: LauncherShortcutPreference,
        language: ResolvedAppLanguage = .japanese
    ) -> ShortcutValidationResult {
        guard let failure = evaluateNormalShortcut(candidate, against: launcher) else {
            return .valid
        }
        return failure.toValidationResult(in: language)
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
