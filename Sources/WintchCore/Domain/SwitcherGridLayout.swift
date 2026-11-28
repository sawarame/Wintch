import CoreGraphics
import Foundation

/// 固定グリッドの 1 行内に描画される、複数ウィンドウを持つアプリグループの連続区間（セグメント）
public struct SwitcherGridGroupSegment: Identifiable, Equatable, Sendable {
    /// 所属するアプリグループの識別子（`WindowAppGroup.id`）
    public let groupID: String

    /// 対象行のインデックス（0 始まり）
    public let rowIndex: Int

    /// この行内での開始列インデックス（0 始まり、両端含む）
    public let startColumn: Int

    /// この行内での終了列インデックス（0 始まり、両端含む）
    public let endColumn: Int

    /// 同一グループが前の行から続いている場合は true（左辺を開放エッジ表現にする）
    public let continuesFromPreviousRow: Bool

    /// 同一グループが次の行へ続いている場合は true（右辺を開放エッジ表現にする）
    public let continuesToNextRow: Bool

    /// 行内セグメントの一意識別子
    public var id: String {
        "\(groupID)#row-\(rowIndex)#col-\(startColumn)-\(endColumn)"
    }

    /// このセグメントが占有する列数（1 以上）
    public var columnSpan: Int {
        endColumn - startColumn + 1
    }

    /// 行内グループセグメントを初期化する
    /// - Parameters:
    ///   - groupID: 所属するアプリグループの識別子
    ///   - rowIndex: 対象行インデックス（0 始まり）
    ///   - startColumn: 行内の開始列インデックス（0 始まり）
    ///   - endColumn: 行内の終了列インデックス（0 始まり）
    ///   - continuesFromPreviousRow: 前行から続いている場合は true
    ///   - continuesToNextRow: 次行へ続いている場合は true
    public init(
        groupID: String,
        rowIndex: Int,
        startColumn: Int,
        endColumn: Int,
        continuesFromPreviousRow: Bool,
        continuesToNextRow: Bool
    ) {
        self.groupID = groupID
        self.rowIndex = rowIndex
        self.startColumn = startColumn
        self.endColumn = endColumn
        self.continuesFromPreviousRow = continuesFromPreviousRow
        self.continuesToNextRow = continuesToNextRow
    }
}

/// アイコン型およびキャプチャ表示型グリッドの列数計算、グループ背面枠セグメント算出、および 4 方向カーソル移動を行う純粋ロジック
public enum SwitcherGridLayout {
    /// キャプチャ表示型 1 枚のカードの固定横幅（ポイント）
    public static let cardWidth: CGFloat = 216
    /// キャプチャ表示型 1 枚のカードの固定高さ（ポイント）
    public static let cardHeight: CGFloat = 164
    /// アイコン型 1 枚のタイルの固定横幅（ポイント）
    public static let iconTileWidth: CGFloat = 128
    /// アイコン型 1 枚のタイルの固定高さ（ポイント）
    public static let iconTileHeight: CGFloat = 120
    /// カード／タイル間の横・縦間隔（ポイント）
    public static let cardSpacing: CGFloat = 10
    /// グリッド外側の余白（ポイント）
    public static let gridPadding: CGFloat = 14
    /// 複数ウィンドウグループの背面枠がカード／タイル外縁から外側へ広がる余白量（ポイント）
    /// `cardSpacing (10pt)` に対して隣接する別グループ枠間に `4pt` の余白を保ちつつ、カード角丸 `10pt` と同心角丸 `13pt` を構成する
    public static let groupFrameInset: CGFloat = 3
    /// キャプチャ表示型で 1 行あたりに配置する最大列数上限
    public static let maxColumnsLimit: Int = 5
    /// アイコン型で 1 行あたりに配置する最大列数上限
    public static let iconMaxColumnsLimit: Int = 10
    /// ディスプレイ利用可能幅に対するパネル最大幅の比率
    public static let maxScreenWidthRatio: CGFloat = 0.85

    /// 項目数、利用可能な画面幅、および表示形式から、1 行あたりの適切な列数を算出する
    /// - Parameters:
    ///   - itemCount: 表示するウィンドウ項目の総数
    ///   - availableScreenWidth: アクティブディスプレイの利用可能横幅（ポイント）
    ///   - style: 計算対象の表示形式（既定値は `.capture`）
    /// - Returns: 1 以上かつ項目数以下のグリッド列数
    public static func columnsCount(
        itemCount: Int,
        availableScreenWidth: CGFloat,
        style: SwitcherDisplayStyle = .capture
    ) -> Int {
        switch style {
        case .icon:
            return columnsCount(
                itemCount: itemCount,
                availableScreenWidth: availableScreenWidth,
                itemWidth: iconTileWidth,
                maxColumns: iconMaxColumnsLimit
            )
        case .capture, .list:
            return columnsCount(
                itemCount: itemCount,
                availableScreenWidth: availableScreenWidth,
                itemWidth: cardWidth,
                maxColumns: maxColumnsLimit
            )
        }
    }

