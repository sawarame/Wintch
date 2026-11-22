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

    /// グルーピング表示時に全アプリへ見出し行が挿入され、ウィンドウ行・アプリ起動行の統一インデックスおよび scrollTargetID が破綻しないことを検証する
    @Test("グルーピング表示時にアプリ見出し行が挿入され全行 ID が一意かつ統一インデックスが連続する")
    func buildRowsWithWindowGroupsInsertsHeadersAndPreservesUnifiedIndices() {
        let windows = [
            WindowSearchResult(
                entry: WindowEntry(id: "s-1", pid: 10, bundleIdentifier: "com.apple.Safari", applicationName: "Safari", windowTitle: "Tab 1")
            ),
            WindowSearchResult(
                entry: WindowEntry(id: "s-2", pid: 10, bundleIdentifier: "com.apple.Safari", applicationName: "Safari", windowTitle: "Tab 2")
            ),
            WindowSearchResult(
                entry: WindowEntry(id: "f-1", pid: 20, bundleIdentifier: "com.apple.finder", applicationName: "Finder", windowTitle: "Desktop")
            )
        ]
        let groups = WindowAppGrouping.group(windows)
        let flattened = WindowAppGrouping.flatten(groups)
        let apps = [
            AppSearchResult(
                app: LaunchableApp(
                    id: "app-xcode",
                    displayName: "Xcode",
                    bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app")
                )
            )
        ]

        let rows = SwitcherListRow.buildRows(
            windowResults: flattened,
            windowGroups: groups,
            appResults: apps,
            isShowingLaunchCandidates: true,
            launchSectionHeaderTitle: "アプリを起動"
        )

        // 見出し 2 行 + ウィンドウ 3 行 + アプリ起動見出し 1 行 + アプリ起動 1 行 = 7 行
        #expect(rows.count == 7)
        #expect(Set(rows.map(\.id)).count == rows.count)

        if case let .appGroupHeader(groupID, appName, _, _, isFirstGroup) = rows[0] {
            #expect(groupID == "bundle:com.apple.Safari")
            #expect(appName == "Safari")
            #expect(isFirstGroup == true)
        } else {
            Issue.record("先頭行が appGroupHeader ではありません")
        }

        if case let .window(index, result) = rows[1] {
            #expect(index == 0)
            #expect(result.id == "s-1")
        } else {
            Issue.record("2 行目が window(0) ではありません")
        }

        if case let .window(index, result) = rows[2] {
            #expect(index == 1)
            #expect(result.id == "s-2")
        } else {
            Issue.record("3 行目が window(1) ではありません")
        }

        if case let .appGroupHeader(groupID, appName, _, _, isFirstGroup) = rows[3] {
            #expect(groupID == "bundle:com.apple.finder")
            #expect(appName == "Finder")
            #expect(isFirstGroup == false)
        } else {
            Issue.record("4 行目が 2 番目の appGroupHeader ではありません")
        }

        if case let .window(index, result) = rows[4] {
            #expect(index == 2)
            #expect(result.id == "f-1")
        } else {
            Issue.record("5 行目が window(2) ではありません")
        }

        #expect(rows[5] == .launchSectionHeader(title: "アプリを起動", hasPrecedingWindows: true))
        if case let .appLaunch(unifiedIndex, _) = rows[6] {
            #expect(unifiedIndex == 3)
        } else {
            Issue.record("7 行目が appLaunch(3) ではありません")
        }

        #expect(
            SwitcherListRow.scrollTargetID(
                for: 2,
                windowResults: flattened,
                appResults: apps,
                isShowingLaunchCandidates: true
            ) == rows[4].id
        )
        #expect(
            SwitcherListRow.scrollTargetID(
                for: 3,
                windowResults: flattened,
                appResults: apps,
                isShowingLaunchCandidates: true
            ) == rows[6].id
        )
    }
}
