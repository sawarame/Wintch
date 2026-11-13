import Foundation

/// スイッチャーリスト内の選択インデックス計算を行う純粋ロジック
public enum SwitcherSelection {
    /// スイッチャー起動時の初期選択インデックスを算出する
    /// - Parameter count: 有効なウィンドウの件数
    /// - Returns: 0件なら nil、1件なら 0、2件以上なら 1（直前のウィンドウ）
    public static func initialIndex(count: Int) -> Int? {
        guard count > 0 else { return nil }
        return count == 1 ? 0 : 1
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
}
