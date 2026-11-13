---

description: "ウィンドウ検索ランチャーモード実装のための依存関係順タスクリスト"
---

# Tasks: ウィンドウ検索ランチャーモード

**Input**: 設計ドキュメント `/specs/002-window-search-launcher/`  
**Prerequisites**: [plan.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/002-window-search-launcher/plan.md), [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/002-window-search-launcher/spec.md), [research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/002-window-search-launcher/research.md), [data-model.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/002-window-search-launcher/data-model.md), [service-contracts.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/002-window-search-launcher/contracts/service-contracts.md), [ui-contracts.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/002-window-search-launcher/contracts/ui-contracts.md)

**Tests**: プロジェクト憲章（テスト可能性）に基づき、ファジー検索・ハイライト範囲・双方向ショートカット競合検証・永続化・ViewModel 状態遷移の Swift Testing ユニットテストを含みます。

**Organization**: ユーザーストーリー単位（US1, US2, US3）にフェーズを分割し、各ストーリーが独立して実装・テスト・検証可能な構成としています。すべてのコードは日本語ドキュメントコメントおよび日本語インラインコメントを必須とします。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並列実行可能（異なるファイルで未完了タスクへの依存なし）
- **[Story]**: 所属するユーザーストーリー（`[US1]`, `[US2]`, `[US3]`）
- すべてのタスクに具体的なファイルパスを記載

---

## Phase 1: Setup（環境確認と既存テストベースライン確保）

**Purpose**: 既存の `WintchCore` / `Wintch` パッケージとテスト環境が健全な状態で新規機能追加を開始できるようにする

- [X] T001 既存のビルドおよび Swift Testing ベースラインを確認し、`TestingMacros` キャッシュ問題が出た場合のクリーン実行手順（`swift package clean && swift test`）を `Package.swift` 構成変更なしで検証する

---

## Phase 2: Foundational（全ストーリー共通の前提基盤）

**Purpose**: US1・US2・US3 が共通して依存するランチャーショートカットモデル、サービスプロトコル拡張、永続化ストア、テストモックを整備する

**⚠️ CRITICAL**: このフェーズが完了するまでユーザーストーリーフェーズへ進めない

- [X] T002 [P] 修飾キー `OptionSet`（`.command`, `.option`, `.control`, `.shift`、`hasPrimaryModifier: Bool`、`displaySymbols: [String]`）および `LauncherShortcutPreference`（`keyCode: UInt16 = 49`, `modifiers: ShortcutModifiers = [.option]`, `keyLabel: String = "Space"`, 必須条件 `modifiers.hasPrimaryModifier == true`、トリガーキー単体/修飾キー・`Esc` `53` 除外、静的 `.default` = `"⌥ + Space"`）を `Sources/WintchCore/Domain/LauncherShortcutPreference.swift` に実装する
- [X] T003 [P] 既存 `ModifierKeyOption` に `ShortcutModifiers` への変換プロパティ（`.option`, `.control`, `.command` 対応）を追加して `Sources/WintchCore/Domain/ShortcutPreference.swift` を更新する
- [X] T004 [P] `HotKeyMonitorMode`（`.inactive`, `.normal`, `.launcher`）、`HotKeyEvent.launcherTriggerPressed`、`activeMode: HotKeyMonitorMode`、`isSuspendedForRecording: Bool`、`updateLauncherShortcut(_:)` を追加して `Sources/WintchCore/Services/Protocols/HotKeyMonitoring.swift` を更新する
- [X] T005 [P] `loadLauncherShortcut() -> LauncherShortcutPreference` および `saveLauncherShortcut(_ preference: LauncherShortcutPreference)` を追加して `Sources/WintchCore/Services/Protocols/PreferencesStoring.swift` を更新する
- [X] T006 独立キー `"dev.wintch.launcherShortcutPreference"` による JSON 永続化（未保存・デコード失敗時は `LauncherShortcutPreference.default` を返却）を `Sources/WintchCore/Services/PreferencesStore.swift` に実装する（T002, T005 依存）
- [X] T007 テスト用モック（`MockHotKeyMonitor` の `activeMode` / `isSuspendedForRecording` / `updatedLauncherShortcuts`、`MockPreferencesStore` の `storedLauncherShortcut`）を `Tests/WintchCoreTests/Mocks/MockServices.swift` に更新する（T002, T004, T005 依存）

