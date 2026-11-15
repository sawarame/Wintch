---

description: "スイッチャーおよび検索ランチャーからの選択中ウィンドウ終了実装のための依存関係順タスクリスト"
---

# Tasks: スイッチャーおよび検索ランチャーからの選択中ウィンドウ終了

**Input**: 設計ドキュメント `/specs/005-close-selected-window/`  
**Prerequisites**: [plan.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/005-close-selected-window/plan.md), [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/005-close-selected-window/spec.md), [research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/005-close-selected-window/research.md), [data-model.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/005-close-selected-window/data-model.md), [service-contracts.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/005-close-selected-window/contracts/service-contracts.md), [quickstart.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/005-close-selected-window/quickstart.md)

**Tests**: プロジェクト憲章（テスト可能性）に基づき、モード別キー判定（`HotKeyMonitorDecisionTests`）、選択位置補正（`SwitcherSelectionTests`）、および ViewModel 状態遷移（`SwitcherViewModelTests`）の Swift Testing ユニットテストを含みます。

**Organization**: ユーザーストーリー単位（US1, US2, US3）にフェーズを分割し、各ストーリーを独立して実装・テスト・検証可能な構成としています。すべてのコードは日本語ドキュメントコメント（概要・`@param`・`@returns`）および日本語インラインコメントを必須とします。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並列実行可能（異なるファイルで未完了タスクへの依存なし）
- **[Story]**: 所属するユーザーストーリー（`[US1]`, `[US2]`, `[US3]`）
- すべてのタスクに具体的なファイルパスを記載

---

## Phase 1: Setup（ベースライン確認）

**Purpose**: 既存実装と Swift Testing テストスイートが健全であることを確認し、安全に変更を開始する

- [X] T001 リポジトリルートで `swift test` を実行し、既存のテストスイートおよびビルドがクリーンに通るベースラインを確認する（`Package.swift` 変更なし）

---

## Phase 2: Foundational（プロトコル契約・純粋ロジック・モック基盤の整備）

**Purpose**: US1・US2・US3 のすべてで共有するサービスプロトコル拡張、除外後インデックス補正の純粋関数、およびテストモック基盤を整備する

**⚠️ CRITICAL**: このフェーズが完了するまでユーザーストーリーの実装・単体テストフェーズへ進めない

- [X] T002 [P] `HotKeyEvent` に `.closeSelectedWindowPressed` ケースを追加し、`HotKeyMonitorMode`（`.normal` / `.launcher`）の日本語ドキュメントコメントを更新する（`Sources/WintchCore/Services/Protocols/HotKeyMonitoring.swift`）
- [X] T003 [P] `WindowServicing` プロトコルに単一ウィンドウを閉じて消滅確認結果を返すメソッド `closeWindow(_ entry: WindowEntry) async -> Bool` を追加し、日本語ドキュメントコメントを記述する（`Sources/WintchCore/Services/Protocols/WindowServicing.swift`）
- [X] T004 [P] `SwitcherSelection` に 1 件除外後のインデックス補正を行う純粋関数 `indexAfterRemoval(current:remainingCount:)`（`remainingCount <= 0` の場合は `0`、それ以外は `min(max(current, 0), remainingCount - 1)`）を追加する（`Sources/WintchCore/Domain/SwitcherSelection.swift`）
- [X] T005 [P] `MockWindowService` に `closeWindow(_:)` 実装、ウィンドウ ID ごとの結果スタブ（`stubbedCloseWindowResults` / `closeWindowDefaultResult`）、および呼び出し履歴（`closedWindows`）を追加する（`Tests/WintchCoreTests/Mocks/MockServices.swift`、T003 依存）
- [X] T006 `SwitcherSelectionTests` に `indexAfterRemoval(current:remainingCount:)` の境界値テスト（先頭・中間・末尾・最後の1件・負インデックス・0件）を追加する（`Tests/WintchCoreTests/SwitcherSelectionTests.swift`、T004 依存）

**Checkpoint**: 基盤となるプロトコル・純粋ロジック・テストモックが揃い、各ユーザーストーリーの実装と単体テストに着手可能になる

---

## Phase 3: User Story 1 - 通常スイッチャーから現在選択中のウィンドウを閉じる (Priority: P1) 🎯 MVP

**Goal**: 通常スイッチャー（ホールド式）起動中に現在設定されている修飾キーを押したまま `Q`（デフォルト `Option + Q`）を押すことで、選択中のウィンドウ 1 枚のみを閉じ、パネルを開いたまま残りの候補一覧・選択位置・パネル高さを更新して連続操作や修飾キー解放確定を行えるようにする

