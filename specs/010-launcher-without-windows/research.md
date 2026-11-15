# Phase 0 調査・設計判断レポート: ウィンドウ 0 件時の検索ランチャー起動対応

**Feature**: `010-launcher-without-windows` | **Date**: 2026-11-16

## 1. 現行コードベースの制約箇所調査

現行実装を確認したところ、ウィンドウ 0 件時に検索ランチャーが起動・維持されない要因は以下の 4 箇所に集中している。

1. **`Sources/WintchCore/ViewModels/SwitcherViewModel.swift` (`present(targetMode:)`)**
   - `SwitcherSelection.initialIndex(count: sorted.count, preferSecondItem: targetMode != .launcher)` を呼び出し、戻り値が `nil`（すなわち `sorted.isEmpty`）の場合に無条件で早期リターンしている。
   - `.normal` モード（通常スイッチャー）では切り替え対象が存在しないため早期リターンが正しいが、`.launcher` モードではアプリ起動ランチャーとして起動できる必要がある。
2. **`Sources/WintchCore/ViewModels/SwitcherViewModel.swift` (`closeSelectedWindow()`)**
   - クローズ後に `if allEntries.isEmpty` となった際、モードにかかわらず `dismiss(reason: .cancelled)` を呼んでパネルを自動で閉じている。
   - 確定した要件（Q2: A）により、`.launcher` モードで最後の 1 枚を閉じた場合はパネルを閉じずに維持し、`updateLauncherSearchResults(for: searchQuery)` および `selectedIndex` 補正を実行する必要がある。`.normal` モード時のみ従来通り自動で閉じる。
3. **`Sources/WintchCore/Views/SwitcherListView.swift` (`emptyResultView` / `appLaunchSectionHeader`)**
   - 候補 0 件時の `emptyResultView` が固定文字列 `"一致するウィンドウがありません"` を表示しているため、ウィンドウ 0 件・検索語未入力の初期状態（Q1: A）や、ウィンドウ 0 件でアプリ検索結果が 0 件の状態と区別できない。
   - また、アプリ起動セクション見出し `appLaunchSectionHeader` が `displayedResults.isEmpty` だけで `"一致するウィンドウがないため、アプリを起動"` を出しており、そもそも開いているウィンドウが 0 件の環境では不自然な表現となる。
4. **`Tests/WintchCoreTests/SwitcherViewModelTests.swift`**
   - `lastWindowCloseDismissesAndBoundaryStatesAreSafe` 内のテストケース（531〜537行目）が「ランチャーモードで最後の1件を閉じるとパネル終了する」旧仕様を検証しているため、新仕様（ランチャーは開いたまま維持される）へ更新および 0 件起動・空状態遷移テストの拡充が必要。

## 2. 設計判断（Decisions & Rationale）

### 決定 1: `SwitcherSelection.initialIndex` の既存契約維持と起動ゲート分離
- **Decision**: `SwitcherSelection.initialIndex(count:preferSecondItem:)` の「`count <= 0` で `nil` を返す」純粋関数契約は変更せず、`SwitcherViewModel.present(targetMode:)` 側で「`sorted.isEmpty && targetMode != .launcher` の場合のみ起動をスキップし、`.launcher` の場合は `selectedIndex = initial ?? 0` で起動を許可する」設計とする。
- **Rationale**: `SwitcherSelection.initialIndex` は「選択可能な候補インデックスを返す」責務を持っており、0 件時に `nil` を返す仕様は既存テスト（`SwitcherSelectionTests`）とも整合している。起動可否ポリシー（通常スイッチャーは 1 件以上必須、ランチャーは 0 件でも起動可能）は `SwitcherViewModel.present(targetMode:)` の責務として分離する方が明快で、単体テストの既存契約も壊さない。
- **Alternatives considered**: `SwitcherSelection.initialIndex` に `allowEmpty: Bool` を追加し 0 件時に `0` を返す案 → 候補が存在しないにもかかわらずインデックス `0` を有効値のように返すのは誤解を招くため却下。

