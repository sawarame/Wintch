import Testing
@testable import WintchCore

/// SwitcherSelection の初期選択位置と前後循環移動ロジックを検証するテストスイート
@Suite("SwitcherSelection テスト")
struct SwitcherSelectionTests {
    /// ウィンドウ数ごとの初期選択インデックスを検証する
    @Test("初期選択インデックスが件数に応じて正しく計算される")
    func initialIndexCalculation() {
        #expect(SwitcherSelection.initialIndex(count: 0) == nil)
        #expect(SwitcherSelection.initialIndex(count: 1) == 0)
        #expect(SwitcherSelection.initialIndex(count: 2) == 1)
        #expect(SwitcherSelection.initialIndex(count: 5) == 1)
    }

    /// 次移動の循環計算（Wrap-Around）を検証する
    @Test("次移動インデックスが末尾から先頭へ循環する")
    func nextIndexWrapAround() {
        #expect(SwitcherSelection.nextIndex(current: 0, count: 3) == 1)
        #expect(SwitcherSelection.nextIndex(current: 1, count: 3) == 2)
        #expect(SwitcherSelection.nextIndex(current: 2, count: 3) == 0)
        #expect(SwitcherSelection.nextIndex(current: 0, count: 1) == 0)
    }

    /// 前移動の循環計算（Wrap-Around）を検証する
    @Test("前移動インデックスが先頭から末尾へ循環する")
    func previousIndexWrapAround() {
        #expect(SwitcherSelection.previousIndex(current: 0, count: 3) == 2)
        #expect(SwitcherSelection.previousIndex(current: 2, count: 3) == 1)
        #expect(SwitcherSelection.previousIndex(current: 1, count: 3) == 0)
        #expect(SwitcherSelection.previousIndex(current: 0, count: 1) == 0)
    }
}
