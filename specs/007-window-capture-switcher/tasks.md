# タスク一覧 (Tasks): 通常スイッチャーのウィンドウキャプチャ表示型および表示形式切替設定

**Input**: Design documents from `/specs/007-window-capture-switcher/`  
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/, quickstart.md

**Tests**: ドメインロジック・サービス契約・ViewModel・コーディネーターのユニットテストを Swift Testing（`import Testing`, `@Test`, `#expect`）で作成・更新する。

**Organization**: ユーザーストーリー単位（US1: P1, US2: P1, US3: P2）で独立検証可能なフェーズに分割して管理する。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 別ファイルで並列実行可能（未完了タスクへの依存なし）
- **[Story]**: 対応するユーザーストーリー（US1, US2, US3）
- 各タスクに正確なファイルパスを記載する

---

## Phase 1: Setup（ドメインモデル・純粋ロジック基盤）

**Purpose**: 外部依存および OS API 非依存のドメイン型・純粋計算ロジックを定義する

- [X] T001 [P] `SwitcherDisplayStyle`（`String, Codable, CaseIterable, Equatable, Sendable`、`.list = "list"` / `.capture = "capture"`、`default == .list`、`displayName`：「リスト型」/「キャプチャ表示型」）を `Sources/WintchCore/Domain/SwitcherDisplayStyle.swift` に作成する
- [X] T002 [P] `ScreenRecordingPermissionStatus`（`Equatable, Sendable`、`.granted` / `.denied`）を `Sources/WintchCore/Domain/ScreenRecordingPermissionStatus.swift` に作成する
- [X] T003 [P] `SwitcherGridLayout`（定数 `cardWidth: 216`, `cardHeight: 164`, `cardSpacing: 10`, `gridPadding: 14`, `maxColumnsLimit: 5`, 画面幅上限比率 `0.85` に基づく `columnsCount(itemCount:availableScreenWidth:)` および 4 方向循環移動 `moveIndex(current:direction:count:columns:)`）を `Sources/WintchCore/Domain/SwitcherGridLayout.swift` に作成する

---

## Phase 2: Foundational（サービス契約・永続化・権限・キャプチャ・矢印キー基盤）

**Purpose**: 全ユーザーストーリーの前提となる設定永続化・オプトイン権限・キャプチャサービス・4 方向キー監視・モック基盤を整備する

**⚠️ CRITICAL**: ユーザーストーリーの実装開始前に本フェーズを完了する

- [X] T004 [P] `PreferencesStoring` に `loadNormalDisplayStyle()` / `saveNormalDisplayStyle(_:)` を追加し、`PreferencesStore` に `"dev.wintch.normalDisplayStyle"` キーでの保存・読み込み（未保存または不正値時は `.list` フォールバック）を実装する（`Sources/WintchCore/Services/Protocols/PreferencesStoring.swift`, `Sources/WintchCore/Services/PreferencesStore.swift`）
- [X] T005 [P] `ScreenRecordingPermissionServicing` プロトコルおよび `ScreenRecordingPermissionService`（`CGPreflightScreenCaptureAccess()`、`CGRequestScreenCaptureAccess()`、`x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture` の開放）を作成する（`Sources/WintchCore/Services/Protocols/ScreenRecordingPermissionServicing.swift`, `Sources/WintchCore/Services/ScreenRecordingPermissionService.swift`）
- [X] T006 [P] `WindowCaptureServicing` プロトコルおよび `WindowCaptureService`（`SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)` と `SCScreenshotManager.captureImage` による最大 4 並列非同期縮小サムネイル取得、最大 50 件のメモリ限定 LRU キャッシュ、`invalidateThumbnail(for:)`・`clearCache()`、ディスク非保存）を作成する（`Sources/WintchCore/Services/Protocols/WindowCaptureServicing.swift`, `Sources/WintchCore/Services/WindowCaptureService.swift`）
- [X] T007 [P] `ArrowDirection` に `.left` / `.right` を追加し、`HotKeyMonitorService.resolveKeyDown` の `mode == .normal` に限り仮想キーコード `123`（左矢印）および `124`（右矢印）を消費通知するよう更新する（`Sources/WintchCore/Services/Protocols/HotKeyMonitoring.swift`, `Sources/WintchCore/Services/HotKeyMonitorService.swift`）
- [X] T008 [P] `MockScreenRecordingPermissionService` と `MockWindowCaptureService` を追加し、`MockPreferencesStore` へ `loadNormalDisplayStyle()` / `saveNormalDisplayStyle(_:)` を実装する（`Tests/WintchCoreTests/Mocks/MockServices.swift`）

