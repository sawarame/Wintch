import CoreGraphics
import Foundation

/// キャプチャ表示型グリッドの列数計算および 4 方向カーソル移動を行う純粋ロジック
public enum SwitcherGridLayout {
    /// 1 枚のカードの固定横幅（ポイント）
    public static let cardWidth: CGFloat = 216
    /// 1 枚のカードの固定高さ（ポイント）
    public static let cardHeight: CGFloat = 164
    /// カード間の横・縦間隔（ポイント）
    public static let cardSpacing: CGFloat = 10
    /// グリッド外側の余白（ポイント）
    public static let gridPadding: CGFloat = 14
    /// 1 行あたりに配置する最大列数上限
    public static let maxColumnsLimit: Int = 5
    /// ディスプレイ利用可能幅に対するパネル最大幅の比率
    public static let maxScreenWidthRatio: CGFloat = 0.85

    /// 項目数と利用可能な画面幅から、1 行あたりの適切な列数を算出する
    /// - Parameters:
    ///   - itemCount: 表示するウィンドウカードの総数
    ///   - availableScreenWidth: アクティブディスプレイの利用可能横幅（ポイント）
    /// - Returns: 1 以上かつ項目数以下のグリッド列数
    public static func columnsCount(itemCount: Int, availableScreenWidth: CGFloat) -> Int {
        guard itemCount > 0 else { return 1 }

        let maxPanelWidth = max(availableScreenWidth * maxScreenWidthRatio, cardWidth + gridPadding * 2)
        let innerWidth = max(maxPanelWidth - gridPadding * 2, cardWidth)
        let rawFitColumns = Int(floor((innerWidth + cardSpacing) / (cardWidth + cardSpacing)))
        let clampedFitColumns = min(max(rawFitColumns, 1), maxColumnsLimit)
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
}
