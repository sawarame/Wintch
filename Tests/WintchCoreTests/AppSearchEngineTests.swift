import Foundation
import Testing
@testable import WintchCore

/// AppSearchEngine のファジー検索・日本語／英語名マッチ・スコア順ソートを検証するテストスイート
@Suite("AppSearchEngine テスト")
struct AppSearchEngineTests {
    /// 空クエリや空白のみの場合はアプリ起動候補を返さないことを検証する
    @Test("空クエリまたは空白のみの場合は空配列を返す")
    func emptyOrWhitespaceQueryReturnsEmpty() {
        let apps = [
            LaunchableApp(displayName: "Safari", bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")),
            LaunchableApp(displayName: "Notes", bundleURL: URL(fileURLWithPath: "/System/Applications/Notes.app"))
        ]

        #expect(AppSearchEngine.search(query: "", in: apps).isEmpty)
        #expect(AppSearchEngine.search(query: "   \t\n ", in: apps).isEmpty)
    }

    /// 英語略称およびローカライズ名（日本語名＋英語別名）の双方でヒットしハイライト範囲が取れることを検証する
    @Test("表示名と英語別名の双方でファジー検索でき一致文字範囲を抽出できる")
    func matchesDisplayNameAndAlternateName() {
        let vscode = LaunchableApp(
            displayName: "Visual Studio Code",
            bundleURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        )
        let notes = LaunchableApp(
            displayName: "メモ",
            alternateName: "Notes",
            bundleURL: URL(fileURLWithPath: "/System/Applications/Notes.app")
        )
        let settings = LaunchableApp(
            displayName: "システム設定",
            alternateName: "System Settings",
            bundleURL: URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )

        // 略称検索 ("vsc") で表示名内の一致範囲が抽出される
        let vscResults = AppSearchEngine.search(query: "vsc", in: [notes, vscode])
        #expect(vscResults.map(\.app.displayName) == ["Visual Studio Code"])
        let vscChars = vscResults[0].matchedDisplayNameRanges.map { String(vscode.displayName[$0]) }.joined()
        #expect(vscChars == "VSC")

        // 日本語環境での英語別名検索 ("note") で「メモ (Notes)」がヒットする
        let engResults = AppSearchEngine.search(query: "note", in: [vscode, notes, settings])
        #expect(engResults.map(\.app.displayName) == ["メモ"])
        let altChars = engResults[0].matchedAlternateNameRanges.map { String(notes.alternateName[$0]) }.joined()
        #expect(altChars == "Note")

        // 日本語検索 ("設定") でもヒットする
        let jpResults = AppSearchEngine.search(query: "設定", in: [notes, settings])
        #expect(jpResults.map(\.app.displayName) == ["システム設定"])
    }

    /// スコア降順、同スコア時は表示名昇順で安定ソートされることを検証する
    @Test("スコア降順および同スコア時の表示名昇順で並び替わる")
    func sortsByScoreDescendingThenDisplayNameAscending() {
        let scattered = LaunchableApp(
            displayName: "My Cool App",
            bundleURL: URL(fileURLWithPath: "/Applications/My Cool App.app")
        )
        let prefixExact = LaunchableApp(
            displayName: "Mail",
            bundleURL: URL(fileURLWithPath: "/System/Applications/Mail.app")
        )
        let appB = LaunchableApp(
            displayName: "Term B",
            bundleURL: URL(fileURLWithPath: "/Applications/Term B.app")
        )
        let appA = LaunchableApp(
            displayName: "Term A",
            bundleURL: URL(fileURLWithPath: "/Applications/Term A.app")
        )

        let scoreOrder = AppSearchEngine.search(query: "mail", in: [scattered, prefixExact])
        #expect(scoreOrder.map(\.app.displayName) == ["Mail"])

        let tieOrder = AppSearchEngine.search(query: "term", in: [appB, appA])
        #expect(tieOrder.map(\.app.displayName) == ["Term A", "Term B"])
    }
}
