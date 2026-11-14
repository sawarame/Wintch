# データモデル・状態遷移設計 (Data Model): 検索ランチャー表示中の通常スイッチャーショートカットによる候補移動

**Feature**: `004-launcher-switcher-nav`  
**Date**: 2026-11-14  
**Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/004-launcher-switcher-nav/spec.md)

---

## 1. 関連データモデル

既存のドメインモデル（`ShortcutPreference`, `LauncherShortcutPreference`, `ShortcutModifiers`, `WindowSearchResult`）および `SwitcherMode` / `HotKeyMonitorMode` / `HotKeyEvent` の型定義は変更しない。純粋な判定結果を表す以下の値型をサービス層（単体テスト公開用）に定義する。

### 1.1 `HotKeyKeyDownDecision`（`HotKeyMonitorService` 内純粋判定結果）

`CGEventTap` の `keyDown` イベントを受信した際、設定スナップショットと現在のモードから「イベントを通知するか」「OS/アプリへのイベント伝播を遮断（消費）するか」を決定する値型。

| フィールド | 型 | 説明 |
|---|---|---|
| `event` | `HotKeyEvent?` | `MainActor` の `onEvent` ハンドラへ通知すべきイベント。通知不要（無視または素通し）の場合は `nil` |
| `shouldConsume` | `Bool` | `true` の場合は `CGEventTap` から `nil` を返してキー入力を消費する。`false` の場合はキーウィンドウへ通過させる |

---

## 2. モード別キー入力判定ルール（`HotKeyMonitorService.resolveKeyDown`）

`keyDown` 受信時の照合条件（既存と同一）：
- `isNormalMatch`: `keyCode == shortcut.keyCode && modifiers.subtracting(.shift) == shortcut.modifiers`
- `isLauncherMatch`: `keyCode == launcherShortcut.keyCode && modifiers == launcherShortcut.modifiers`
- `isShiftPressed`: `modifiers.contains(.shift)`

| `activeMode` | 入力キー条件 | `event` | `shouldConsume` | 理由 |
|---|---|---|---|---|
| `.inactive` | `isNormalMatch` | `.triggerPressed(isShiftPressed:)` | `true` | 通常スイッチャー起動 |
| `.inactive` | `isLauncherMatch` | `.launcherTriggerPressed` | `true` | 検索ランチャー起動 |
| `.inactive` | その他 | `nil` | `false` | 通常アプリ入力へ通過 |
| `.normal` | `Esc` (53) | `.escapePressed` | `true` | キャンセル |
| `.normal` | `↑` (126) / `↓` (125) | `.arrowPressed(.up / .down)` | `true` | 補助選択移動 |
| `.normal` | `isNormalMatch` | `.triggerPressed(isShiftPressed:)` | `true` | 次へ / 前へ選択移動 |
| `.normal` | `isLauncherMatch` | `nil` | `true` | 無視してモード維持（FR-008） |
| `.normal` | その他 | `nil` | `false` | 通過 |
| `.launcher` | `isLauncherMatch` | `.launcherTriggerPressed` | `true` | トグル終了（優先判定） |
| **`.launcher`** | **`isNormalMatch`** | **`.triggerPressed(isShiftPressed:)`** | **`true`** | **ランチャー内候補の「次へ / 前へ」移動（FR-001〜FR-003）** |
| `.launcher` | その他（`Esc`/`↑`/`↓`/`Enter`/`Ctrl+N`/`Ctrl+P`/文字/IME） | `nil` | `false` | キーウィンドウの検索入力欄・IME へ通過 |

### `flagsChanged` 判定ルール（変更なし）

| `activeMode` | 修飾キー状態 | 通知イベント | `shouldConsume` | 理由 |
|---|---|---|---|---|
| `.normal` | `!shortcut.modifiers.isSubset(of: currentModifiers)` | `.modifierReleased` | `false` | 修飾キー解放で選択確定 |
| `.launcher` | 任意の修飾キー変化（解放含む） | なし | `false` | トグル式のため解放で閉じない（FR-004） |

---

## 3. `SwitcherViewModel` 状態遷移表（改定箇所強調）

| イベント / 操作 | 現在の `mode` | 遷移先 `mode` | 状態変化 |
|---|---|---|---|
| `triggerPressed(isShiftPressed:)` | `.inactive` | `.normal`（権限あり & 1件以上） | `allEntries = sorted`, `displayedResults = 全件`, `selectedIndex = initialIndex` |
| `triggerPressed(isShiftPressed:)` | `.normal` | `.normal` | `displayedResults` 内で次へ / 前へ（`isShiftPressed`）循環移動 |
| **`triggerPressed(isShiftPressed:)`** | **`.launcher`** | **`.launcher`** | **`searchQuery`・`displayedResults` を維持したまま `moveSelection(isShiftPressed ? .up : .down)` を実行（0件時は変更なし）** |
| `launcherTriggerPressed` | `.inactive` | `.launcher`（権限あり & 1件以上） | `searchQuery = ""`, `displayedResults = 全件`, `selectedIndex = initialIndex` |
| `launcherTriggerPressed` | `.normal` | `.normal` | 無視（通常モード維持、FR-008） |
| `launcherTriggerPressed` | `.launcher` | `.inactive` | 切り替えせずパネル終了（トグル終了） |
| `modifierReleased` | `.normal` | `.inactive` | 選択ウィンドウをアクティブ化して終了 |
| `modifierReleased` | `.launcher` | `.launcher` | 無視（パネル開維持、FR-004） |
| `moveSelection(_:)` | `.normal` / `.launcher` | 同じモード | `displayedResults` 件数内で循環移動（0件時は何もしない） |
| `updateSearchQuery(_:)` | `.launcher` | `.launcher` | ファジー検索結果で `displayedResults` を更新し、`selectedIndex = 0` にリセット |
| `confirmSelection()` | `.normal` / `.launcher` | `.inactive`（0件時は `.launcher` 維持） | 有効インデックスなら対象ウィンドウをアクティブ化して終了 |
| `cancel(reason:)` | `.normal` / `.launcher` | `.inactive` | 切り替えせずパネル終了 |
