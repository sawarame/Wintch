import Foundation

/// サムネイルキャッシュ整理時の保持対象ウィンドウ ID を安全に算出する純粋ドメインポリシー
public enum WindowCaptureCachePolicy {
    /// キャッシュ整理（`pruneCache`）時に保持すべき生存 CGWindow ID 集合を安全に算出する
    ///
    /// 別スペースやフルスクリーン空間のウィンドウが一時的なフィルタ除外（タイトル未補完等）で
    /// 表示候補から一瞬漏れただけでキャッシュが誤消去されるのを防ぐため、
    /// OS 側の全生存 CGWindow ID 集合（取得可能な場合）およびフィルタ前生候補との和集合を保持対象とする。
    /// OS 側の一時的な取得失敗で空集合が返った場合は、全キャッシュ誤消去を防ぐため `nil` を返して整理を抑止する。
    ///
    /// - Parameters:
    ///   - survivingCGWindowIDs: OS（`CGWindowListCopyWindowInfo`）から取得した全生存 CGWindow ID 集合（未対応実装時は nil）
    ///   - rawCandidates: フィルタ前の生ウィンドウ候補一覧
    ///   - filteredEntries: フィルタ後の表示対象ウィンドウ一覧
    /// - Returns: 保持すべき CGWindow ID 集合（整理を見送るべき場合は nil）
    public static func cacheRetentionWindowIDs(
        survivingCGWindowIDs: Set<UInt32>?,
        rawCandidates: [RawWindowCandidate],
        filteredEntries: [WindowEntry]
    ) -> Set<UInt32>? {
        var retained = Set(rawCandidates.compactMap(\.cgWindowID))
        retained.formUnion(filteredEntries.compactMap(\.cgWindowID))

        if let survivingCGWindowIDs {
            // OS 側の生存一覧が空かつ候補も空の場合は、一時的な WindowServer 応答異常での全破棄を避ける
            if survivingCGWindowIDs.isEmpty && retained.isEmpty {
                return nil
            }
            retained.formUnion(survivingCGWindowIDs)
        }
        return retained
    }
}