**Independent Test**: `HotKeyMonitorDecisionTests` で `.normal` モードの `修飾キー + Q` が `.closeSelectedWindowPressed` かつ `shouldConsume == true` と判定され、`SwitcherViewModelTests` で通常スイッチャー表示中のクローズ・同インデックス/末尾補正・連続クローズ・修飾キー解放確定がすべてパスすること

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T007 [P] [US1] `HotKeyMonitorDecisionTests` に `.normal` モードで仮想キーコード `12`（`Q`）と必須修飾キー一致（`Shift` 併用許容）が `.closeSelectedWindowPressed` + `shouldConsume == true` を返すこと、および `Esc` / 矢印 / 通常移動 / ランチャーショートカットとの優先順位を検証するテストを追加する（`Tests/WintchCoreTests/HotKeyMonitorDecisionTests.swift`、T002 依存）
- [X] T008 [P] [US1] `SwitcherViewModelTests` に通常スイッチャー表示中のウィンドウクローズテスト（中間項目のクローズ後パネル維持と同インデックス選択、末尾項目クローズ後の新末尾選択、連続クローズ後に修飾キー解放で残りウィンドウへ確定切り替え、`Esc` キャンセル）を追加する（`Tests/WintchCoreTests/SwitcherViewModelTests.swift`、T005 依存）

### Implementation for User Story 1

- [X] T009 [P] [US1] `HotKeyMonitorService` に `Q` キー定数（仮想キーコード `12`）および `isCloseWindowMatch`（`keyCode == 12 && modifiers.subtracting(.shift) == shortcut.modifiers`）を追加し、`resolveKeyDown` の `.normal` 分岐（`Esc`/矢印/`isNormalMatch`/`isLauncherMatch` の後）で `.closeSelectedWindowPressed` + `shouldConsume: true` を返すよう実装する（`Sources/WintchCore/Services/HotKeyMonitorService.swift`、T002, T007 依存）
- [X] T010 [P] [US1] `WindowService` に `closeWindow(_ entry: WindowEntry) async -> Bool` を実装し、キャッシュおよび再スキャンフォールバックによる `AXUIElement` 解決、`kAXCloseButtonAttribute` / `kAXEnabledAttribute` 検証、`kAXPressAction` 実行、最大約 150ms・15ms 間隔での消滅確認ポーリング、消滅確認時のキャッシュ除去を行う（`Sources/WintchCore/Services/WindowService.swift`、T003 依存）
- [X] T011 [US1] `SwitcherViewModel` に `isClosingWindow` 再入防止フラグ、`.closeSelectedWindowPressed` ハンドリング、および `closeSelectedWindow() async`（`allEntries` からの除外、`.normal` 時の `displayedResults` 再構築、`SwitcherSelection.indexAfterRemoval` によるインデックス補正、`onSearchResultsUpdated?()` 発火）を実装する（`Sources/WintchCore/ViewModels/SwitcherViewModel.swift`、T004, T006, T008, T009, T010 依存）
- [X] T012 [US1] `SwitcherPanel` の `updateAnchoredHeight(to:)` および `updateAnchoredHeightIfNeeded()` を拡張し、`.normal` モード表示中にウィンドウクローズで候補行数が減った際もコンテンツの `fittingSize` に合わせてパネル高さとシャドウ（`invalidateShadow()`）を更新するよう実装する（`Sources/WintchCore/Views/SwitcherPanel.swift`、T011 依存）

**Checkpoint**: User Story 1 が完全に動作し、通常スイッチャーからの単一ウィンドウ連続クローズに関する単体テストがすべてパスする

---

## Phase 4: User Story 2 - 検索ランチャーから現在選択中のウィンドウを閉じる (Priority: P1)

**Goal**: 検索ランチャー（トグル式）起動中に「スイッチャー修飾キー + `Q`」（デフォルト `Option + Q`）で選択中ウィンドウ 1 枚のみを閉じつつ、単体 `Q` / `Shift + Q` の検索文字入力、検索入力欄への特殊文字混入防止、検索キーワード維持・絞り込み再計算、およびカスタム修飾キー設定への追従を実現する

**Independent Test**: `HotKeyMonitorDecisionTests` で `.launcher` モードの `修飾キー + Q` 消費（デフォルトおよびカスタム修飾キー）と単体 `Q` / `Shift + Q` 通過がパスし、`SwitcherViewModelTests` で検索語維持のまま絞り込み一覧から対象ウィンドウが除外・補正・0件案内遷移されることがパスすること

### Tests for User Story 2 ⚠️

