import Foundation

/// ウィンドウ一覧に対してスペース区切り AND のファジー検索・スコア順ソート・一致範囲抽出を行う純粋ロジック
public enum WindowSearchEngine {
    /// 1文字単位の正規化済み文字と元文字列内の位置範囲
    private struct FoldedCharacter {
        /// 元文字列内の文字位置範囲
        let sourceRange: Range<String.Index>
        /// 正規化（小文字化・発音区別符号除去・幅正規化）された1文字
        let foldedChar: Character
        /// 単語境界（先頭・区切り文字直後・キャメルケース境界）に位置するかどうか
        let isWordBoundary: Bool
    }

    /// フィールド単体に対するトークン一致結果
    private struct FieldMatch {
        /// 一致スコア
        let score: Int
        /// 元文字列内の一致文字範囲配列
        let matchedRanges: [Range<String.Index>]
    }

    /// DP 計算の上限文字数（極端に長いタイトルでも 100ms 未満の応答を保証するため）
    private static let maxDPTargetLength = 256

    /// クエリ文字列を用いてウィンドウ一覧を絞り込み、スコア降順（同点は MRU 順）で返す
    /// - Parameters:
    ///   - query: ユーザーが入力した検索クエリ
    ///   - entries: MRU ソート済みのウィンドウ項目配列
    /// - Returns: 一致した検索結果配列（空クエリ時は全件を MRU 順で返却）
    public static func search(query: String, in entries: [WindowEntry]) -> [WindowSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return entries.map { WindowSearchResult(entry: $0) }
        }

        let tokens = trimmedQuery
            .split(whereSeparator: \.isWhitespace)
            .map { foldQueryToken(String($0)) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            return entries.map { WindowSearchResult(entry: $0) }
        }

        var scoredResults: [(mruIndex: Int, result: WindowSearchResult)] = []
        scoredResults.reserveCapacity(entries.count)

        for (mruIndex, entry) in entries.enumerated() {
            guard let result = evaluateEntry(entry, tokens: tokens) else {
                continue
            }
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

    /// 単一のウィンドウ項目が全トークンに一致するか評価し、合算スコアとハイライト範囲を返す
    /// - Parameters:
    ///   - entry: 評価対象のウィンドウ項目
    ///   - tokens: 正規化済みの検索トークン配列
    /// - Returns: 全トークンに一致した場合は WindowSearchResult、1つでも不一致なら nil
    private static func evaluateEntry(
        _ entry: WindowEntry,
        tokens: [[Character]]
    ) -> WindowSearchResult? {
        let appFolded = buildFoldedCharacters(from: entry.applicationName)
        // 空タイトルはプレースホルダ文字列に一致させないため空として扱う
        let rawTitle = entry.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : entry.windowTitle
        let titleFolded = buildFoldedCharacters(from: rawTitle)

        var totalScore = 0
        var appRanges: [Range<String.Index>] = []
        var titleRanges: [Range<String.Index>] = []

        for token in tokens {
            let appMatch = matchToken(token, in: appFolded, fieldBonus: 25)
            let titleMatch = matchToken(token, in: titleFolded, fieldBonus: 0)

            // AND 条件のため、アプリ名とタイトルのどちらにも一致しなければ除外する
            guard appMatch != nil || titleMatch != nil else {
                return nil
            }

            if let appMatch {
                appRanges.append(contentsOf: appMatch.matchedRanges)
            }
            if let titleMatch {
                titleRanges.append(contentsOf: titleMatch.matchedRanges)
            }

            let bestScore = max(appMatch?.score ?? Int.min, titleMatch?.score ?? Int.min)
            totalScore += bestScore
        }

        return WindowSearchResult(
            entry: entry,
            score: totalScore,
            matchedAppNameRanges: mergeRanges(appRanges),
            matchedTitleRanges: mergeRanges(titleRanges)
        )
    }

    /// 検索トークン1つを正規化済み文字配列へ変換する
    /// - Parameter token: 元のトークン文字列
    /// - Returns: 比較用の正規化済み Character 配列
    private static func foldQueryToken(_ token: String) -> [Character] {
        var result: [Character] = []
        for ch in token {
            let folded = String(ch).folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            result.append(contentsOf: folded)
        }
        return result
    }

    /// 対象文字列から文字位置・正規化文字・単語境界情報を構築する
    /// - Parameter text: 検索対象の元文字列
    /// - Returns: 正規化文字配列
    private static func buildFoldedCharacters(from text: String) -> [FoldedCharacter] {
        var result: [FoldedCharacter] = []
        result.reserveCapacity(text.count)

        var index = text.startIndex
        var previousOriginal: Character?

        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            let originalChar = text[index]
            let sourceRange = index..<nextIndex
            let boundary = isBoundary(current: originalChar, previous: previousOriginal)

            let folded = String(originalChar).folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )

            for (offset, foldedChar) in folded.enumerated() {
                result.append(
                    FoldedCharacter(
                        sourceRange: sourceRange,
                        foldedChar: foldedChar,
                        isWordBoundary: boundary && offset == 0
                    )
                )
            }

            previousOriginal = originalChar
            index = nextIndex
        }

