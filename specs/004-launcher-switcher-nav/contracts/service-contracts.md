# サービスおよび ViewModel 契約 (Contracts): 検索ランチャー表示中の通常スイッチャーショートカットによる候補移動

**Feature**: `004-launcher-switcher-nav`  
**Date**: 2026-11-14  
**Purpose**: `HotKeyMonitoring` / `HotKeyMonitorService` と `SwitcherViewModel` 間のイベント契約およびモード別の責務を定義する。

---

## 1. `HotKeyMonitoring` / `HotKeyMonitorService` 契約

既存の `HotKeyMonitoring` プロトコル（`activeMode`, `updateShortcut`, `updateLauncherShortcut`, `onEvent`）のメソッドシグネチャは変更しない。

### 1.1 `HotKeyMonitorMode` ドキュメントおよび振る舞い契約

- `.inactive`: 通常・ランチャー双方の起動ショートカットを監視・消費し、それぞれ `.triggerPressed(isShiftPressed:)` / `.launcherTriggerPressed` を配送する。
- `.normal`: `Esc`・`↑`・`↓`・通常ショートカット（順/逆）を監視・消費・配送し、必須修飾キー解放時に `.modifierReleased` を配送する。ランチャーショートカットは消費するが通知しない（無視）。
- `.launcher`:
  - ランチャーショートカットの一致（4 修飾キー完全一致）を最優先で検知し、`.launcherTriggerPressed` を配送・消費する。
  - 通常スイッチャーショートカットの一致（`Shift` を除いた修飾キーが `shortcut.modifiers` と一致、かつ `keyCode == shortcut.keyCode`）を検知し、`.triggerPressed(isShiftPressed: modifiers.contains(.shift))` を配送してイベントを消費する（検索フィールドや背面アプリへ通過させない）。
  - `flagsChanged` による `.modifierReleased` は配送しない。
  - その他の全キー入力（`Esc`, `↑`, `↓`, `Enter`, `Ctrl+N`, `Ctrl+P`, 文字入力, IME 変換操作）は消費せずキーウィンドウへ通過させる。

### 1.2 純粋判定ヘルパー契約（テスト用インターフェース）

`HotKeyMonitorService` に以下の静的純粋判定メソッドを提供する（`internal` または `public`、`WintchCore` テストから直接検証可能）：

```swift
public struct HotKeyKeyDownDecision: Equatable, Sendable {
    public let event: HotKeyEvent?
    public let shouldConsume: Bool
}

public static func resolveKeyDown(
    mode: HotKeyMonitorMode,
    keyCode: UInt16,
    modifiers: ShortcutModifiers,
    shortcut: ShortcutPreference,
    launcherShortcut: LauncherShortcutPreference
) -> HotKeyKeyDownDecision
```

- **不変条件**: `handleCGEvent` の `.keyDown` 分岐は必ず本メソッドの結果に従って `dispatchEvent` および戻り値（`nil` または `Unmanaged.passUnretained(event)`）を決定し、判定ロジックの重複を持たない。

---

## 2. `SwitcherViewModel` 契約

- `handleHotKeyEvent(.triggerPressed(isShiftPressed:))` の契約：
  - `mode == .inactive`: 権限確認・ウィンドウ取得を行い、1件以上あれば `.normal` でパネルを表示する。
  - `mode == .normal` または `mode == .launcher`: `moveSelection(isShiftPressed ? .up : .down)` を呼び出し、現在の `displayedResults` 内で選択カーソルを循環移動する。`mode`、`searchQuery`、`displayedResults` は一切変更しない。
- `handleHotKeyEvent(.modifierReleased)` の契約：
  - `mode == .normal`: `confirmSelection()` を実行する。
  - `mode == .launcher` または `.inactive`: 何もしない（パネルを閉じない）。
- `handleHotKeyEvent(.launcherTriggerPressed)` の契約：
  - `mode == .inactive`: `.launcher` でパネルを表示する。
  - `mode == .launcher`: `cancel(reason: .cancelled)` でトグル終了する。
  - `mode == .normal`: 何もしない（通常スイッチャーを維持する）。

---

## 3. UI / ビュー層契約（変更なしの確認）

- `SwitcherListView` は `viewModel.selectedIndex` の変更を `@Observable` で購読し、選択行の強調表示更新および `ScrollViewReader` によるスクロール追従を自動的に行う。
- `LauncherSearchField` は `HotKeyMonitorService` が通常ショートカットを消費するため追加のキーイベント処理を必要とせず、既存の IME 優先制御（`hasMarkedText()` チェックおよび `Enter` / `Esc` / `↑` / `↓` ハンドリング）をそのまま維持する。
