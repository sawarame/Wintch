import Foundation
import Testing
@testable import WintchCore

/// アプリの「ウィンドウ」メニュー項目抽出・別スペース CGWindow とのタイトル補完ペアリング・厳密照合を検証するテストスイート
@Suite("ウィンドウメニュー補完・厳密照合テスト")
struct WindowMenuPairingTests {
    /// メニューバータイトル判定が日本語・英語の「ウィンドウ」メニューのみを認識することを検証する
    @Test("メニューバー項目のウィンドウメニュー判定が日英表記を正しく識別する")
    func recognizesWindowMenuTitles() {
        #expect(WindowMenuExtractor.isWindowMenuBarTitle("Window"))
        #expect(WindowMenuExtractor.isWindowMenuBarTitle(" window "))
        #expect(WindowMenuExtractor.isWindowMenuBarTitle("ウィンドウ"))
        #expect(WindowMenuExtractor.isWindowMenuBarTitle("ウインドウ"))
        #expect(!WindowMenuExtractor.isWindowMenuBarTitle("ファイル"))
        #expect(!WindowMenuExtractor.isWindowMenuBarTitle("View"))
    }

    /// AppKit / Electron / Chromium 標準の "makeKeyAndOrderFront:" 識別子に基づき
    /// 実在するウィンドウ項目のみを抽出し、システム補助項目を除外することを検証する
    @Test("標準識別子 makeKeyAndOrderFront: を優先して実ウィンドウ項目のみを抽出する")
    func extractsStandardMakeKeyAndOrderFrontItems() {
        let items = [
            WindowMenuItemSnapshot(title: "しまう", identifier: "performMiniaturize:", hasCommandKey: true, index: 0),
            WindowMenuItemSnapshot(title: "", identifier: nil, index: 1),
            WindowMenuItemSnapshot(title: "進行状況ウインドウを表示", identifier: "_NS:965", hasCommandKey: false, index: 2),
            WindowMenuItemSnapshot(title: "iPad に移動", identifier: "_toggleIPad:", hasCommandKey: false, index: 3),
            WindowMenuItemSnapshot(title: "tasks.md — Wintch", identifier: "makeKeyAndOrderFront:", mark: "✓", index: 4),
            WindowMenuItemSnapshot(title: "tech_stack.md — Nickmark", identifier: "makeKeyAndOrderFront:", mark: nil, index: 5)
        ]

        let extracted = WindowMenuExtractor.extractWindowListItems(from: items)
        #expect(extracted.map(\.title) == ["tasks.md — Wintch", "tech_stack.md — Nickmark"])
        #expect(extracted[0].isChecked)
        #expect(!extracted[1].isChecked)
    }

    /// 標準識別子を持たないアプリ向けのフォールバックで、チェックマーク付き連続ブロックのみ抽出し
    /// チェックマークがない通常メニューでは誤認識せず空配列を返すことを検証する
    @Test("フォールバック抽出はチェックマーク付き連続ブロックのみ抽出し非対象メニューを誤認しない")
    func fallbackExtractionRequiresCheckedAnchorBlock() {
        let customAppMenu = [
            WindowMenuItemSnapshot(title: "すべてを手前に移動", identifier: nil, hasCommandKey: false, index: 0),
            WindowMenuItemSnapshot(title: "", identifier: nil, index: 1),
            WindowMenuItemSnapshot(title: "Document A", identifier: nil, mark: nil, index: 2),
            WindowMenuItemSnapshot(title: "Document B", identifier: nil, mark: "✓", index: 3),
            WindowMenuItemSnapshot(title: "", identifier: nil, index: 4),
            WindowMenuItemSnapshot(title: "iPad に移動", identifier: "_toggleIPad:", index: 5)
        ]

        let extracted = WindowMenuExtractor.extractWindowListItems(from: customAppMenu)
        #expect(extracted.map(\.title) == ["Document A", "Document B"])

        let nonWindowMenu = [
            WindowMenuItemSnapshot(title: "閉じる", identifier: nil, hasCommandKey: true, index: 0),
            WindowMenuItemSnapshot(title: "すべてを手前に移動", identifier: nil, hasCommandKey: false, index: 1)
        ]
        #expect(WindowMenuExtractor.extractWindowListItems(from: nonWindowMenu).isEmpty)
    }

