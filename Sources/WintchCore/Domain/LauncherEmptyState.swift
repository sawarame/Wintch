import Foundation

/// 検索ランチャーで表示可能な候補（ウィンドウ・アプリ起動候補）が 0 件のときに提示する空状態種別
public enum LauncherEmptyState: Equatable, Sendable {
    /// 開いている通常ウィンドウが 0 件かつ検索キーワードが未入力の初期状態
    case noOpenWindows
    /// ウィンドウ 0 件環境で検索キーワードを入力したが、一致するアプリ起動候補が見つからない状態
    case noMatchingApps
    /// ウィンドウ 1 件以上環境で検索キーワードを入力したが、一致するウィンドウもアプリも見つからない状態
    case noMatchingCandidates

    /// ユーザーへ表示する案内メッセージ文字列
    public var message: String {
        switch self {
        case .noOpenWindows:
            return "開いているウィンドウがありません（アプリ名を入力して起動）"
        case .noMatchingApps:
            return "一致するアプリがありません"
        case .noMatchingCandidates:
            return "一致するウィンドウやアプリがありません"
        }
    }

    /// ランチャーの表示状態と検索入力から空状態種別を判定する純粋関数
    /// - Parameters:
    ///   - hasOpenWindows: ランチャーが保持している有効な通常ウィンドウが 1 件以上存在するか
    ///   - searchQuery: 現在の検索入力文字列
    ///   - displayedWindowCount: 現在表示中のウィンドウ候補件数
    ///   - displayedAppCount: 現在表示中のアプリ起動候補件数
    /// - Returns: 候補が 0 件の場合は該当する `LauncherEmptyState`、1 件以上表示中なら `nil`
    public static func resolve(
        hasOpenWindows: Bool,
        searchQuery: String,
        displayedWindowCount: Int,
        displayedAppCount: Int
    ) -> LauncherEmptyState? {
        // ウィンドウ候補またはアプリ起動候補が 1 件でも表示されている場合は空状態を表示しない
        guard displayedWindowCount == 0 && displayedAppCount == 0 else {
            return nil
        }

        let isQueryEmpty = FuzzySearchMatcher.tokenize(searchQuery).isEmpty
        if !hasOpenWindows {
            // ウィンドウ 0 件環境では未入力時の起動案内と検索不一致の案内を明確に分ける
            return isQueryEmpty ? .noOpenWindows : .noMatchingApps
        }
        return .noMatchingCandidates
    }
}
