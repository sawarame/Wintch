# サービスおよび ViewModel 契約 (Contracts): スイッチャーおよび検索ランチャーからの選択中ウィンドウ終了

**Feature**: `005-close-selected-window`  
**Date**: 2026-11-15  
**Purpose**: `HotKeyMonitoring`、`WindowServicing`、`SwitcherViewModel`、および `SwitcherPanel` 間のインターフェース契約と不変条件を定義する。

---

## 1. `HotKeyMonitoring` / `HotKeyMonitorService` 契約

### 1.1 `HotKeyEvent` 拡張

```swift
public enum HotKeyEvent: Equatable, Sendable {
    case triggerPressed(isShiftPressed: Bool)
    case launcherTriggerPressed
    case modifierReleased
    case escapePressed
    case arrowPressed(direction: ArrowDirection)
    case closeSelectedWindowPressed
}
```

### 1.2 `HotKeyMonitorService.resolveKeyDown(...)` 判定契約

- `Q` キー判定定数: 仮想キーコード `12`（ANSI `Q`）かつ `modifiers.subtracting(.shift) == shortcut.modifiers`。
- モード別優先順位（上から順に評価し、最初に一致した分岐を返す）:

1. **`.inactive`**:
   - 既存と変更なし（`isNormalMatch` → `isLauncherMatch` → 非消費通過）。
2. **`.normal`**:
   - `Esc (53)` / `↑ (126)` / `↓ (125)` → 各対応イベント通知・消費
   - `isNormalMatch` → `.triggerPressed(isShiftPressed:)` 通知・消費
   - `isLauncherMatch` → イベント通知なし（無視）・消費
   - **`isCloseWindowMatch`** → **`.closeSelectedWindowPressed` 通知・消費（`shouldConsume: true`）**
   - その他 → 非消費通過
3. **`.launcher`**:
   - `isLauncherMatch` → `.launcherTriggerPressed` 通知・消費
   - `isNormalMatch` → `.triggerPressed(isShiftPressed:)` 通知・消費
   - **`isCloseWindowMatch`** → **`.closeSelectedWindowPressed` 通知・消費（`shouldConsume: true`）**
   - その他（単体 `Q`、`Shift + Q`、`Esc`、矢印、文字入力、IME 操作等）→ 非消費通過（`shouldConsume: false`）

- **不変条件**:
  - 単体 `Q`（`modifiers == []`）および `Shift + Q`（`modifiers == [.shift]`）は `shortcut.modifiers` に必ず必須修飾キーが含まれるため、`isCloseWindowMatch` に一致しない。
  - `isCloseWindowMatch` が成立した場合、`shouldConsume` は必ず `true` であり、背面アプリおよび検索欄への文字・`Command + Q` 伝播を遮断する。

---

## 2. `WindowServicing` / `WindowService` 契約

### 2.1 プロトコルメソッド追加

```swift
@MainActor
public protocol WindowServicing: AnyObject {
    // 既存メソッド（省略なし）
    func startObserving()
    func stopObserving()
    func fetchRawWindowCandidates() -> [RawWindowCandidate]
    func activateWindow(_ entry: WindowEntry)

    /// 指定されたウィンドウ1枚のみを閉じる操作を実行し、実際にウィンドウが閉じられたかを返す
    /// - Parameter entry: クローズ対象のウィンドウ項目
    /// - Returns: ウィンドウの消滅を確認できた場合は true、未対応や未保存確認ダイアログ等で開いたまま残った場合は false
    func closeWindow(_ entry: WindowEntry) async -> Bool
}
```

### 2.2 実装仕様契約（`WindowService`）

1. **対象 `AXUIElement` の解決**:
   - `cachedWindowsByPID[entry.pid]` から `entry.id` で検索する。
   - 見つからない場合（`cg-*` 補完候補等）は `refreshAXWindows(for: entry.pid, markFrontmostAsActive: false)` を実行後、`entry.id` または `entry.windowTitle` で照合する。
   - それでも解決できない場合は `false` を返す（クラッシュしない）。
2. **クローズ実行**:
   - `kAXCloseButtonAttribute` を取得する。存在しない場合は `false` を返す。
   - `kAXEnabledAttribute` が存在し、かつ `false` の場合はクローズ不可として `false` を返す。
   - `AXUIElementPerformAction(closeButton, kAXPressAction as CFString)` を実行する。`.success` 以外でも、対象アプリによっては非同期閉じが起きないため直ちに `false` とせず、原則 `.success` 時のみ消滅確認へ進む（エラー時は安全に `false`）。
3. **消滅確認とキャッシュ除去**:
   - 最大約 150ms の範囲で短い間隔（例: 15ms ごと）に対象ウィンドウが依然として生存しているか（`kAXRoleAttribute` 取得および該当 PID の `kAXWindowsAttribute` 残存確認）を確認する。
   - 消滅が確認できた時点で即座に `cachedWindowsByPID[entry.pid]` から該当エントリを削除し `true` を返す。
   - タイムアウト時点で依然としてウィンドウが存在する場合（未保存確認ダイアログ表示中等）はキャッシュを維持したまま `false` を返す。

---

## 3. `SwitcherViewModel` 契約

- `handleHotKeyEvent(.closeSelectedWindowPressed)` 受信時：
  - `mode == .inactive`、`isClosingWindow == true`、または `!displayedResults.indices.contains(selectedIndex)` の場合は何もしない。
  - 非同期タスクを起動して `closeSelectedWindow()` を実行する（テスト容易性のために `public func closeSelectedWindow() async` としても呼び出し可能にする）。
- `closeSelectedWindow()` の契約：
  1. `guard mode != .inactive, !isClosingWindow, displayedResults.indices.contains(selectedIndex) else { return }`
  2. `isClosingWindow = true` とし、`defer { isClosingWindow = false }` を保証する。
  3. 実行前に対象 `target = displayedResults[selectedIndex].entry` と `previousIndex = selectedIndex` を保持し、`let closed = await windowService.closeWindow(target)` を呼ぶ。
  4. `await` 復帰後に `mode == .inactive` になっていた場合（処理中のキャンセル・確定等）、または `!closed` の場合は何も変更せず終了する。
  5. `allEntries.removeAll { $0.id == target.id }` を実行する。
  6. `allEntries.isEmpty` の場合は `dismiss(reason: .cancelled)` を実行して終了する。
  7. 残余がある場合、モードに応じて `displayedResults` を再生成する：
     - `.normal`: `displayedResults = allEntries.map { WindowSearchResult(entry: $0) }`
     - `.launcher`: `displayedResults = WindowSearchEngine.search(query: searchQuery, in: allEntries)`
  8. `selectedIndex = SwitcherSelection.indexAfterRemoval(current: previousIndex, remainingCount: displayedResults.count)` を設定する。
  9. `onSearchResultsUpdated?()` を呼び出し、パネル高さの再調整を通知する。

---

## 4. `SwitcherPanel` UI 契約

- `updateAnchoredHeight(to:)` および `updateAnchoredHeightIfNeeded()` は、`.launcher` モードだけでなく `.normal` モード表示中の高さ変化（ウィンドウクローズに伴うリスト縮小）にも対応する。
- `.launcher` モード時は従来通り上端座標 `anchoredTopY` を固定して下方向へ伸縮する。
- `.normal` モード時は現在のパネル中心 Y 座標（または上端座標）を基準に `fittingSize` へリサイズし、`invalidateShadow()` によって角丸シャドウを再計算する。
