---

description: "Task list for 010-launcher-without-windows"
---

# Tasks: ウィンドウ 0 件時の検索ランチャー起動対応

**Input**: Design documents from `/specs/010-launcher-without-windows/`  
**Prerequisites**: `plan.md`（必須）, `spec.md`（必須）, `research.md`, `data-model.md`, `contracts/launcher-zero-windows-contracts.md`, `quickstart.md`

**Tests**: 本機能は憲章（純粋ビジネスロジックのユニットテスト可能性）および `quickstart.md` に従い、ドメイン層・ViewModel 層のユニットテストタスクを含む。

**Organization**: 共通ドメイン型 `LauncherEmptyState` を Phase 2 で構築した上で、User Story 1（P1: MVP — ウィンドウ 0 件状態での検索ランチャー起動とアプリ起動）および User Story 2（P2: 通常スイッチャーとの役割分離・最後のウィンドウ終了維持・境界状態遷移）をそれぞれ独立テスト可能な単位で実装する。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 依存関係がなく別ファイルを扱うため並列実行可能なタスク
- **[Story]**: 対応するユーザーストーリー（`US1`, `US2`）。Setup / Foundational / Polish フェーズには付与しない
- すべてのタスクに正確なファイルパスと契約・制約条件を明記している

## Path Conventions

- ソースコード: `Sources/WintchCore/`
- ユニットテスト: `Tests/WintchCoreTests/`
- 仕様ドキュメント: `specs/`

---

## Phase 1: Setup（ベースライン確認）

**Purpose**: 既存ビルドおよび全ユニットテストのベースライン状態を確認する

- [ ] T001 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行し、`Package.swift` および `Tests/WintchCoreTests/` の現状テストベースラインが全件合格することを確認する

---

## Phase 2: Foundational（空状態ドメインモデル基盤の構築）

**Purpose**: ウィンドウ 0 件時の初期案内状態・検索結果 0 件状態を UI 非依存の純粋ロジックとして定義し、全ユーザーストーリーで共通利用できる基盤を整える

**⚠️ CRITICAL**: すべてのユーザーストーリーは `LauncherEmptyState` に依存するため、Phase 2 完了後に各ストーリーの実装・検証へ進む

- [ ] T002 `Tests/WintchCoreTests/LauncherEmptyStateTests.swift` を新規作成し、`LauncherEmptyState.resolve(hasOpenWindows:searchQuery:displayedWindowCount:displayedAppCount:)` の純粋判定規則（`displayedWindowCount > 0 || displayedAppCount > 0` なら常に `nil`、`!hasOpenWindows` かつ空文字/空白/全角スペースのみで `.noOpenWindows`、`!hasOpenWindows` かつ非空トークンで `.noMatchingApps`、`hasOpenWindows` かつ非空トークンで `.noMatchingCandidates`）および各状態の `message` 文言を検証する単体テストを先行記述する
- [ ] T003 `Sources/WintchCore/Domain/LauncherEmptyState.swift` を新規作成し、`Equatable`・`Sendable` 準拠の `LauncherEmptyState` 列挙型（`.noOpenWindows` / `.noMatchingApps` / `.noMatchingCandidates`）、`FuzzySearchMatcher.tokenize(_:)` を用いた `resolve(...)` 純粋関数、および `message: String`（`noOpenWindows`: `"開いているウィンドウがありません（アプリ名を入力して起動）"`、`noMatchingApps`: `"一致するアプリがありません"`、`noMatchingCandidates`: `"一致するウィンドウやアプリがありません"`）を日本語ドキュメントコメント・インラインコメント付きで実装する（T002 に依存）

**Checkpoint**: `LauncherEmptyStateTests` が合格し、空状態判定とメッセージ定義の基盤が利用可能になる

---

## Phase 3: User Story 1 - ウィンドウが 0 件の状態でも検索ランチャーを起動してアプリを起動する (Priority: P1) 🎯 MVP

**Goal**: 有効な通常ウィンドウが 0 件の状態でも（アクセシビリティ権限許可時）検索ランチャーを起動でき、未入力時は案内メッセージを表示しつつ、文字入力によってインストール済みアプリを検索・選択・起動・キャンセルできることを実現する

**Independent Test**: `SwitcherViewModelTests` で、通常ウィンドウ 0 件・アクセシビリティ権限許可の状態で `.launcherTriggerPressed` を送った際に `mode == .launcher`・`isPresented == true`・`emptyState == .noOpenWindows`・`selectedIndex == 0` で起動すること、文字入力で `displayedAppResults` に一致アプリが現れて `emptyState == nil` になり `confirmSelection()` でアプリ起動して閉じること、および `cancel()` で起動せず閉じることを独立して検証できる

### Tests for User Story 1

> **NOTE: 対象テストを先行追加し、期待される 0 件起動・アプリ起動挙動を検証可能にする**