**Checkpoint**: 共通ドメインモデル・サービス契約・永続化・モックが揃い、各ユーザーストーリーの実装・テストが可能になる

---

## Phase 3: User Story 1 - ランチャー検索によるウィンドウの絞り込みと切り替え (Priority: P1) 🎯 MVP

**Goal**: デフォルトショートカット（`Option + Space`）によるトグル起動、未入力時の MRU 表示（初期選択 2 番目、1 件時は 1 番目）、スペース区切り AND ファジー検索（タイトル空は `""` 扱い）、スコア順（同点は MRU 順）並び替え、一致文字の太字ハイライト、`↑`/`↓`・`Ctrl+N`/`Ctrl+P` 選択移動、`Enter`/クリック確定、`Esc`/ショートカット再押下/外部クリックでのキャンセル、日本語 IME 変換優先、モード排他制御を提供する

**Independent Test**: 複数アプリ・複数ウィンドウを開いた状態で `Option + Space` によりトグル起動〜ファジー検索〜ハイライト〜`Enter` 切り替え〜`Esc` キャンセルおよび日本語 IME 変換操作が動作し、`WindowSearchEngineTests` と `SwitcherViewModelTests` がすべてパスすること

### Tests for User Story 1 ⚠️

> **NOTE**: 純粋検索ロジックおよび ViewModel 状態遷移のテストを先に記述し、実装前に失敗することを確認する

- [X] T008 [P] [US1] スペース区切り AND ファジー検索、大文字小文字・発音区別符号非区別、`windowTitle` 空文字時は `"(タイトルなし)"` に一致させない制約、一致スコア降順・同点時 MRU インデックス昇順、および `matchedAppNameRanges` / `matchedTitleRanges` 検証テストを `Tests/WintchCoreTests/WindowSearchEngineTests.swift` に作成する
- [X] T009 [P] [US1] `SwitcherViewModel` のランチャー状態遷移テスト（`.inactive` ⇄ `.launcher` トグル起動/終了、初期選択 2 番目→検索文字入力後 0 番目自動移動、`modifierReleased` 無視、`confirmSelection` / `cancel`、`.normal` 表示中の `launcherTriggerPressed` 無視および `.launcher` 表示中の `triggerPressed` 無視）を `Tests/WintchCoreTests/SwitcherViewModelTests.swift` に追加する

### Implementation for User Story 1

