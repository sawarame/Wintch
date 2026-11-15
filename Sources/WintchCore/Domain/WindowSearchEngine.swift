import Foundation

/// ウィンドウ一覧に対してスペース区切り AND のファジー検索・スコア順ソート・一致範囲抽出を行う純粋ロジック
public enum WindowSearchEngine {
    /// クエリ文字列を用いてウィンドウ一覧を絞り込み、スコア降順（同点は MRU 順）で返す
    /// - Parameters:
    ///   - query: ユーザーが入力した検索クエリ
    ///   - entries: MRU ソート済みのウィンドウ項目配列
    /// - Returns: 一致した検索結果配列（空クエリ時は全件を MRU 順で返却）
    public static func search(query: String, in entries: [WindowEntry]) -> [WindowSearchResult] {
        let tokens = FuzzySearchMatcher.tokenize(query)
        guard !tokens.isEmpty else {
            return entries.map { WindowSearchResult(entry: $0) }
        }

        var scoredResults: [(mruIndex: Int, result: WindowSearchResult)] = []
        scoredResults.reserveCapacity(entries.count)

        for (mruIndex, entry) in entries.enumerated() {
            // 空タイトルはプレースホルダ文字列に一致させないため空として扱う
            let rawTitle = entry.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ""
                : entry.windowTitle

            guard let match = FuzzySearchMatcher.evaluate(
                tokens: tokens,
                primaryText: entry.applicationName,
                secondaryText: rawTitle,
                primaryFieldBonus: 25
            ) else {
                continue
            }

            let result = WindowSearchResult(
                entry: entry,
                score: match.score,
                matchedAppNameRanges: match.primaryMatchedRanges,
                matchedTitleRanges: match.secondaryMatchedRanges
            )
            scoredResults.append((mruIndex: mruIndex, result: result))
        }

        // スコア降順、同スコア時は元の MRU インデックス昇順で並び替える
        scoredResults.sort { lhs, rhs in
            if lhs.result.score != rhs.result.score {
                return lhs.result.score > rhs.result.score
            }
            return lhs.mruIndex < rhs.mruIndex
        }

        return scoredResults.map(\.result)
    }
}