**Checkpoint**: 基盤サービス・プロトコル・モックが揃い、各ユーザーストーリーの並行・順次実装が可能な状態になる。

---

## Phase 3: User Story 1 - キャプチャ表示型でのウィンドウ識別とグリッド切り替え (Priority: P1) 🎯 MVP

**Goal**: 通常スイッチャーを「キャプチャ表示型」で起動した際、直前キャッシュまたはアイコンプレースホルダーで即座に複数行カードグリッドを表示し、非同期で最新キャプチャへ差し替え、4 方向矢印キー／トリガーキー移動・修飾キー解放確定・クリック確定・`Esc` キャンセル・`Mod + Q` クローズを一貫して操作できるようにする。

**Independent Test**: `SwitcherGridLayoutTests`、`HotKeyMonitorDecisionTests`、`SwitcherViewModelTests` がすべてパスし、起動時即時表示・非同期差し替え・4 方向移動・クローズ更新が単体テストで検証でき、実アプリ上で Alt+Tab 風グリッド切り替えが動作すること。

### Tests for User Story 1

- [X] T009 [P] [US1] `SwitcherGridLayoutTests`（1 件〜多数件の列数計算、`maxColumnsLimit: 5` と画面幅 85% 制限、`←`/`→` 循環移動、`↑`/`↓` 行間移動、最終行が列数未満の場合の末尾クランプと行循環）を `Tests/WintchCoreTests/SwitcherGridLayoutTests.swift` に作成する
- [X] T010 [P] [US1] `HotKeyMonitorDecisionTests` に `.normal` モードでの左矢印（123）・右矢印（124）消費テスト、および `.launcher` モードでの左右矢印非消費維持テストを追加する（`Tests/WintchCoreTests/HotKeyMonitorDecisionTests.swift`）
- [X] T011 [P] [US1] `SwitcherViewModelTests` にキャプチャ表示型の即時パネル表示（既存キャッシュ反映・未キャッシュ時 `nil` プレースホルダー）、非同期サムネイル到着時の `capturedThumbnails` 反映、4 方向移動（`gridColumnCount` 連動）、および `closeSelectedWindow()` での対象キャッシュ無効化と選択インデックス補正テストを追加する（`Tests/WintchCoreTests/SwitcherViewModelTests.swift`）

### Implementation for User Story 1

- [X] T012 [US1] `SwitcherViewModel` を拡張し、`normalDisplayStyle`、`capturedThumbnails`、`isScreenRecordingGranted`、`gridColumnCount`、`thumbnail(for:)`、`updateGridColumnCount(_:)`、世代カウンタ付き非同期キャプチャ取得タスク、4 方向 `moveSelection(_:)`、および `closeSelectedWindow()` 時のキャッシュ削除を実装する（`Sources/WintchCore/ViewModels/SwitcherViewModel.swift`, T003, T006, T007 依存）
- [X] T013 [P] [US1] `SwitcherCaptureGridView`（`LazyVGrid` による複数行カードグリッド、16:10 キャプチャプレビューまたはアプリアイコンプレースホルダー・アイコン・アプリ名・タイトル、`ScrollViewReader` 自動スクロール追従、選択強調、クリック確定、最大高さ時縦スクロール）を `Sources/WintchCore/Views/SwitcherCaptureGridView.swift` に作成する
- [X] T014 [US1] `SwitcherContentView` を作成して `mode == .normal && normalDisplayStyle == .capture` 時は `SwitcherCaptureGridView`、それ以外は `SwitcherListView` へ切り替え、`SwitcherPanel` が動的サイズ変化（幅・高さ）を上端中央基準でリサイズおよびシャドウ再計算するよう更新する（`Sources/WintchCore/Views/SwitcherContentView.swift`, `Sources/WintchCore/Views/SwitcherPanel.swift`, `Sources/WintchCore/App/AppCoordinator.swift`, T012, T013 依存）

**Checkpoint**: User Story 1 のキャプチャグリッド表示・非同期差し替え・4 方向キーボード移動・クリック／クローズ操作が独立して検証・利用可能な状態になる。

---

## Phase 4: User Story 2 - 設定画面での表示形式切替とオプトイン権限管理 (Priority: P1)

**Goal**: 設定画面から通常スイッチャーの表示形式を「リスト型（デフォルト）」と「キャプチャ表示型」で切り替え・永続化でき、リスト型選択時は画面収録権限を一切確認・案内せず、キャプチャ表示型選択時のみオプトインの画面収録権限状態と設定導線を提供し、検索ランチャーは常にリスト型を維持する。

