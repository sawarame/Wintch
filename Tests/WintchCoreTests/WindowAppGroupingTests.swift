import Foundation
import Testing
@testable import WintchCore

/// WindowAppGrouping のグルーピングキー解決・安定グルーピング・MRU 2 番目初期選択解決・ハイライト集約を検証するテストスイート
@Suite("WindowAppGrouping テスト")
struct WindowAppGroupingTests {
    /// bundleIdentifier 優先および未取得・空白時の pid フォールバックによるグルーピングキー生成を検証する
    @Test("groupKey は非空の bundleIdentifier を優先し、未取得・空白時は pid にフォールバックする")
    func groupKeyPrefersBundleIdentifierAndFallsBackToPID() {
        let withBundle = WindowEntry(
            id: "w1",
            pid: 10,
            bundleIdentifier: " com.google.Chrome ",
            applicationName: "Google Chrome",
            windowTitle: "Docs"
        )
        let withBlankBundle = WindowEntry(
            id: "w2",
            pid: 20,
            bundleIdentifier: "   ",
            applicationName: "CustomTool",
            windowTitle: "Main"
        )
        let withoutBundle = WindowEntry(
            id: "w3",
            pid: 30,
            bundleIdentifier: nil,
            applicationName: "CLIApp",
            windowTitle: "Output"
        )

        #expect(WindowAppGrouping.groupKey(for: withBundle) == "bundle:com.google.Chrome")
        #expect(WindowAppGrouping.groupKey(for: withBlankBundle) == "pid:20")
        #expect(WindowAppGrouping.groupKey(for: withoutBundle) == "pid:30")
    }

    /// 未検索時（MRU 順入力）に初出順でアプリグループが構成され、各グループ内の MRU 順と開始インデックスが維持されることを検証する
    @Test("未検索時は初出順（最上位ウィンドウの MRU 順）でグルーピングし各グループ内順序を保持する")
    func groupsPreservingFirstAppearanceAndInGroupMRUOrder() {
        let now = Date()
        let entries = [
            WindowEntry(
                id: "chrome-1",
                pid: 100,
                bundleIdentifier: "com.google.Chrome",
                applicationName: "Google Chrome",
                windowTitle: "PR #49",
                lastActivatedAt: now
            ),
            WindowEntry(
                id: "term-1",
                pid: 200,
                bundleIdentifier: "com.apple.Terminal",
                applicationName: "Terminal",
                windowTitle: "zsh",
                lastActivatedAt: now.addingTimeInterval(-10)
            ),
            WindowEntry(
                id: "chrome-2",
                pid: 101,
                bundleIdentifier: "com.google.Chrome",
                applicationName: "Google Chrome",
                windowTitle: "Issue #49",
                lastActivatedAt: now.addingTimeInterval(-20)
            ),
            WindowEntry(
                id: "finder-1",
                pid: 300,
                bundleIdentifier: nil,
                applicationName: "Finder",
                windowTitle: "Desktop",
                lastActivatedAt: now.addingTimeInterval(-30)
            ),
            WindowEntry(
                id: "term-2",
                pid: 200,
                bundleIdentifier: "com.apple.Terminal",
                applicationName: "Terminal",
                windowTitle: "git log",
                lastActivatedAt: now.addingTimeInterval(-40)
            )
        ]

        let results = entries.map { WindowSearchResult(entry: $0) }
        let groups = WindowAppGrouping.group(results)

        #expect(groups.count == 3)
        #expect(groups.map(\.id) == ["bundle:com.google.Chrome", "bundle:com.apple.Terminal", "pid:300"])
        #expect(groups[0].applicationName == "Google Chrome")
        #expect(groups[0].representativePID == 100)
        #expect(groups[0].startIndex == 0)
        #expect(groups[0].results.map(\.id) == ["chrome-1", "chrome-2"])

        #expect(groups[1].applicationName == "Terminal")
        #expect(groups[1].representativePID == 200)
        #expect(groups[1].startIndex == 2)
        #expect(groups[1].results.map(\.id) == ["term-1", "term-2"])

        #expect(groups[2].applicationName == "Finder")
        #expect(groups[2].representativePID == 300)
        #expect(groups[2].startIndex == 4)
        #expect(groups[2].results.map(\.id) == ["finder-1"])

        let flattened = WindowAppGrouping.flatten(groups)
        #expect(flattened.map(\.id) == ["chrome-1", "chrome-2", "term-1", "term-2", "finder-1"])
    }

