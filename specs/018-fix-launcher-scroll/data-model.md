# データモデル設計 (Data Model): 統一リスト行およびスクロール識別モデル

**Feature**: `018-fix-launcher-scroll` | **Date**: 2026-11-17

## 1. エンティティ定義

### `SwitcherListRow` (`Sources/WintchCore/Domain/SwitcherListRow.swift`)

リスト型スイッチャーおよび検索ランチャーの単一 `ScrollView` / `LazyVStack` 内に描画される各要素を表す純粋モデル（`Identifiable`, `Equatable`, `Sendable`）。

| ケース / フィールド | 型 | 説明 | 識別子（`id: String`） |
|---|---|---|---|
| `.window(index: Int, result: WindowSearchResult)` | `Int`, `WindowSearchResult` | 切り替え対象のウィンドウ候補行 | `"window-\(result.id)"` |
| `.launchSectionHeader(title: String, hasPrecedingWindows: Bool)` | `String`, `Bool` | ウィンドウ候補の下に続く「アプリを起動」セクションの見出し（`hasPrecedingWindows == true` 時は上部に区切り線を描画） | `"app-launch-section-header"` |
| `.appLaunch(unifiedIndex: Int, result: AppSearchResult)` | `Int`, `AppSearchResult` | ランチャー用の新規アプリ起動候補行（`unifiedIndex = windowResults.count + appIndex`） | `"app-\(result.id)"` |

### 付随する純粋関数（`SwitcherListRow` 静的ヘルパーまたは `SwitcherListRowsBuilder`）

- **`buildRows(windowResults: [WindowSearchResult], appResults: [AppSearchResult], isShowingLaunchCandidates: Bool, launchSectionHeaderTitle: String) -> [SwitcherListRow]`**
  - 先頭から順に `windowResults` を `.window(index:result:)` として追加する。
  - `isShowingLaunchCandidates && !appResults.isEmpty` の場合のみ、`.launchSectionHeader(...)` と `appResults` の各要素（`.appLaunch(unifiedIndex:result:)`）を追加する。
  - 出力配列内の全要素の `id` は重複しない。
- **`scrollTargetID(for selectedIndex: Int, windowResults: [WindowSearchResult], appResults: [AppSearchResult], isShowingLaunchCandidates: Bool) -> String?`**
  - `windowResults.indices.contains(selectedIndex)` なら `"window-\(windowResults[selectedIndex].id)"` を返す。
  - そうでない場合、`isShowingLaunchCandidates` が `true` かつ `appIndex = selectedIndex - windowResults.count` が `appResults.indices` 内であれば `"app-\(appResults[appIndex].id)"` を返す。
  - いずれにも該当しない範囲外インデックス（候補 0 件時など）の場合は `nil` を返す。

## 2. 不変条件（Invariants）

1. **`ForEach` 要素 ID と `scrollTargetID` の完全一致**:
   - `SwitcherListRow` 配列内の `.window` / `.appLaunch` 要素の `id` は、対応する `selectedIndex` に対して `scrollTargetID(for:...)` が返す文字列と常に 100% 一致する。
2. **接頭辞による名前空間分離**:
   - ウィンドウ行 ID（`"window-..."`）、セクション見出し行 ID（`"app-launch-section-header"`）、アプリ起動行 ID（`"app-..."`）は互いに接頭辞で分離されており、元の `WindowEntry.id` や `LaunchableApp.id` がいかなる文字列であっても衝突しない。
3. **既存ドメインモデル無変更**:
   - `WindowSearchResult`, `AppSearchResult`, `WindowEntry`, `LaunchableApp`, `SwitcherViewModel` の公開データ構造や選択インデックス計算ロジックは変更しない。