- [ ] T004 [US1] `Tests/WintchCoreTests/SwitcherViewModelTests.swift` に、ウィンドウ 0 件環境における検索ランチャー起動（`mode == .launcher`、`allEntries.isEmpty`、`displayedResults.isEmpty`、`displayedAppResults.isEmpty`、`selectedIndex == 0`、`emptyState == .noOpenWindows`、`hotKeyMonitor.activeMode == .launcher`、`scheduleInstalledAppsRefresh()` 実行）、未入力空白文字維持、文字入力によるアプリ起動候補表示（`emptyState == nil`）と `confirmSelection()` / `selectAndActivate(at:)` によるアプリ起動、キャンセル（`Esc`・トグル再押下）、および権限未許可時の `onPermissionDenied` フォールバックを検証するユニットテストを追加する

### Implementation for User Story 1

- [ ] T005 [US1] `Sources/WintchCore/ViewModels/SwitcherViewModel.swift` を更新し、`present(targetMode:)` で `sorted.isEmpty && targetMode != .launcher` の場合のみ早期リターン（`.launcher` は `sorted.isEmpty` でも `selectedIndex = initial ?? 0` で起動許可し、`scheduleInstalledAppsRefresh()` と通知ハンドラを実行）するよう修正し、導出プロパティ `hasOpenWindows: Bool`、`emptyState: LauncherEmptyState?`（`mode == .launcher` 時のみ `LauncherEmptyState.resolve(...)` を返却）、および `launchSectionHeaderTitle: String`（`hasOpenWindows && displayedResults.isEmpty` なら `"一致するウィンドウがないため、アプリを起動"`、それ以外は `"アプリを起動"`）を日本語ドキュメントコメント付きで追加する（T003, T004 に依存）
- [ ] T006 [US1] `Sources/WintchCore/Views/SwitcherListView.swift` を更新し、`viewModel.emptyState` が非 `nil` の場合に `emptyResultView(for: emptyState)` で `emptyState.message` を描画するよう分岐を変更し、`appLaunchSectionHeader` の見出し文字列に `viewModel.launchSectionHeaderTitle` を適用する（T005 に依存）

**Checkpoint**: User Story 1（MVP）が完結し、ウィンドウ 0 件の環境から検索ランチャーを起動してインストール済みアプリを検索・起動できるようになる

---

## Phase 4: User Story 2 - 通常スイッチャーとの役割分離およびウィンドウ 0 件状態へのシームレスな遷移維持 (Priority: P2)

**Goal**: ウィンドウ 0 件時は通常スイッチャー（`Option + Tab`）が開かない既存仕様を維持しつつ、検索ランチャー上で最後の 1 枚のウィンドウを閉じた場合もパネルを閉じずに 0 件状態へシームレスに遷移し、検索文字列クリア・一致 0 件・安全無視操作が破綻しないことを保証する

**Independent Test**: `SwitcherViewModelTests` で、ウィンドウ 0 件時の通常スイッチャーショートカット（順・逆）でパネルが開かないこと、通常スイッチャー表示中に最後の 1 枚を閉じると従来通り閉じること、検索ランチャー表示中に最後の 1 枚を閉じるとパネルが閉じずに維持され（未入力時は `emptyState == .noOpenWindows`、検索語入力中は `displayedAppResults` 再評価）、および検索語削除・一致 0 件状態（`emptyState == .noMatchingApps`）で `Enter`・矢印キー・修飾キー + `Q` が安全に無視されることを独立して検証できる

### Tests for User Story 2

- [ ] T007 [US2] `Tests/WintchCoreTests/SwitcherViewModelTests.swift` の既存テスト `lastWindowCloseDismissesAndBoundaryStatesAreSafe` を更新し、通常モードで最後の 1 件を閉じた場合の自動終了は維持しつつ、ランチャーモードで最後の 1 件を閉じた場合はパネルが維持されて `emptyState == .noOpenWindows` へ遷移する検証へ改定するとともに、検索キーワード入力中に最後のウィンドウを閉じた場合のアプリ起動候補再評価・検索語クリアによる `.noOpenWindows` 復帰・一致 0 件（`.noMatchingApps`）時の `confirmSelection()` / `moveSelection(_:)` / `closeSelectedWindow()` 安全無視・ウィンドウ 0 件時の通常スイッチャー（順・逆）非起動を検証するテストを追加する

### Implementation for User Story 2

- [ ] T008 [US2] `Sources/WintchCore/ViewModels/SwitcherViewModel.swift` の `closeSelectedWindow()` を更新し、`if allEntries.isEmpty && targetMode == .normal` の場合のみ `dismiss(reason: .cancelled)` を実行して終了し、`targetMode == .launcher` の場合は `dismiss` せず `updateLauncherSearchResults(for: searchQuery)`・`selectedIndex` 補正・`onSearchResultsUpdated?()`・`onPanelFocusRestoreNeeded?(targetMode)` をそのまま実行してパネルとフォーカスを維持する（T005, T007 に依存）

**Checkpoint**: User Stories 1 と 2 の双方が独立して機能・テスト合格し、通常スイッチャーと検索ランチャーの境界および最後のウィンドウ終了時の遷移が一貫する

