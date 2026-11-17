# 調査レポート (Research): ランチャーおよびリスト型スイッチャーのスクロール追従不具合

**Feature**: `018-fix-launcher-scroll` | **Date**: 2026-11-17 | **Related Issue**: #25

## 1. 事象とコード上の調査

`Sources/WintchCore/Views/SwitcherListView.swift` では、すでに `ScrollViewReader` と `.onChange(of: viewModel.selectedIndex)` を用いた `proxy.scrollTo(targetID, anchor: .center)` が実装されていたにもかかわらず、実際のランチャー画面ではスクロールバーが表示されていても方向キーによる候補移動に追従しない事象が発生していた。

`SwitcherPanel`（`NSPanel` + `NSHostingView`）および `SwitcherListView` 相当の構造を用いた最小再現実験（macOS 14+ / Swift 6 / AppKit `NSScrollView` の `contentView.bounds` 計測）を実施し、各構成要素を切り分けて検証した。

## 2. 実験による根本原因の特定

| 検証ケース | `ForEach` の `id:` 指定 | 行ビューへの `.id(...)` 指定 | `proxy.scrollTo` 引数 | 実測結果（20番目移動後の `NSScrollView.contentView.bounds.origin.y`） |
|---|---|---|---|---|
| **現行実装相当** (`id: \.element` + 別 `.id`) | `\.element` (`result.id`) | `"window-\(result.id)"` | `"window-\(result.id)"` | **`0.0`（一切スクロールしない）** |
| **同上（`VStack` 変更・アニメーション無効・`fixedSize` 無効）** | `\.element` (`result.id`) | `"window-\(result.id)"` | `"window-\(result.id)"` | **`0.0`（一切スクロールしない）** |
| **修正案A（2つの `ForEach` で `.id` と一致）** | `\.element` | なし（または `result.id`） | `result.id` | **`536.0`（正常スクロール）** |
| **修正案B（単一 `Identifiable` 行モデル）** | 統一モデル `id` (`"window-..."` / `"app-..."`) | なし（または `row.id`） | `row.id` | **`564.0`（正常スクロール）** |

### 結論（根本原因）

SwiftUI（macOS `NSScrollView` バックエンド）において、`ForEach(Array(items.enumerated()), id: \.element.id)` のように **`String` 型の ID を `ForEach` が割り当てている要素の直下に、異なる `String` 値（`"window-\(result.id)"` / `"app-\(result.id)"`）の `.id(...)` モディファイアを付与すると、`ScrollViewReader` の `proxy.scrollTo(targetID)` が対象要素を解決できずスクロールが完全に無効化される**。

- `SwitcherCaptureGridView`（キャプチャ表示型）では `ForEach` の `id: \.element.id` と `.id(result.id)` と `scrollTo(result.id)` が同一文字列であったため正常に動作していた。
- 一方、`SwitcherListView` ではウィンドウ候補（`WindowSearchResult`）とアプリ起動候補（`AppSearchResult`）の ID 衝突を防ぐために `"window-"` / `"app-"` 接頭辞を後付けの `.id(...)` モディファイア側だけに付与し、`ForEach` 側の `id:` を `\.element.id` のまま残したため、ランチャー・通常リスト型の双方でスクロール追従が機能しなくなっていた。

## 3. 設計判断と代替案の比較

### 決定事項: 統一行モデル `SwitcherListRow` による単一 `ForEach` 化

- **Decision**: ウィンドウ候補行・アプリ起動セクション見出し行・アプリ起動候補行を 1 つの `Identifiable` 型 `SwitcherListRow` にまとめ、`ForEach(rows)` の `id` と `scrollTargetID(for:)` の戻り値を共通化する（行ビューに異なる ID の `.id(...)` を重ねない）。
- **Rationale**:
  1. `ForEach` が生成する識別子と `proxy.scrollTo` に渡す識別子が型・値レベルで完全に一致し、ID 不一致によるスクロール無効化の再発を構造的に防止できる。
  2. ウィンドウ候補とアプリ起動候補で同一文字列の元 ID が万が一発生しても、`"window-"` / `"app-"` 接頭辞により確実に一意性を保てる。
  3. 行配列生成とインデックス解決を `Domain/SwitcherListRow.swift` に切り出すことで、SwiftUI ビュー外からも純粋ユニットテストで検証できる。
  4. `NSHostingView` 上でラップ移動（`0 → 29`、`29 → 0`）、セクション跨ぎ連続移動（`0 → 20`）、パネル非表示後の再表示（`dismiss → reopen`）まで含め、`bounds.origin.y` が期待通り追従することを実機環境で確認済み。
- **Alternatives considered**:
  - 2つの `ForEach` のまま `id: \.offset` に変更する案: `offset`（`Int`）は異なるデータ変更時にアニメや再利用アイデンティティが不安定になりやすく、2セクションの境界や統一選択ロジックが View 内に分散するため不採用。
  - 2つの `ForEach` のまま接頭辞付きラッパーをそれぞれ作る案: 共通の `SwitcherListRow` 配列にする方が単一 `LazyVStack` の構造が明快であり、将来的な拡張やテストも容易。

## 4. 追加で考慮したエッジケース

1. **検索クエリ変更時に `selectedIndex` が `0` のまま変化しないケース**:
   - ユーザーが `selectedIndex == 0` の状態でトラックパッド／マウスホイール等によりリストを下方へ手動スクロールした後、検索欄へ文字入力してリストが再絞り込みされた場合、`selectedIndex` は `0 → 0` で変化せず `onChange(of: viewModel.selectedIndex)` のみでは先頭へ戻らない可能性がある。
   - 対策: `onChange(of: viewModel.searchQuery)` でも現在の選択先（先頭行）へスクロール位置を戻す処理を追加する。
2. **パネル再表示・モード切替時の初期選択位置保証**:
   - パネルインスタンスが再利用されるため、`onChange(of: viewModel.mode)`（非表示から `.normal` / `.launcher` へ遷移時）および `resultListView` の `.onAppear` 時にも、初期選択行（通常モードのインデックス `1` やランチャーのインデックス `0`）が見える位置へスクロールさせる。
3. **非アニメーション・アニメーションの使い分け**:
   - キーボード移動（`selectedIndex` 変化時）は既存の滑らかな視認性のため `withAnimation(.easeOut(duration: 0.08))` を維持する。
   - 初回表示（`onAppear` / `mode` 変化時）および検索リセット（`searchQuery` 変化時）は即時配置して表示のチラつきを防ぐ。
