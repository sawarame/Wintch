import Foundation
import Testing
@testable import WintchCore

/// WindowSearchEngine のファジー検索・スコア順ソート・ハイライト範囲算出を検証するテストスイート
@Suite("WindowSearchEngine テスト")
struct WindowSearchEngineTests {
    /// 空クエリおよび空白のみのクエリでは MRU 順のまま全件返却されることを検証する
    @Test("空クエリ時は元の MRU 順を維持して全件返す")
    func emptyQueryPreservesMRUOrder() {
        let entries = [
            WindowEntry(id: "w1", pid: 1, applicationName: "Safari", windowTitle: "Apple"),
            WindowEntry(id: "w2", pid: 2, applicationName: "Xcode", windowTitle: "Wintch")
        ]

        let resultsEmpty = WindowSearchEngine.search(query: "", in: entries)
        let resultsSpaces = WindowSearchEngine.search(query: "   \t ", in: entries)

        #expect(resultsEmpty.map(\.id) == ["w1", "w2"])
        #expect(resultsSpaces.map(\.id) == ["w1", "w2"])
        #expect(resultsEmpty.allSatisfy { $0.score == 0 && $0.matchedAppNameRanges.isEmpty && $0.matchedTitleRanges.isEmpty })
    }

    /// 略称のサブシーケンス一致（"vsc" → "Visual Studio Code"）とハイライト範囲を検証する
    @Test("サブシーケンスによるファジー検索で一致文字範囲を抽出できる")
    func fuzzySubsequenceMatchesAndExtractsRanges() {
        let vsc = WindowEntry(id: "vsc", pid: 1, applicationName: "Visual Studio Code", windowTitle: "README.md")
        let safari = WindowEntry(id: "safari", pid: 2, applicationName: "Safari", windowTitle: "News")

        let results = WindowSearchEngine.search(query: "vsc", in: [safari, vsc])

        #expect(results.map(\.id) == ["vsc"])
        let matchedText = results[0].matchedAppNameRanges
            .map { String(vsc.applicationName[$0]) }
            .joined()
        #expect(matchedText.lowercased() == "vsc")
    }

    /// スペース区切りの複数キーワードによる AND 条件検索を検証する
    @Test("スペース区切りでアプリ名とタイトルを横断した AND 検索ができる")
    func spaceSeparatedTokensRequireAllMatches() {
        let chromeGit = WindowEntry(id: "cg", pid: 1, applicationName: "Google Chrome", windowTitle: "GitHub - Wintch")
        let chromeDocs = WindowEntry(id: "cd", pid: 2, applicationName: "Google Chrome", windowTitle: "Google Docs")
        let safariGit = WindowEntry(id: "sg", pid: 3, applicationName: "Safari", windowTitle: "GitHub")

        let results = WindowSearchEngine.search(query: "chr git", in: [chromeDocs, safariGit, chromeGit])

        #expect(results.map(\.id) == ["cg"])
        #expect(!results[0].matchedAppNameRanges.isEmpty)
        #expect(!results[0].matchedTitleRanges.isEmpty)
    }

    /// ウィンドウタイトルが空の項目では補助表示文字列「(タイトルなし)」に一致しないことを検証する
    @Test("空タイトルウィンドウは補助表記「(タイトルなし)」に一致しない")
    func emptyTitleDoesNotMatchPlaceholderText() {
        let untitled = WindowEntry(id: "u1", pid: 1, applicationName: "Finder", windowTitle: "   ")
        let titled = WindowEntry(id: "t1", pid: 2, applicationName: "Notes", windowTitle: "タイトルメモ")

        let results = WindowSearchEngine.search(query: "タイトル", in: [untitled, titled])

        #expect(results.map(\.id) == ["t1"])
    }

    /// 高スコア項目が上位になり、同スコア時は元の MRU 順が保たれることを検証する
    @Test("一致スコア降順で並び、同スコアの場合は元の MRU 順を維持する")
    func sortsByScoreDescendingWithMRUTieBreaker() {
        // w1 は古い MRU 位置だが連続・先頭一致するため、散在一致の w0 より上位になるべき
        let scattered = WindowEntry(id: "w0", pid: 1, applicationName: "App", windowTitle: "My C_a_r_d View")
        let prefixExact = WindowEntry(id: "w1", pid: 2, applicationName: "CardApp", windowTitle: "Home")
        // 同条件のアプリ同士では MRU 先頭側が維持される
        let mruFirst = WindowEntry(id: "m1", pid: 3, applicationName: "Terminal", windowTitle: "zsh")
        let mruSecond = WindowEntry(id: "m2", pid: 4, applicationName: "Terminal", windowTitle: "zsh")

        let scoreResults = WindowSearchEngine.search(query: "card", in: [scattered, prefixExact])
        #expect(scoreResults.map(\.id) == ["w1", "w0"])

        let tieResults = WindowSearchEngine.search(query: "term", in: [mruFirst, mruSecond])
        #expect(tieResults.map(\.id) == ["m1", "m2"])
    }

    /// 日本語および大文字小文字を区別しない検索が正しく動作することを検証する
    @Test("日本語および大文字小文字を区別せずに検索できる")
    func caseInsensitiveAndJapaneseSearch() {
        let settings = WindowEntry(id: "s1", pid: 1, applicationName: "システム設定", windowTitle: "アクセシビリティ")
        let mail = WindowEntry(id: "m1", pid: 2, applicationName: "Mail", windowTitle: "Café Meeting")

        let jpResults = WindowSearchEngine.search(query: "設定 アク", in: [mail, settings])
        #expect(jpResults.map(\.id) == ["s1"])

        let diacriticResults = WindowSearchEngine.search(query: "cafe", in: [settings, mail])
        #expect(diacriticResults.map(\.id) == ["m1"])
    }
}