- [X] T013 [P] [US2] `HotKeyMonitorDecisionTests` に `.launcher` モードにおけるデフォルト/カスタム修飾キー（`Control`、`Command`、複数修飾キー）+ `Q` の `.closeSelectedWindowPressed` + `shouldConsume == true` テスト、単体 `Q` / `Shift + Q` の非消費通過（`event == nil, shouldConsume == false`）テスト、およびランチャー再押下・通常移動優先テストを追加する（`Tests/WintchCoreTests/HotKeyMonitorDecisionTests.swift`、T009 依存）
- [X] T014 [P] [US2] `SwitcherViewModelTests` に検索ランチャー表示中のクローズテスト（検索キーワード維持のまま対象ウィンドウを除外、絞り込み中インデックス補正、絞り込み後 0 件時の 0 件案内維持と検索語・パネル継続、検索語消去後に閉じたウィンドウが復活しないことの確認）を追加する（`Tests/WintchCoreTests/SwitcherViewModelTests.swift`、T011 依存）

### Implementation for User Story 2

- [X] T015 [US2] `HotKeyMonitorService.resolveKeyDown` の `.launcher` 分岐で `isLauncherMatch`・`isNormalMatch` の後に `isCloseWindowMatch` を評価し、`.closeSelectedWindowPressed` + `shouldConsume: true` を返す（単体 `Q` / `Shift + Q` は消費せず通過させ、`Option + Q` 等の特殊文字入力混入を防ぐ）よう実装する（`Sources/WintchCore/Services/HotKeyMonitorService.swift`、T009, T013 依存）
- [X] T016 [US2] `SwitcherViewModel.closeSelectedWindow()` の `.launcher` 分岐にて、`allEntries` 更新後に `WindowSearchEngine.search(query: searchQuery, in: allEntries)` で絞り込み結果を再計算し、絞り込み 0 件時は `selectedIndex = 0` のまま検索語とパネルを維持する処理を実装する（`Sources/WintchCore/ViewModels/SwitcherViewModel.swift`、T011, T014 依存）

**Checkpoint**: User Story 1 と User Story 2 の双方が独立して機能し、通常スイッチャー・検索ランチャー双方でのウィンドウクローズおよび検索文字入力との非競合がテストで保証される

---

## Phase 5: User Story 3 - 閉じられないウィンドウ・確認ダイアログ・残余0件時の安全な振る舞い (Priority: P2)

**Goal**: クローズ非対応ウィンドウ、未保存確認ダイアログ表示による残存、最後の 1 件クローズによる全ウィンドウ 0 件化、検索結果 0 件状態での操作、クローズ待機中の連打・キャンセル、および `Command` 修飾キー設定時の `Command + Q` 誤終了防止などの境界ケースを安全に処理する

**Independent Test**: `HotKeyMonitorDecisionTests` で `Command + Q` の消費テストがパスし、`SwitcherViewModelTests` で `closeWindow == false` 時の維持・最後の 1 件クローズ時の自動終了・検索結果 0 件時の無操作・再入/キャンセル競合回避がすべてパスすること

### Tests for User Story 3 ⚠️

- [X] T017 [P] [US3] `HotKeyMonitorDecisionTests` に通常スイッチャーの必須修飾キーが `Command` に設定されている場合の `Command + Q` が `.normal` / `.launcher` 双方で `.closeSelectedWindowPressed` + `shouldConsume == true` となりアプリ終了へ漏れないことを検証するテストを追加する（`Tests/WintchCoreTests/HotKeyMonitorDecisionTests.swift`、T015 依存）
- [X] T018 [P] [US3] `SwitcherViewModelTests` に境界ケーステスト（`closeWindow` が `false` を返した場合の一覧・選択位置・パネル維持、最後の 1 件を閉じて `allEntries` が 0 件になった場合の `.normal` / `.launcher` 双方での自動 `dismiss`、検索結果 0 件時の `.closeSelectedWindowPressed` 無視、クローズ待機中の再入ガードと途中キャンセル時安全リターン）を追加する（`Tests/WintchCoreTests/SwitcherViewModelTests.swift`、T016 依存）

### Implementation for User Story 3

- [X] T019 [US3] `WindowService.closeWindow(_:)` において、`kAXCloseButtonAttribute` 未存在・`kAXEnabledAttribute == false`・`AXUIElementPerformAction` エラー・消滅確認タイムアウト時（未保存確認ダイアログ表示中等）のすべてのケースでクラッシュせずキャッシュ保持のまま安全に `false` を返すフォールバック処理を確認・強化する（`Sources/WintchCore/Services/WindowService.swift`、T010 依存）
- [X] T020 [US3] `SwitcherViewModel.closeSelectedWindow()` における最後の 1 件クローズ後の `allEntries.isEmpty` 自動終了（`dismiss(reason: .cancelled)`）、および `await` 復帰時の `mode == .inactive` チェックと `defer { isClosingWindow = false }` による再入・レース防止を検証・補強する（`Sources/WintchCore/ViewModels/SwitcherViewModel.swift`、T011, T018 依存）

