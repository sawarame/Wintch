import Foundation

/// インストール済みアプリ一覧に対してスペース区切り AND のファジー検索・重複除外・スコア順ソートを行う純粋ロジック
public enum AppSearchEngine {
    /// クエリ文字列を用いてアプリ起動候補を絞り込み、既出ウィンドウアプリを除外した上でスコア降順（同点は表示名昇順）で返す
    /// - Parameters:
    ///   - query: ユーザーが入力した検索クエリ
    ///   - apps: 起動可能なインストール済みアプリ一覧
    ///   - excludingWindowEntries: 上のウィンドウ検索結果にすでに表示されているウィンドウ項目一覧（同一アプリを除外するために使用）
    /// - Returns: 一致したアプリ検索結果配列（空クエリまたは空白のみの場合は空配列）
    public static func search(
        query: String,
        in apps: [LaunchableApp],
        excludingWindowEntries: [WindowEntry] = []
    ) -> [AppSearchResult] {
        let tokens = FuzzySearchMatcher.tokenize(query)
        guard !tokens.isEmpty else {
            return []
        }

        var scoredResults: [AppSearchResult] = []
        scoredResults.reserveCapacity(apps.count)

        for app in apps {
            // 上のウィンドウ候補にすでに表示されているアプリは重複表示しない
            if isExcluded(app, by: excludingWindowEntries) {
                continue
            }

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

    /// 対象のアプリ起動候補がすでにウィンドウ候補群に含まれているかを判定する
    /// - Parameters:
    ///   - app: 判定対象のアプリ起動候補
    ///   - windowEntries: ウィンドウ検索結果の項目配列
    /// - Returns: 同一アプリケーションがウィンドウ候補に含まれている場合は true
    private static func isExcluded(_ app: LaunchableApp, by windowEntries: [WindowEntry]) -> Bool {
        let appBundleID = app.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let appDisplayName = app.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let appAlternateName = app.alternateName.trimmingCharacters(in: .whitespacesAndNewlines)

        for entry in windowEntries {
            let entryBundleID = entry.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !appBundleID.isEmpty && !entryBundleID.isEmpty {
                // 双方にバンドル識別子がある場合は厳密照合を優先する
                if appBundleID.caseInsensitiveCompare(entryBundleID) == .orderedSame {
                    return true
                }
                continue
            }

            // バンドル識別子が片方でも未取得の場合はアプリ名称の大小文字無視比較へフォールバックする
            let entryAppName = entry.applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entryAppName.isEmpty else { continue }
            if entryAppName.caseInsensitiveCompare(appDisplayName) == .orderedSame {
                return true
            }
            if !appAlternateName.isEmpty && entryAppName.caseInsensitiveCompare(appAlternateName) == .orderedSame {
                return true
            }
        }

        return false
    }
}