        return result
    }

    /// 単語境界（先頭、区切り記号の直後、キャメルケース遷移）かどうかを判定する
    /// - Parameters:
    ///   - current: 現在の文字
    ///   - previous: 直前の文字
    /// - Returns: 単語境界であれば true
    private static func isBoundary(current: Character, previous: Character?) -> Bool {
        guard let previous else { return true }
        let separators: Set<Character> = [" ", "\t", "-", "_", "/", ".", ":", "(", "[", "{"]
        if separators.contains(previous) {
            return true
        }
        // 小文字・数字から大文字への遷移をキャメルケース境界とみなす
        if (previous.isLowercase || previous.isNumber) && current.isUppercase {
            return true
        }
        return false
    }

    /// 1つのトークンを正規化済み対象文字列へファジーマッチし、最適スコアと位置範囲を返す
    /// - Parameters:
    ///   - token: 正規化済みトークン文字配列
    ///   - target: 検索対象の正規化済み文字配列
    ///   - fieldBonus: フィールド種別に応じた加点ボーナス
    /// - Returns: 一致した場合は FieldMatch、不一致時は nil
    private static func matchToken(
        _ token: [Character],
        in target: [FoldedCharacter],
        fieldBonus: Int
    ) -> FieldMatch? {
        let m = token.count
        let n = target.count
        guard m > 0, n >= m else { return nil }

        // 高速な事前チェック（サブシーケンス一致が存在しない場合は即座に弾く）
        guard hasSubsequence(token: token, in: target) else {
            return nil
        }

        let matchedIndices: [Int]
        var score: Int

        if n <= maxDPTargetLength {
            let dpResult = bestSubsequenceAlignment(token: token, in: target)
            matchedIndices = dpResult.indices
            score = dpResult.score
        } else {
            let greedyResult = greedySubsequenceAlignment(token: token, in: target)
            matchedIndices = greedyResult.indices
            score = greedyResult.score
        }

        // 先頭一致・完全一致・コンパクトさの追加ボーナスを加算する
        if let first = matchedIndices.first, let last = matchedIndices.last {
            if first == 0 {
                score += 30
            }
            if first == 0 && m == n {
                score += 80
            }
            let span = (last - first + 1) - m
            score -= min(span * 2, 40)
        }

        score += fieldBonus
        let ranges = matchedIndices.map { target[$0].sourceRange }
        return FieldMatch(score: score, matchedRanges: ranges)
    }

    /// 線形走査でサブシーケンス一致の存在だけを高速判定する
    /// - Parameters:
    ///   - token: 検索トークン
    ///   - target: 検索対象
    /// - Returns: サブシーケンスとして一致すれば true
    private static func hasSubsequence(token: [Character], in target: [FoldedCharacter]) -> Bool {
        var tIndex = 0
        for item in target {
            if item.foldedChar == token[tIndex] {
                tIndex += 1
                if tIndex == token.count {
                    return true
                }
            }
        }
        return false
    }

    /// 動的計画法により単語境界・連続一致を最大化する最適一致インデックス列を算出する
    /// - Parameters:
    ///   - token: 検索トークン
    ///   - target: 検索対象
    /// - Returns: 最高スコアと対応する target インデックス配列
    private static func bestSubsequenceAlignment(
        token: [Character],
        in target: [FoldedCharacter]
    ) -> (score: Int, indices: [Int]) {
        let m = token.count
        let n = target.count
        let negInf = Int.min / 4

        // dp[i][j]: token[0...i] を target[j] で終わるように一致させた最大スコア
        var dp = Array(repeating: Array(repeating: negInf, count: n), count: m)
        var consecutive = Array(repeating: Array(repeating: 0, count: n), count: m)
        var prevCol = Array(repeating: Array(repeating: -1, count: n), count: m)

        // 0文字目の初期化
        for j in 0..<n where target[j].foldedChar == token[0] {
            var base = 10
            if target[j].isWordBoundary {
                base += 20
            }
            if j == 0 {
                base += 15
            }
            // 後方にズレるほど軽微な位置ペナルティを与える
            base -= j
            dp[0][j] = base
            consecutive[0][j] = 1
        }

        // 1文字目以降の遷移
        if m > 1 {
            for i in 1..<m {
                var bestPrevScore = negInf
                var bestPrevIndex = -1

                for j in 0..<n {
                    // j より前の最良候補を逐次更新する（O(m * n)）
                    if j > 0 && dp[i - 1][j - 1] > bestPrevScore {
                        bestPrevScore = dp[i - 1][j - 1]
                        bestPrevIndex = j - 1
                    }

                    guard target[j].foldedChar == token[i], bestPrevIndex >= 0 else {
                        continue
                    }

                    // 直前文字と連続する場合と非連続で最良な前位置を比較する
                    let contiguousCandidate = j > 0 && dp[i - 1][j - 1] > negInf
                    var chosenPrev = bestPrevIndex
                    var chosenScore = bestPrevScore
                    var nextConsecutive = 1

                    let charScore = 10 + (target[j].isWordBoundary ? 20 : 0)

                    if contiguousCandidate {
                        let streak = consecutive[i - 1][j - 1] + 1
                        let contiguousBonus = 24 + min(streak * 6, 30)
                        let contiguousTotal = dp[i - 1][j - 1] + charScore + contiguousBonus
                        let nonContiguousGap = max(0, (j - bestPrevIndex - 1))
                        let nonContiguousTotal = bestPrevScore + charScore - nonContiguousGap

                        if contiguousTotal >= nonContiguousTotal {
                            chosenPrev = j - 1
                            chosenScore = contiguousTotal
                            nextConsecutive = streak
                        } else {
                            chosenScore = nonContiguousTotal
                        }
                    } else {
                        let gap = max(0, (j - bestPrevIndex - 1))
                        chosenScore = bestPrevScore + charScore - gap
                    }

                    dp[i][j] = chosenScore
                    consecutive[i][j] = nextConsecutive
                    prevCol[i][j] = chosenPrev
                }
            }
        }

        // 最終行で最大スコアとなる終了位置を探索する
        var bestFinalScore = negInf
        var bestFinalJ = -1
        for j in 0..<n where dp[m - 1][j] > bestFinalScore {
            bestFinalScore = dp[m - 1][j]
            bestFinalJ = j
        }

        var indices = Array(repeating: 0, count: m)
        var cursor = bestFinalJ
        for i in stride(from: m - 1, through: 0, by: -1) {
            indices[i] = cursor
            cursor = prevCol[i][cursor]
        }

        return (bestFinalScore, indices)
    }

    /// 長文タイトル向けのフォールバック前方貪欲一致計算
    /// - Parameters:
    ///   - token: 検索トークン
    ///   - target: 検索対象
    /// - Returns: 簡易スコアとインデックス配列
    private static func greedySubsequenceAlignment(
        token: [Character],
        in target: [FoldedCharacter]
    ) -> (score: Int, indices: [Int]) {
        var indices: [Int] = []
        indices.reserveCapacity(token.count)
        var tIdx = 0
        var score = 0
        var prevMatch = -2

        for (j, item) in target.enumerated() {
            guard item.foldedChar == token[tIdx] else { continue }
            score += 10
            if item.isWordBoundary { score += 20 }
            if j == prevMatch + 1 { score += 24 }
            prevMatch = j
            indices.append(j)
            tIdx += 1
            if tIdx == token.count { break }
        }
        return (score, indices)
    }

    /// 重複または隣接する文字位置範囲を昇順にソート・統合する
    /// - Parameter ranges: 統合前の範囲配列
    /// - Returns: 重複のない統合済み範囲配列
    private static func mergeRanges(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        guard !ranges.isEmpty else { return [] }
        let sorted = ranges.sorted { lhs, rhs in
            if lhs.lowerBound != rhs.lowerBound {
                return lhs.lowerBound < rhs.lowerBound
            }
            return lhs.upperBound < rhs.upperBound
        }

        var merged: [Range<String.Index>] = [sorted[0]]
        for range in sorted.dropFirst() {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                let upper = max(last.upperBound, range.upperBound)
                merged[merged.count - 1] = last.lowerBound..<upper
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
