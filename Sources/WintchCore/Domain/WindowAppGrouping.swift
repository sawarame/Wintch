import Foundation

/// 同一アプリケーションに属するウィンドウ検索結果をまとめたグループモデル
public struct WindowAppGroup: Identifiable, Equatable, Sendable {
    /// アプリグループの一意識別子（bundleIdentifier 優先、未取得時は pid ベース）
    public let id: String

    /// グループ見出しに表示するアプリケーション名（先頭ウィンドウのアプリ名）
    public let applicationName: String

    /// グループ見出しのアイコン取得に使用する代表プロセス ID（先頭ウィンドウの PID）
    public let representativePID: Int32

    /// 検索時にグループ見出しのアプリ名へ適用する一致文字ハイライト範囲
    public let matchedAppNameRanges: [Range<String.Index>]

    /// このグループに属するウィンドウ検索結果一覧（表示順）
    public let results: [WindowSearchResult]

    /// 全体フラット配列における、このグループ先頭ウィンドウの開始インデックス
    public let startIndex: Int

    /// アプリグループを初期化する
    /// - Parameters:
    ///   - id: グループ識別子
    ///   - applicationName: 表示するアプリケーション名
    ///   - representativePID: 代表プロセス ID
    ///   - matchedAppNameRanges: 見出しアプリ名に対するハイライト範囲配列
    ///   - results: グループに属するウィンドウ検索結果一覧
    ///   - startIndex: 全体配列上の開始インデックス
    public init(
        id: String,
        applicationName: String,
        representativePID: Int32,
        matchedAppNameRanges: [Range<String.Index>] = [],
        results: [WindowSearchResult],
        startIndex: Int
    ) {
        self.id = id
        self.applicationName = applicationName
        self.representativePID = representativePID
        self.matchedAppNameRanges = matchedAppNameRanges
        self.results = results
        self.startIndex = startIndex
    }
}

/// ウィンドウ検索結果をアプリケーション単位で安定グルーピングし、通常スイッチャーの初期選択位置を解決する純粋ロジック
public enum WindowAppGrouping {
    /// ウィンドウ項目から同一アプリ判定用のグループキーを生成する
    /// - Parameter entry: 対象のウィンドウ項目
    /// - Returns: 非空の bundleIdentifier があればそれに基づくキー、未取得時は pid ベースのキー
    public static func groupKey(for entry: WindowEntry) -> String {
        if let bundleID = entry.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleID.isEmpty {
            return "bundle:\(bundleID)"
        }
        return "pid:\(entry.pid)"
    }

    /// 入力配列の初出順を維持したままウィンドウ検索結果をアプリケーション単位でグルーピングする
    /// 未検索時は MRU 順、検索時はスコア降順（同点 MRU 順）の配列をそのまま渡すことで双方の並び順規約を満たす
    /// - Parameter results: 並び替え済みのウィンドウ検索結果配列
    /// - Returns: グループ先頭開始インデックス付きのアプリグループ配列
    public static func group(_ results: [WindowSearchResult]) -> [WindowAppGroup] {
        guard !results.isEmpty else { return [] }

        var orderedKeys: [String] = []
        var groupedResults: [String: [WindowSearchResult]] = [:]
        orderedKeys.reserveCapacity(results.count)

        for result in results {
            let key = groupKey(for: result.entry)
            if groupedResults[key] == nil {
                orderedKeys.append(key)
                groupedResults[key] = [result]
            } else {
                groupedResults[key]?.append(result)
            }
        }

        var groups: [WindowAppGroup] = []
        groups.reserveCapacity(orderedKeys.count)
        var currentStartIndex = 0

        for key in orderedKeys {
            guard let items = groupedResults[key], let first = items.first else { continue }
            let headerAppName = first.entry.applicationName
            let mergedRanges = mergedMatchedAppNameRanges(
                for: headerAppName,
                from: items
            )
            groups.append(
                WindowAppGroup(
                    id: key,
                    applicationName: headerAppName,
                    representativePID: first.entry.pid,
                    matchedAppNameRanges: mergedRanges,
                    results: items,
                    startIndex: currentStartIndex
                )
            )
            currentStartIndex += items.count
        }

        return groups
    }