**Checkpoint**: すべてのユーザーストーリー（US1・US2・US3）と境界条件が満たされ、安全性・信頼性を含む単体テストがすべてパスする

---

## Phase 6: Polish & Cross-Cutting Concerns（品質・規約・全体検証）

**Purpose**: プロジェクト規約および憲章への完全準拠を確認し、全体ビルド・テストと手動検証準備を完了する

- [X] T021 [P] 変更した全ソースおよびテストファイル（`HotKeyMonitoring.swift`, `WindowServicing.swift`, `SwitcherSelection.swift`, `HotKeyMonitorService.swift`, `WindowService.swift`, `SwitcherViewModel.swift`, `SwitcherPanel.swift`, `MockServices.swift`, `HotKeyMonitorDecisionTests.swift`, `SwitcherSelectionTests.swift`, `SwitcherViewModelTests.swift`）の日本語ドキュメントコメント（概要・`@param`・`@returns`）、日本語インラインコメント、および憲章遵守（画面収録権限不使用、非公開 API 不使用、MVVM+Services 境界）を点検する
- [X] T022 リポジトリルートで `swift build` および `swift test` を実行して全テストスイートのパスを確認し、`specs/005-close-selected-window/quickstart.md` に記載された自動テスト・手動検証観点との整合を最終確認する

---

## Phase 7: Revision — 単一ウィンドウアプリ終了・別スペース自動移動フォールバック・フォーカス保護

**Purpose**: 最後の1枚を閉じる際の残存CGWindowによる再出現防止、別スペース上ウィンドウへの自動 `AXUIElement` 取得・クローズ対応（案B）、および処理中のフォーカス喪失キャンセル抑止と復元を実装・検証する

- [X] T023 [P] `WindowServicing` プロトコルに `terminateApplication(pid: Int32) async -> Bool` を追加する（`Sources/WintchCore/Services/Protocols/WindowServicing.swift`）
- [X] T024 [P] `MockWindowService` に `terminateApplication(pid:)`、`terminatedPIDs`、`stubbedTerminateResults`、`terminateDefaultResult`、`terminateHandler` を追加する（`Tests/WintchCoreTests/Mocks/MockServices.swift`、T023 依存）
- [X] T025 [P] `WindowService` に `terminateApplication(pid:)`（`NSRunningApplication.terminate()` 非強制終了 + 最大約500ms終了確認 + キャッシュ/オブザーバ掃除）および `resolveCachedWindowWithSpaceFallback(_:)`（未キャッシュ `cg-*` ウィンドウに対する `app.activate()` 自動スペース移動 + `AXUIElement` 再スキャン）を実装する（`Sources/WintchCore/Services/WindowService.swift`、T023 依存）
- [X] T026 [P] `SwitcherPanel` に `restoreFocusIfNeeded(mode:)` を追加し、`AppCoordinator` で `switcherViewModel.onPanelFocusRestoreNeeded` と配線する（`Sources/WintchCore/Views/SwitcherPanel.swift`, `Sources/WintchCore/App/AppCoordinator.swift`）
- [X] T027 `SwitcherViewModel` に `allEntries` 全候補ベースの同PID残余ウィンドウ数判定（1件以下なら `terminateApplication`、2件以上なら `closeWindow`）、処理中 `isClosingWindow` 間の `.resignedActive` キャンセル抑止、および完了・失敗時の `onPanelFocusRestoreNeeded?(targetMode)` 通知を実装する（`Sources/WintchCore/ViewModels/SwitcherViewModel.swift`、T023, T025, T026 依存）
- [X] T028 `SwitcherViewModelTests` を改訂仕様に合わせて更新し、検索絞り込み中でも全候補基準でウィンドウ数判定されるテスト、同一アプリ2枚→1枚目の `closeWindow` / 2枚目の `terminateApplication` 切替テスト、クローズ待機中の `.resignedActive` 無視および完了後フォーカス復元テストを追加する（`Tests/WintchCoreTests/SwitcherViewModelTests.swift`、T024, T027 依存）
- [X] T029 リポジトリルートで `swift build` および `swift test` を再実行し、全テストスイートと全日本語コメント・憲章準拠の最終確認を完了する

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし — 即時実行可能（T001）
- **Foundational (Phase 2)**: Setup 完了後 — T002, T003, T004 は並列実行可能。T003 完了後に T005、T004 完了後に T006 を並列実行可能
- **User Story 1 (Phase 3)**: Foundational（Phase 2）完了後
  - テスト T007（T002 依存）と T008（T005 依存）を並列作成
  - 実装 T009（`HotKeyMonitorService.swift`）と T010（`WindowService.swift`）を並列実行可能
  - T011（`SwitcherViewModel.swift`）は T009, T010 完了後に実行し、その後に T012（`SwitcherPanel.swift`）を実行
