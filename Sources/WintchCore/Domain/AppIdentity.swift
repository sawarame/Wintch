import Foundation

/// 実行中アプリケーションのバンドル情報およびビルド構成から、アプリ名・識別子・UI 表示文言を解決するモデル
public struct AppIdentity: Equatable, Sendable {
    /// 配布版（リリースビルド）の標準アプリ表示名
    public static let releaseDisplayName = "Wintch"

    /// ローカル開発版（デバッグビルド）の標準アプリ表示名
    public static let developmentDisplayName = "Wintch_dev"

    /// 配布版（リリースビルド）の標準バンドル識別子
    public static let releaseBundleIdentifier = "dev.wintch.Wintch"

    /// ローカル開発版（デバッグビルド）の標準バンドル識別子
    public static let developmentBundleIdentifier = "dev.wintch.Wintch.dev"

    /// 未バンドル実行時などに用いる既定のフォールバック表示名
    public static var defaultFallbackDisplayName: String {
        #if DEBUG
        return developmentDisplayName
        #else
        return releaseDisplayName
        #endif
    }

    /// 未バンドル実行時などに用いる既定のフォールバックバンドル識別子
    public static var defaultFallbackBundleIdentifier: String {
        #if DEBUG
        return developmentBundleIdentifier
        #else
        return releaseBundleIdentifier
        #endif
    }

    /// UI および OS 連携文言に使用するアプリ表示名
    public let displayName: String

    /// アプリケーションのバンドル識別子
    public let bundleIdentifier: String

    /// 開発用ビルドとして識別されているかどうか
    public let isDevelopment: Bool

    /// メニューバーおよびウィンドウタイトルで使用する「〜について」文言
    public var aboutMenuTitle: String {
        "\(displayName)について"
    }

    /// メニューバーの終了ボタン文言
    public var quitMenuTitle: String {
        "\(displayName) を終了"
    }

    /// 設定ウィンドウのタイトル文言
    public var settingsWindowTitle: String {
        "\(displayName) 設定"
    }

    /// 権限誘導ウィンドウのタイトル文言
    public var permissionGuideWindowTitle: String {
        "\(displayName) - 権限の確認"
    }

    /// 権限誘導画面のステップ 2 に表示するスイッチ許可案内文言
    public var accessibilitySwitchInstruction: String {
        "2. 一覧の「\(displayName)」のスイッチをオンにします"
    }

    /// バンドルの Info.plist 辞書からアプリ識別情報を生成する
    /// - Parameters:
    ///   - infoDictionary: Info.plist 相当の辞書（未バンドル実行やテスト時は nil 可）
    ///   - fallbackDisplayName: 表示名が取得できない場合の既定値
    ///   - fallbackBundleIdentifier: 識別子が取得できない場合の既定値
    public init(
        infoDictionary: [String: Any]?,
        fallbackDisplayName: String = AppIdentity.defaultFallbackDisplayName,
        fallbackBundleIdentifier: String = AppIdentity.defaultFallbackBundleIdentifier
    ) {
        let resolvedDisplayName = Self.firstNormalizedString(
            in: [
                infoDictionary?["CFBundleDisplayName"],
                infoDictionary?["CFBundleName"]
            ],
            fallback: fallbackDisplayName
        )
        let resolvedBundleIdentifier = Self.firstNormalizedString(
            in: [infoDictionary?["CFBundleIdentifier"]],
            fallback: fallbackBundleIdentifier
        )

        self.displayName = resolvedDisplayName
        self.bundleIdentifier = resolvedBundleIdentifier
        self.isDevelopment = resolvedDisplayName == Self.developmentDisplayName
            || resolvedBundleIdentifier == Self.developmentBundleIdentifier
            || resolvedBundleIdentifier.hasSuffix(".dev")
    }

    /// 現在実行中のメインバンドルからアプリ識別情報を取得する
    /// - Returns: メインバンドルに基づく AppIdentity
    public static var current: AppIdentity {
        AppIdentity(infoDictionary: Bundle.main.infoDictionary)
    }

    /// 候補配列の先頭から有効な（空文字でない）トリミング済み文字列を取り出し、すべて無効なら既定値を返す
    /// - Parameters:
    ///   - candidates: 優先順に並べた辞書値候補配列
    ///   - fallback: 有効な文字列が得られなかった場合の既定値
    /// - Returns: 正規化済み文字列またはフォールバック値
    private static func firstNormalizedString(in candidates: [Any?], fallback: String) -> String {
        for candidate in candidates {
            guard let text = candidate as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return fallback
    }
}