**Independent Test**: `SettingsViewModelTests` および `AppCoordinatorTests` がすべてパスし、初期値 `.list`・設定永続化・`.list` 時権限非プローブ・`.capture` 時権限案内・即時反映・`PermissionGuideView` 文言整合が確認できること。

### Tests for User Story 2

- [X] T015 [P] [US2] `SettingsViewModelTests` に表示形式初期値 `.list` 検証、`.list` 時の `ScreenRecordingPermissionServicing` 非呼び出し検証、`.capture` 選択時の保存・通知・権限確認／リクエスト・システム設定起動検証、および `.list` 復帰時動作検証を追加する（`Tests/WintchCoreTests/SettingsViewModelTests.swift`）
- [X] T016 [P] [US2] `AppCoordinatorTests` に `SettingsViewModel` で表示形式を切り替えた際に即座に `SwitcherViewModel` へ反映される連携テストおよび起動時ロードテストを追加する（`Tests/WintchCoreTests/AppCoordinatorTests.swift`）

### Implementation for User Story 2

- [X] T017 [US2] `SettingsViewModel` に `normalDisplayStyle`、`screenRecordingStatus`、`onNormalDisplayStyleChanged`、`updateNormalDisplayStyle(_:)`、`requestScreenRecordingPermission()`、`openScreenRecordingSettings()` を実装し、`refreshStatus()` を含む全経路で `.list` 選択中の画面収録権限非チェックを徹底する（`Sources/WintchCore/ViewModels/SettingsViewModel.swift`, T004, T005 依存）
- [X] T018 [US2] `SettingsView` の「通常スイッチャー（ホールド式）」セクションに表示形式 `Picker`（「リスト型」／「キャプチャ表示型」）を追加し、`normalDisplayStyle == .capture` のときのみ画面収録権限の案内・要求／設定ボタン（および許可後再起動が必要な場合がある旨の補足）とシステム権限セクション内の「画面収録権限」行を表示する（`Sources/WintchCore/Views/SettingsView.swift`, T017 依存）
- [X] T019 [US2] `AppCoordinator` で `ScreenRecordingPermissionService` と `WindowCaptureService` を生成・DI 注入し、`start()` 時の表示形式ロード・`onNormalDisplayStyleChanged` の接続・設定ウィンドウの高さ調整を行う（`Sources/WintchCore/App/AppCoordinator.swift`, T012, T017 依存）
- [X] T020 [P] [US2] `PermissionGuideView` の画面収録権限に関する注記を「リスト型および検索ランチャーでは使用せず、キャプチャ表示型を選択した場合のみ任意で使用する」趣旨の文言へ更新する（`Sources/WintchCore/Views/PermissionGuideView.swift`）

**Checkpoint**: User Story 1 と User Story 2 が結合し、設定画面からの切り替えとオプトイン権限管理を含めた MVP 体験が完結する。

---

## Phase 5: User Story 3 - 権限未許可・取得不能ウィンドウに対する安全なフォールバックと安定動作 (Priority: P2)

**Goal**: 画面収録権限が未許可・取り消し済みの場合でもクラッシュや操作不能にならず、パネル上部の権限案内バナーとアイコンプレースホルダーで切り替え操作を継続でき、最小化・別スペースウィンドウやセッション跨ぎの古い非同期タスクも安全に処理・キャッシュ制御できるようにする。

**Independent Test**: `SwitcherViewModelTests` で権限未許可時の `WindowCaptureServicing` 非呼び出し＋フォールバック継続、非同期取得途中でのキャンセル／パネル再起動による古い結果破棄、`.capture` 設定中のランチャー起動時非キャプチャ、および `.list` 戻し時のキャッシュ全消去がすべてパスすること。

### Tests for User Story 3

- [X] T021 [P] [US3] `SwitcherViewModelTests` に画面収録権限 `.denied` 時のキャプチャ取得スキップ＋`isScreenRecordingGranted == false`＋ウィンドウ切替継続、セッション世代不一致時の遅延キャプチャ破棄、検索ランチャー起動時のキャプチャ非実行、および `updateNormalDisplayStyle(.list)` 時の `clearCache()` 呼び出し検証テストを追加する（`Tests/WintchCoreTests/SwitcherViewModelTests.swift`）

### Implementation for User Story 3