    /// 項目数、利用可能な画面幅、個別アイテム幅、および最大列数上限から、1 行あたりの列数を算出する
    /// - Parameters:
    ///   - itemCount: 表示するウィンドウ項目の総数
    ///   - availableScreenWidth: アクティブディスプレイの利用可能横幅（ポイント）
    ///   - itemWidth: 1 アイテムあたりの固定横幅（ポイント）
    ///   - maxColumns: 1 行あたりの最大列数上限
    /// - Returns: 1 以上かつ項目数以下のグリッド列数
    public static func columnsCount(
        itemCount: Int,
        availableScreenWidth: CGFloat,
        itemWidth: CGFloat,
        maxColumns: Int
    ) -> Int {
        guard itemCount > 0 else { return 1 }

        let safeItemWidth = max(itemWidth, 1)
        let safeMaxColumns = max(maxColumns, 1)
        let maxPanelWidth = max(availableScreenWidth * maxScreenWidthRatio, safeItemWidth + gridPadding * 2)
        let innerWidth = max(maxPanelWidth - gridPadding * 2, safeItemWidth)
        let rawFitColumns = Int(floor((innerWidth + cardSpacing) / (safeItemWidth + cardSpacing)))
        let clampedFitColumns = min(max(rawFitColumns, 1), safeMaxColumns)
        return min(itemCount, clampedFitColumns)
    }

    /// 項目数・列数・表示形式からグリッド全体の確定コンテンツ高さを算出する
    /// 固定高さタイル／カードで構成されるグリッドで `ScrollView` の高さを確定させ、`.fixedSize` 由来の再計測ループを防ぐために使用する
    /// - Parameters:
    ///   - itemCount: 表示するウィンドウ項目の総数
    ///   - columns: 1 行あたりの列数（1 以上）
    ///   - style: 計算対象の表示形式（`.icon` または `.capture`）
    /// - Returns: グリッド外側の余白と行間スペーシングを含むコンテンツ高さ（ポイント）
    public static func contentHeight(
        itemCount: Int,
        columns: Int,
        style: SwitcherDisplayStyle = .capture
    ) -> CGFloat {
        guard itemCount > 0 else {
            return gridPadding * 2
        }
        let safeColumns = max(columns, 1)
        let rows = (itemCount + safeColumns - 1) / safeColumns
        let tileHeight = (style == .icon) ? iconTileHeight : cardHeight
        return CGFloat(rows) * tileHeight
            + CGFloat(max(rows - 1, 0)) * cardSpacing
            + gridPadding * 2
    }

    /// 現在の選択インデックスを指定された矢印方向へグリッド上で循環移動する
    /// - Parameters:
    ///   - current: 現在の選択インデックス
    ///   - direction: 矢印キーの移動方向（上下左右）
    ///   - count: グリッド内の全項目数
    ///   - columns: 現在の 1 行あたり列数
    /// - Returns: 移動後の選択インデックス
    public static func moveIndex(
        current: Int,
        direction: ArrowDirection,
        count: Int,
        columns: Int
    ) -> Int {
        guard count > 0 else { return 0 }
        let safeCurrent = min(max(current, 0), count - 1)
        let safeColumns = max(columns, 1)

        switch direction {
        case .left:
            return SwitcherSelection.previousIndex(current: safeCurrent, count: count)
        case .right:
            return SwitcherSelection.nextIndex(current: safeCurrent, count: count)
        case .down:
            return moveVertically(
                current: safeCurrent,
                rowDelta: 1,
                count: count,
                columns: safeColumns
            )
        case .up:
            return moveVertically(
                current: safeCurrent,
                rowDelta: -1,
                count: count,
                columns: safeColumns
            )
        }
    }

    /// 同じ列を維持しつつ上下の行へ循環移動したインデックスを算出する
    /// - Parameters:
    ///   - current: 範囲保証済みの現在インデックス
    ///   - rowDelta: 行移動量（+1 で下方向、-1 で上方向）
    ///   - count: 総項目数（1 以上）
    ///   - columns: 列数（1 以上）
    /// - Returns: 移動先のインデックス（最終行の列数が不足する場合はその行の末尾に丸める）
    private static func moveVertically(
        current: Int,
        rowDelta: Int,
        count: Int,
        columns: Int
    ) -> Int {
        let totalRows = (count + columns - 1) / columns
        guard totalRows > 1 else {
            // 1 行しかない場合は左右の前後移動と同じく循環する
            return rowDelta > 0
                ? SwitcherSelection.nextIndex(current: current, count: count)
                : SwitcherSelection.previousIndex(current: current, count: count)
        }

        let currentRow = current / columns
        let currentCol = current % columns
        let targetRow = (currentRow + rowDelta + totalRows) % totalRows
        let rowStart = targetRow * columns
        let rowLength = min(columns, count - rowStart)
        return rowStart + min(currentCol, rowLength - 1)
    }