- [X] T010 [P] [US1] `WindowSearchResult`（`entry: WindowEntry`, `score: Int`, `matchedAppNameRanges: [Range<String.Index>]`, `matchedTitleRanges: [Range<String.Index>]`, `id` は `entry.id` 委譲）を `Sources/WintchCore/Domain/WindowSearchResult.swift` に実装する
- [X] T011 [US1] 純粋ファジー検索エンジン `WindowSearchEngine`（空クエリ時 MRU 順返却、スペース区切り AND トークン走査、先頭/連続/単語境界/アプリ名重みスコアリング、ハイライト用 `Range<String.Index>` 結合・ソート）を `Sources/WintchCore/Domain/WindowSearchEngine.swift` に実装する（T010 依存）
- [X] T012 [US1] `HotKeyMonitorService` の `TapState` に `activeMode: HotKeyMonitorMode`, `launcherShortcut: LauncherShortcutPreference`, `isSuspendedForRecording: Bool` を追加し、モード別の消費・通過制御（`.inactive` で双方検知、`.normal` でランチャー無視、`.launcher` でランチャー再押下のみ消費し `Esc`/`↑`/`↓`/文字キー/IME 入力をすべてキーウィンドウへ通過、4 修飾キー完全一致判定）を `Sources/WintchCore/Services/HotKeyMonitorService.swift` に実装する（T002〜T004 依存）
- [X] T013 [US1] `SwitcherViewModel` に `SwitcherMode`（`.inactive`, `.normal`, `.launcher`）、`searchQuery`、`displayedResults: [WindowSearchResult]`、`updateSearchQuery(_:)`、`moveSelection(_:)`、`confirmSelection()`、`launcherTriggerPressed` 処理、および相互排他制御を実装する（`Sources/WintchCore/ViewModels/SwitcherViewModel.swift`、T011 依存）
- [X] T014 [P] [US1] `NSTextField` を `NSViewRepresentable` でラップした `LauncherSearchField`（開時にファーストレスポンダ取得、`NSTextFieldDelegate.control(_:textView:doCommandBy:)` で `!textView.hasMarkedText()` 確認の上 `insertNewline:` / `cancelOperation:` / `moveUp:` / `moveDown:` をハンドルして IME 優先動作を保証）を `Sources/WintchCore/Views/LauncherSearchField.swift` に作成する
- [X] T015 [US1] `SwitcherListView` の上部に `mode == .launcher` 時のみ検索ヘッダ（`LauncherSearchField` ＋区切り線）を統合し、各行で `AttributedString` を用いた一致文字の太字・ハイライト描画を実装する（`Sources/WintchCore/Views/SwitcherListView.swift`、T013, T014 依存）
- [X] T016 [US1] `SwitcherPanel` にランチャーモード時のアプリアクティブ化（直前アプリ `NSWorkspace.shared.frontmostApplication` 記録、キャンセル/トグル終了時の直前アプリ復元、通常モード時の `.nonactivatingPanel` 非アクティブ維持）を実装する（`Sources/WintchCore/Views/SwitcherPanel.swift`、T015 依存）
- [X] T017 [US1] `AppCoordinator` の起動時に `loadLauncherShortcut()` を読み込んで `hotKeyMonitor.updateLauncherShortcut(_:)` へ反映し、パネル表示モードに応じた表示制御を接続する（`Sources/WintchCore/App/AppCoordinator.swift`、T006, T012, T013, T016 依存）

**Checkpoint**: User Story 1（ランチャー起動・ファジー検索・ハイライト・IME 対応切り替え）が単独で動作し、`WindowSearchEngineTests` と `SwitcherViewModelTests` がパスする状態

---

## Phase 4: User Story 2 - 検索中のパネル位置安定性と 0 件時のフィードバック (Priority: P2)

**Goal**: 検索入力による候補件数の増減時にパネル上端位置を固定して下方向のみに伸縮させ、一致するウィンドウが 0 件の場合もパネルを閉じずに「一致するウィンドウがありません」メッセージを表示し、0 件時の `Enter` による誤切り替えを防止する

**Independent Test**: 10 件以上開いた状態から一致 0 件・再入力までパネル上端座標（`frame.maxY`）が 0pt ズレなく固定されたまま下方向のみ伸縮し、0 件時に案内表示が出ること、および 0 件時 `Enter` 無視のユニットテストがパスすること

### Tests for User Story 2 ⚠️

- [X] T018 [P] [US2] `SwitcherViewModel` の 0 件検索結果時に `confirmSelection()`（`Enter`）および `moveSelection(_:)` が安全に無視されパネルが開いたまま維持されるテストケースを `Tests/WintchCoreTests/SwitcherViewModelTests.swift` に追加する

### Implementation for User Story 2

- [X] T019 [US2] `SwitcherListView` に `displayedResults.isEmpty` 時の「一致するウィンドウがありません」表示ビューおよびコンテンツサイズ変化通知を追加する（`Sources/WintchCore/Views/SwitcherListView.swift`、T015 依存）
- [X] T020 [US2] `SwitcherPanel` に起動時の上端 Y 座標（`anchoredTopY = frame.maxY`）の保持、`hostingView.layoutSubtreeIfNeeded()` 後の `fittingSize.height` を用いた上端固定・下方向リサイズ（`newOriginY = anchoredTopY - newHeight`）、および `hidePanel()` 時のアンカーリセットを実装する（`Sources/WintchCore/Views/SwitcherPanel.swift`、T016, T019 依存）
- [X] T021 [US2] `AppCoordinator` に検索結果更新（`displayedResults` / `searchQuery` 変化）時の `SwitcherPanel` 上端固定リサイズ呼び出しを接続する（`Sources/WintchCore/App/AppCoordinator.swift`、T017, T020 依存）

