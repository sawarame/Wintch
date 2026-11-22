import Foundation

/// アプリ内で実際に表示に使用する解決済みの対応言語（5 言語）
public enum ResolvedAppLanguage: String, CaseIterable, Codable, Equatable, Hashable, Sendable, Identifiable {
    /// 日本語
    case japanese = "ja"
    /// 英語
    case english = "en"
    /// 中国語（簡体字）
    case simplifiedChinese = "zh-Hans"
    /// 中国語（繁体字）
    case traditionalChinese = "zh-Hant"
    /// 韓国語
    case korean = "ko"

    /// Identifiable 準拠のための一意識別子
    public var id: String { rawValue }

    /// 言語切替 UI に表示する各言語のネイティブ表記（現在の表示言語に依存しない固定表記）
    public var nativeDisplayName: String {
        switch self {
        case .japanese:
            "日本語"
        case .english:
            "English"
        case .simplifiedChinese:
            "简体中文"
        case .traditionalChinese:
            "繁體中文"
        case .korean:
            "한국어"
        }
    }

    /// 対応する Foundation の Locale 値
    public var locale: Locale {
        Locale(identifier: rawValue)
    }
}

/// ユーザーが設定画面および UserDefaults で選択する言語設定（システム設定追従＋5 言語）
public enum AppLanguage: String, CaseIterable, Codable, Equatable, Hashable, Sendable, Identifiable {
    /// macOS のシステム優先言語設定に従う（デフォルト）
    case system = "system"
    /// 日本語
    case japanese = "ja"
    /// 英語
    case english = "en"
    /// 中国語（簡体字）
    case simplifiedChinese = "zh-Hans"
    /// 中国語（繁体字）
    case traditionalChinese = "zh-Hant"
    /// 韓国語
    case korean = "ko"

    /// 未保存時および不正値フォールバック時の既定言語設定
    public static let `default`: AppLanguage = .system

    /// Identifiable 準拠のための一意識別子
    public var id: String { rawValue }

    /// 設定画面の言語ピッカーに表示する選択肢ラベルを返す
    /// `.system` は現在の表示言語でローカライズ表記し、各言語は誤操作時に戻せるようネイティブ表記を返す
    /// - Parameter displayLanguage: 現在 UI に適用されている解決済み言語
    /// - Returns: ピッカーに表示する文字列
    public func pickerDisplayName(in displayLanguage: ResolvedAppLanguage) -> String {
        switch self {
        case .system:
            AppStrings(language: displayLanguage).languageFollowSystem
        case .japanese:
            ResolvedAppLanguage.japanese.nativeDisplayName
        case .english:
            ResolvedAppLanguage.english.nativeDisplayName
        case .simplifiedChinese:
            ResolvedAppLanguage.simplifiedChinese.nativeDisplayName
        case .traditionalChinese:
            ResolvedAppLanguage.traditionalChinese.nativeDisplayName
        case .korean:
            ResolvedAppLanguage.korean.nativeDisplayName
        }
    }

    /// この言語設定を実際に描画へ使用する 5 言語のいずれかへ解決する
    /// - Parameter preferredLanguages: macOS の優先言語識別子配列（既定値は `Locale.preferredLanguages`）
    /// - Returns: 解決済みの対応言語
    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> ResolvedAppLanguage {
        switch self {
        case .system:
            Self.resolveSystemLanguage(from: preferredLanguages)
        case .japanese:
            .japanese
        case .english:
            .english
        case .simplifiedChinese:
            .simplifiedChinese
        case .traditionalChinese:
            .traditionalChinese
        case .korean:
            .korean
        }
    }

    /// macOS の優先言語リストを先頭から評価し、最初に一致した対応言語を返す（一致なし時は英語へフォールバック）
    /// - Parameter preferredLanguages: 優先順に並んだ言語識別子配列（例: `["ja-JP", "en-US"]`）
    /// - Returns: 最初に一致した対応言語、またはフォールバック先の `.english`
    public static func resolveSystemLanguage(from preferredLanguages: [String]) -> ResolvedAppLanguage {
        for identifier in preferredLanguages {
            if let matched = matchPreferredLanguageIdentifier(identifier) {
                return matched
            }
        }
        return .english
    }

    /// 単一の言語識別子（BCP 47 / POSIX 形式）を対応言語へマッピングする
    /// - Parameter identifier: 言語識別子文字列（例: `"zh-Hant-TW"`, `"zh_CN"`, `"ja-JP"`）
    /// - Returns: 対応する言語（非対応言語や空文字列の場合は nil）
    public static func matchPreferredLanguageIdentifier(_ identifier: String) -> ResolvedAppLanguage? {
        let normalized = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        let subtags = normalized.split(separator: "-").map(String.init)
        guard let primaryLanguage = subtags.first else { return nil }

        switch primaryLanguage {
        case "ja":
            return .japanese
        case "en":
            return .english
        case "ko":
            return .korean
        case "zh":
            return resolveChineseVariant(subtags: Array(subtags.dropFirst()))
        default:
            return nil
        }
    }

    /// 中国語タグ（`zh-*`）のサブタグ列から簡体字または繁体字を判定する
    /// 明示的なスクリプトサブタグ（`hans` / `hant`）を最優先し、未指定時は地域サブタグ（`tw`/`hk`/`mo` → 繁体字、それ以外 → 簡体字）で判定する
    /// - Parameter subtags: 言語コード `"zh"` を除いた後続サブタグ配列（小文字化済み）
    /// - Returns: 簡体字（`.simplifiedChinese`）または繁体字（`.traditionalChinese`）
    private static func resolveChineseVariant(subtags: [String]) -> ResolvedAppLanguage {
        // 明示的なスクリプト指定を最優先する（例: zh-Hans-HK は簡体字、zh-Hant-CN は繁体字）
        for tag in subtags {
            if tag == "hant" {
                return .traditionalChinese
            }
            if tag == "hans" {
                return .simplifiedChinese
            }
        }

        // スクリプト未指定時は地域コードで繁体字圏と簡体字圏を判別する
        let traditionalRegions: Set<String> = ["tw", "hk", "mo"]
        for tag in subtags where traditionalRegions.contains(tag) {
            return .traditionalChinese
        }

        // zh / zh-CN / zh-SG 等は簡体字として解決する
        return .simplifiedChinese
    }
}