    /// すべてのウィンドウが別スペースにあるアプリ（VS Code / Chrome 等）で、
    /// cg-* 候補へチェックマーク優先・Zオーダー順に実タイトルを割り当て、余剰ゴーストを除外することを検証する
    @Test("全窓が別スペースのcg-*候補に実タイトルを補完し余剰ゴーストCGWindowを除外する")
    func pairsOffspaceCGWindowsWithCheckedPriorityAndDropsGhost() {
        let candidates = [
            makeCandidate(id: "cg-4989", pid: 5453, title: nil, hasAXInfo: false, width: 1728, height: 1117, zOrder: 10),
            makeCandidate(id: "cg-2161", pid: 5453, title: nil, hasAXInfo: false, width: 1728, height: 1117, zOrder: 25),
            makeCandidate(id: "cg-9001", pid: 5453, title: nil, hasAXInfo: false, width: 1200, height: 800, zOrder: 40),
            // 極小・ツールバー風のノイズ窓にタイトルが奪われないこと
            makeCandidate(id: "cg-9002", pid: 5453, title: nil, hasAXInfo: false, width: 1728, height: 32, zOrder: 1)
        ]

        let menuItems = [
            WindowMenuItemSnapshot(title: "GitHub PR #16", identifier: "makeKeyAndOrderFront:", mark: nil, index: 4),
            WindowMenuItemSnapshot(title: "Nickmark Bookmarks", identifier: "makeKeyAndOrderFront:", mark: "✓", index: 5)
        ]

        let result = WindowMenuCandidatePairing.applyMenuTitles(to: candidates, menuItems: menuItems)
        #expect(result.count == 2)
        #expect(result[0].id == "cg-4989")
        #expect(result[0].title == "Nickmark Bookmarks")
        #expect(result[1].id == "cg-2161")
        #expect(result[1].title == "GitHub PR #16")
    }

    /// 現在スペースに 1 枚（AX 捕捉済み）、別スペースに 2 枚目（cg-*）がある場合に、
    /// AX 済みタイトル分を消費して残りの別スペースタイトルのみを cg-* に割り当てることを検証する
    @Test("現在スペースのAX捕捉済み窓タイトルを重複除外し未捕捉cg-*へ別スペース窓のタイトルを付与する")
    func consumesAlreadyMatchedAXTitleAndPairsRemainingMenuTitle() {
        let candidates = [
            makeCandidate(id: "ax-664-1", pid: 664, title: "sawarame_yasushi", hasAXInfo: true, width: 900, height: 600, zOrder: 2),
            makeCandidate(id: "cg-2108", pid: 664, title: nil, hasAXInfo: false, width: 900, height: 600, zOrder: 18),
            makeCandidate(id: "cg-2085", pid: 664, title: nil, hasAXInfo: false, width: 900, height: 600, zOrder: 19)
        ]

        let menuItems = [
            WindowMenuItemSnapshot(title: "sawarame_yasushi", identifier: "makeKeyAndOrderFront:", mark: "✓", index: 4),
            WindowMenuItemSnapshot(title: "tmp", identifier: "makeKeyAndOrderFront:", mark: nil, index: 5)
        ]

        let result = WindowMenuCandidatePairing.applyMenuTitles(to: candidates, menuItems: menuItems)
        #expect(result.count == 2)
        #expect(result[0].id == "ax-664-1")
        #expect(result[0].title == "sawarame_yasushi")
        #expect(result[1].id == "cg-2108")
        #expect(result[1].title == "tmp")
    }

    /// 同じウィンドウタイトルを持つ 2 枚のウィンドウがある場合は多重集合として消費し、
    /// 2 枚目の別スペース窓にも同名タイトルが正しく補完されることを検証する
    @Test("同名タイトルが複数存在しても多重消費により2枚目の別スペース窓へ正しく補完する")
    func handlesDuplicateWindowTitlesUsingMultisetConsumption() {
        let candidates = [
            makeCandidate(id: "ax-100-1", pid: 100, title: "無題", hasAXInfo: true, width: 800, height: 600, zOrder: 1),
            makeCandidate(id: "cg-100-2", pid: 100, title: nil, hasAXInfo: false, width: 800, height: 600, zOrder: 5)
        ]
        let menuItems = [
            WindowMenuItemSnapshot(title: "無題", identifier: "makeKeyAndOrderFront:", mark: "✓", index: 0),
            WindowMenuItemSnapshot(title: "無題", identifier: "makeKeyAndOrderFront:", mark: nil, index: 1)
        ]

        let result = WindowMenuCandidatePairing.applyMenuTitles(to: candidates, menuItems: menuItems)
        #expect(result.count == 2)
        #expect(result[1].title == "無題")
    }