### 決定 2: ランチャー空状態（`LauncherEmptyState`）のドメインモデル化
- **Decision**: ランチャー表示中で表示候補（`displayedResults` と `displayedAppResults` の双方）が 0 件のときの状態を識別する値型 `LauncherEmptyState`（`.noOpenWindows` / `.noMatchingApps` / `.noMatchingCandidates`）を `Domain/` 層（または純粋判定ロジック付き）として定義し、`SwitcherViewModel` の算出プロパティ `emptyState` および `hasOpenWindows` を通じて `SwitcherListView` に提供する。
- **Rationale**: Q1: A の確定仕様により、「ウィンドウ 0 件・未入力時」と「検索語入力後の一致 0 件時（ウィンドウあり／なし）」で表示メッセージを切り替える必要がある。文言判定条件を View 内の複雑な `if/else` に置かず、`Domain/` と `ViewModel` で状態 enum として表現することで、純粋ユニットテストで全境界状態を検証できる。
- **Alternatives considered**: `SwitcherListView` 側で `viewModel.searchQuery.trimmingCharacters(...)` と `viewModel.entries` を直接比較して分岐する案 → View へのロジック漏洩とテスト困難性を招くため却下。

### 決定 3: 最後のウィンドウ終了時（`closeSelectedWindow`）のモード別分岐
- **Decision**: `closeSelectedWindow()` で `allEntries.isEmpty` となった際、`if allEntries.isEmpty && targetMode == .normal` の場合のみ `dismiss(reason: .cancelled)` を実行し、`targetMode == .launcher` の場合はそのまま `updateLauncherSearchResults(for: searchQuery)`・`selectedIndex` 補正・`onSearchResultsUpdated?()`・`onPanelFocusRestoreNeeded?(targetMode)` へ進める。
- **Rationale**: Q2: A の要件を最小変更かつバグなく満たせる。既存の `updateLauncherSearchResults(for:)` は `allEntries` が空でも `WindowSearchEngine.search` が `[]` を返し、`AppSearchEngine.search` が `excludingWindowEntries: []` として動作するためそのまま再利用でき、最後のウィンドウだったアプリ自身も検索語に一致すれば起動候補へ自然に再登場する。`SwitcherSelection.indexAfterRemoval` も `remainingCount == 0` のときに `0` を返す仕様になっているため安全に補正される。
- **Alternatives considered**: `closeSelectedWindow()` 内で 0 件になったとき専用のリセットパスを別途書く案 → 既存の `updateLauncherSearchResults` とロジック重複するため却下。

### 決定 4: ウィンドウ 0 件時のフローティングパネル表示・フォーカス・IME・上端固定の確認
- **Decision**: `SwitcherPanel.show(mode: .launcher)` および `LauncherSearchField` の既存機構をそのまま使用する。
- **Rationale**: `SwitcherPanel.show(mode: .launcher)` は `NSWorkspace.shared.frontmostApplication`（ウィンドウが 0 枚でも Finder 等が最前面アプリとなる）を `previousFrontmostApp` に保存し、`NSApplication.shared.activate()` と `makeKey()`、`anchoredTopY` 設定を行うため、ウィンドウ 0 件時でも検索入力欄への自動フォーカス・日本語 IME 入力・キャンセル時のフォーカス復元・パネル上端固定リサイズがそのまま成立する。

## 3. 憲章・既存仕様との整合確認
- **画面収録権限・非公開 API**: 一切使用しない（リスト型検索ランチャーおよび `NSWorkspace` / `Launched` 系公開 API のみ）。
- **パフォーマンス**: `present(targetMode: .launcher)` でウィンドウ 0 件時は `WindowFilter` / `WindowSorter` が空配列を O(1) で通過し、`installedAppService?.cachedInstalledApps()` のメモリキャッシュのみ利用（未入力時は検索自体スキップ）するため、100ms 以内の即時起動を維持できる。
- **既存仕様書の整合更新**: FR-009 に従い、`002-window-search-launcher`・`005-close-selected-window`・`006-launcher-app-launch`・`008-launcher-ux-refinement` の該当記述（0 件時非起動・最後 1 枚クローズ時自動終了）を `010-launcher-without-windows` への参照注記付きで整合化する。
