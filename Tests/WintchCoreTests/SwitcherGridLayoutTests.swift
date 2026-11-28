import CoreGraphics
import Foundation
import Testing
@testable import WintchCore

/// SwitcherGridLayout の列数算出および 4 方向グリッド移動の純粋ロジックを検証するテストスイート
@Suite("SwitcherGridLayout テスト")
struct SwitcherGridLayoutTests {
    /// 項目数と画面幅に応じた列数算出が上限・下限・最小余白制約を満たすことを検証する
    @Test("項目数と画面幅から適切なグリッド列数を算出する")
    func columnsCountRespectsItemCountAndScreenWidth() {
        // キャプチャ表示型（グルーピング OFF）のカード寸法および最大列数上限は従来通り不変であること
        #expect(SwitcherGridLayout.cardWidth == 216)
        #expect(SwitcherGridLayout.cardHeight == 164)
        #expect(SwitcherGridLayout.maxColumnsLimit == 5)

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

    /// アイコン型の拡大後タイル幅（128pt）と最大列数上限（10 列）に基づく列数算出および SwitcherDisplayStyle の定義を検証する
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
        #expect(SwitcherGridLayout.iconTileWidth == 128)
        #expect(SwitcherGridLayout.iconMaxColumnsLimit == 10)

        // アイコン型でも 1〜3 件のときは項目数に一致し、不要な空列を作らない
        #expect(SwitcherGridLayout.columnsCount(itemCount: 1, availableScreenWidth: 1440, style: .icon) == 1)
        #expect(SwitcherGridLayout.columnsCount(itemCount: 3, availableScreenWidth: 1440, style: .icon) == 3)

        // 1440pt 画面では画面幅 85% 以内（8 列）に収まり、広い画面では最大列数上限（10 列）でクランプされる
        #expect(SwitcherGridLayout.columnsCount(itemCount: 12, availableScreenWidth: 1440, style: .icon) == 8)
        #expect(SwitcherGridLayout.columnsCount(itemCount: 12, availableScreenWidth: 1920, style: .icon) == 10)
        #expect(SwitcherGridLayout.columnsCount(itemCount: 20, availableScreenWidth: 2560, style: .icon) == 10)

        // 狭い画面では画面幅 85% 以内に収まる列数へ自動折り返しされる
        // availableScreenWidth = 500 -> maxPanelWidth = 425 -> innerWidth = 397 -> floor((397 + 10) / 138) = 2 列
        #expect(SwitcherGridLayout.columnsCount(itemCount: 10, availableScreenWidth: 500, style: .icon) == 2)
        // availableScreenWidth = 300 -> maxPanelWidth = 255 -> innerWidth = 227 -> floor((227 + 10) / 138) = 1 列
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

    /// 項目数・列数・表示形式からグリッドの確定コンテンツ高さが正確に算出されることを検証する
    @Test("グリッドの確定コンテンツ高さがタイル寸法・行間・余白から正確に算出される")
    func gridContentHeightCalculatesExactRowsAndPadding() {
        // 0 件時は上下余白のみ
        #expect(
            SwitcherGridLayout.contentHeight(itemCount: 0, columns: 5, style: .capture)
                == SwitcherGridLayout.gridPadding * 2
        )

        // キャプチャ表示型: 1 行（3 件 / 3 列）= 164 + 28 = 192
        #expect(
            SwitcherGridLayout.contentHeight(itemCount: 3, columns: 3, style: .capture)
                == SwitcherGridLayout.cardHeight + SwitcherGridLayout.gridPadding * 2
        )

