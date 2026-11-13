import Foundation
import Testing
@testable import WintchCore

/// WindowFilter のノイズ除外ロジックを検証するテストスイート
@Suite("WindowFilter テスト")
struct WindowFilterTests {
    /// 通常の標準ウィンドウが正しく WindowEntry に変換・保持されることを検証する
    @Test("通常ウィンドウはフィルタを通過する")
    func validWindowPasses() {
        let candidate = RawWindowCandidate(
            id: "win-1",
            cgWindowID: 101,
            pid: 1000,
            applicationName: "Safari",
            title: "GitHub",
            layer: 0,
            bounds: WindowBounds(width: 1200, height: 800),
            alpha: 1.0,
            isRegularApplication: true,
            isSelf: false,
            axSubrole: "AXStandardWindow"
        )

        let result = WindowFilter.filterAndMap([candidate])
        #expect(result.count == 1)
        #expect(result[0].id == "win-1")
        #expect(result[0].applicationName == "Safari")
        #expect(result[0].windowTitle == "GitHub")
    }

    /// 各種ノイズウィンドウがすべて除外されることを検証する
    @Test("ノイズウィンドウをすべて除外する")
    func noiseWindowsAreExcluded() {
        let candidates = [
            // 自アプリのウィンドウ
            RawWindowCandidate(id: "self", pid: 1, applicationName: "Wintch", isSelf: true),
            // 非通常アプリ（メニューバー専用常駐アプリ等）
            RawWindowCandidate(id: "agent", pid: 2, applicationName: "MenuHelper", isRegularApplication: false),
            // レイヤーが 0 以外（メニューバー、Dock、オーバーレイ等）
            RawWindowCandidate(id: "layer", pid: 3, applicationName: "Dock", layer: 20),
            // 不透明度が 0.0（不可視ウィンドウ）
            RawWindowCandidate(id: "alpha", pid: 4, applicationName: "Hidden", alpha: 0.0),
            // 幅または高さが 50pt 未満の極小トラッキングウィンドウ
            RawWindowCandidate(id: "tiny-w", pid: 5, applicationName: "Tracker", bounds: WindowBounds(width: 49, height: 200)),
            RawWindowCandidate(id: "tiny-h", pid: 6, applicationName: "Tracker", bounds: WindowBounds(width: 200, height: 49)),
            // 許可されないサブロール（ポップオーバー等）
            RawWindowCandidate(id: "subrole", pid: 7, applicationName: "App", axSubrole: "AXUnknown")
        ]

        let result = WindowFilter.filterAndMap(candidates)
        #expect(result.isEmpty)
    }

    /// 境界値（幅50x高さ50）および別スペース由来のサブロールnilウィンドウが通過することを検証する
    @Test("境界サイズ50x50およびサブロール未取得ウィンドウは通過する")
    func boundarySizeAndNilSubrolePass() {
        let candidates = [
            RawWindowCandidate(
                id: "min-size",
                pid: 10,
                applicationName: "SmallApp",
                title: nil,
                bounds: WindowBounds(width: 50, height: 50),
                axSubrole: "AXDialog"
            ),
            RawWindowCandidate(
                id: "other-space",
                pid: 11,
                applicationName: "Terminal",
                title: nil,
                bounds: WindowBounds(width: 600, height: 400),
                axSubrole: nil
            )
        ]

        let result = WindowFilter.filterAndMap(candidates)
        #expect(result.count == 2)
        #expect(result[0].windowTitle == "")
        #expect(result[0].displayTitle == "(タイトルなし)")
        #expect(result[1].id == "other-space")
    }