    /// Chrome 等のメニュー項目で長いタイトルが「…」で中央省略された場合でも、
    /// AX タイトルとの一致消費および補助照合が正しく機能することを検証する
    @Test("中央省略されたメニュータイトルがフルタイトルと一致判定される")
    func matchesMiddleEllipsisTitles() {
        let fullTitle = "feat(list): 管理画面一覧の列幅固定・URL入力対応 pull request #16 · sawarame/Nickmark"
        let menuTitle = "feat(list): 管理画面一覧の列幅固定・UR…t #16 · sawarame/Nickmark"
        #expect(WindowMenuCandidatePairing.titlesMatch(fullTitle, menuTitle))
        #expect(!WindowMenuCandidatePairing.titlesMatch("完全に別のページタイトル", menuTitle))

        let candidates = [
            makeCandidate(id: "ax-1", pid: 5453, title: fullTitle, hasAXInfo: true, width: 1200, height: 800, zOrder: 0),
            makeCandidate(id: "cg-2", pid: 5453, title: nil, hasAXInfo: false, width: 1200, height: 800, zOrder: 5)
        ]
        let menuItems = [
            WindowMenuItemSnapshot(title: menuTitle, identifier: "makeKeyAndOrderFront:", mark: nil, index: 0),
            WindowMenuItemSnapshot(title: "Nickmark Bookmarks", identifier: "makeKeyAndOrderFront:", mark: "✓", index: 1)
        ]

        let result = WindowMenuCandidatePairing.applyMenuTitles(to: candidates, menuItems: menuItems)
        #expect(result.count == 2)
        #expect(result[1].title == "Nickmark Bookmarks")
    }

    /// フォローアップのキャッシュ再照合で対象が見つからない場合に、別ウィンドウ（先頭要素）へフォールバックしないことを検証する
    @Test("ウィンドウ再照合で一致が見つからない場合は先頭要素へフォールバックせず nil を返す")
    func matchWindowIndexDoesNotFallbackToFirstElementOnMismatch() {
        let items: [(id: String, title: String?)] = [
            (id: "ax-1081-1", title: "tasks.md — Wintch"),
            (id: "ax-1081-2", title: "README.md — Wintch")
        ]

        let mismatched = WindowService.matchWindowIndex(
            preferredID: "cg-4880",
            title: "tech_stack.md — Nickmark",
            items: items,
            id: { $0.id },
            windowTitle: { $0.title }
        )
        #expect(mismatched == nil)

        let emptyTitleMismatch = WindowService.matchWindowIndex(
            preferredID: "cg-4880",
            title: "",
            items: items,
            id: { $0.id },
            windowTitle: { $0.title }
        )
        #expect(emptyTitleMismatch == nil)

        let titleMatched = WindowService.matchWindowIndex(
            preferredID: "cg-4880",
            title: "README.md — Wintch",
            items: items,
            id: { $0.id },
            windowTitle: { $0.title }
        )
        #expect(titleMatched == 1)
    }

