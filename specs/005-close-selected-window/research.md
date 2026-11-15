# Phase 0 技術調査・設計判断レポート: スイッチャーおよび検索ランチャーからの選択中ウィンドウ／アプリ終了

**Feature**: `005-close-selected-window`  
**Date**: 2026-11-15  
**Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/005-close-selected-window/spec.md)

## 調査目的

`005-close-selected-window` の仕様改定（単一ウィンドウ時はアプリ通常終了、複数ウィンドウ時は該当ウィンドウのみクローズ、および別スペース未キャッシュウィンドウへの自動移動クローズ）を実現するため、技術方針を再評価・決定した。

---

## 1. 「単一ウィンドウ／複数ウィンドウ」の判定基準

### Decision
`SwitcherViewModel` が保持する絞り込み前の有効ウィンドウ一覧 `allEntries`（`WindowFilter.filterAndMap` 通過後の通常ウィンドウ集合）内の同一 `pid` 件数（`allEntries.filter { $0.pid == target.pid }.count <= 1`）によって「アプリ終了」か「単一ウィンドウクローズ」かを決定する。

### Rationale
- 生の `CGWindowListCopyWindowInfo` には、ウィンドウが 1 枚しかないアプリであってもメニューバー項目や `alpha: 0` の内部補助ウィンドウ、ツールバー片など多数の `layer == 0` 要素が含まれるため、生件数で判定すると実質 1 ウィンドウのアプリを誤って「複数あり」と判定してしまう。
- 一方、検索ランチャーで絞り込んだ後の `displayedResults` 件数で判定すると、検索に一致しなかった同一アプリの別ウィンドウがあるにもかかわらずアプリごと終了してしまう危険がある。
- `allEntries` 上の同一 `pid` 件数を基準にすることで、ユーザー視点のウィンドウ数と完全に一致し、検索絞り込み中も誤爆しない。

### Alternatives Considered
- **`WindowService` 内の生キャッシュ／CGWindow 件数で判定する案**: 内部補助ウィンドウのノイズにより誤判定しやすいため不採用。

---

## 2. 単一ウィンドウ時のアプリケーション通常終了（`NSRunningApplication.terminate()`）

### Decision
`WindowServicing` に `terminateApplication(pid: Int32) async -> Bool` を追加し、以下の手順で安全にアプリを終了する：
1. `NSRunningApplication(processIdentifier: pid)` を取得（存在しないか既に `isTerminated` ならキャッシュと `AXObserver` を掃除して `true`）。
2. `app.terminate()` を呼び出す（`forceTerminate()` は使用しない）。
3. 最大約 500ms（20ms 間隔 × 最大 25 回）で `app.isTerminated` をポーリングし、終了を確認でき次第キャッシュ（`cachedWindowsByPID[pid]`）および `AXObserver` を解除して即座に `true` を返す。
4. 確認ダイアログ表示等でタイムアウト時点でも終了していない場合はキャッシュを保ったまま `false` を返す。

### Rationale
- `NSRunningApplication.terminate()` は `Command + Q` / Dock の終了と等価の通常終了要求であり、未保存ドキュメントを持つアプリは確認アラートを出すためデータが強制破棄されない（FR-011）。
- アプリプロセス自体が終了するため、ウィンドウを閉じただけの状態と異なり、背後の隠し `CGWindow`（`selectRepresentativeCGFallbackIDs` による補完候補）が次回のスイッチャー起動時に再出現する問題を完全に解消できる（SC-002）。
- `AXUIElement` が未キャッシュの別スペース状態（`cg-*`）であっても、`pid` のみで即座に（スペース移動なしで）終了できる。

### Alternatives Considered
- **メニューバー `AXMenuBar` 経由で Quit 項目を探す案**: 言語依存・非アクティブ状態での応答不安定があるため、`NSRunningApplication.terminate()` を採用。

---

