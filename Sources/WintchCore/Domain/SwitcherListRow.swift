import Foundation

/// リスト型スイッチャーおよび検索ランチャーの単一スクロールリスト内に描画する行モデル
/// `ForEach` の要素識別子と `ScrollViewReader` のスクロール先識別子を完全に一致させるために使用する
public enum SwitcherListRow: Identifiable, Equatable, Sendable {
    /// グルーピング表示時のアプリケーション見出し行（非選択・非クリック可能）
    case appGroupHeader(
        groupID: String,
        applicationName: String,
        representativePID: Int32,
        matchedAppNameRanges: [Range<String.Index>],
        isFirstGroup: Bool
    )

    /// 切り替え対象のウィンドウ候補行
    case window(index: Int, result: WindowSearchResult)

    /// ランチャーモードにおける「アプリを起動」セクションの見出し行
    case launchSectionHeader(title: String, hasPrecedingWindows: Bool)

    /// ランチャーモードにおける新規アプリ起動候補行
    case appLaunch(unifiedIndex: Int, result: AppSearchResult)

    /// `ForEach` および `ScrollViewReader` で共通利用する一意識別子
    public var id: String {
        switch self {
        case let .appGroupHeader(groupID, _, _, _, _):
            return Self.appGroupHeaderScrollID(for: groupID)
        case let .window(_, result):
            return Self.windowScrollID(for: result.id)
        case .launchSectionHeader:
            return "app-launch-section-header"
        case let .appLaunch(_, result):
            return Self.appScrollID(for: result.id)
        }
    }

    /// アプリグループ ID からスクロール識別子を生成する
    /// - Parameter groupID: アプリグループの一意識別子
    /// - Returns: 名前空間を分離したスクロール識別子
    public static func appGroupHeaderScrollID(for groupID: String) -> String {
        "group-\(groupID)"
    }

    /// ウィンドウ検索結果 ID からスクロール識別子を生成する
    /// - Parameter windowID: ウィンドウ検索結果の一意識別子
    /// - Returns: 名前空間を分離したスクロール識別子
    public static func windowScrollID(for windowID: String) -> String {
        "window-\(windowID)"
    }

    /// アプリ検索結果 ID からスクロール識別子を生成する
    /// - Parameter appID: アプリ検索結果の一意識別子
    /// - Returns: 名前空間を分離したスクロール識別子
    public static func appScrollID(for appID: String) -> String {
        "app-\(appID)"
    }

    /// ウィンドウ候補とアプリ起動候補からリスト表示用の統一配列を構築する
    /// - Parameters:
    ///   - windowResults: 表示対象のウィンドウ検索結果一覧
    ///   - windowGroups: アプリグルーピング表示時のグループ一覧（nil の場合はフラット表示）
    ///   - appResults: 表示対象のアプリ起動候補一覧
    ///   - isShowingLaunchCandidates: アプリ起動候補セクションを表示するかどうか
    ///   - launchSectionHeaderTitle: アプリ起動候補セクションに表示する見出し文言
    /// - Returns: 表示順に並んだ `SwitcherListRow` 配列
    public static func buildRows(
        windowResults: [WindowSearchResult],
        windowGroups: [WindowAppGroup]? = nil,
        appResults: [AppSearchResult],
        isShowingLaunchCandidates: Bool,
        launchSectionHeaderTitle: String
    ) -> [SwitcherListRow] {
        var rows: [SwitcherListRow] = []
        let includeLaunchSection = isShowingLaunchCandidates && !appResults.isEmpty
        let headerCount = windowGroups?.count ?? 0
        rows.reserveCapacity(windowResults.count + headerCount + (includeLaunchSection ? appResults.count + 1 : 0))

        if let windowGroups {
            for (groupIndex, group) in windowGroups.enumerated() {
                rows.append(
                    .appGroupHeader(
                        groupID: group.id,
                        applicationName: group.applicationName,
                        representativePID: group.representativePID,
                        matchedAppNameRanges: group.matchedAppNameRanges,
                        isFirstGroup: groupIndex == 0
                    )
                )
                for (offset, result) in group.results.enumerated() {
                    rows.append(.window(index: group.startIndex + offset, result: result))
                }
            }
        } else {
            for (index, result) in windowResults.enumerated() {
                rows.append(.window(index: index, result: result))
            }
        }

        if includeLaunchSection {
            rows.append(
                .launchSectionHeader(
                    title: launchSectionHeaderTitle,
                    hasPrecedingWindows: !windowResults.isEmpty
                )
            )
            for (appIndex, result) in appResults.enumerated() {
                rows.append(
                    .appLaunch(
                        unifiedIndex: windowResults.count + appIndex,
                        result: result
                    )
                )
            }
        }

        return rows
    }

    /// 統一選択インデックスに対応するスクロール先識別子を返す
    /// - Parameters:
    ///   - index: 現在の選択インデックス
    ///   - windowResults: 表示対象のウィンドウ検索結果一覧
    ///   - appResults: 表示対象のアプリ起動候補一覧
    ///   - isShowingLaunchCandidates: アプリ起動候補セクションを表示しているかどうか
    /// - Returns: 対応する行の `id`（範囲外の場合は `nil`）
    public static func scrollTargetID(
        for index: Int,
        windowResults: [WindowSearchResult],
        appResults: [AppSearchResult],
        isShowingLaunchCandidates: Bool
    ) -> String? {
        if windowResults.indices.contains(index) {
            return windowScrollID(for: windowResults[index].id)
        }
        guard isShowingLaunchCandidates else { return nil }
        let appIndex = index - windowResults.count
        guard appResults.indices.contains(appIndex) else { return nil }
        return appScrollID(for: appResults[appIndex].id)
    }
}
