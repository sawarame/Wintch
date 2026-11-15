# サービスおよび ViewModel 契約 (Contracts): スイッチャーおよび検索ランチャーからの選択中ウィンドウ／アプリ終了

**Feature**: `005-close-selected-window`  
**Date**: 2026-11-15  
**Purpose**: `HotKeyMonitoring`、`WindowServicing`、`SwitcherViewModel`、および `SwitcherPanel` 間のインターフェース契約を定義する。

---

## 1. `HotKeyMonitoring` / `HotKeyMonitorService` 契約

初版（仮想キーコード `12` + `modifiers.subtracting(.shift) == shortcut.modifiers` で `.closeSelectedWindowPressed` を `.normal` / `.launcher` 双方にて通知・消費、単体 `Q` / `Shift + Q` は通過）から変更なし。

---

## 2. `WindowServicing` / `WindowService` 契約

### 2.1 プロトコル定義

```swift
@MainActor
public protocol WindowServicing: AnyObject {
    func startObserving()
    func stopObserving()
    func fetchRawWindowCandidates() -> [RawWindowCandidate]
    func activateWindow(_ entry: WindowEntry)
    func closeWindow(_ entry: WindowEntry) async -> Bool
    func terminateApplication(pid: Int32) async -> Bool
}
```

### 2.2 `closeWindow(_ entry: WindowEntry) async -> Bool` 契約

1. **キャッシュ解決および別スペース自動移動フォールバック**:
   - `cachedWindowsByPID[entry.pid]` → `refreshAXWindows` の順で対象 `AXUIElement` を解決する。
   - いずれでも解決できない（別スペースの未訪問ウィンドウ `cg-*` 等）場合、`NSRunningApplication(processIdentifier: entry.pid)?.activate(options: [])` を実行して操作スペースを切り替え、最大約 600ms（40ms 間隔 × 15 回）`refreshAXWindows` して対象 `AXUIElement`（`entry.id` / `entry.cgWindowID` / タイトル照合）を取得する。
   - それでも解決できない場合は `false` を返す。
2. **クローズ実行と消滅確認**:
   - `kAXCloseButtonAttribute` 取得・`kAXEnabledAttribute` 確認・`kAXPressAction` 実行後、最大約 150ms（15ms 間隔 × 10 回）で消滅確認を行う。
   - 消滅確認できた場合はキャッシュから該当ウィンドウを除去し `true`、残存時は `false` を返す。

### 2.3 `terminateApplication(pid: Int32) async -> Bool` 契約

1. `NSRunningApplication(processIdentifier: pid)` を取得する。アプリが見つからない、または既に `isTerminated == true` の場合は該当 PID のキャッシュと `AXObserver` を解放して `true` を返す。
2. `app.terminate()` を呼び出す（`forceTerminate()` は使用禁止）。拒否された（`false`）場合は `false` を返す。
3. 最大約 500ms（20ms 間隔 × 25 回）で `app.isTerminated` を確認する。
4. 終了を確認できた場合は `cachedWindowsByPID.removeValue(forKey: pid)` と `unregisterObserver(for: pid)` を行って `true` を返す。確認ダイアログ表示等で未終了のままタイムアウトした場合は `false` を返す。

---

## 3. `SwitcherViewModel` 契約

- **`cancel(reason:)` の保護**:
  - `if reason == .resignedActive && isClosingWindow { return }` により、クローズ／終了処理に伴う一時的な別スペース切り替え等で発生したフォーカス喪失ではパネルを閉じない。
- **`closeSelectedWindow()` の分岐と更新契約**:
  1. 絞り込み前の有効一覧 `allEntries` から `sameAppCount = allEntries.filter { $0.pid == target.pid }.count` を算出する。
  2. `sameAppCount <= 1` なら `await windowService.terminateApplication(pid: target.pid)`、`sameAppCount >= 2` なら `await windowService.closeWindow(target)` を呼び出す。
  3. 待機後、別セッションへ遷移済み（`mode != targetMode || presentationGeneration != capturedGeneration`）なら何もせず終了する。
  4. 失敗（`false`）なら一覧を変更せず、`onPanelFocusRestoreNeeded?(targetMode)` のみ呼んで終了する。
  5. 成功（`true`）なら `allEntries` から対象を除外し、`allEntries.isEmpty` なら `dismiss(reason: .cancelled)` を呼ぶ。
  6. 残余がある場合はモード別に `displayedResults` を再構築し、`selectedIndex = SwitcherSelection.indexAfterRemoval(...)` へ更新して `onSearchResultsUpdated?()` および `onPanelFocusRestoreNeeded?(targetMode)` を呼び出す。

---

## 4. `SwitcherPanel` / `AppCoordinator` 契約

- `SwitcherPanel.restoreFocusIfNeeded(mode: SwitcherMode)` を追加し、`mode == .launcher` 時は `NSApplication.shared.activate()` + `orderFrontRegardless()` + `makeKey()`、`mode == .normal` 時は `orderFrontRegardless()` + `makeKey()` でパネルの前面表示とキーフォーカスを回復する。
- `AppCoordinator` は `switcherViewModel.onPanelFocusRestoreNeeded` を `switcherPanel?.restoreFocusIfNeeded(mode:)` に接続する。