---

## Phase 5: Polish & Cross-Cutting Concerns（関連仕様整合・規約確認・最終検証）

**Purpose**: 過去仕様書との整合化（FR-009）、日本語コメント・憲章準拠レビュー、全ユニットテスト実行、および `.app` ビルド・動作確認を行う

- [ ] T009 [P] `specs/002-window-search-launcher/spec.md` の Edge Cases / Requirements における「ウィンドウ 0 件時はランチャーを起動しない」旨の記述を `010-launcher-without-windows` への参照注記付きで改定・整合化する
- [ ] T010 [P] `specs/005-close-selected-window/spec.md` における「ランチャーで最後のウィンドウを閉じたらパネルを閉じる」旨の記述を `010-launcher-without-windows` への参照注記付きで改定・整合化する
- [ ] T011 [P] `specs/006-launcher-app-launch/spec.md` の Assumptions における「有効な通常ウィンドウが 1 件以上開かれている場合にランチャーパネルを開く」旨の記述を `010-launcher-without-windows` への参照注記付きで改定・整合化する
- [ ] T012 [P] `specs/008-launcher-ux-refinement/spec.md` の Edge Cases における「ウィンドウ 0 件時はランチャーでも空パネルを表示しない」旨の記述を `010-launcher-without-windows` への参照注記付きで改定・整合化する
- [ ] T013 変更した全 Swift ファイル（`Sources/WintchCore/Domain/LauncherEmptyState.swift`, `Sources/WintchCore/ViewModels/SwitcherViewModel.swift`, `Sources/WintchCore/Views/SwitcherListView.swift`, `Tests/WintchCoreTests/LauncherEmptyStateTests.swift`, `Tests/WintchCoreTests/SwitcherViewModelTests.swift`）について、日本語ドキュメントコメント（`///`）・日本語インラインコメント・憲章遵守（外部依存ゼロ・非公開 API 禁止・画面収録権限不使用・コード重複なし）をレビュー確認する（T003, T006, T008 完了後）
- [ ] T014 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行し、全ユニットテストが 100% 合格することを確認する（T009〜T013 完了後）
- [ ] T015 `specs/010-launcher-without-windows/quickstart.md` に従い `./scripts/build-app.sh` で `.build/Wintch.app` をビルドし、エラーなくバンドルが生成されることを確認する（T014 完了後）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし — 即座に開始可能（`T001`）
- **Foundational (Phase 2)**: Phase 1 完了後 — `T002` → `T003` の順で実装（`US1`・`US2` 双方の前提）
- **User Story 1 (Phase 3)**: Phase 2 完了後 — `T004` → `T005` → `T006` の順で実装（MVP）
- **User Story 2 (Phase 4)**: Phase 3 の `T005` 完了後 — `T007` → `T008` の順で実装（`SwitcherViewModel.swift` / `SwitcherViewModelTests.swift` を共有するため `US1` 完了後の直列実行を推奨）
- **Polish (Phase 5)**: Phase 3・4 完了後 — `T009`〜`T012` は並列実行可能、その後 `T013` → `T014` → `T015`

### User Story Dependencies

- **User Story 1 (P1)**: Phase 2（`T003`）完了後に開始可能。他ストーリーへの依存なし。
- **User Story 2 (P2)**: Phase 2（`T003`）および US1 の ViewModel 変更（`T005`）完了後に実施し、`SwitcherViewModel.swift` の変更競合を回避する。

### Parallel Opportunities

- Phase 5 の既存仕様書整合更新（`T009`, `T010`, `T011`, `T012`）はそれぞれ独立したファイルを編集するため、すべて並列実行可能。

```bash
# Phase 5 の並列ドキュメント整合タスク例:
Task: "T009 [P] specs/002-window-search-launcher/spec.md の0件時記述整合"
Task: "T010 [P] specs/005-close-selected-window/spec.md の最後1枚終了時記述整合"
Task: "T011 [P] specs/006-launcher-app-launch/spec.md の起動前提整合"
Task: "T012 [P] specs/008-launcher-ux-refinement/spec.md の0件時記述整合"
```

---

## Implementation Strategy

### MVP First (Phase 1 → Phase 2 → Phase 3: US1)

1. Phase 1 でベースラインテスト合格を確認する（`T001`）。
2. Phase 2 で `LauncherEmptyState.swift` とその単体テストを実装・検証する（`T002` → `T003`）。
3. Phase 3（User Story 1）でウィンドウ 0 件時のランチャー起動・案内メッセージ・アプリ検索起動を実装しテストを通す（`T004` → `T005` → `T006`）。

### Incremental Delivery

4. Phase 4（User Story 2）で通常スイッチャーとの役割分離およびランチャー表示中の最後 1 枚ウィンドウ終了時の維持動作を実装・検証する（`T007` → `T008`）。
5. Phase 5 で関連仕様書 4 件の整合更新・コメント/憲章レビュー・全 `swift test` 合格・`.build/Wintch.app` ビルド検証を完了する（`T009`〜`T015`）。
