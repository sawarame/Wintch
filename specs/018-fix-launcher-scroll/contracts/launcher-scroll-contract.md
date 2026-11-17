# UI 契約 (Contract): リスト型スイッチャー・検索ランチャーのスクロール追従

**Feature**: `018-fix-launcher-scroll` | **Date**: 2026-11-17

## 1. スクロール識別・追従契約（`SwitcherListView` + `SwitcherListRow`）

- **単一スクロールコンテナ契約**:
  - `SwitcherListView` の候補一覧は、最大高さ `420pt` の単一 `ScrollViewReader` + `ScrollView(.vertical, showsIndicators: true)` + `LazyVStack(spacing: 4)` で描画する。
- **識別子一致契約**:
  - `LazyVStack` 内のリスト項目はすべて `SwitcherListRow` の単一配列から `ForEach(rows)` で生成し、`ForEach` の `id`（`row.id`）と `proxy.scrollTo(targetID, anchor: .center)` に渡す `targetID` を一致させなければならない（MUST）。
  - `ForEach` の要素直下に異なる識別子で `.id(...)` を上書きしてはならない（MUST NOT）。
- **追従トリガー契約**:
  1. **選択移動時**（`onChange(of: viewModel.selectedIndex)`）: `scrollTargetID(for: newIndex)` が非 `nil` なら `withAnimation(.easeOut(duration: 0.08))` で `proxy.scrollTo(targetID, anchor: .center)` を実行する。
  2. **検索クエリ変更時**（`onChange(of: viewModel.searchQuery)`）: 手動スクロール後に `selectedIndex == 0` のまま検索語が変化した場合にも整合を保つため、現在の `selectedIndex` の対象行へ `proxy.scrollTo(targetID, anchor: .center)` を実行する（先頭行であれば上部余白ごと可視領域最上部へ確実に戻る）。
  3. **表示開始・モード切替時**（`resultListView` の `onAppear` / `onChange(of: viewModel.mode)`）: パネルが非表示から `.normal` / `.launcher` へ遷移した際、初期選択位置が可視領域に収まるよう `proxy.scrollTo(targetID, anchor: .center)` を実行する。

## 2. 既存インターフェース・動作との互換性契約

- **キーボード入力・IME 契約**: `LauncherSearchField` の `NSTextFieldDelegate`（`moveUp(_:)`, `moveDown(_:)`, `insertNewline(_:)`, `cancelOperation(_:)`, `hasMarkedText()` 時の IME 優先）は一切変更しない。
- **パネル上端固定リサイズ契約**: `SwitcherListView` の `GeometryReader` による `onContentHeightChanged` 通知および `SwitcherPanel.updateAnchoredSize` の挙動は維持する。
- **キャプチャ表示型契約**: `SwitcherCaptureGridView` には影響を与えない。
