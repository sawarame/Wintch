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
}
