import Testing
@testable import WintchCore

/// SwitcherSelection の初期選択位置と前後循環移動ロジックを検証するテストスイート
@Suite("SwitcherSelection テスト")
struct SwitcherSelectionTests {
    /// ウィンドウ数および起動モード方針ごとの初期選択インデックスを検証する
    @Test("初期選択インデックスが件数と起動モード方針に応じて正しく計算される")
    func initialIndexCalculation() {
        // 通常スイッチャー（既定: preferSecondItem = true）は2件以上で2番目を選択
        #expect(SwitcherSelection.initialIndex(count: 0) == nil)
        #expect(SwitcherSelection.initialIndex(count: 1) == 0)
        #expect(SwitcherSelection.initialIndex(count: 2) == 1)
        #expect(SwitcherSelection.initialIndex(count: 5) == 1)
        #expect(SwitcherSelection.initialIndex(count: 2, preferSecondItem: true) == 1)

        // 検索ランチャー（preferSecondItem = false）は1件以上なら常に1番目（0）を選択
        #expect(SwitcherSelection.initialIndex(count: 0, preferSecondItem: false) == nil)
        #expect(SwitcherSelection.initialIndex(count: 1, preferSecondItem: false) == 0)
        #expect(SwitcherSelection.initialIndex(count: 2, preferSecondItem: false) == 0)
        #expect(SwitcherSelection.initialIndex(count: 5, preferSecondItem: false) == 0)
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

    /// 1件除外後のインデックス補正ロジックを検証する
    @Test("項目除外後のインデックスが範囲内に安全に補正される")
    func indexAfterRemovalCalculation() {
        // 先頭・中間を除外した場合は同じ位置を保つ
        #expect(SwitcherSelection.indexAfterRemoval(current: 0, remainingCount: 2) == 0)
        #expect(SwitcherSelection.indexAfterRemoval(current: 1, remainingCount: 2) == 1)
        // 末尾を除外して件数が減った場合は新しい末尾へ補正する
        #expect(SwitcherSelection.indexAfterRemoval(current: 2, remainingCount: 2) == 1)
        // 最後の1件を除外した（残余0件）場合や負インデックスも安全に0へ丸める
        #expect(SwitcherSelection.indexAfterRemoval(current: 0, remainingCount: 0) == 0)
        #expect(SwitcherSelection.indexAfterRemoval(current: -1, remainingCount: 3) == 0)
    }
}