    /// 検索結果入力時は最高スコア順でアプリグループが並び、見出しアプリ名の一致ハイライト範囲が安全にマージされることを検証する
    @Test("検索時はスコア降順でアプリグループが並び見出しアプリ名の一致範囲が集約される")
    func searchGroupingOrdersByHighestScoreAndMergesHeaderHighlightRanges() {
        let entries = [
            WindowEntry(
                id: "code-1",
                pid: 10,
                bundleIdentifier: "com.microsoft.VSCode",
                applicationName: "Visual Studio Code",
                windowTitle: "README.md"
            ),
            WindowEntry(
                id: "safari-1",
                pid: 20,
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Visual Guide"
            ),
            WindowEntry(
                id: "code-2",
                pid: 10,
                bundleIdentifier: "com.microsoft.VSCode",
                applicationName: "Visual Studio Code",
                windowTitle: "Package.swift"
            )
        ]

        let searched = WindowSearchEngine.search(query: "Visual", in: entries)
        let groups = WindowAppGrouping.group(searched)

        #expect(groups.count == 2)
        // primaryFieldBonus によりアプリ名に一致した Visual Studio Code が先頭グループになる
        #expect(groups[0].applicationName == "Visual Studio Code")
        #expect(groups[0].results.map(\.id) == ["code-1", "code-2"])
        #expect(!groups[0].matchedAppNameRanges.isEmpty)
        let highlighted = groups[0].matchedAppNameRanges
            .map { String(groups[0].applicationName[$0]) }
            .joined()
        #expect(highlighted.lowercased() == "visual")

        // タイトルのみ一致した Safari の見出しアプリ名にはハイライトが付かない
        #expect(groups[1].applicationName == "Safari")
        #expect(groups[1].matchedAppNameRanges.isEmpty)
    }

    /// 通常スイッチャー起動時の初期選択が、グルーピング ON 時は MRU 2 番目ウィンドウの位置へ解決されることを検証する
    @Test("通常スイッチャー初期選択はグルーピング ON 時に MRU 2 番目ウィンドウの表示位置を返す")
    func resolvesSecondMRUWindowIndexWhenGrouped() {
        let now = Date()
        let mruEntries = [
            WindowEntry(id: "chrome-1", pid: 10, bundleIdentifier: "com.google.Chrome", applicationName: "Chrome", windowTitle: "Tab 1", lastActivatedAt: now),
            WindowEntry(id: "term-1", pid: 20, bundleIdentifier: "com.apple.Terminal", applicationName: "Terminal", windowTitle: "zsh", lastActivatedAt: now.addingTimeInterval(-5)),
            WindowEntry(id: "chrome-2", pid: 10, bundleIdentifier: "com.google.Chrome", applicationName: "Chrome", windowTitle: "Tab 2", lastActivatedAt: now.addingTimeInterval(-15))
        ]
        let groups = WindowAppGrouping.group(mruEntries.map { WindowSearchResult(entry: $0) })
        let groupedResults = WindowAppGrouping.flatten(groups)
        // 表示順: [chrome-1 (0), chrome-2 (1), term-1 (2)] -> MRU 2 番目の term-1 はインデックス 2
        #expect(groupedResults.map(\.id) == ["chrome-1", "chrome-2", "term-1"])

        let groupedInitial = WindowAppGrouping.resolveInitialIndexForNormalSwitcher(
            mruSortedEntries: mruEntries,
            displayedResults: groupedResults,
            isGrouped: true
        )
        #expect(groupedInitial == 2)

        // グルーピング OFF 時は従来どおりインデックス 1
        let flatInitial = WindowAppGrouping.resolveInitialIndexForNormalSwitcher(
            mruSortedEntries: mruEntries,
            displayedResults: mruEntries.map { WindowSearchResult(entry: $0) },
            isGrouped: false
        )
        #expect(flatInitial == 1)

        // 1 件のみ時は 0、0 件時は nil
        #expect(
            WindowAppGrouping.resolveInitialIndexForNormalSwitcher(
                mruSortedEntries: [mruEntries[0]],
                displayedResults: [WindowSearchResult(entry: mruEntries[0])],
                isGrouped: true
            ) == 0
        )
        #expect(
            WindowAppGrouping.resolveInitialIndexForNormalSwitcher(
                mruSortedEntries: [],
                displayedResults: [],
                isGrouped: true
            ) == nil
        )
    }
}
