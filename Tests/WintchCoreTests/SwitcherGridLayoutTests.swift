import CoreGraphics
import Testing
@testable import WintchCore

/// SwitcherGridLayout の列数算出および 4 方向グリッド移動の純粋ロジックを検証するテストスイート
@Suite("SwitcherGridLayout テスト")
struct SwitcherGridLayoutTests {
    /// 項目数と画面幅に応じた列数算出が上限・下限・最小余白制約を満たすことを検証する
    @Test("項目数と画面幅から適切なグリッド列数を算出する")
    func columnsCountRespectsItemCountAndScreenWidth() {
        // 1 件〜2 件のときは項目数に一致し、不要な空列を作らない
        #expect(SwitcherGridLayout.columnsCount(itemCount: 1, availableScreenWidth: 1440) == 1)
        #expect(SwitcherGridLayout.columnsCount(itemCount: 2, availableScreenWidth: 1440) == 2)

        // 広い画面でも最大列数上限（5 列）を超えない
        #expect(SwitcherGridLayout.columnsCount(itemCount: 12, availableScreenWidth: 2560) == 5)

        // 狭い画面（例: 520pt）では画面幅 85% 以内に収まる列数へ自動調整される
        #expect(SwitcherGridLayout.columnsCount(itemCount: 6, availableScreenWidth: 520) == 1)
        #expect(SwitcherGridLayout.columnsCount(itemCount: 6, availableScreenWidth: 800) == 2)

        // 0 件以下でも安全な 1 を返す
        #expect(SwitcherGridLayout.columnsCount(itemCount: 0, availableScreenWidth: 1440) == 1)
    }

    /// 3 列 × 7 件（最終行 1 件）のグリッドにおける上下左右の循環移動を検証する
    @Test("4 方向矢印キーでグリッド上の循環移動および最終行クランプが正しく動作する")
    func fourWayNavigationWithPartialLastRow() {
        // グリッド配置 (count = 7, columns = 3):
        // [0] [1] [2]
        // [3] [4] [5]
        // [6]
        let count = 7
        let columns = 3

        // 右移動: 末尾(6)から先頭(0)へ循環する
        #expect(SwitcherGridLayout.moveIndex(current: 0, direction: .right, count: count, columns: columns) == 1)
        #expect(SwitcherGridLayout.moveIndex(current: 6, direction: .right, count: count, columns: columns) == 0)

        // 左移動: 先頭(0)から末尾(6)へ循環する
        #expect(SwitcherGridLayout.moveIndex(current: 0, direction: .left, count: count, columns: columns) == 6)
        #expect(SwitcherGridLayout.moveIndex(current: 3, direction: .left, count: count, columns: columns) == 2)

        // 下移動: 列 0 は 0 -> 3 -> 6 -> 0 と縦循環する
        #expect(SwitcherGridLayout.moveIndex(current: 0, direction: .down, count: count, columns: columns) == 3)
        #expect(SwitcherGridLayout.moveIndex(current: 3, direction: .down, count: count, columns: columns) == 6)
        #expect(SwitcherGridLayout.moveIndex(current: 6, direction: .down, count: count, columns: columns) == 0)

        // 下移動: 最終行に列 2 が存在しないため、2 行目の列 2 (index 5) からは最終行末尾 (index 6) に丸められる
        #expect(SwitcherGridLayout.moveIndex(current: 2, direction: .down, count: count, columns: columns) == 5)
        #expect(SwitcherGridLayout.moveIndex(current: 5, direction: .down, count: count, columns: columns) == 6)

        // 上移動: 1 行目の列 2 (index 2) から上へ抜けると最終行末尾 (index 6) へ循環する
        #expect(SwitcherGridLayout.moveIndex(current: 2, direction: .up, count: count, columns: columns) == 6)
        // 上移動: 1 行目の列 1 (index 1) から上へ抜けると最終行末尾 (index 6) へ循環し、index 4 からは index 1 へ戻る
        #expect(SwitcherGridLayout.moveIndex(current: 1, direction: .up, count: count, columns: columns) == 6)
        #expect(SwitcherGridLayout.moveIndex(current: 4, direction: .up, count: count, columns: columns) == 1)
    }

    /// 1 行のみのグリッドで上下キーが左右移動と同様に循環することを検証する
    @Test("1 行のみのグリッドでは上下移動も前後循環として動作する")
    func singleRowGridUpDownWrapsSequentially() {
        let count = 3
        let columns = 3

        #expect(SwitcherGridLayout.moveIndex(current: 0, direction: .down, count: count, columns: columns) == 1)
        #expect(SwitcherGridLayout.moveIndex(current: 2, direction: .down, count: count, columns: columns) == 0)
        #expect(SwitcherGridLayout.moveIndex(current: 0, direction: .up, count: count, columns: columns) == 2)
    }
}
