import Foundation

/// スイッチャーリスト内の選択インデックス計算を行う純粋ロジック
public enum SwitcherSelection {
    /// スイッチャー起動時の初期選択インデックスを算出する
    /// - Parameters:
    ///   - count: 有効なウィンドウの件数
    ///   - preferSecondItem: 2件以上ある場合に2番目（インデックス1）を初期選択するか（通常スイッチャーは true、ランチャーは false）
    /// - Returns: 0件なら nil、1件なら 0、2件以上かつ preferSecondItem が true なら 1、false なら 0
    public static func initialIndex(count: Int, preferSecondItem: Bool = true) -> Int? {
        guard count > 0 else { return nil }
        if count == 1 || !preferSecondItem {
            return 0
        }
        return 1
    }

    /// 次の項目へ循環移動（Wrap-Around）するインデックスを算出する
    /// - Parameters:
    ///   - current: 現在の選択インデックス
    ///   - count: リスト全体の件数
    /// - Returns: 移動後のインデックス
    public static func nextIndex(current: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (current + 1) % count
    }

    /// 前の項目へ逆順循環移動（Wrap-Around）するインデックスを算出する
    /// - Parameters:
    ///   - current: 現在の選択インデックス
    ///   - count: リスト全体の件数
    /// - Returns: 移動後のインデックス
    public static func previousIndex(current: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (current - 1 + count) % count
    }

    /// 項目を1件除外した後の選択インデックスを安全に補正する
    /// - Parameters:
    ///   - current: 除外前の選択インデックス
    ///   - remainingCount: 除外後のリスト件数
    /// - Returns: 残余が0件以下の場合は 0、それ以外は同じ位置または新しい末尾インデックス
    public static func indexAfterRemoval(current: Int, remainingCount: Int) -> Int {
        guard remainingCount > 0 else { return 0 }
        return min(max(current, 0), remainingCount - 1)
    }

    /// 項目除外前後で選択カーソルを追従させるための対象識別子
    public enum SelectionTarget: Equatable, Sendable {
        /// ウィンドウ候補項目を選択中
        case window(id: String)
        /// ランチャーのアプリ起動候補項目を選択中
        case app(id: String)
    }

    /// 任意の項目が遅延完了や外部イベントで除外された後の選択インデックスを算出する
    /// 除外前に選択していた項目が残存している場合はその項目へカーソルを追従させ、
    /// 選択中の項目自身が除外された場合は従来の同じ位置（末尾削除時は新しい末尾）へ補正する
    /// - Parameters:
    ///   - previousIndex: 除外前の選択インデックス
    ///   - previousTarget: 除外前に選択していた対象識別子（範囲外だった場合は nil）
    ///   - remainingWindowIDs: 除外・再構築後に表示されているウィンドウ ID 一覧
    ///   - remainingAppIDs: 除外・再構築後に表示されているアプリ起動候補 ID 一覧（通常モード時は空配列）
    /// - Returns: 補正後の選択インデックス
    public static func indexAfterExternalRemoval(
        previousIndex: Int,
        previousTarget: SelectionTarget?,
        remainingWindowIDs: [String],
        remainingAppIDs: [String] = []
    ) -> Int {
        switch previousTarget {
        case let .window(id):
            if let nextWindowIndex = remainingWindowIDs.firstIndex(of: id) {
                return nextWindowIndex
            }
        case let .app(id):
            if let nextAppIndex = remainingAppIDs.firstIndex(of: id) {
                return remainingWindowIDs.count + nextAppIndex
            }
        case nil:
            break
        }
        return indexAfterRemoval(
            current: previousIndex,
            remainingCount: remainingWindowIDs.count + remainingAppIDs.count
        )
    }
}
