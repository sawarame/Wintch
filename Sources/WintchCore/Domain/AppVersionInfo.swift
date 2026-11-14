import Foundation

/// アプリケーションのバンドル情報からバージョンおよび著作権表記を抽出・保持するモデル
public struct AppVersionInfo: Equatable, Sendable {
    /// ユーザー向けのセマンティックバージョン（例: "0.1.0"）
    public let shortVersion: String

    /// リポジトリのコミット数等に基づくビルド番号（例: "1"）
    public let buildNumber: String

    /// 著作権およびライセンス表記
    public let copyright: String

    /// 画面表示用の整形済みバージョン文字列
    public var displayVersionText: String {
        "バージョン \(shortVersion) (\(buildNumber))"
    }

    /// バンドルの Info.plist 辞書からバージョン情報を生成する
    /// - Parameter infoDictionary: Info.plist 相当の辞書（未バンドル実行やテスト時は nil 可）
    public init(infoDictionary: [String: Any]?) {
        self.shortVersion = Self.normalizedString(
            from: infoDictionary?["CFBundleShortVersionString"],
            fallback: "dev"
        )
        self.buildNumber = Self.normalizedString(
            from: infoDictionary?["CFBundleVersion"],
            fallback: "1"
        )
        self.copyright = Self.normalizedString(
            from: infoDictionary?["NSHumanReadableCopyright"],
            fallback: "Copyright © 2026 Wintch Contributors. MIT License."
        )
    }

    /// 現在実行中のメインバンドルからバージョン情報を取得する
    /// - Returns: メインバンドルに基づく AppVersionInfo
    public static var current: AppVersionInfo {
        AppVersionInfo(infoDictionary: Bundle.main.infoDictionary)
    }

    /// 辞書値から空白除去済みの文字列を取り出し、無効な場合はフォールバック値を返す
    /// - Parameters:
    ///   - rawValue: 辞書から取り出した生の値
    ///   - fallback: 値が文字列でない、または空文字の場合に返す既定値
    /// - Returns: 正規化済み文字列またはフォールバック値
    private static func normalizedString(from rawValue: Any?, fallback: String) -> String {
        guard let text = rawValue as? String else {
            return fallback
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
