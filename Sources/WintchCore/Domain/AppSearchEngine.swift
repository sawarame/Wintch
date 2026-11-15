import Foundation

/// インストール済みアプリ一覧に対してスペース区切り AND のファジー検索・スコア順ソート・一致範囲抽出を行う純粋ロジック
public enum AppSearchEngine {
    /// クエリ文字列を用いてアプリ起動候補を絞り込み、スコア降順（同点は表示名昇順）で返す
    /// - Parameters:
    ///   - query: ユーザーが入力した検索クエリ
    ///   - apps: 起動可能なインストール済みアプリ一覧
    /// - Returns: 一致したアプリ検索結果配列（空クエリまたは空白のみの場合は空配列）
    public static func search(query: String, in apps: [LaunchableApp]) -> [AppSearchResult] {
        let tokens = FuzzySearchMatcher.tokenize(query)
        guard !tokens.isEmpty else {
            return []
        }

        var scoredResults: [AppSearchResult] = []
        scoredResults.reserveCapacity(apps.count)

        for app in apps {
            let trimmedAlt = app.alternateName.trimmingCharacters(in: .whitespacesAndNewlines)
            let secondary = trimmedAlt.caseInsensitiveCompare(app.displayName) == .orderedSame
                ? ""
                : trimmedAlt

            guard let match = FuzzySearchMatcher.evaluate(
                tokens: tokens,
                primaryText: app.displayName,
                secondaryText: secondary,
                primaryFieldBonus: 25
            ) else {
                continue
            }

            scoredResults.append(
                AppSearchResult(
                    app: app,
                    score: match.score,
                    matchedDisplayNameRanges: match.primaryMatchedRanges,
                    matchedAlternateNameRanges: match.secondaryMatchedRanges
                )
            )
        }

        // スコア降順、同スコア時は表示名の自然な昇順で安定ソートする
        scoredResults.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            let nameOrder = lhs.app.displayName.localizedStandardCompare(rhs.app.displayName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.app.id < rhs.app.id
        }

        return scoredResults
    }
}
