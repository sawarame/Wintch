# タスク一覧 (Tasks): 検索ランチャーでの検索入力時におけるアプリ起動候補の併用表示

**Input**: Design documents from `/specs/006-launcher-app-launch/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: ドメインロジック・サービス・ViewModel のユニットテストを Swift Testing で作成・更新する。

**Organization**: ユーザーストーリー単位（US1: P1, US2: P2, US3: P2）で独立検証可能なフェーズに分割して管理する。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 別ファイルで並列実行可能（未完了タスクへの依存なし）
- **[Story]**: 対応するユーザーストーリー（US1, US2, US3）
- 各タスクに正確なファイルパスを記載する

---

## Phase 1: Setup（事前確認と共通基盤）

**Purpose**: 既存プロジェクト構造と共通検索基盤・サービス契約の整備（前段仕様にて構築済み）

- [X] T001 既存の2フィールドファジー検索ロジックを `Sources/WintchCore/Domain/FuzzySearchMatcher.swift` へ抽出し、`Sources/WintchCore/Domain/WindowSearchEngine.swift` をリファクタリングする
- [X] T002 [P] `LaunchableApp`（`id`, `displayName`, `alternateName`, `bundleIdentifier`, `bundleURL`）を `Sources/WintchCore/Domain/LaunchableApp.swift` に作成する
- [X] T003 [P] `AppSearchResult`（`app`, `score`, `matchedDisplayNameRanges`, `matchedAlternateNameRanges`）を `Sources/WintchCore/Domain/AppSearchResult.swift` に作成する

---

## Phase 2: Foundational（アプリ収集・アイコン・重複除外照合基盤）

**Purpose**: 全ユーザーストーリーの土台となるインストール済みアプリ収集・起動サービス、アイコン取得、および既存ウィンドウ側への `bundleIdentifier` 伝播を整備する

- [X] T004 [P] `InstalledAppServicing` プロトコルを `Sources/WintchCore/Services/Protocols/InstalledAppServicing.swift` に定義する
- [X] T005 [P] `IconProviding` プロトコルおよび `IconProviderService` へ `icon(forAppURL:)` を追加する（`Sources/WintchCore/Services/Protocols/IconProviding.swift`, `Sources/WintchCore/Services/IconProviderService.swift`）
- [X] T006 `InstalledAppService`（標準ディレクトリ走査・深さ制限 3・シンボリックリンク解決・重複排除・`LSBackgroundOnly` / 自アプリ / 不完全バンドル除外・`NSWorkspace.shared.openApplication` 起動）を `Sources/WintchCore/Services/InstalledAppService.swift` に実装する（T002, T004 依存）
- [X] T007 [P] `MockIconProvider.icon(forAppURL:)` および `MockInstalledAppService` を `Tests/WintchCoreTests/Mocks/MockServices.swift` に追加する
- [X] T008 [P] `InstalledAppServiceTests`（仮ディレクトリ構造での走査・サブディレクトリ・シンボリックリンク・重複排除・除外フィルタ検証）を `Tests/WintchCoreTests/InstalledAppServiceTests.swift` に作成する
- [X] T009 `WindowEntry` へ `bundleIdentifier: String? = nil` を追加し、`WindowFilter.filterAndMap(_:)` から `RawWindowCandidate.bundleIdentifier` を引き継ぐ（`Sources/WintchCore/Domain/WindowEntry.swift`, `Sources/WintchCore/Domain/WindowFilter.swift`）

**Checkpoint**: アプリ収集基盤とウィンドウ側 `bundleIdentifier` 伝播が完了し、検索・表示統合へ進める状態になる。

---

## Phase 3: User Story 1 - 検索入力時に既存ウィンドウ候補の下へ未表示アプリ起動候補を併せて表示し起動する (Priority: P1) 🎯 MVP

**Goal**: ランチャー検索時（既存ウィンドウが 0 件でも 1 件以上でも）、上のウィンドウ候補に表示済みのアプリを除外したアプリ起動候補をウィンドウ候補の下に併用表示し、キーボード／クリックで両セクション間を貫通移動・確定起動できるようにする。

**Independent Test**: `AppSearchEngineTests` で上のウィンドウ候補重複除外（`bundleIdentifier` 一致およびアプリ名フォールバック一致）がパスし、`SwitcherViewModelTests` で混在表示・貫通循環移動・修飾キー解放無視・空検索時非表示・各セクション確定（ウィンドウ切替／アプリ起動）がパスすること。

### Tests for User Story 1

- [X] T010 [P] [US1] `AppSearchEngineTests` に `excludingWindowEntries` による上のウィンドウ候補アプリ重複除外テスト（`bundleIdentifier` 一致、日本語表示名＋英語名の組み合わせ、`bundleIdentifier` 欠落時のアプリ名フォールバック一致）を追加する（`Tests/WintchCoreTests/AppSearchEngineTests.swift`）
- [X] T011 [P] [US1] `SwitcherViewModelTests` に検索時の混在表示（上ウィンドウ・下未表示アプリ）、重複アプリ除外、ウィンドウ↔アプリ間の貫通上下循環移動（矢印および通常スイッチャーショートカット）、修飾キー解放無視、空検索時のアプリ非表示、各セクションでの確定実行テストを追加・更新する（`Tests/WintchCoreTests/SwitcherViewModelTests.swift`）

### Implementation for User Story 1

- [X] T012 [US1] `AppSearchEngine.search(query:in:excludingWindowEntries:)` へ重複アプリ除外ロジック（`bundleIdentifier` 優先照合・アプリ名フォールバック）を実装する（`Sources/WintchCore/Domain/AppSearchEngine.swift`, T009 依存）
- [X] T013 [US1] `AppCoordinator` に `InstalledAppService` の DI 接続と `start()` 時プリロードを追加し、`LauncherSearchField` のプレースホルダーを更新する（`Sources/WintchCore/App/AppCoordinator.swift`, `Sources/WintchCore/Views/LauncherSearchField.swift`）
- [X] T014 [US1] `SwitcherViewModel` を更新し、非空クエリ時はウィンドウ件数にかかわらず `AppSearchEngine.search(query:in:excludingWindowEntries:)` で `displayedAppResults` を更新し、統合リスト件数（`displayedResults.count + displayedAppResults.count`）に対する `selectedIndex` 貫通移動・確定分岐・クリック選択を実装する（`Sources/WintchCore/ViewModels/SwitcherViewModel.swift`, T012 依存）
- [X] T015 [US1] `SwitcherListView` を単一 `ScrollViewReader` + `ScrollView` の統合構成へ更新し、上部にウィンドウ候補、下部に区切り線＋セクション案内ヘッダ（「アプリを起動」／「一致するウィンドウがないため、アプリを起動」）＋アプリ起動候補を表示し、全候補の選択ハイライト・クリック確定・スクロール追従を実装する（`Sources/WintchCore/Views/SwitcherListView.swift`, T014 依存）

**Checkpoint**: User Story 1 の全受入シナリオが独立してテスト・動作確認可能な状態になる。

---

## Phase 4: User Story 2 - 日本語名・英語名の双方によるアプリ検索とハイライト表示 (Priority: P2)

**Goal**: ローカライズ名と英語別名を持つアプリについて、日本語・英語・空白区切り AND ファジー検索のいずれでも一致し、両名称のハイライト表示とスコア順／表示名昇順ソートが行われることを保証する。

**Independent Test**: `AppSearchEngineTests` で空クエリ空返却、日本語表示名・英語別名・略称のファジーマッチと文字ハイライト範囲抽出、空白区切り AND、スコア降順／表示名昇順ソートがすべてパスすること。

- [X] T016 [P] [US2] `AppSearchEngineTests` に空／空白クエリ、日本語名／英語別名ファジーマッチとハイライト範囲抽出、スコア降順・同点時表示名昇順ソートのテストを作成する（`Tests/WintchCoreTests/AppSearchEngineTests.swift`）
- [X] T017 [US2] `AppSearchEngine` および `SwitcherListView`（`AppLaunchRowView`）にて表示名・別名の双方のハイライト描画を実装する（`Sources/WintchCore/Domain/AppSearchEngine.swift`, `Sources/WintchCore/Views/SwitcherListView.swift`）

**Checkpoint**: User Story 2 の日本語・英語検索とハイライト要件が完全に検証された状態になる。

---

## Phase 5: User Story 3 - 境界状態・重複除外・パネル安定性および既存操作との安全な共存 (Priority: P2)

**Goal**: 双方 0 件時の空表示・無操作、ウィンドウクローズに伴う双方再評価、アプリ候補選択中の `修飾キー + Q` 安全無視、裏リフレッシュ完了時の整合更新、パネル上端位置固定を保証する。

**Independent Test**: `SwitcherViewModelTests` で双方 0 件時のパネル維持、アプリ候補選択中の `closeSelectedWindow()` 無視、ウィンドウクローズ後の双方再評価、および裏リフレッシュ完了時の候補・選択位置補正がすべてパスすること。

### Tests for User Story 3

- [X] T018 [P] [US3] `SwitcherViewModelTests` に、混在表示中のアプリ起動候補カーソル位置での `closeSelectedWindow()` 無視テスト、ウィンドウクローズ後に未表示アプリ候補へ現れる再評価テスト、および混在表示中の裏リフレッシュ反映（ウィンドウ側選択位置維持含む）テストを追加・更新する（`Tests/WintchCoreTests/SwitcherViewModelTests.swift`）

### Implementation for User Story 3

- [X] T019 [US3] `SwitcherViewModel.scheduleInstalledAppsRefresh()` を更新し、既存ウィンドウが 1 件以上ある場合も含め検索クエリ入力中のランチャー表示中であれば最新のアプリ候補（重複除外適用済み）を再評価して `selectedIndex` を安全に維持・補正するよう実装する（`Sources/WintchCore/ViewModels/SwitcherViewModel.swift`, T014 依存）

**Checkpoint**: すべてのユーザーストーリーおよび境界条件・既存機能共存が完全に動作する。

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: 仕様整合性確認・全テストスイート実行・`.app` バンドルビルド検証

- [X] T020 [P] 既存仕様書（`specs/002-window-search-launcher/spec.md`, `specs/004-launcher-switcher-nav/spec.md`, `specs/005-close-selected-window/spec.md`）の 0 件時・選択操作・クローズ再評価記述を本仕様に合わせて改定する
- [X] T021 日本語ドキュメントコメント・インラインコメントおよびコード品質（重複排除・Swift 6 並行性）を全変更ファイルで確認する
- [X] T022 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` および `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh` を実行し、`specs/006-launcher-app-launch/quickstart.md` の検証を完了する

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)** → **Phase 2 (Foundational)**: T009 の `WindowEntry.bundleIdentifier` 引き継ぎ完了後に Phase 3 の重複除外が有効化される。
- **Phase 3 (US1)** → **Phase 4 (US2)** / **Phase 5 (US3)**: US1 で統合検索・貫通選択・単一スクロール UI が完成した後、US3 の裏リフレッシュ・境界検証を統合する（US2 のコア検索機能は実装済みで US1 と連動）。
- **Phase 6 (Polish)**: すべてのストーリー完了後に実行する。

### Parallel Opportunities

- Phase 2: T009 は独立して実行可能。
- Phase 3: T010 と T011 は別テストファイルのため並列作成可能。
- Phase 5: T018 のテスト作成後に T019 で検証。