- [X] T022 [US3] `SwitcherCaptureGridView` 上部に `viewModel.isScreenRecordingGranted == false` の場合のみ表示するコンパクトな権限未許可バナー（「システム設定を開く」操作付き）を追加し、`SwitcherViewModel.openScreenRecordingSettings()` と `AppCoordinator` の設定遷移・安全キャンセルを実装する（`Sources/WintchCore/Views/SwitcherCaptureGridView.swift`, `Sources/WintchCore/ViewModels/SwitcherViewModel.swift`, `Sources/WintchCore/App/AppCoordinator.swift`, T012, T013 依存）
- [X] T023 [US3] `SwitcherViewModel` の `updateNormalDisplayStyle(_:)`、ランチャーモード遷移時ガード、および非同期サムネイル反映時のセッション世代・現在表示リスト一致検証（陳腐化／閉じたウィンドウの誤反映防止）を網羅・確定する（`Sources/WintchCore/ViewModels/SwitcherViewModel.swift`, T012 依存）

**Checkpoint**: すべてのユーザーストーリー（US1, US2, US3）が安全にフォールバックし、独立してテスト・検証可能な状態になる。

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: ドキュメント・コメント規約の最終確認、全テスト実行、および `.app` バンドルビルド確認

- [X] T024 [P] `AGENTS.md` の旧原則 1 要約箇所を憲章 v2.0.0（最小権限およびオプトイン原則）の内容へ同期する（`AGENTS.md`）
- [X] T025 全新規・変更ファイルにおいて日本語ドキュメントコメント（`///`）と日本語インラインコメント、および Swift 6 Strict Concurrency（`@MainActor` / `Sendable`）・憲章準拠を点検する
- [X] T026 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` および `./scripts/build-app.sh` を実行し、`specs/007-window-capture-switcher/quickstart.md` の検証シナリオを通過することを確認する

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: 依存なし — `T001`, `T002`, `T003` はすべて並列実行可能。
- **Phase 2 (Foundational)**: Phase 1 の型定義完了後（特に `T004`→`T001`, `T005`→`T002`）に完了させる。`T004`〜`T008` はファイルが異なるため並列実行可能。
- **Phase 3 (US1)** と **Phase 4 (US2)**: Phase 2 完了後、独立して着手可能。ただし `AppCoordinator.swift`（`T014` と `T019`）は共有ファイルのため順次統合する。
- **Phase 5 (US3)**: Phase 3（`T012`, `T013`）完了後にバナー・世代保護・キャッシュ破棄検証を仕上げる。
- **Phase 6 (Polish)**: すべてのユーザーストーリー完了後に実行する。

### Parallel Opportunities

- **Setup**: `T001`, `T002`, `T003` を並列実行。
- **Foundational**: `T004`, `T005`, `T006`, `T007`, `T008` を並列実行。
- **US1**: テスト `T009`, `T010`, `T011` を並列作成後、`T012` と `T013` を並列実装し `T014` で統合。
- **US2**: テスト `T015`, `T016` と文言修正 `T020` を並列実行しつつ `T017` → `T018` / `T019` を順次実装。

---

## Parallel Example: Phase 1 & Phase 2

```bash
# Phase 1（ドメインモデル並列作成）:
T001: Sources/WintchCore/Domain/SwitcherDisplayStyle.swift
T002: Sources/WintchCore/Domain/ScreenRecordingPermissionStatus.swift
T003: Sources/WintchCore/Domain/SwitcherGridLayout.swift

# Phase 2（サービス・プロトコル・モック並列作成）:
T004: PreferencesStoring / PreferencesStore
T005: ScreenRecordingPermissionServicing / ScreenRecordingPermissionService
T006: WindowCaptureServicing / WindowCaptureService
T007: HotKeyMonitoring / HotKeyMonitorService
T008: MockServices.swift
```

---

## Implementation Strategy

### MVP First (Phase 1 + Phase 2 + US1 + US2)

1. Phase 1〜2 でドメインモデル・永続化・権限サービス・`ScreenCaptureKit` ベースのキャプチャサービス・4 方向矢印監視を構築する。
2. Phase 3（US1）でキャプチャグリッドと即時表示／非同期更新／4 方向操作を実装する。
3. Phase 4（US2）で設定画面の切り替え UI とオプトイン権限管理（`.list` 時完全無権限）を接続し、MVP として検証する。
4. Phase 5（US3）でパネル上部の権限未許可バナーと陳腐化・境界ケースの防御を完成させ、Phase 6 でテスト・`.app` ビルド検証を行う。
