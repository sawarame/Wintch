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

    /// 遅延完了や外部イベントで他項目が除外された場合に選択カーソルが対象項目へ追従することを検証する
    @Test("他項目除外時は選択中ウィンドウやアプリ起動候補へ追従し、選択中項目自身の除外時は同位置・新末尾へ補正する")
    func indexAfterExternalRemovalTracksSelectedItemAndFallsBackSafely() {
        // 1. 選択中ウィンドウより前の項目が除外された場合、選択中ウィンドウの新位置へ追従する
        #expect(
            SwitcherSelection.indexAfterExternalRemoval(
                previousIndex: 2,
                previousTarget: .window(id: "w3"),
                remainingWindowIDs: ["w2", "w3"]
            ) == 1
        )

        // 2. 選択中ウィンドウより後ろの項目が除外された場合も選択中ウィンドウを維持する
        #expect(
            SwitcherSelection.indexAfterExternalRemoval(
                previousIndex: 0,
                previousTarget: .window(id: "w1"),
                remainingWindowIDs: ["w1", "w2"]
            ) == 0
        )

        // 3. ランチャーでアプリ起動候補を選択中に上部のウィンドウが除外されても、同じアプリ起動候補へ追従する
        #expect(
            SwitcherSelection.indexAfterExternalRemoval(
                previousIndex: 3,
                previousTarget: .app(id: "app-beta"),
                remainingWindowIDs: ["w2"],
                remainingAppIDs: ["app-alpha", "app-beta", "app-gamma"]
            ) == 2
        )

        // 4. 選択中だったウィンドウ自身が除外された場合は同じインデックス（末尾削除時は新末尾）へ補正する
        #expect(
            SwitcherSelection.indexAfterExternalRemoval(
                previousIndex: 1,
                previousTarget: .window(id: "w2"),
                remainingWindowIDs: ["w1", "w3"]
            ) == 1
        )
        #expect(
            SwitcherSelection.indexAfterExternalRemoval(
                previousIndex: 2,
                previousTarget: .window(id: "w3"),
                remainingWindowIDs: ["w1", "w2"]
            ) == 1
        )

        // 5. 全件 0 になった場合や対象不明時も安全に 0 へ丸める
        #expect(
            SwitcherSelection.indexAfterExternalRemoval(
                previousIndex: 0,
                previousTarget: .window(id: "w1"),
                remainingWindowIDs: [],
                remainingAppIDs: []
            ) == 0
        )
        #expect(
            SwitcherSelection.indexAfterExternalRemoval(
                previousIndex: 1,
                previousTarget: nil,
                remainingWindowIDs: ["w1"]
            ) == 0
        )
    }
}