**Checkpoint**: 検索中の上端固定伸縮と 0 件時フィードバックが安定動作し、US1 + US2 が独立検証可能な状態

---

## Phase 5: User Story 3 - ランチャーショートカットのカスタマイズと双方向競合防止 (Priority: P2)

**Goal**: 設定画面のショートカットレコーダーでランチャー起動ショートカットを任意に変更・保存でき、修飾キーなし/`Shift` のみ拒否、`Esc` キャンセル、および通常スイッチャー（順方向・逆方向 `Option + Shift + Tab`）との双方向重複ブロックを実現する

**Independent Test**: `SettingsView` のレコーダーで有効キー登録・修飾キーなし拒否・`Esc` キャンセルができ、通常スイッチャー側とレコーダー側の双方で重複がブロックされ、`LauncherShortcutPreferenceTests`、`ShortcutConflictValidatorTests`、`SettingsViewModelTests` がすべてパスすること

### Tests for User Story 3 ⚠️

- [X] T022 [P] [US3] `LauncherShortcutPreference` のデフォルト値（`⌥ + Space`）、`Codable` 往復、`displayString` 書式のテストを `Tests/WintchCoreTests/LauncherShortcutPreferenceTests.swift` に作成する
- [X] T023 [P] [US3] `ShortcutConflictValidator` の修飾キー必須チェック（修飾キーなし・`.shift` のみ拒否）および通常スイッチャー順方向（`[modifier]`）・逆方向（`[modifier, .shift]`）との双方向競合判定テストを `Tests/WintchCoreTests/ShortcutConflictValidatorTests.swift` に作成する
- [X] T024 [P] [US3] `SettingsViewModel` のランチャーショートカット更新、記録開始/終了による `isSuspendedForRecording` 切り替え、重複時の変更ブロック＋エラーメッセージ保持テストを `Tests/WintchCoreTests/SettingsViewModelTests.swift` に追加する

### Implementation for User Story 3

- [X] T025 [US3] 純粋競合検証ロジック `ShortcutConflictValidator`（`validateLauncherShortcut(_:against:)`、`validateNormalShortcut(_:against:)`、`conflicts(launcher:normal:)`）を `Sources/WintchCore/Domain/ShortcutConflictValidator.swift` に実装する（T002, T003 依存）
- [X] T026 [US3] `SettingsViewModel` に `launcherShortcut`、`shortcutValidationError`、`isRecordingLauncherShortcut`、`beginRecordingLauncherShortcut()`、`endRecordingLauncherShortcut()`、`recordLauncherShortcut(_:)`、および `updateModifier(_:)` / `updateTrigger(_:)` での双方向競合ブロックを実装する（`Sources/WintchCore/ViewModels/SettingsViewModel.swift`、T004〜T006, T025 依存）
- [X] T027 [P] [US3] 実キー入力を受け取る `ShortcutRecorderView`（`NSEvent.addLocalMonitorForEvents(matching: .keyDown)` による `keyCode`・修飾キー・表示ラベル取得、`Esc` キャンセル、フォーカス喪失時サスペンド解除）を `Sources/WintchCore/Views/ShortcutRecorderView.swift` に作成する（T002 依存）
- [X] T028 [US3] `SettingsView` に通常スイッチャーと検索ランチャーのセクション整理、`ShortcutRecorderView` の組み込み、双方の重複・バリデーションエラー表示、画面クローズ時の記録サスペンド解除安全策を実装する（`Sources/WintchCore/Views/SettingsView.swift`、T026, T027 依存）

**Checkpoint**: 全 3 ユーザーストーリーが実装・単体テスト完了し、設定カスタマイズおよび双方向競合防止まで含めて完結する状態

---

## Phase 6: Polish & Cross-Cutting Concerns（仕上げ・品質・実機検証）

