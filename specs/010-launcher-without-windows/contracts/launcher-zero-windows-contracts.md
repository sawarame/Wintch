# Phase 1 インターフェース契約: ウィンドウ 0 件時の検索ランチャー起動対応

**Feature**: `010-launcher-without-windows` | **Date**: 2026-11-16

## 1. ドメイン層契約 (`LauncherEmptyState`)

`Sources/WintchCore/Domain/LauncherEmptyState.swift`

- `LauncherEmptyState` は `Equatable` かつ `Sendable` な純粋値型列挙型とする。
- `LauncherEmptyState.resolve(hasOpenWindows:searchQuery:displayedWindowCount:displayedAppCount:)` は副作用を持たない純粋関数とし、以下に準拠する：
  - `displayedWindowCount > 0 || displayedAppCount > 0` の場合、必ず `nil` を返す。
  - `displayedWindowCount == 0 && displayedAppCount == 0` の場合：
    - `!hasOpenWindows` かつ `FuzzySearchMatcher.tokenize(searchQuery).isEmpty` なら `.noOpenWindows` を返す。
    - `!hasOpenWindows` かつ非空トークンなら `.noMatchingApps` を返す。
    - `hasOpenWindows` なら `.noMatchingCandidates` を返す。
- `message: String` プロパティで各状態に対応する日本語案内文言を提供する（View 側に文言分岐ロジックを重複させない）。

## 2. ViewModel 層契約 (`SwitcherViewModel`)

`Sources/WintchCore/ViewModels/SwitcherViewModel.swift`

### 2.1 起動契約 (`handleHotKeyEvent(.launcherTriggerPressed)` / `present(targetMode: .launcher)`)

- アクセシビリティ権限が `.granted` の場合、`windowService.fetchRawWindowCandidates()` のフィルタ結果が **0 件であっても**、`mode` を `.launcher` に遷移させ、`hotKeyMonitor.activeMode = .launcher` を設定し、`onPresentationChanged?(true)` および `onModePresentationChanged?(.launcher, nil)` を通知しなければならない（MUST）。
- 起動直後の状態は `allEntries == []`、`searchQuery == ""`、`displayedResults == []`、`displayedAppResults == []`、`selectedIndex == 0`、`emptyState == .noOpenWindows` とし、`scheduleInstalledAppsRefresh()` を開始して最新アプリ一覧のバックグラウンド取得を行う（MUST）。
- `targetMode == .normal` においては、フィルタ結果が 0 件のときは従来通り起動せず、`mode == .inactive` を維持しなければならない（MUST）。

### 2.2 ウィンドウ終了契約 (`closeSelectedWindow()`)

- クローズ成功後に `allEntries.isEmpty` となった場合：
  - `targetMode == .normal`: 従来通り `dismiss(reason: .cancelled)` を実行してパネルを閉じる（MUST）。
  - `targetMode == .launcher`: パネルを閉じず、`updateLauncherSearchResults(for: searchQuery)` を実行して `displayedResults`（空）・`displayedAppResults`・`selectedIndex` を再計算し、`onSearchResultsUpdated?()` および `onPanelFocusRestoreNeeded?(.launcher)` を発火する（MUST）。

### 2.3 表示支援プロパティ契約

- `hasOpenWindows`: `Bool`（`!allEntries.isEmpty`）
- `emptyState`: `LauncherEmptyState?`（`mode == .launcher` のときのみ `LauncherEmptyState.resolve(...)` を返し、それ以外は `nil`）
- `launchSectionHeaderTitle`: `String`（`hasOpenWindows && displayedResults.isEmpty` のとき `"一致するウィンドウがないため、アプリを起動"`、それ以外は `"アプリを起動"`）

## 3. View 層契約 (`SwitcherListView`)

`Sources/WintchCore/Views/SwitcherListView.swift`

- `viewModel.emptyState` が非 `nil` の場合は `emptyResultView(for: emptyState)` を表示し、`emptyState.message` を描画する。
- `viewModel.emptyState` が `nil` の場合は `resultListView` を表示する。
- `appLaunchSectionHeader` の見出しテキストは `viewModel.launchSectionHeaderTitle` を使用する。
- パネル上端アンカーおよび幅 `520pt`・角丸 `14pt` のデザイン構造は変更しない。
