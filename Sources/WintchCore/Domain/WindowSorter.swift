import Foundation

/// ウィンドウ項目を直近アクティブ順（MRU）およびシステム重なり順に並び替える純粋ロジック
public enum WindowSorter {
    /// ウィンドウ項目を MRU 降順でソートし、未記録項目は Z オーダー昇順で並べる
    /// - Parameter entries: ソート対象のウィンドウ項目配列
    /// - Returns: 並び替え後のウィンドウ項目配列
    public static func sortByMRU(_ entries: [WindowEntry]) -> [WindowEntry] {
        entries.sorted { lhs, rhs in
            switch (lhs.lastActivatedAt, rhs.lastActivatedAt) {
            case let (lhsDate?, rhsDate?):
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.zOrderIndex < rhs.zOrderIndex
            case (.some, .none):
                // MRU 履歴が記録されている項目を未記録より優先する
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                // 未記録同士はシステムの画面重なり順（Z オーダー）に従う
                return lhs.zOrderIndex < rhs.zOrderIndex
            }
        }
    }
}
