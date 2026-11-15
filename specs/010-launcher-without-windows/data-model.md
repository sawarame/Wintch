# Phase 1 データモデル設計: ウィンドウ 0 件時の検索ランチャー起動対応

**Feature**: `010-launcher-without-windows` | **Date**: 2026-11-16

## 1. 新規ドメイン型: `LauncherEmptyState`

検索ランチャー表示中において、ウィンドウ候補（`displayedResults`）およびアプリ起動候補（`displayedAppResults`）がいずれも 0 件である場合の UI 案内状態を表す列挙型（`Sources/WintchCore/Domain/LauncherEmptyState.swift`）。

| ケース | 発生条件 | ユーザーへの表示意図（案内メッセージ） |
|---|---|---|
| `.noOpenWindows` | `!hasOpenWindows` かつ検索キーワードが空（空白のみを含む） | 開いているウィンドウがなく、アプリ名入力で起動できることを案内（例：`開いているウィンドウがありません（アプリ名を入力して起動）`） |
| `.noMatchingApps` | `!hasOpenWindows` かつ有効な検索キーワードが入力されているが一致アプリ 0 件 | 検索キーワードに一致するアプリがないことを案内（例：`一致するアプリがありません`） |
| `.noMatchingCandidates` | `hasOpenWindows` かつ有効な検索キーワードが入力されているが一致ウィンドウ・アプリともに 0 件 | 検索キーワードに一致するウィンドウ・アプリがないことを案内（例：`一致するウィンドウやアプリがありません`） |

### 純粋判定メソッド: `LauncherEmptyState.resolve`

```text
LauncherEmptyState.resolve(
    hasOpenWindows: Bool,
    searchQuery: String,
    displayedWindowCount: Int,
    displayedAppCount: Int
) -> LauncherEmptyState?
```

- **ガード条件**: `displayedWindowCount > 0 || displayedAppCount > 0` の場合は `nil`（空状態ではない）。
- **トークン判定**: `FuzzySearchMatcher.tokenize(searchQuery).isEmpty` を用いて、空文字および空白・全角スペースのみを「未入力」と判定する。
- **分岐規則**:
  1. `!hasOpenWindows && isQueryEmpty` → `.noOpenWindows`
  2. `!hasOpenWindows && !isQueryEmpty` → `.noMatchingApps`
  3. `hasOpenWindows && !isQueryEmpty` → `.noMatchingCandidates`
  4. `hasOpenWindows && isQueryEmpty` → `displayedWindowCount > 0` のはずだが万一の防御として `.noMatchingCandidates` を返す（または `nil` にならない安全側）。

## 2. `SwitcherViewModel` 状態の拡張

既存の `SwitcherViewModel`（`@MainActor @Observable`）に以下の導出プロパティを追加する（永続化ストレージの変更なし）。

| プロパティ | 型 | 定義・役割 |
|---|---|---|
| `hasOpenWindows` | `Bool` | `!allEntries.isEmpty`。現在のセッションで保持している有効な通常ウィンドウが 1 件以上存在するかどうか。 |
| `emptyState` | `LauncherEmptyState?` | `mode == .launcher` のとき `LauncherEmptyState.resolve(...)` を返す。`mode != .launcher` の場合は常に `nil`。 |
| `launchSectionHeaderTitle` | `String` | `hasOpenWindows && displayedResults.isEmpty` なら `"一致するウィンドウがないため、アプリを起動"`、それ以外は `"アプリを起動"`。 |

## 3. 状態遷移（State Transitions）

### 3.1 起動時 (`present(targetMode:)`)

| 起動時の条件 | `targetMode == .normal` | `targetMode == .launcher` |
|---|---|---|
| 権限未許可 | `onPermissionDenied?()` を通知し非表示維持 | `onPermissionDenied?()` を通知し非表示維持 |
| 権限許可・ウィンドウ `0` 件 | **起動しない**（`mode = .inactive` 維持） | **起動する**（`allEntries = []`, `displayedResults = []`, `displayedAppResults = []`, `selectedIndex = 0`, `emptyState = .noOpenWindows`） |
| 権限許可・ウィンドウ `1` 件以上 | **起動する**（従来通り 1 件目/2 件目を初期選択） | **起動する**（`selectedIndex = 0` で 1 件目を初期選択） |

### 3.2 表示中の操作と遷移（ウィンドウ 0 件状態）

1. **未入力状態 (`emptyState == .noOpenWindows`)**:
   - `updateSearchQuery("saf")` → `displayedResults = []`, `displayedAppResults = [Safari, ...]`, `selectedIndex = 0`, `emptyState = nil`
   - `confirmSelection()` / `moveSelection(_:)` / `closeSelectedWindow()` → 候補 0 件のため安全に無視（パネル維持）
2. **アプリ起動候補表示中 (`displayedResults.isEmpty && !displayedAppResults.isEmpty`)**:
   - `moveSelection(_:)` → `displayedAppResults` の範囲で循環移動
   - `confirmSelection()` → `installedAppService?.launchApplication(...)` 実行して `dismiss(reason: .confirmed)`
   - `closeSelectedWindow()` → `displayedResults.indices.contains(selectedIndex)` が `false` のため安全に無視（パネル維持）
   - `updateSearchQuery("")` → `displayedAppResults = []`, `selectedIndex = 0`, `emptyState = .noOpenWindows`
3. **最後のウィンドウを閉じたとき (`closeSelectedWindow()`, `allEntries` が `1` → `0` 件)**:
   - `mode == .normal` → `dismiss(reason: .cancelled)` でパネルを閉じる（既存動作維持）
   - `mode == .launcher` → `dismiss` せず `updateLauncherSearchResults(for: searchQuery)` を再実行。
     - `searchQuery` が空なら `emptyState = .noOpenWindows`、`selectedIndex = 0`
     - `searchQuery` が入力中なら一致アプリ候補を再評価（閉じたばかりのアプリが検索語に一致すれば起動候補として表示）、`selectedIndex` を `0 ..< activeResultCount` へ補正し、`onSearchResultsUpdated?()` および `onPanelFocusRestoreNeeded?(.launcher)` を通知する。