- **User Story 2 (Phase 4)**: User Story 1（Phase 3）完了後
  - テスト T013・T014 を並列作成 → T015・T016 を順次／並列実装
- **User Story 3 (Phase 5)**: User Story 2（Phase 4）完了後
  - テスト T017・T018 を並列作成 → T019・T020 を並列実装
- **Polish (Phase 6)**: Phase 3〜5 完了後に T021 → T022 を実施

### User Story Dependencies

- **User Story 1 (P1)**: Foundational 完了後に着手可能。他ストーリーへの依存なし（MVP）。
- **User Story 2 (P1)**: US1 で整備した `isCloseWindowMatch`・`WindowService.closeWindow`・`SwitcherViewModel.closeSelectedWindow()` をランチャーモードの検索語維持・非競合入力に拡張するため、US1 完了後に着手する。
- **User Story 3 (P2)**: US1・US2 のクローズ経路に対する境界ケース・安全性強化（未保存確認・最後の1件・`Command+Q` 消費）を検証するため、US2 完了後に着手する。

### Parallel Opportunities

- **Phase 2**: T002 (`HotKeyMonitoring.swift`), T003 (`WindowServicing.swift`), T004 (`SwitcherSelection.swift`) はすべて別ファイルのため並列実行可能。
- **Phase 3 (US1)**:
  - テスト: T007 (`HotKeyMonitorDecisionTests.swift`) と T008 (`SwitcherViewModelTests.swift`) は並列実行可能。
  - 実装: T009 (`HotKeyMonitorService.swift`) と T010 (`WindowService.swift`) は並列実行可能。
- **Phase 4 (US2)**: T013 (`HotKeyMonitorDecisionTests.swift`) と T014 (`SwitcherViewModelTests.swift`) は並列実行可能。
- **Phase 5 (US3)**: T017 (`HotKeyMonitorDecisionTests.swift`) と T018 (`SwitcherViewModelTests.swift`)、および実装 T019 (`WindowService.swift`) と T020 (`SwitcherViewModel.swift`) はそれぞれ別ファイルのため並列実行可能。

---

## Parallel Example: User Story 1

```bash
# US1 のテスト作成を並列で開始:
Task: "T007 [US1] HotKeyMonitorDecisionTests に .normal モード修飾キー+Q 判定テストを追加"
Task: "T008 [US1] SwitcherViewModelTests に通常スイッチャー表示中のクローズ・連続操作テストを追加"

# US1 のサービス層実装を並列で実施:
Task: "T009 [US1] HotKeyMonitorService の .normal 分岐に .closeSelectedWindowPressed 判定を実装"
Task: "T010 [US1] WindowService に closeWindow(_:) async -> Bool を実装"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1（Setup）および Phase 2（Foundational）を完了する
2. Phase 3（User Story 1）を完了する（通常スイッチャーからの連続単一ウィンドウクローズ）
3. **STOP and VALIDATE**: `swift test` で US1 の全テストが通ることを確認する

### Incremental Delivery

1. Phase 1 + 2 で基盤整備
2. Phase 3（US1: 通常スイッチャー対応）→ 単体テスト検証
3. Phase 4（US2: 検索ランチャー対応・文字入力非競合）→ 単体テスト検証
4. Phase 5（US3: 未保存確認・クローズ非対応・0件終了・`Command+Q` 安全保護）→ 単体テスト検証
5. Phase 6（Polish）→ 規約点検、`swift build` / `swift test` 全パス確認、`quickstart.md` 手動確認

---

## Notes

- [P] タスクは別ファイルで依存がないため並列作業可能
- `[USx]` ラベルは各タスクと機能仕様書のユーザーストーリーとのトレーサビリティを示す
- 低レイヤー API（`CGEventTap`・`AXUIElement`）は必ず `Services/` 層に閉じ込め、`ViewModels/` や `Views/` へ漏らさないこと
- すべてのクラス・関数・メソッドに日本語ドキュメントコメントと日本語インラインコメントを記述すること