## 3. 別スペース未キャッシュウィンドウ（`cg-*`）の自動スペース移動＋クローズ

### Decision
`WindowService.closeWindow(_ entry: WindowEntry)` において、キャッシュからも通常の `refreshAXWindows` からも対象 `AXUIElement` を解決できない場合（未訪問の別スペースにある `cg-*` 候補）：
1. `NSRunningApplication(processIdentifier: entry.pid)?.activate(options: [])` で対象アプリをアクティブ化し、対象ウィンドウが存在する操作スペースへ一時的に切り替える。
2. 最大約 600ms（40ms 間隔 × 最大 15 回）`refreshAXWindows(for: entry.pid, ...)` を繰り返して `AXUIElement` を取得し、`entry.cgWindowID` または `bounds` / `title` で対象ウィンドウを照合・特定する。
3. 特定でき次第、既存の `kAXCloseButtonAttribute` + `kAXPressAction` によるクローズと消滅確認を実行する。

### Rationale
- macOS の公開 Accessibility API（`kAXWindowsAttribute`）では、一度もアクセスしていない別スペース上のウィンドウの `AXUIElement` を裏から直接取得する手段が存在しない（非公開 API の使用は憲章で禁止）。
- スペースへ切り替えて `AXUIElement` をキャッシュに載せてからクローズボタンを押すことで、憲章（非公開 API 禁止・最小権限）を守りつつ未訪問スペースの複数ウィンドウの 1 枚だけも確実に閉じられる。

### Alternatives Considered
- **非公開 CGS API で別スペースのウィンドウを操作する案**: 憲章第 5 条違反のため採用不可。

---

## 4. 一時的なスペース移動・アプリ終了中のパネルフォーカス保護と再取得

### Decision
1. `SwitcherViewModel.cancel(reason:)` にて `if reason == .resignedActive && isClosingWindow { return }` とし、クローズ／終了処理中に他アプリのスペース移動や確認ウィンドウ遷移で `SwitcherPanel.resignKey()` が発火してもパネルが誤ってキャンセル終了しないように保護する。
2. `SwitcherViewModel` に `onPanelFocusRestoreNeeded: ((SwitcherMode) -> Void)?` コールバックを追加し、`closeSelectedWindow()` の結果パネルが継続表示される場合（特に別スペースへ切り替わった後にパネルがキーフォーカスを失っていた場合）、`AppCoordinator` → `SwitcherPanel.restoreFocusIfNeeded(mode:)` 経由でパネルの前面表示・キーウィンドウ状態を再確立する。

### Rationale
- `NSRunningApplication.activate()` によるスペース移動を行うと、その瞬間に `SwitcherPanel` が `resignKey()` を受けてパネルが自動的に閉じてしまう（既存仕様では外部クリック時等に閉じる設計のため）。
- `isClosingWindow` 中の `resignedActive` を抑止し、クローズ完了後にパネルのフォーカスを戻すことで、通常スイッチャー・検索ランチャーの双方でシームレスに連続整理を継続できる（FR-004）。
- ※なお、もし終了／クローズがキャンセル（未保存確認アラート等で `false`）されてそのままパネルのフォーカスを戻すべきか、ユーザーがアラートを操作できるようにすべきかについて：確認アラートが出たアプリがアクティブ化した際も、処理タイムアウト後にパネル上の入力が続行できるか、あるいはユーザーが画面上の確認アラートをクリックした時点で（`isClosingWindow == false` になった後なので）`resignKey()` でパネルが閉じて確認アラートを操作できるため両立する！

---

## 5. `HotKeyMonitorService` と `SwitcherSelection` の継続活用

### Decision
`005` 初版で設計した `HotKeyMonitorService.resolveKeyDown`（仮想キーコード `12` + `modifiers.subtracting(.shift) == shortcut.modifiers`）、`SwitcherSelection.indexAfterRemoval`、および `SwitcherPanel` の高さ追従制御はそのまま維持・活用する。