    /// 1枚しか開いていない Chrome 等で、タイトル差異により AX 候補とメニュー項目が文字列一致しない場合でも、
    /// メニュー総数を超えて裏方のゴースト CGWindow（cg-2220 等）を追加表示しないことを検証する
    @Test("AXタイトルとメニュータイトルが不一致でも実ウィンドウ総数を超えてゴーストCGWindowを増殖させない")
    func doesNotDuplicateWindowWhenAXAndMenuTitlesDiverge() {
        let candidates = [
            makeCandidate(
                id: "ax-5453-1",
                pid: 5453,
                title: "Wintch | macOS 向けシンプルウィンドウ単位スイッチャー | sawara.me",
                hasAXInfo: true,
                width: 1920,
                height: 992,
                zOrder: 1
            ),
            // Chrome のアドレスバー予測変換等によるオフスクリーン裏方ウィンドウ
            makeCandidate(
                id: "cg-2220",
                pid: 5453,
                title: nil,
                hasAXInfo: false,
                width: 1344,
                height: 378,
                zOrder: 30
            )
        ]

        // 別スペース滞在中の更新や末尾表記違いでタイトルが完全一致・単一省略一致しないケース
        let menuItems = [
            WindowMenuItemSnapshot(
                title: "Wintch | macOS 向けシンプルウィンド…ー | sawara.me | sawara.me",
                identifier: "makeKeyAndOrderFront:",
                mark: nil,
                index: 5
            )
        ]

        let result = WindowMenuCandidatePairing.applyMenuTitles(to: candidates, menuItems: menuItems)
        #expect(result.count == 1)
        #expect(result[0].id == "ax-5453-1")
    }

    /// メニューに載らないフローティングウィンドウ（AXFloatingWindow）が AX 捕捉済みであっても、
    /// メニュー総数の差し引き対象に含めず別スペースの通常ウィンドウを正しく補完できることと ASCII 三点リーダー対応を検証する
    @Test("フローティングAX窓はメニュー総数から差し引かずASCII三点リーダー省略も照合できる")
    func excludesFloatingAXFromMenuCapacityAndMatchesAsciiEllipsis() {
        #expect(
            WindowMenuCandidatePairing.titlesMatch(
                "Very Long Document Title - Part 1 of Series",
                "Very Long Docu...Part 1 of Series"
            )
        )

        let candidates = [
            makeCandidate(
                id: "ax-700-1",
                pid: 700,
                title: "Main Document",
                hasAXInfo: true,
                subrole: "AXStandardWindow",
                width: 1200,
                height: 800,
                zOrder: 0
            ),
            makeCandidate(
                id: "ax-700-float",
                pid: 700,
                title: "Inspector",
                hasAXInfo: true,
                subrole: "AXFloatingWindow",
                width: 320,
                height: 480,
                zOrder: 1
            ),
            makeCandidate(
                id: "cg-700-offspace",
                pid: 700,
                title: nil,
                hasAXInfo: false,
                width: 1200,
                height: 800,
                zOrder: 10
            )
        ]

        let menuItems = [
            WindowMenuItemSnapshot(title: "Main Document", identifier: "makeKeyAndOrderFront:", mark: "✓", index: 0),
            WindowMenuItemSnapshot(title: "Second Window", identifier: "makeKeyAndOrderFront:", mark: nil, index: 1)
        ]

        let result = WindowMenuCandidatePairing.applyMenuTitles(to: candidates, menuItems: menuItems)
        #expect(result.count == 3)
        #expect(result.last?.id == "cg-700-offspace")
        #expect(result.last?.title == "Second Window")
    }

    /// テスト用 RawWindowCandidate 生成ヘルパー
    /// - Parameters:
    ///   - id: ウィンドウ識別子
    ///   - pid: プロセス ID
    ///   - title: タイトル
    ///   - hasAXInfo: AX 情報保持フラグ
    ///   - subrole: AX サブロール
    ///   - width: 幅
    ///   - height: 高さ
    ///   - zOrder: Z オーダー順位
    /// - Returns: 構築された RawWindowCandidate
    private func makeCandidate(
        id: String,
        pid: Int32,
        title: String?,
        hasAXInfo: Bool,
        subrole: String? = "AXStandardWindow",
        width: Double,
        height: Double,
        zOrder: Int
    ) -> RawWindowCandidate {
        RawWindowCandidate(
            id: id,
            cgWindowID: UInt32(max(1, zOrder + 100)),
            pid: pid,
            bundleIdentifier: "com.example.app",
            applicationName: "ExampleApp",
            title: title,
            layer: 0,
            bounds: WindowBounds(x: 0, y: 0, width: width, height: height),
            alpha: 1.0,
            isRegularApplication: true,
            isSelf: false,
            isMinimized: false,
            axRole: hasAXInfo ? "AXWindow" : nil,
            axSubrole: hasAXInfo ? subrole : nil,
            hasAXInfo: hasAXInfo,
            isOnScreen: hasAXInfo,
            lastActivatedAt: nil,
            zOrderIndex: zOrder
        )
    }
}