**Purpose**: プロジェクト憲章・コーディング規約（日本語コメント・外部依存ゼロ・最小権限）の遵守確認と全体結合検証を実施する

- [X] T029 [P] 新規・更新した全ファイル（`Sources/WintchCore/` および `Tests/WintchCoreTests/`）のクラス・関数・メソッドに日本語ドキュメントコメント（概要・`@param`・`@returns`）および日本語インラインコメントが揃っているか点検・補完する
- [X] T030 全ユニットテストを実行（`swift package clean && swift test` または `swift test`）して全テストスイートが 100% パスすることを確認する
- [ ] T031 `./scripts/build-app.sh` で `.build/Wintch.app` をビルドし、[quickstart.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/002-window-search-launcher/quickstart.md) のシナリオ A〜D（ファジー検索・IME 優先・上端固定リサイズ・0件表示・ショートカットレコーダー・双方向競合ブロック・画面収録権限不使用）を検証する（`.build/Wintch.app` のビルド・アドホック署名までは完了、実機 GUI シナリオ確認は未実施）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし — 既存ベースライン確認のみ（完了済みとして即 Phase 2 へ進める構成）
- **Foundational (Phase 2)**: T002〜T005 は並列実行可能 → T006・T007 が依存。完了まで US1〜US3 はブロック
- **User Story 1 (Phase 3 - P1 🎯 MVP)**: Foundational 完了後に開始。テスト（T008, T009）を先に作成し、Domain (`T010`→`T011`)・Service (`T012`)・ViewModel (`T013`)・Views (`T014`→`T015`→`T016`)・App (`T017`) の順で統合
- **User Story 2 (Phase 4 - P2)**: US1 のパネル・リスト統合（T015, T016, T017）完了後に、`SwitcherListView` 空状態と `SwitcherPanel` 上端固定リサイズ（T018〜T021）を順次実装
- **User Story 3 (Phase 5 - P2)**: Foundational（T002〜T007）完了後、US1/US2 と独立して並列実装も可能（`SettingsView` / `SettingsViewModel` / `ShortcutConflictValidator` / `ShortcutRecorderView`）
- **Polish (Phase 6)**: 全ストーリー完了後に実施

### Parallel Opportunities

- **Foundational**: `T002`, `T003`, `T004`, `T005` は別ファイルのため完全並列実行可能
- **US1 Tests & Independent Files**: `T008`, `T009`, `T010`, `T014` は並列着手可能
- **US3 vs US1/US2**: Phase 2 完了後、`T022`, `T023`, `T024`, `T025`, `T027` は US1 実装と並行して進められる

---

## Parallel Example: User Story 1 & User Story 3

```text
# Phase 2 完了直後に並列実行できるタスク群:
- T008 [US1]: Tests/WintchCoreTests/WindowSearchEngineTests.swift
- T009 [US1]: Tests/WintchCoreTests/SwitcherViewModelTests.swift
- T010 [US1]: Sources/WintchCore/Domain/WindowSearchResult.swift
- T014 [US1]: Sources/WintchCore/Views/LauncherSearchField.swift
- T022 [US3]: Tests/WintchCoreTests/LauncherShortcutPreferenceTests.swift
- T023 [US3]: Tests/WintchCoreTests/ShortcutConflictValidatorTests.swift
- T025 [US3]: Sources/WintchCore/Domain/ShortcutConflictValidator.swift
- T027 [US3]: Sources/WintchCore/Views/ShortcutRecorderView.swift
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 2（Foundational: T002〜T007）を完了する
2. Phase 3（User Story 1: T008〜T017）を完了する
3. **STOP & VALIDATE**: `swift test` および `Option + Space` による実機ファジー検索・切り替え・IME 優先動作を検証する

### Incremental Delivery

1. Foundational + US1 完了 → 中核の検索ランチャーが利用可能（MVP）
2. US2 完了（T018〜T021） → 検索時のパネル上端固定と 0 件フィードバックが完成
3. US3 完了（T022〜T028） → ショートカットレコーダーと双方向競合防止が完成
4. Polish（T029〜T031） → コメント規約・全テスト・`.app` 実機シナリオを最終確認
