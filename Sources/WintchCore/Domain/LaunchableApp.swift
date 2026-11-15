import Foundation

/// ランチャーから新規起動可能なアプリケーション候補を表すドメインモデル
public struct LaunchableApp: Identifiable, Equatable, Sendable {
    /// アプリケーションの一意識別子（正規化済みバンドル URL パス）
    public let id: String

    /// 画面表示・検索に用いるアプリケーション名（例: "メモ", "Visual Studio Code"）
    public let displayName: String

    /// ローカライズ前またはファイル名由来の別名（例: "Notes"、displayName と同一なら空文字）
    public let alternateName: String

    /// バンドル識別子（取得できる場合）
    public let bundleIdentifier: String?

    /// アプリケーションバンドルのファイル URL
    public let bundleURL: URL

    /// 起動可能アプリ情報を初期化する
    /// - Parameters:
    ///   - id: 一意識別子（省略時は bundleURL.standardizedFileURL.path）
    ///   - displayName: 表示用のアプリケーション名
    ///   - alternateName: 補助検索用の別名（デフォルトは空文字）
    ///   - bundleIdentifier: バンドル識別子（デフォルトは nil）
    ///   - bundleURL: アプリケーションバンドルの URL
    public init(
        id: String? = nil,
        displayName: String,
        alternateName: String = "",
        bundleIdentifier: String? = nil,
        bundleURL: URL
    ) {
        self.id = id ?? bundleURL.standardizedFileURL.path
        self.displayName = displayName
        self.alternateName = alternateName
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
    }
}
