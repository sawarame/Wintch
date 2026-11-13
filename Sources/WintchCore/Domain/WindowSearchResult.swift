import Foundation

/// ファジー検索によって評価されたウィンドウ項目およびハイライト範囲
public struct WindowSearchResult: Identifiable, Equatable, Sendable {
    /// 検索対象となったウィンドウ項目
    public let entry: WindowEntry

    /// 算出された一致スコア（未検索時は 0）
    public let score: Int

    /// アプリケーション名内で一致した文字位置範囲の配列（結合済み・昇順）
    public let matchedAppNameRanges: [Range<String.Index>]

    /// ウィンドウタイトル内で一致した文字位置範囲の配列（結合済み・昇順）
    public let matchedTitleRanges: [Range<String.Index>]

    /// Identifiable 準拠のための一意識別子
    public var id: String { entry.id }

    /// 検索結果項目を初期化する
    /// - Parameters:
    ///   - entry: 対象のウィンドウ項目
    ///   - score: 算出された一致スコア
    ///   - matchedAppNameRanges: アプリケーション名内の一致範囲配列
    ///   - matchedTitleRanges: ウィンドウタイトル内の一致範囲配列
    public init(
        entry: WindowEntry,
        score: Int = 0,
        matchedAppNameRanges: [Range<String.Index>] = [],
        matchedTitleRanges: [Range<String.Index>] = []
    ) {
        self.entry = entry
        self.score = score
        self.matchedAppNameRanges = matchedAppNameRanges
        self.matchedTitleRanges = matchedTitleRanges
    }
}
