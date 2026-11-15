# Phase 1 データモデルおよび状態遷移設計: スイッチャーおよび検索ランチャーからの選択中ウィンドウ／アプリ終了

**Feature**: `005-close-selected-window`  
**Date**: 2026-11-15  
**Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/005-close-selected-window/spec.md)

## 1. エンティティと型拡張

### 1.1 `HotKeyEvent`（`Services/Protocols/HotKeyMonitoring.swift`）
- 変更なし（`.closeSelectedWindowPressed` を継続使用）。

### 1.2 `WindowServicing`（`Services/Protocols/WindowServicing.swift`）

| メソッド | 責務 | 戻り値 |
|---|---|---|
| `closeWindow(_ entry: WindowEntry) async -> Bool` | 選択中ウィンドウ 1 枚のみを閉じる（未キャッシュの別スペースウィンドウ時は対象スペースへ一時移動して `AXUIElement` を解決後クローズ） | 消滅確認できたら `true`、残存時は `false` |
| `terminateApplication(pid: Int32) async -> Bool` | ウィンドウが 1 枚のみのアプリケーション全体を通常終了する（`NSRunningApplication.terminate()`） | プロセス終了を確認できたら `true`、未終了時は `false` |

### 1.3 `SwitcherViewModel` 内部状態拡張

| プロパティ / コールバック | 型 | 役割 |
|---|---|---|
| `isClosingWindow` | `Bool` | クローズ／終了処理中の多重実行防止、および処理中の一時的な `resignedActive` による誤キャンセル抑止 |
| `presentationGeneration` | `Int` | 非同期待機中にセッションが終了・再開された場合の古い完了イベント無視用世代トークン |
| `onPanelFocusRestoreNeeded` | `((SwitcherMode) -> Void)?` | スペース移動等に伴うクローズ完了後にパネルの前面表示・キーフォーカスを回復させる通知 |

---

## 2. 状態遷移（分岐付きクローズ／アプリ終了フロー）

```text
[表示中: mode == .normal または .launcher]
   │
   ▼ HotKeyEvent.closeSelectedWindowPressed
[事前チェック]
   ├─ isClosingWindow == true ──────────────► 無視
   ├─ displayedResults が空（0件）──────────► 無視
   └─ target = displayedResults[selectedIndex].entry
         │
         ▼ sameAppWindowCount = allEntries.filter { $0.pid == target.pid }.count
         ▼ isClosingWindow = true（この間 .resignedActive キャンセルを抑止）
         │
         ├─ sameAppWindowCount <= 1 の場合:
         │     └─ await windowService.terminateApplication(pid: target.pid)
         │
         └─ sameAppWindowCount >= 2 の場合:
               └─ await windowService.closeWindow(target)
                     （※未キャッシュの別スペースなら対象スペースへ一時移動して AX 取得後クローズ）
         │
         ▼ await 復帰（defer: isClosingWindow = false）
         ├─ mode != targetMode または世代不一致 ─► 何もしない
         │
         ├─ didSucceed == false（確認ダイアログ残存・クローズ不可等）
         │     └─ 一覧・選択位置は変更せず、パネルフォーカス回復通知（必要時）を発火
         │
         └─ didSucceed == true（消滅／終了確認済み）
               ├─ singleWindow 終了なら `pid == target.pid`（＝`target.id`）を除外、
               │  複数ウィンドウクローズなら `target.id` のみ除外
               ├─ allEntries.isEmpty == true
               │     └─ dismiss(reason: .cancelled) → パネル自動終了
               └─ allEntries.isEmpty == false
                     ├─ モード別（.normal / .launcher）で displayedResults 再構築
                     ├─ selectedIndex = SwitcherSelection.indexAfterRemoval(...)
                     ├─ onSearchResultsUpdated?()
                     └─ onPanelFocusRestoreNeeded?(targetMode)
```