        // キャプチャ表示型: 3 行（11 件 / 5 列）= 164*3 + 10*2 + 28 = 540
        #expect(
            SwitcherGridLayout.contentHeight(itemCount: 11, columns: 5, style: .capture)
                == SwitcherGridLayout.cardHeight * 3
                    + SwitcherGridLayout.cardSpacing * 2
                    + SwitcherGridLayout.gridPadding * 2
        )

        // アイコン型: 2 行（11 件 / 10 列）= 120*2 + 10 + 28 = 278
        #expect(
            SwitcherGridLayout.contentHeight(itemCount: 11, columns: 10, style: .icon)
                == SwitcherGridLayout.iconTileHeight * 2
                    + SwitcherGridLayout.cardSpacing
                    + SwitcherGridLayout.gridPadding * 2
        )
    }

    /// 複数ウィンドウを持つアプリのみ行内グループセグメントが生成され、
    /// 行またぎ（末尾 1 枚＋先頭 1 枚、3 行跨ぎの中間行含む）の開放エッジフラグが正確に算出されることを検証する
    @Test("2 枚以上ウィンドウを持つアプリのみ背面枠セグメントが生成され行またぎ継続フラグが正確に設定される")
    func groupSegmentsCoverOnlyMultiWindowAppsAndMarkRowContinuations() {
        /// テスト用のダミーアプリグループを生成するローカルヘルパー
        func makeGroup(id: String, count: Int, startIndex: Int) -> WindowAppGroup {
            let results = (0..<count).map { offset in
                WindowSearchResult(
                    entry: WindowEntry(
                        id: "\(id)-\(offset)",
                        pid: Int32(startIndex + 10),
                        bundleIdentifier: id,
                        applicationName: id,
                        windowTitle: "Window \(offset)"
                    )
                )
            }
            return WindowAppGroup(
                id: "bundle:\(id)",
                applicationName: id,
                representativePID: Int32(startIndex + 10),
                results: results,
                startIndex: startIndex
            )
        }

        // 5 列グリッド配置:
        // Row 0: [SoloA(0)] [AppB(1)] [AppB(2)] [AppB(3)] [SplitC(4)]
        // Row 1: [SplitC(5)] [SoloD(6)] [GiantE(7)] [GiantE(8)] [GiantE(9)]
        // Row 2: [GiantE(10)] [GiantE(11)] [GiantE(12)] [GiantE(13)] [GiantE(14)]
        // Row 3: [GiantE(15)] [GiantE(16)]
        let groups: [WindowAppGroup] = [
            makeGroup(id: "SoloA", count: 1, startIndex: 0),
            makeGroup(id: "AppB", count: 3, startIndex: 1),
            makeGroup(id: "SplitC", count: 2, startIndex: 4),
            makeGroup(id: "SoloD", count: 1, startIndex: 6),
            makeGroup(id: "GiantE", count: 10, startIndex: 7)
        ]

        let segments = SwitcherGridLayout.groupSegments(for: groups, columns: 5)
        #expect(segments.count == 6)

        // 1 枚のみの SoloA / SoloD はセグメントに含まれないこと
        #expect(!segments.contains { $0.groupID == "bundle:SoloA" || $0.groupID == "bundle:SoloD" })

        // Row 0 の AppB（列 1〜3）は行内で完結するため前後継続ともに false
        #expect(
            segments[0] == SwitcherGridGroupSegment(
                groupID: "bundle:AppB",
                rowIndex: 0,
                startColumn: 1,
                endColumn: 3,
                continuesFromPreviousRow: false,
                continuesToNextRow: false
            )
        )

        // SplitC は Row 0 末尾 1 枚（右開放）＋ Row 1 先頭 1 枚（左開放）として両方セグメント化される
        #expect(
            segments[1] == SwitcherGridGroupSegment(
                groupID: "bundle:SplitC",
                rowIndex: 0,
                startColumn: 4,
                endColumn: 4,
                continuesFromPreviousRow: false,
                continuesToNextRow: true
            )
        )
        #expect(
            segments[2] == SwitcherGridGroupSegment(
                groupID: "bundle:SplitC",
                rowIndex: 1,
                startColumn: 0,
                endColumn: 0,
                continuesFromPreviousRow: true,
                continuesToNextRow: false
            )
        )

        // GiantE は 3 行に跨ぎ、先頭行は右開放・中間行は左右開放・最終行は左開放となる
        #expect(
            segments[3] == SwitcherGridGroupSegment(
                groupID: "bundle:GiantE",
                rowIndex: 1,
                startColumn: 2,
                endColumn: 4,
                continuesFromPreviousRow: false,
                continuesToNextRow: true
            )
        )
        #expect(
            segments[4] == SwitcherGridGroupSegment(
                groupID: "bundle:GiantE",
                rowIndex: 2,
                startColumn: 0,
                endColumn: 4,
                continuesFromPreviousRow: true,
                continuesToNextRow: true
            )
        )
        #expect(
            segments[5] == SwitcherGridGroupSegment(
                groupID: "bundle:GiantE",
                rowIndex: 3,
                startColumn: 0,
                endColumn: 1,
                continuesFromPreviousRow: true,
                continuesToNextRow: false
            )
        )

        // 選択中グループ ID 解決: 複数ウィンドウグループは ID を返し、単体グループや範囲外は nil
        #expect(SwitcherGridLayout.selectedMultiWindowGroupID(selectedIndex: 0, in: groups) == nil)
        #expect(SwitcherGridLayout.selectedMultiWindowGroupID(selectedIndex: 2, in: groups) == "bundle:AppB")
        #expect(SwitcherGridLayout.selectedMultiWindowGroupID(selectedIndex: 4, in: groups) == "bundle:SplitC")
        #expect(SwitcherGridLayout.selectedMultiWindowGroupID(selectedIndex: 5, in: groups) == "bundle:SplitC")
        #expect(SwitcherGridLayout.selectedMultiWindowGroupID(selectedIndex: 6, in: groups) == nil)
        #expect(SwitcherGridLayout.selectedMultiWindowGroupID(selectedIndex: 12, in: groups) == "bundle:GiantE")
        #expect(SwitcherGridLayout.selectedMultiWindowGroupID(selectedIndex: 99, in: groups) == nil)
        #expect(SwitcherGridLayout.selectedMultiWindowGroupID(selectedIndex: -1, in: groups) == nil)

        // 空配列でも安全に空結果を返すこと
        #expect(SwitcherGridLayout.groupSegments(for: [], columns: 5).isEmpty)
    }

    /// 行内セグメントの背面枠矩形がカード列と整合し、隣接別グループ枠およびパネル外縁との干渉が起きないことを検証する
    @Test("行内グループ枠の座標計算で隣接別グループ間およびパネル外縁に適切な余白が確保される")
    func segmentFrameInRowPreservesGapsBetweenAdjacentGroupsAndPanelEdges() {
        let leftSegment = SwitcherGridGroupSegment(
            groupID: "bundle:Left",
            rowIndex: 0,
            startColumn: 0,
            endColumn: 1,
            continuesFromPreviousRow: false,
            continuesToNextRow: false
        )
        let rightSegment = SwitcherGridGroupSegment(
            groupID: "bundle:Right",
            rowIndex: 0,
            startColumn: 2,
            endColumn: 3,
            continuesFromPreviousRow: false,
            continuesToNextRow: false
        )

        let leftRect = SwitcherGridLayout.segmentFrameInRow(
            for: leftSegment,
            itemWidth: SwitcherGridLayout.cardWidth,
            itemHeight: SwitcherGridLayout.cardHeight
        )
        let rightRect = SwitcherGridLayout.segmentFrameInRow(
            for: rightSegment,
            itemWidth: SwitcherGridLayout.cardWidth,
            itemHeight: SwitcherGridLayout.cardHeight
        )

        // 2 枚分の幅 + インセット両端
        let expectedWidth = SwitcherGridLayout.cardWidth * 2
            + SwitcherGridLayout.cardSpacing
            + SwitcherGridLayout.groupFrameInset * 2
        #expect(leftRect.minX == -SwitcherGridLayout.groupFrameInset)
        #expect(leftRect.minY == -SwitcherGridLayout.groupFrameInset)
        #expect(leftRect.width == expectedWidth)
        #expect(leftRect.height == SwitcherGridLayout.cardHeight + SwitcherGridLayout.groupFrameInset * 2)

        // 隣り合う別グループ枠の間に 4pt 以上の隙間が保たれ、接触しないこと
        let horizontalGap = rightRect.minX - leftRect.maxX
        #expect(horizontalGap == SwitcherGridLayout.cardSpacing - SwitcherGridLayout.groupFrameInset * 2)
        #expect(horizontalGap >= 4)

        // 外側パディング内に枠インセットが十分に収まること
        #expect(SwitcherGridLayout.gridPadding - SwitcherGridLayout.groupFrameInset >= 8)

        // 開放エッジ 4 パターンすべての枠線パスが有効な矩形内に生成されること
        let sampleBounds = CGRect(x: 0, y: 0, width: leftRect.width, height: leftRect.height)
        for openLeading in [false, true] {
            for openTrailing in [false, true] {
                let shape = SwitcherGridGroupBorderShape(
                    closedCornerRadius: 13,
                    openEdgeInset: 2,
                    lineWidth: 1.5,
                    openLeading: openLeading,
                    openTrailing: openTrailing
                )
                let path = shape.path(in: sampleBounds)
                #expect(!path.isEmpty)
                #expect(path.boundingRect.minX >= -0.01)
                #expect(path.boundingRect.minY >= -0.01)
                #expect(path.boundingRect.maxX <= sampleBounds.width + 0.01)
                #expect(path.boundingRect.maxY <= sampleBounds.height + 0.01)
            }
        }
    }
}