    /// Finder の隠し小窓・デスクトップ要素や Chrome のフルスクリーン用補助バーが除外されることを検証する
    @Test("Finder や Chrome の内部補助ウィンドウを除外する")
    func internalGhostWindowsAreExcluded() {
        let candidates = [
            // Finder デスクトップ等の非ウィンドウ AX 要素（AXScrollArea / サブロール未設定）
            RawWindowCandidate(
                id: "finder-desktop",
                pid: 100,
                applicationName: "Finder",
                bounds: WindowBounds(width: 1920, height: 1080),
                axRole: "AXScrollArea",
                axSubrole: nil,
                hasAXInfo: true
            ),
            // Finder 内部の 64x64 隠し CGWindow（AX 情報なし）
            RawWindowCandidate(
                id: "cg-finder-64",
                cgWindowID: 61,
                pid: 100,
                applicationName: "Finder",
                bounds: WindowBounds(x: 0, y: 580, width: 64, height: 64),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false
            ),
            // Chrome フルスクリーン時のツールバー / 上端オーバーレイストリップ（1920x81, 1920x158）
            RawWindowCandidate(
                id: "cg-chrome-toolbar",
                cgWindowID: 1487,
                pid: 200,
                applicationName: "Google Chrome",
                bounds: WindowBounds(x: 0, y: 41, width: 1920, height: 81),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false
            ),
            RawWindowCandidate(
                id: "cg-chrome-reveal",
                cgWindowID: 1489,
                pid: 200,
                applicationName: "Google Chrome",
                bounds: WindowBounds(x: 0, y: 0, width: 1920, height: 158),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false
            ),
            // 現在のスペース上に表示中だが AX と照合されなかった内部オーバーレイ（isOnScreen == true）
            RawWindowCandidate(
                id: "cg-onscreen-overlay",
                cgWindowID: 999,
                pid: 200,
                applicationName: "Google Chrome",
                bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: true
            ),
            // 別スペースの通常サイズ CGWindow 補完候補（通過すべき対象）
            RawWindowCandidate(
                id: "cg-chrome-fullscreen-content",
                cgWindowID: 1486,
                pid: 200,
                applicationName: "Google Chrome",
                bounds: WindowBounds(x: 0, y: 122, width: 1920, height: 958),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false
            )
        ]

        let result = WindowFilter.filterAndMap(candidates)
        #expect(result.count == 1)
        #expect(result[0].id == "cg-chrome-fullscreen-content")
    }

    /// 同一座標に二重生成された Finder 等の CGWindow と、AX 捕捉済みアプリの裏 CGWindow が重複統合されることを検証する
    @Test("同一座標の CGWindow 二重生成と AX 捕捉済みアプリの裏 CGWindow を除外する")
    func duplicateCGFallbacksAreConsolidated() {
        let candidates = [
            // Finder: AX 未捕捉の別スペース上に、同一座標の CGWindow が 2 つ存在するケース
            RawWindowCandidate(
                id: "cg-2107",
                cgWindowID: 2107,
                pid: 1244,
                applicationName: "Finder",
                bounds: WindowBounds(x: 273, y: 240, width: 1150, height: 688),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false,
                zOrderIndex: 0
            ),
            RawWindowCandidate(
                id: "cg-2085",
                cgWindowID: 2085,
                pid: 1244,
                applicationName: "Finder",
                bounds: WindowBounds(x: 273, y: 240, width: 1150, height: 688),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false,
                zOrderIndex: 1
            ),
            // Chrome: AX で 1 ウィンドウが既に捕捉されており、裏の CGWindow が別座標で残っているケース
            RawWindowCandidate(
                id: "ax-chrome-1",
                cgWindowID: 1486,
                pid: 1240,
                applicationName: "Google Chrome",
                title: "Google",
                bounds: WindowBounds(x: 0, y: 0, width: 1920, height: 1080),
                axRole: "AXWindow",
                axSubrole: "AXStandardWindow",
                hasAXInfo: true,
                zOrderIndex: 2
            ),
            RawWindowCandidate(
                id: "cg-chrome-hidden",
                cgWindowID: 1526,
                pid: 1240,
                applicationName: "Google Chrome",
                bounds: WindowBounds(x: 99, y: 26, width: 1344, height: 458),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false,
                zOrderIndex: 3
            )
        ]

        let result = WindowFilter.filterAndMap(candidates)
        #expect(result.count == 2)
        #expect(result.map(\.id) == ["cg-2107", "ax-chrome-1"])
    }

    /// AX 未捕捉の別スペースにフルスクリーン本体と別座標の裏ウィンドウが並存する場合に代表 1 件のみ残ることを検証する
    @Test("AX未捕捉アプリで別座標の裏CGWindowがあっても最大面積の代表1件だけを残す")
    func axUncoveredPIDConsolidatesToLargestCGFallback() {
        let candidates = [
            // 裏ウィンドウの方が Z オーダー手前にあっても、面積最大のフルスクリーン本体が代表として選ばれる
            RawWindowCandidate(
                id: "cg-wezterm-hidden",
                cgWindowID: 3001,
                pid: 2500,
                applicationName: "WezTerm",
                bounds: WindowBounds(x: 100, y: 120, width: 1200, height: 600),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false,
                zOrderIndex: 0
            ),
            RawWindowCandidate(
                id: "cg-wezterm-fullscreen",
                cgWindowID: 3002,
                pid: 2500,
                applicationName: "WezTerm",
                bounds: WindowBounds(x: 0, y: 38, width: 1512, height: 944),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false,
                zOrderIndex: 1
            )
        ]

        let result = WindowFilter.filterAndMap(candidates)
        #expect(result.count == 1)
        #expect(result[0].id == "cg-wezterm-fullscreen")
    }
}
