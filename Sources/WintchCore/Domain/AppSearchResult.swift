import Foundation

/// ファジー検索によって評価されたアプリ起動候補およびハイライト範囲
public struct AppSearchResult: Identifiable, Equatable, Sendable {
    /// 検索対象となったアプリ情報
    public let app: LaunchableApp

    /// 算出された一致スコア
    public let score: Int

    /// 表示名内で一致した文字位置範囲の配列（結合済み・昇順）
    public let matchedDisplayNameRanges: [Range<String.Index>]

    /// 別名（英語名など）内で一致した文字位置範囲の配列（結合済み・昇順）
    public let matchedAlternateNameRanges: [Range<String.Index>]

    /// Identifiable 準拠のための一意識別子
    public var id: String { app.id }

    /// アプリ検索結果項目を初期化する
    /// - Parameters:
    ///   - app: 対象のアプリ情報
    ///   - score: 算出された一致スコア
    ///   - matchedDisplayNameRanges: 表示名内の一致範囲配列
    ///   - matchedAlternateNameRanges: 別名内の一致範囲配列
    public init(
        app: LaunchableApp,
        score: Int = 0,
        matchedDisplayNameRanges: [Range<String.Index>] = [],
        matchedAlternateNameRanges: [Range<String.Index>] = []
    ) {
        self.app = app
        self.score = score
        self.matchedDisplayNameRanges = matchedDisplayNameRanges
        self.matchedAlternateNameRanges = matchedAlternateNameRanges
    }
}
