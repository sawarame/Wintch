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

        // 広い画面でも最大列数上限（キャプチャ表示型: 5 列）を超えない
        #expect(SwitcherGridLayout.columnsCount(itemCount: 12, availableScreenWidth: 2560) == 5)

        // 狭い画面（例: 520pt）では画面幅 85% 以内に収まる列数へ自動調整される
        #expect(SwitcherGridLayout.columnsCount(itemCount: 6, availableScreenWidth: 520) == 1)
        #expect(SwitcherGridLayout.columnsCount(itemCount: 6, availableScreenWidth: 800) == 2)

        // 0 件以下でも安全な 1 を返す
        #expect(SwitcherGridLayout.columnsCount(itemCount: 0, availableScreenWidth: 1440) == 1)
    }

    /// アイコン型のタイル幅（112pt）と最大列数上限（8 列）に基づく列数算出および SwitcherDisplayStyle の定義を検証する
    @Test("アイコン型の列数計算および SwitcherDisplayStyle の定義順・プロパティを検証する")
    func iconStyleColumnsCountAndDisplayStyleProperties() {
        // SwitcherDisplayStyle の列挙順・rawValue・displayName・default・usesGridLayout
        #expect(SwitcherDisplayStyle.allCases == [.list, .icon, .capture])
        #expect(SwitcherDisplayStyle.default == .list)
        #expect(SwitcherDisplayStyle.list.rawValue == "list")
        #expect(SwitcherDisplayStyle.icon.rawValue == "icon")
        #expect(SwitcherDisplayStyle.capture.rawValue == "capture")
        #expect(SwitcherDisplayStyle.list.displayName == "リスト型")
        #expect(SwitcherDisplayStyle.icon.displayName == "アイコン型")
        #expect(SwitcherDisplayStyle.capture.displayName == "キャプチャ表示型")
        #expect(SwitcherDisplayStyle.list.usesGridLayout == false)
        #expect(SwitcherDisplayStyle.icon.usesGridLayout == true)
        #expect(SwitcherDisplayStyle.capture.usesGridLayout == true)

        // アイコン型でも 1〜3 件のときは項目数に一致し、不要な空列を作らない
        #expect(SwitcherGridLayout.columnsCount(itemCount: 1, availableScreenWidth: 1440, style: .icon) == 1)
        #expect(SwitcherGridLayout.columnsCount(itemCount: 3, availableScreenWidth: 1440, style: .icon) == 3)

        // 広い画面では最大列数上限（8 列）でクランプされる
        #expect(SwitcherGridLayout.columnsCount(itemCount: 12, availableScreenWidth: 1440, style: .icon) == 8)
        #expect(SwitcherGridLayout.columnsCount(itemCount: 20, availableScreenWidth: 2560, style: .icon) == 8)

        // 狭い画面では画面幅 85% 以内に収まる列数へ自動折り返しされる
        // availableScreenWidth = 500 -> maxPanelWidth = 425 -> innerWidth = 397 -> floor((397 + 10) / 122) = 3 列
        #expect(SwitcherGridLayout.columnsCount(itemCount: 10, availableScreenWidth: 500, style: .icon) == 3)
        // availableScreenWidth = 300 -> maxPanelWidth = 255 -> innerWidth = 227 -> floor((227 + 10) / 122) = 1 列
        #expect(SwitcherGridLayout.columnsCount(itemCount: 10, availableScreenWidth: 300, style: .icon) == 1)
        #expect(SwitcherGridLayout.columnsCount(itemCount: 0, availableScreenWidth: 1440, style: .icon) == 1)
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

    /// グルーピング表示時のセクション別列数算出と 4 方向カーソル移動（セクション跨ぎ・末尾丸め・循環）を検証する
    @Test("セクション付きグリッドの列数算出および 4 方向移動（セクション跨ぎ・列クランプ・循環）を検証する")
    func groupedGridColumnsAndFourWaySectionNavigation() {
        // セクション件数 [4, 1, 2], 最大列数 3 の行配置:
        // セクション 0:
        //   [0] [1] [2]
        //   [3]
        // セクション 1:
        //   [4]
        // セクション 2:
        //   [5] [6]
        #expect(
            SwitcherGridLayout.groupedColumnsCount(
                sectionCounts: [4, 1, 2],
                availableScreenWidth: 1440,
                style: .capture
            ) == 4
        )
        #expect(
            SwitcherGridLayout.groupedColumnsCount(
                sectionCounts: [1, 1, 1],
                availableScreenWidth: 1440,
                style: .icon
            ) == 1
        )

        let sections = [4, 1, 2]
        let columns = 3

        // 左右は全セクション貫通で連続循環
        #expect(SwitcherGridLayout.moveIndex(current: 3, direction: .right, sectionCounts: sections, columns: columns) == 4)
        #expect(SwitcherGridLayout.moveIndex(current: 6, direction: .right, sectionCounts: sections, columns: columns) == 0)
        #expect(SwitcherGridLayout.moveIndex(current: 0, direction: .left, sectionCounts: sections, columns: columns) == 6)

        // 下移動: 列 2 の index 2 -> セクション 0 の 2 行目は 1 件しかないので index 3 に丸められる
        #expect(SwitcherGridLayout.moveIndex(current: 2, direction: .down, sectionCounts: sections, columns: columns) == 3)
        // 下移動: index 3 (列 0) -> セクション 1 の index 4 -> セクション 2 の index 5 -> 先頭行 index 0 へ循環
        #expect(SwitcherGridLayout.moveIndex(current: 3, direction: .down, sectionCounts: sections, columns: columns) == 4)
        #expect(SwitcherGridLayout.moveIndex(current: 4, direction: .down, sectionCounts: sections, columns: columns) == 5)
        #expect(SwitcherGridLayout.moveIndex(current: 5, direction: .down, sectionCounts: sections, columns: columns) == 0)

        // 上移動: index 6 (列 1) -> セクション 1 は 1 件なので index 4 に丸められる
        #expect(SwitcherGridLayout.moveIndex(current: 6, direction: .up, sectionCounts: sections, columns: columns) == 4)
        // 上移動: 先頭行の index 2 (列 2) -> 最終行（セクション 2、2 件）の末尾 index 6 へ循環する
        #expect(SwitcherGridLayout.moveIndex(current: 2, direction: .up, sectionCounts: sections, columns: columns) == 6)
        // 上移動: 先頭行の index 0 (列 0) -> 最終行の列 0 である index 5 へ循環する
        #expect(SwitcherGridLayout.moveIndex(current: 0, direction: .up, sectionCounts: sections, columns: columns) == 5)
    }
}