    /// グルーピング済みアプリ一覧とグリッド列数から、2 枚以上ウィンドウを持つアプリのみの行単位セグメント配列を算出する
    /// 1 枚のみのアプリグループは対象外とし、行をまたぐグループは各行ごとに分割して前後行への継続フラグを付与する
    /// - Parameters:
    ///   - groups: 表示順（`WindowAppGrouping.group` 済み）のアプリグループ配列
    ///   - columns: 現在のグリッド列数（1 以上）
    /// - Returns: 行インデックス順・開始列順に並んだ複数ウィンドウグループの行内セグメント配列
    public static func groupSegments(
        for groups: [WindowAppGroup],
        columns: Int
    ) -> [SwitcherGridGroupSegment] {
        guard !groups.isEmpty else { return [] }
        let safeColumns = max(columns, 1)

        var segments: [SwitcherGridGroupSegment] = []
        for group in groups {
            let itemCount = group.results.count
            // 1 枚のみのアプリは単体カード／タイルとして表示するため背面枠の対象外とする
            guard itemCount >= 2 else { continue }

            let groupStart = group.startIndex
            let groupEnd = groupStart + itemCount - 1
            let firstRow = groupStart / safeColumns
            let lastRow = groupEnd / safeColumns

            for row in firstRow...lastRow {
                let rowStartIndex = row * safeColumns
                let rowEndIndex = rowStartIndex + safeColumns - 1
                let segStartIndex = max(groupStart, rowStartIndex)
                let segEndIndex = min(groupEnd, rowEndIndex)

                segments.append(
                    SwitcherGridGroupSegment(
                        groupID: group.id,
                        rowIndex: row,
                        startColumn: segStartIndex - rowStartIndex,
                        endColumn: segEndIndex - rowStartIndex,
                        continuesFromPreviousRow: segStartIndex > groupStart,
                        continuesToNextRow: segEndIndex < groupEnd
                    )
                )
            }
        }

        return segments
    }

    /// 行単位グループセグメントを行インデックスごとの辞書へまとめて返す
    /// - Parameters:
    ///   - groups: 表示順のアプリグループ配列
    ///   - columns: 現在のグリッド列数（1 以上）
    /// - Returns: キーが行インデックス、値がその行に属するセグメント配列の辞書
    public static func groupSegmentsByRow(
        for groups: [WindowAppGroup],
        columns: Int
    ) -> [Int: [SwitcherGridGroupSegment]] {
        Dictionary(grouping: groupSegments(for: groups, columns: columns), by: \.rowIndex)
    }

    /// 指定された選択インデックスが 2 枚以上ウィンドウを持つアプリグループに属している場合、そのグループ ID を返す
    /// - Parameters:
    ///   - selectedIndex: 現在選択中の表示インデックス
    ///   - groups: 表示順のアプリグループ配列
    /// - Returns: 2 枚以上のグループに属していればそのグループ ID、1 枚グループや範囲外なら nil
    public static func selectedMultiWindowGroupID(
        selectedIndex: Int,
        in groups: [WindowAppGroup]
    ) -> String? {
        guard selectedIndex >= 0 else { return nil }
        for group in groups {
            let itemCount = group.results.count
            let groupRange = group.startIndex..<(group.startIndex + itemCount)
            if groupRange.contains(selectedIndex) {
                return itemCount >= 2 ? group.id : nil
            }
        }
        return nil
    }

    /// 行内グループセグメントの背面枠矩形を行基準座標（行の左上を原点とする座標系）で算出する
    /// - Parameters:
    ///   - segment: 対象の行内グループセグメント
    ///   - itemWidth: 1 カード／タイルの固定横幅（ポイント）
    ///   - itemHeight: 1 カード／タイルの固定高さ（ポイント）
    ///   - spacing: カード／タイル間の間隔（ポイント）
    ///   - frameInset: カード／タイル外縁から背面枠を外側へ広げる余白量（ポイント）
    /// - Returns: 行内座標系における背面枠の `CGRect`
    public static func segmentFrameInRow(
        for segment: SwitcherGridGroupSegment,
        itemWidth: CGFloat,
        itemHeight: CGFloat,
        spacing: CGFloat = cardSpacing,
        frameInset: CGFloat = groupFrameInset
    ) -> CGRect {
        let minX = CGFloat(segment.startColumn) * (itemWidth + spacing) - frameInset
        let span = max(segment.columnSpan, 1)
        let contentWidth = CGFloat(span) * itemWidth + CGFloat(span - 1) * spacing
        let width = contentWidth + frameInset * 2
        let minY = -frameInset
        let height = itemHeight + frameInset * 2
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
}