    /// アプリグループ配列を画面表示・キーボード連続移動用の単一フラット配列へ展開する
    /// - Parameter groups: アプリグループ配列
    /// - Returns: グループ順・グループ内順を維持したウィンドウ検索結果配列
    public static func flatten(_ groups: [WindowAppGroup]) -> [WindowSearchResult] {
        groups.flatMap(\.results)
    }

    /// 通常スイッチャー起動時の初期選択インデックスを算出する
    /// グルーピング ON かつ候補 2 件以上の場合は、表示順のインデックス 1 ではなく
    /// MRU 2 番目（直前アクティブウィンドウ）が配置された表示インデックスを返す
    /// - Parameters:
    ///   - mruSortedEntries: MRU ソート済みの元ウィンドウ項目配列
    ///   - displayedResults: 画面表示順（グルーピング反映済み）のウィンドウ検索結果配列
    ///   - isGrouped: アプリグルーピングが有効かどうか
    /// - Returns: 初期選択インデックス（候補 0 件時は nil）
    public static func resolveInitialIndexForNormalSwitcher(
        mruSortedEntries: [WindowEntry],
        displayedResults: [WindowSearchResult],
        isGrouped: Bool
    ) -> Int? {
        guard !displayedResults.isEmpty else { return nil }
        if displayedResults.count == 1 {
            return 0
        }
        guard isGrouped else {
            return 1
        }
        guard mruSortedEntries.count >= 2 else {
            return 0
        }

        let secondMRUID = mruSortedEntries[1].id
        if let matchedIndex = displayedResults.firstIndex(where: { $0.entry.id == secondMRUID }) {
            return matchedIndex
        }
        return min(1, displayedResults.count - 1)
    }

    /// グループ内ウィンドウ群から見出しアプリ名に適用するハイライト範囲を安全に集約・マージする
    /// - Parameters:
    ///   - headerAppName: グループ見出しに表示するアプリケーション名
    ///   - results: グループに属するウィンドウ検索結果一覧
    /// - Returns: 重複・隣接範囲を統合し昇順に整列した範囲配列
    private static func mergedMatchedAppNameRanges(
        for headerAppName: String,
        from results: [WindowSearchResult]
    ) -> [Range<String.Index>] {
        guard !headerAppName.isEmpty else { return [] }

        let totalLength = headerAppName.utf16.count
        var offsetIntervals: [(start: Int, end: Int)] = []

        for result in results {
            guard result.entry.applicationName == headerAppName,
                  !result.matchedAppNameRanges.isEmpty else {
                continue
            }
            let sourceText = result.entry.applicationName
            for range in result.matchedAppNameRanges {
                let startOffset = sourceText.utf16.distance(from: sourceText.startIndex, to: range.lowerBound)
                let endOffset = sourceText.utf16.distance(from: sourceText.startIndex, to: range.upperBound)
                guard startOffset >= 0, endOffset <= totalLength, startOffset < endOffset else {
                    continue
                }
                offsetIntervals.append((start: startOffset, end: endOffset))
            }
        }

        guard !offsetIntervals.isEmpty else { return [] }

        offsetIntervals.sort { lhs, rhs in
            if lhs.start != rhs.start {
                return lhs.start < rhs.start
            }
            return lhs.end < rhs.end
        }

        var mergedOffsets: [(start: Int, end: Int)] = []
        for interval in offsetIntervals {
            if let last = mergedOffsets.last, interval.start <= last.end {
                mergedOffsets[mergedOffsets.count - 1].end = max(last.end, interval.end)
            } else {
                mergedOffsets.append(interval)
            }
        }

        return mergedOffsets.compactMap { interval in
            guard let lower = headerAppName.utf16.index(
                headerAppName.startIndex,
                offsetBy: interval.start,
                limitedBy: headerAppName.endIndex
            ),
            let upper = headerAppName.utf16.index(
                headerAppName.startIndex,
                offsetBy: interval.end,
                limitedBy: headerAppName.endIndex
            ),
            lower < upper else {
                return nil
            }
            return lower..<upper
        }
    }
}
