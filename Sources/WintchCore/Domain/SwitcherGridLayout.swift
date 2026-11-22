import CoreGraphics
import Foundation

/// アイコン型およびキャプチャ表示型グリッドの列数計算および 4 方向カーソル移動を行う純粋ロジック
public enum SwitcherGridLayout {
    /// キャプチャ表示型 1 枚のカードの固定横幅（ポイント）
    public static let cardWidth: CGFloat = 216
    /// キャプチャ表示型 1 枚のカードの固定高さ（ポイント）
    public static let cardHeight: CGFloat = 164
    /// アイコン型 1 枚のタイルの固定横幅（ポイント）
    public static let iconTileWidth: CGFloat = 112
    /// アイコン型 1 枚のタイルの固定高さ（ポイント）
    public static let iconTileHeight: CGFloat = 120
    /// カード／タイル間の横・縦間隔（ポイント）
    public static let cardSpacing: CGFloat = 10
    /// グリッド外側の余白（ポイント）
    public static let gridPadding: CGFloat = 14
    /// キャプチャ表示型で 1 行あたりに配置する最大列数上限
    public static let maxColumnsLimit: Int = 5
    /// アイコン型で 1 行あたりに配置する最大列数上限
    public static let iconMaxColumnsLimit: Int = 8
    /// ディスプレイ利用可能幅に対するパネル最大幅の比率
    public static let maxScreenWidthRatio: CGFloat = 0.85
    /// アイコン型のグルーピング表示時にセクション見出しが読みやすい最小パネル幅（2 タイル分相当）
    public static let iconGroupedMinPanelWidth: CGFloat = iconTileWidth * 2 + cardSpacing + gridPadding * 2

    /// グルーピング表示時の各セクション件数・利用可能画面幅・表示形式から、1 行あたりの列数を算出する
    /// - Parameters:
    ///   - sectionCounts: 各アプリセクションに属するウィンドウ件数の配列
    ///   - availableScreenWidth: アクティブディスプレイの利用可能横幅（ポイント）
    ///   - style: 計算対象の表示形式（既定値は `.capture`）
    /// - Returns: 1 以上かつ最大セクション件数以下のグリッド列数
    public static func groupedColumnsCount(
        sectionCounts: [Int],
        availableScreenWidth: CGFloat,
        style: SwitcherDisplayStyle = .capture
    ) -> Int {
        let maxSectionCount = sectionCounts.max() ?? 0
        return columnsCount(
            itemCount: maxSectionCount,
            availableScreenWidth: availableScreenWidth,
            style: style
        )
    }

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

    /// セクション分けされたグリッド上で、現在の選択インデックスを指定方向へ循環移動する
    /// - Parameters:
    ///   - current: 現在の選択インデックス
    ///   - direction: 矢印キーの移動方向（上下左右）
    ///   - sectionCounts: 各セクションの項目数配列
    ///   - columns: 現在の 1 行あたり列数
    /// - Returns: 移動後の選択インデックス
    public static func moveIndex(
        current: Int,
        direction: ArrowDirection,
        sectionCounts: [Int],
        columns: Int
    ) -> Int {
        let validSections = sectionCounts.filter { $0 > 0 }
        let totalCount = validSections.reduce(0, +)
        guard totalCount > 0 else { return 0 }

        let safeCurrent = min(max(current, 0), totalCount - 1)
        let safeColumns = max(columns, 1)

        switch direction {
        case .left:
            return SwitcherSelection.previousIndex(current: safeCurrent, count: totalCount)
        case .right:
            return SwitcherSelection.nextIndex(current: safeCurrent, count: totalCount)
        case .down:
            return moveVerticallyAcrossSections(
                current: safeCurrent,
                rowDelta: 1,
                sectionCounts: validSections,
                totalCount: totalCount,
                columns: safeColumns
            )
        case .up:
            return moveVerticallyAcrossSections(
                current: safeCurrent,
                rowDelta: -1,
                sectionCounts: validSections,
                totalCount: totalCount,
                columns: safeColumns
            )
        }
    }

    /// セクションごとの折り返し行構造を構築し、同じ列を維持しつつ上下の行へ循環移動する
    /// - Parameters:
    ///   - current: 範囲保証済みの現在インデックス
    ///   - rowDelta: 行移動量（+1 で下方向、-1 で上方向）
    ///   - sectionCounts: 正の値のみを含むセクション件数配列
    ///   - totalCount: 全セクション合計項目数（1 以上）
    ///   - columns: 1 行あたりの最大列数（1 以上）
    /// - Returns: 移動後のインデックス（移動先行の列数が不足する場合はその行の末尾へ丸める）
    private static func moveVerticallyAcrossSections(
        current: Int,
        rowDelta: Int,
        sectionCounts: [Int],
        totalCount: Int,
        columns: Int
    ) -> Int {
        var rows: [(startIndex: Int, length: Int)] = []
        var offset = 0

        for sectionCount in sectionCounts {
            var remaining = sectionCount
            while remaining > 0 {
                let rowLength = min(columns, remaining)
                rows.append((startIndex: offset, length: rowLength))
                offset += rowLength
                remaining -= rowLength
            }
        }

        guard rows.count > 1 else {
            return rowDelta > 0
                ? SwitcherSelection.nextIndex(current: current, count: totalCount)
                : SwitcherSelection.previousIndex(current: current, count: totalCount)
        }

        guard let currentRowIndex = rows.firstIndex(where: { row in
            current >= row.startIndex && current < row.startIndex + row.length
        }) else {
            return 0
        }

        let currentCol = current - rows[currentRowIndex].startIndex
        let targetRowIndex = (currentRowIndex + rowDelta + rows.count) % rows.count
        let targetRow = rows[targetRowIndex]
        return targetRow.startIndex + min(currentCol, targetRow.length - 1)
    }
}
