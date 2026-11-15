# Phase 1 データモデルおよび状態遷移設計: スイッチャーおよび検索ランチャーからの選択中ウィンドウ終了

**Feature**: `005-close-selected-window`  
**Date**: 2026-11-15  
**Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/005-close-selected-window/spec.md)

## 1. エンティティと型拡張

本機能は永続ストレージ（`UserDefaults`）に新しい設定キーを追加せず、インメモリのイベント型・ドメインヘルパー・状態管理プロパティの拡張のみで構成される。

### 1.1 `HotKeyEvent`（`Services/Protocols/HotKeyMonitoring.swift`）

グローバルキー監視サービスから `SwitcherViewModel` へ通知されるイベント列挙型に 1 ケースを追加する。

| ケース | 説明 | 発生モード |
|---|---|---|
| `.triggerPressed(isShiftPressed: Bool)` | 通常スイッチャー起動または候補移動（既存） | `.inactive`, `.normal`, `.launcher` |
| `.launcherTriggerPressed` | ランチャー起動またはトグル終了（既存） | `.inactive`, `.launcher` |
| `.modifierReleased` | 必須修飾キー解放による確定（既存） | `.normal` |
| `.escapePressed` | `Esc` キーによるキャンセル（既存） | `.normal` |
| `.arrowPressed(direction: ArrowDirection)` | 上下矢印キーによる移動（既存） | `.normal` |
| **`.closeSelectedWindowPressed`** | **設定中の通常スイッチャー必須修飾キー + `Q` キー押下（新規）** | **`.normal`, `.launcher`** |

### 1.2 `CloseWindowKeySpec`（判定定数・純粋ロジック）

- **トリガー仮想キーコード**: `12`（ANSI `Q` キー）
- **修飾キー判定ルール**: `modifiers.subtracting(.shift) == shortcut.modifiers`
  - 既存の `ShortcutConflictValidator` の不変条件により `shortcut.modifiers` には必ず `Command` / `Option` / `Control` のいずれか 1 つ以上が含まれ、`.shift` は含まれない。
  - よって、`[]`（単体 `Q`）や `[.shift]`（`Shift + Q`）には決して一致しない。

### 1.3 `SwitcherSelection`（`Domain/SwitcherSelection.swift`）

ウィンドウ 1 件除外後の選択インデックス補正を行う純粋関数を追加する。

| メソッド | 入力 | 出力 / ルール |
|---|---|---|
| `indexAfterRemoval(current: Int, remainingCount: Int) -> Int` | 除外前の選択インデックス `current`、除外後の候補件数 `remainingCount` | `remainingCount <= 0` の場合は `0`、それ以外は `min(max(current, 0), remainingCount - 1)` |

---

## 2. 状態遷移（State Transitions）

### 2.1 クローズ要求受信から完了までの状態遷移

```text
[表示中: mode == .normal または .launcher]
   │
   ▼ HotKeyEvent.closeSelectedWindowPressed
[事前チェック]
   ├─ isClosingWindow == true ──────────────► 無視（多重実行防止）
   ├─ displayedResults が空（0件）──────────► 無視（何もしない）
   └─ 選択対象 target = displayedResults[selectedIndex].entry
         │
         ▼ isClosingWindow = true
   [WindowServicing.closeWindow(target) 実行]
         │
         ├─ 結果: false（閉じられず存続 / 非対応 / 未保存確認ダイアログ表示）
         │     └─ isClosingWindow = false
         │     └─ リスト・選択インデックス・パネル表示は変更せず維持
         │
         └─ 結果: true（対象ウィンドウの消滅を確認）
               ├─ isClosingWindow = false
               ├─ allEntries から target.id を除外
               │
               ├─ allEntries.isEmpty == true（全通常ウィンドウが 0 件）
               │     └─ dismiss(reason: .cancelled) → パネルを閉じて .inactive へ遷移
               │
               └─ allEntries.isEmpty == false（残余ウィンドウあり）
                     ├─ mode == .normal の場合:
                     │     └─ displayedResults = allEntries.map { WindowSearchResult(entry: $0) }
                     │     └─ selectedIndex = SwitcherSelection.indexAfterRemoval(current: previousIndex, remainingCount: displayedResults.count)
                     │     └─ パネルリサイズ通知を発火（パネル維持）
                     │
                     └─ mode == .launcher の場合:
                           └─ displayedResults = WindowSearchEngine.search(query: searchQuery, in: allEntries)
                           └─ displayedResults.isEmpty == true の場合:
                           │     └─ selectedIndex = 0（0件案内表示、検索語・パネル維持）
                           └─ displayedResults.isEmpty == false の場合:
                           │     └─ selectedIndex = SwitcherSelection.indexAfterRemoval(current: previousIndex, remainingCount: displayedResults.count)
                           └─ パネルリサイズ通知を発火（パネル維持）
```

### 2.2 境界条件の検証ルール

- **クローズ処理中のパネル終了（Race Condition 対策）**:
  - `await windowService.closeWindow(target)` の待機中にユーザーが `Esc` を押した、パネル外をクリックして `resignedActive` になった、あるいは修飾キーを離して別確定が起きた場合（`mode == .inactive` になった場合）は、完了後のリスト更新や `onSearchResultsUpdated` を実行せず安全にリターンする。
- **キャッシュ同期とクローズ後確定**:
  - クローズが成功して `allEntries` から除外された後、ユーザーがそのままパネル上で別のウィンドウを選択・確定した場合は、除外されずに残っている最新の選択ウィンドウがアクティブ化される。
- **ランチャーで最後の 1 件を閉じた場合のフォーカス復元**:
  - 全ウィンドウが 0 件になり `dismiss(reason: .cancelled)` が呼ばれた場合、他にアクティブにすべき対象ウィンドウが存在しないため安全にパネルが非表示になる。
