import Foundation
import Testing
@testable import WintchCore

/// 統一リスト行モデル SwitcherListRow の行構築・識別子一意性・インデックス解決を検証するテストスイート
@Suite("SwitcherListRow テスト")
struct SwitcherListRowTests {
    /// ウィンドウ候補とアプリ起動候補の双方が同一の元 ID を持つ場合でも接頭辞で一意性が保たれ、scrollTargetID と一致することを検証する
    @Test("構築された行の識別子がすべて一意であり、scrollTargetID と完全一致する")
    func buildRowsProducesUniqueIDsMatchingScrollTargetID() {
        let windows = [
            WindowSearchResult(
                entry: WindowEntry(id: "shared-id", pid: 10, applicationName: "Safari", windowTitle: "Tab 1")
            ),
            WindowSearchResult(
                entry: WindowEntry(id: "win-2", pid: 20, applicationName: "Finder", windowTitle: "Home")
            )
        ]
        let apps = [
            AppSearchResult(
                app: LaunchableApp(
                    id: "shared-id",
                    displayName: "Xcode",
                    bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app")
                )
            )
        ]

        let rows = SwitcherListRow.buildRows(
            windowResults: windows,
            appResults: apps,
            isShowingLaunchCandidates: true,
            launchSectionHeaderTitle: "アプリを起動"
        )

        #expect(rows.count == 4)
        // 先頭 2 件はウィンドウ行、3 件目は見出し行、4 件目は統一インデックス 2 のアプリ行
        #expect(rows[0].id == "window-shared-id")
        #expect(rows[1].id == "window-win-2")
        #expect(rows[2] == .launchSectionHeader(title: "アプリを起動", hasPrecedingWindows: true))
        #expect(rows[3].id == "app-shared-id")
        if case let .appLaunch(unifiedIndex, _) = rows[3] {
            #expect(unifiedIndex == 2)
        } else {
            Issue.record("4番目の行が appLaunch ではありません")
        }

        // 全行の ID に重複がないこと
        let uniqueIDs = Set(rows.map(\.id))
        #expect(uniqueIDs.count == rows.count)

        // 各選択インデックスの scrollTargetID が対応する行の id と一致すること
        #expect(
            SwitcherListRow.scrollTargetID(
                for: 0,
                windowResults: windows,
                appResults: apps,
                isShowingLaunchCandidates: true
            ) == rows[0].id
        )
        #expect(
            SwitcherListRow.scrollTargetID(
                for: 1,
                windowResults: windows,
                appResults: apps,
                isShowingLaunchCandidates: true
            ) == rows[1].id
        )
        #expect(
            SwitcherListRow.scrollTargetID(
                for: 2,
                windowResults: windows,
                appResults: apps,
                isShowingLaunchCandidates: true
            ) == rows[3].id
        )
    }

    /// ウィンドウ 0 件時のアプリ起動セクション構築と範囲外・非表示フラグ時の scrollTargetID ガードを検証する
    @Test("ウィンドウ0件時の見出しフラグと境界外インデックスのnil返却が正しく動作する")
    func handlesEmptyWindowsAndOutOfBoundsIndices() {
        let apps = [
            AppSearchResult(
                app: LaunchableApp(
                    id: "app-notes",
                    displayName: "メモ",
                    bundleURL: URL(fileURLWithPath: "/System/Applications/Notes.app")
                )
            )
        ]

        // ウィンドウ 0 件時は hasPrecedingWindows が false になる
        let appOnlyRows = SwitcherListRow.buildRows(
            windowResults: [],
            appResults: apps,
            isShowingLaunchCandidates: true,
            launchSectionHeaderTitle: "一致するウィンドウがないため、アプリを起動"
        )
        #expect(appOnlyRows.count == 2)
        #expect(
            appOnlyRows[0] == .launchSectionHeader(
                title: "一致するウィンドウがないため、アプリを起動",
                hasPrecedingWindows: false
            )
        )
        #expect(
            SwitcherListRow.scrollTargetID(
                for: 0,
                windowResults: [],
                appResults: apps,
                isShowingLaunchCandidates: true
            ) == appOnlyRows[1].id
        )

        // 範囲外インデックスやアプリ起動候補非表示時は nil を返すこと
        #expect(
            SwitcherListRow.scrollTargetID(
                for: -1,
                windowResults: [],
                appResults: apps,
                isShowingLaunchCandidates: true
            ) == nil
        )
        #expect(
            SwitcherListRow.scrollTargetID(
                for: 1,
                windowResults: [],
                appResults: apps,
                isShowingLaunchCandidates: true
            ) == nil
        )
        #expect(
            SwitcherListRow.scrollTargetID(
                for: 0,
                windowResults: [],
                appResults: apps,
                isShowingLaunchCandidates: false
            ) == nil
        )
    }
}
