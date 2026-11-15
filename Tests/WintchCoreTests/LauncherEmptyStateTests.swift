import Testing
@testable import WintchCore

/// 検索ランチャーの空状態判定ロジックおよび表示メッセージ定義を検証するテストスイート
@Suite("LauncherEmptyState テスト")
struct LauncherEmptyStateTests {
    /// ウィンドウ候補またはアプリ起動候補が 1 件以上ある場合は空状態にならないことを検証する
    @Test("ウィンドウ候補またはアプリ候補が1件以上ある場合はnilを返す")
    func nonEmptyResultsReturnNil() {
        #expect(
            LauncherEmptyState.resolve(
                hasOpenWindows: true,
                searchQuery: "",
                displayedWindowCount: 1,
                displayedAppCount: 0
            ) == nil
        )
        #expect(
            LauncherEmptyState.resolve(
                hasOpenWindows: false,
                searchQuery: "saf",
                displayedWindowCount: 0,
                displayedAppCount: 1
            ) == nil
        )
        #expect(
            LauncherEmptyState.resolve(
                hasOpenWindows: true,
                searchQuery: "s",
                displayedWindowCount: 2,
                displayedAppCount: 3
            ) == nil
        )
    }

    /// ウィンドウ0件かつ未入力（空文字・半角空白・全角空白）の場合は noOpenWindows を返すことを検証する
    @Test("ウィンドウ0件かつ検索未入力時はnoOpenWindowsを返す")
    func zeroWindowsWithEmptyQueryReturnsNoOpenWindows() {
        let emptyQueries = ["", "   ", "\t\n", "　　"]
        for query in emptyQueries {
            let state = LauncherEmptyState.resolve(
                hasOpenWindows: false,
                searchQuery: query,
                displayedWindowCount: 0,
                displayedAppCount: 0
            )
            #expect(state == .noOpenWindows)
        }
    }

    /// 検索キーワード入力後に一致0件となった場合、開いているウィンドウの有無に応じた空状態を返すことを検証する
    @Test("検索キーワード入力後の一致0件時は開いているウィンドウ有無に応じた状態を返す")
    func nonEmptyQueryWithZeroResultsDistinguishesWindowPresence() {
        let stateWithoutWindows = LauncherEmptyState.resolve(
            hasOpenWindows: false,
            searchQuery: "nonexistent",
            displayedWindowCount: 0,
            displayedAppCount: 0
        )
        #expect(stateWithoutWindows == .noMatchingApps)

        let stateWithWindows = LauncherEmptyState.resolve(
            hasOpenWindows: true,
            searchQuery: "nonexistent",
            displayedWindowCount: 0,
            displayedAppCount: 0
        )
        #expect(stateWithWindows == .noMatchingCandidates)
    }

    /// 各空状態に対応するユーザー向け案内メッセージが意図通りに定義されていることを検証する
    @Test("各空状態に応じた適切な日本語案内メッセージを返す")
    func messagesMatchEachEmptyState() {
        #expect(
            LauncherEmptyState.noOpenWindows.message
                == "開いているウィンドウがありません（アプリ名を入力して起動）"
        )
        #expect(LauncherEmptyState.noMatchingApps.message == "一致するアプリがありません")
        #expect(
            LauncherEmptyState.noMatchingCandidates.message
                == "一致するウィンドウやアプリがありません"
        )
    }
}
