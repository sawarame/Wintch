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

    /// 同一非フルスクリーン座標に二重生成された Finder 等の CGWindow は統合しつつ、
    /// 別スペース上のフルスクリーン／別座標ウィンドウは同アプリでも個別に保持されることを検証する
    @Test("同一非フルスクリーン座標の CGWindow 二重生成を統合し、別スペースの複数ウィンドウは集約せず保持する")
    func duplicateNonFullscreenConsolidatedWhileDistinctAndFullscreenMultiWindowsPreserved() {
        let candidates = [
            // Finder: 同一非フルスクリーン座標で二重生成された CGWindow は 1 件に統合する
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
            // VS Code: 1 枚が AX 捕捉済みでも、別スペースにある 2 枚目のフルスクリーンウィンドウは両方保持する
            RawWindowCandidate(
                id: "ax-vscode-1",
                cgWindowID: 55,
                pid: 1081,
                applicationName: "Code",
                title: "Wintch",
                bounds: WindowBounds(x: 0, y: 0, width: 1920, height: 1080),
                axRole: "AXWindow",
                axSubrole: "AXStandardWindow",
                hasAXInfo: true,
                isOnScreen: true,
                zOrderIndex: 2
            ),
            RawWindowCandidate(
                id: "cg-4880",
                cgWindowID: 4880,
                pid: 1081,
                applicationName: "Code",
                bounds: WindowBounds(x: 0, y: 0, width: 1920, height: 1080),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false,
                zOrderIndex: 3
            ),
            // Google Chrome: AX 未捕捉の別スペースに 2 枚のフルスクリーンウィンドウが存在する場合も両方保持する
            RawWindowCandidate(
                id: "cg-4989",
                cgWindowID: 4989,
                pid: 5453,
                applicationName: "Google Chrome",
                bounds: WindowBounds(x: 0, y: 88, width: 1920, height: 992),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false,
                zOrderIndex: 4
            ),
            RawWindowCandidate(
                id: "cg-2161",
                cgWindowID: 2161,
                pid: 5453,
                applicationName: "Google Chrome",
                bounds: WindowBounds(x: 0, y: 88, width: 1920, height: 992),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false,
                zOrderIndex: 5
            )
        ]

        let result = WindowFilter.filterAndMap(candidates)
        #expect(result.map(\.id) == ["cg-2107", "ax-vscode-1", "cg-4880", "cg-4989", "cg-2161"])
    }

    /// AX 未捕捉の別スペースに異なる矩形の通常ウィンドウが複数ある場合、1 件へ集約せず両方残ることを検証する
    @Test("AX未捕捉アプリでも異なる座標・サイズの通常ウィンドウが複数あれば個別に保持する")
    func axUncoveredPIDPreservesMultipleDistinctNonFullscreenWindows() {
        let candidates = [
            RawWindowCandidate(
                id: "cg-wezterm-sub",
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
        #expect(result.map(\.id) == ["cg-wezterm-sub", "cg-wezterm-fullscreen"])
    }

    /// 実質サイズを持つフローティングウィンドウ（layer=3 / AXFloatingWindow）が通過し、小サイズ補助窓が除外されることを検証する
    @Test("通常サイズのフローティングウィンドウを通過させ小サイズのフローティング補助窓を除外する")
    func floatingWindowsAreFilteredBySubstantialSize() {
        let candidates = [
            // Gemini ミニチャット等の通常サイズフローティングウィンドウ（AX 情報あり）
            RawWindowCandidate(
                id: "ax-gemini-floating",
                cgWindowID: 3026,
                pid: 4000,
                applicationName: "Gemini",
                title: "Gemini",
                layer: 3,
                bounds: WindowBounds(x: 267, y: 149, width: 1386, height: 811),
                axRole: "AXWindow",
                axSubrole: "AXFloatingWindow",
                hasAXInfo: true
            ),
            // システムフローティングサブロールかつ十分大きいパネル
            RawWindowCandidate(
                id: "ax-system-floating",
                cgWindowID: 3027,
                pid: 4001,
                applicationName: "QuickNote",
                title: "メモ",
                layer: 3,
                bounds: WindowBounds(x: 100, y: 100, width: 400, height: 300),
                axRole: "AXWindow",
                axSubrole: "AXSystemFloatingWindow",
                hasAXInfo: true
            ),
            // 64x64 のフルスクリーン補助窓（layer=3）は除外される
            RawWindowCandidate(
                id: "cg-floating-thumbnail",
                cgWindowID: 2959,
                pid: 4000,
                applicationName: "Gemini",
                layer: 3,
                bounds: WindowBounds(x: 903, y: 953, width: 64, height: 64),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: false
            ),
            // 小サイズのフローティングツールパレット（AXFloatingWindow でも最小サイズ未満は除外）
            RawWindowCandidate(
                id: "ax-tiny-palette",
                cgWindowID: 3030,
                pid: 4002,
                applicationName: "Designer",
                title: "Colors",
                layer: 3,
                bounds: WindowBounds(x: 10, y: 10, width: 150, height: 120),
                axRole: "AXWindow",
                axSubrole: "AXFloatingWindow",
                hasAXInfo: true
            )
        ]

        let result = WindowFilter.filterAndMap(candidates)
        #expect(result.map(\.id) == ["ax-gemini-floating", "ax-system-floating"])
    }

    /// AX 未捕捉のアプリで画面表示中（isOnScreen == true）の実サイズ CGWindow のみが存在する場合に救済されることを検証する
    @Test("AX未捕捉で表示中の実サイズウィンドウのみ存在するアプリは代表1件を救済し、AX捕捉済みアプリの裏窓は除外する")
    func onScreenFallbackRescuesUncoveredAppWithoutLeakingCoveredOverlays() {
        let candidates = [
            // AX で捕捉できなかった表示中のフローティングウィンドウとフルスクリーン本体（未捕捉 PID）
            RawWindowCandidate(
                id: "cg-gemini-floating",
                cgWindowID: 3026,
                pid: 5000,
                applicationName: "Gemini",
                layer: 3,
                bounds: WindowBounds(x: 267, y: 149, width: 1386, height: 811),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: true,
                zOrderIndex: 0
            ),
            RawWindowCandidate(
                id: "cg-gemini-main",
                cgWindowID: 2958,
                pid: 5000,
                applicationName: "Gemini",
                layer: 0,
                bounds: WindowBounds(x: 0, y: 0, width: 1920, height: 1080),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: true,
                zOrderIndex: 1
            ),
            // ツールバー帯は表示中フォールバックでも除外される
            RawWindowCandidate(
                id: "cg-gemini-toolbar",
                cgWindowID: 3135,
                pid: 5000,
                applicationName: "Gemini",
                layer: 0,
                bounds: WindowBounds(x: 0, y: 0, width: 1920, height: 52),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: true,
                zOrderIndex: 2
            ),
            // 既に AX で捕捉されている別アプリの isOnScreen == true 内部オーバーレイは引き続き除外される
            RawWindowCandidate(
                id: "ax-covered-main",
                cgWindowID: 6001,
                pid: 5001,
                applicationName: "Browser",
                title: "Main",
                layer: 0,
                bounds: WindowBounds(x: 0, y: 0, width: 1200, height: 800),
                axRole: "AXWindow",
                axSubrole: "AXStandardWindow",
                hasAXInfo: true,
                zOrderIndex: 3
            ),
            RawWindowCandidate(
                id: "cg-covered-overlay",
                cgWindowID: 6002,
                pid: 5001,
                applicationName: "Browser",
                layer: 0,
                bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600),
                axSubrole: nil,
                hasAXInfo: false,
                isOnScreen: true,
                zOrderIndex: 4
            )
        ]

        let result = WindowFilter.filterAndMap(candidates)
        #expect(result.map(\.id) == ["cg-gemini-main", "ax-covered-main"])
    }
}
