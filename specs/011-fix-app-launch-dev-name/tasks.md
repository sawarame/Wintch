---

description: "Task list for 011-fix-app-launch-dev-name"
---

# Tasks: ランチャーからのアプリ起動安定化およびローカル開発版の識別名分離

**Input**: Design documents from `/specs/011-fix-app-launch-dev-name/`  
**Prerequisites**: `plan.md`（必須）, `spec.md`（必須）, `research.md`, `data-model.md`, `contracts/app-launch-and-identity-contracts.md`, `quickstart.md`

**Tests**: 本機能は憲章（純粋ビジネスロジックのユニットテスト可能性）および `quickstart.md` に従い、ドメイン層（`AppIdentity`）・サービス層（`InstalledAppService`）・コーディネーター層のユニットテストタスクを含む。

**Organization**: 共通の識別ドメインモデル `AppIdentity` を Phase 2 で構築した上で、User Story 1（P1: MVP — ランチャーアプリ起動クラッシュ修正）、User Story 2（P2: ローカル開発版 `Wintch_dev` の名称・バンドル分離）、User Story 3（P3: 配布版・開発版共存時の自己除外と統合確認）をそれぞれ独立テスト可能な単位で実装する。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 依存関係がなく別ファイルを扱うため並列実行可能なタスク
- **[Story]**: 対応するユーザーストーリー（`US1`, `US2`, `US3`）。Setup / Foundational / Polish フェーズには付与しない
- すべてのタスクに正確なファイルパスと契約・制約条件を明記している

## Path Conventions

- エントリポイント: `Sources/Wintch/`
- コアモジュール: `Sources/WintchCore/`
- ビルドスクリプト: `scripts/`
- ユニットテスト: `Tests/WintchCoreTests/`

---

## Phase 1: Setup（ベースライン確認）

**Purpose**: 既存ビルドおよび全ユニットテストのベースライン状態を確認する

- [X] T001 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行し、現行コードベースの全ユニットテストが合格することを確認する

---

## Phase 2: Foundational（アプリ識別ドメイン基盤の構築）

**Purpose**: 実行中のアプリケーションが開発版（`Wintch_dev`）か配布版（`Wintch`）かをバンドル情報およびビルド構成から一元解決する純粋ドメインモデルを構築する

**⚠️ CRITICAL**: User Story 2 および User Story 3 は `AppIdentity` に依存するため、Phase 2 完了後にこれらへ進む（User Story 1 は独立しており並列進行可能）

- [X] T002 `Tests/WintchCoreTests/AppIdentityTests.swift` を新規作成し、`AppIdentity` のメタデータ抽出優先順位（`CFBundleDisplayName` > `CFBundleName` > `fallbackDisplayName`、`CFBundleIdentifier` > `fallbackBundleIdentifier`）、前後空白・改行のトリミング、空文字・非文字列時のフォールバック、`isDevelopment` 判定（`"Wintch_dev"` / `"dev.wintch.Wintch.dev"` / `".dev"` 接尾辞）、および UI 文言導出プロパティ（`aboutMenuTitle` / `quitMenuTitle` / `settingsWindowTitle` / `permissionGuideWindowTitle` / `accessibilitySwitchInstruction`）を検証する単体テストを先行記述する
- [X] T003 `Sources/WintchCore/Domain/AppIdentity.swift` を新規作成し、`Equatable`・`Sendable` 準拠の `AppIdentity` 構造体（`releaseDisplayName = "Wintch"`, `developmentDisplayName = "Wintch_dev"`, `releaseBundleIdentifier = "dev.wintch.Wintch"`, `developmentBundleIdentifier = "dev.wintch.Wintch.dev"`、`init(infoDictionary:fallbackDisplayName:fallbackBundleIdentifier:)`、`current`、および UI 文言導出プロパティ）を日本語ドキュメントコメント・インラインコメント付きで実装する（T002 に依存）

**Checkpoint**: `AppIdentityTests` が合格し、アプリ識別名・識別子・UI 文言解決の共通基盤が利用可能になる

---

## Phase 3: User Story 1 - 検索ランチャーから新しいアプリケーションをクラッシュせず安定起動する (Priority: P1) 🎯 MVP

**Goal**: 検索ランチャーからアプリを起動する際、LaunchServices のバックグラウンドディスパッチキュー上で `@MainActor` 分離クロージャが呼ばれることによる `SIGTRAP` クラッシュを完全に解消し、リリースビルドを含む全環境で安定常駐を維持する

**Independent Test**: `InstalledAppServiceTests` で `launchApplication(_:)` が対象バンドル URL と `activates == true` な起動構成を渡してクラッシュせず起動要求を発行できること、および `./scripts/build-app.sh release` の出力バイナリに `launchApplication` の完了クロージャシンボルが存在しないことを確認できる

### Tests for User Story 1

> **NOTE: 起動要求パラメータ検証テストを先行記述し、リグレッションを防止する**

- [X] T004 [P] [US1] `Tests/WintchCoreTests/InstalledAppServiceTests.swift` に、`InstalledAppService.launchApplication(_:)` が指定した `LaunchableApp.bundleURL` と `activates == true` を設定した `NSWorkspace.OpenConfiguration` を用いて起動要求を発行することを検証するユニットテストを追加する

### Implementation for User Story 1

- [X] T005 [US1] `Sources/WintchCore/Services/InstalledAppService.swift` の `launchApplication(_:)` を更新し、`NSWorkspace.shared.openApplication(at:configuration:completionHandler:)` の空クロージャ `{ _, _ in }` を廃止して `completionHandler: nil` を渡すように修正するとともに、既定値 `nil` の任意テスト用起動ハンドラ注入に対応し、日本語ドキュメントコメント・インラインコメントを整備する（T004 に依存）

**Checkpoint**: User Story 1（MVP）が完結し、ランチャーからのアプリ起動直後に Wintch がクラッシュ終了しなくなる

---

## Phase 4: User Story 2 - ローカル開発用ビルドを「Wintch_dev」として配布版と明確に区別する (Priority: P2)

**Goal**: ローカル開発ビルド（`debug`）で生成・起動したアプリをバンドルファイル名・実行プロセス名・OS 権限一覧・メニューバー・「〜について」・設定画面タイトルのすべてにおいて「`Wintch_dev`」として識別可能にし、リリースビルド（`release`）では従来通り「`Wintch`」を維持する

**Independent Test**: `./scripts/build-app.sh` で `.build/Wintch_dev.app`（`CFBundleDisplayName` / `CFBundleName` / `CFBundleExecutable` = `"Wintch_dev"`, `CFBundleIdentifier` = `"dev.wintch.Wintch.dev"`）が生成され、`./scripts/build-app.sh release` で `.build/Wintch.app`（`"Wintch"`, `"dev.wintch.Wintch"`）が生成されること、および全 UI コンポーネントが `AppIdentity` の表示名を描画することを確認できる

### Implementation for User Story 2

- [X] T006 [P] [US2] `Sources/WintchCore/Views/AboutView.swift` を更新し、`appIdentity: AppIdentity = .current` 引数を追加して見出しの固定文字列 `"Wintch"` を `appIdentity.displayName` へ置き換える（T003 に依存）
- [X] T007 [P] [US2] `Sources/WintchCore/Views/PermissionGuideView.swift` を更新し、`appIdentity: AppIdentity = .current` 引数を追加して手順 2 の固定文字列 `"2. 一覧の「Wintch」のスイッチをオンにします"` を `appIdentity.accessibilitySwitchInstruction` へ置き換える（T003 に依存）
- [X] T008 [US2] `Sources/WintchCore/App/AppCoordinator.swift` を更新し、`public let appIdentity: AppIdentity`（既定値 `.current`）を保持して、設定ウィンドウタイトル（`appIdentity.settingsWindowTitle`）、About ウィンドウタイトル（`appIdentity.aboutMenuTitle`）、権限誘導ウィンドウタイトル（`appIdentity.permissionGuideWindowTitle`）および `AboutView` / `PermissionGuideView` の初期化へ `appIdentity` を渡すよう変更する（T003, T006, T007 に依存）
- [X] T009 [P] [US2] `Sources/Wintch/WintchApp.swift` を更新し、`appDelegate.coordinator.appIdentity` を用いてメニューバー項目 `"Wintchについて"` と `"Wintch を終了"` をそれぞれ `aboutMenuTitle` と `quitMenuTitle` に動的化する（T008 に依存）
- [X] T010 [P] [US2] `scripts/build-app.sh` を更新し、`CONFIGURATION=debug`（既定）時はバンドル名・実行ファイル名・表示名を `Wintch_dev`、出力バンドルを `.build/Wintch_dev.app`、バンドル内 `Info.plist` の `CFBundleExecutable`・`CFBundleName`・`CFBundleDisplayName` を `Wintch_dev`、`CFBundleIdentifier` を `dev.wintch.Wintch.dev` に設定し、`CONFIGURATION=release` 時は従来通り `Wintch`（`.build/Wintch.app`、`dev.wintch.Wintch`）を生成するよう拡張する（`Resources/Info.plist` 本体は無変更を維持）

**Checkpoint**: User Story 2 が完結し、ローカル開発版が `Wintch_dev` として完全に識別でき、リリースビルドとの切替が動作する

---

## Phase 5: User Story 3 - 配布版とローカル開発版の共存時における動作と自己除外の整合性を保つ (Priority: P3)

**Goal**: 同一端末上に配布版（`Wintch`）とローカル開発版（`Wintch_dev`）が共存する環境でも、開発版ランチャーの自己除外・コーディネーターの識別情報管理が混線せず独立して機能することをテストで保証する

**Independent Test**: `InstalledAppServiceTests` および `AppCoordinatorTests` により、開発版識別子 `dev.wintch.Wintch.dev` と配布版識別子 `dev.wintch.Wintch` が共存するディレクトリ走査で自分自身のみが除外されること、および `AppCoordinator` に開発版/配布版の `AppIdentity` を注入して正しく保持・参照できることを検証できる

### Tests for User Story 3

- [X] T011 [P] [US3] `Tests/WintchCoreTests/InstalledAppServiceTests.swift` に、開発版（`Wintch_dev.app`, `dev.wintch.Wintch.dev`）と配布版（`Wintch.app`, `dev.wintch.Wintch`）が共存する環境を模擬し、`excludedBundleIdentifier` に一致する自分自身のみが検索候補から除外されることを検証するテストを追加する（T005 に依存）
- [X] T012 [P] [US3] `Tests/WintchCoreTests/AppCoordinatorTests.swift` に、開発版と配布版それぞれの `AppIdentity` を渡した `AppCoordinator` が対応する `appIdentity`（表示名・タイトル群・`isDevelopment`）を保持することを検証するテストを追加する（T008 に依存）

**Checkpoint**: 全 User Stories（US1, US2, US3）が独立して検証・テスト合格する

---

## Phase 6: Polish & Cross-Cutting Concerns（規約確認・最終テスト・ビルド検証）

**Purpose**: 憲章・日本語コメント規約レビュー、全ユニットテスト実行、および開発版／リリース版両方の `.app` バンドル・バイナリ検証を完了する

- [X] T013 変更した全 Swift ファイル（`Sources/WintchCore/Domain/AppIdentity.swift`, `Sources/WintchCore/Services/InstalledAppService.swift`, `Sources/WintchCore/App/AppCoordinator.swift`, `Sources/WintchCore/Views/AboutView.swift`, `Sources/WintchCore/Views/PermissionGuideView.swift`, `Sources/Wintch/WintchApp.swift`, `Tests/WintchCoreTests/*.swift`）および `scripts/build-app.sh` について、日本語ドキュメントコメント（`///`）・日本語インラインコメント・憲章遵守（外部依存ゼロ・非公開 API 不使用・画面収録権限不使用・コード重複なし）および `Resources/Info.plist` が未変更であることを確認する（T005, T009, T010, T011, T012 完了後）
- [X] T014 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行し、新規テストを含む全ユニットテストが 100% 合格することを確認する（T013 完了後）
- [X] T015 `specs/011-fix-app-launch-dev-name/quickstart.md` に従い、`./scripts/build-app.sh` で `.build/Wintch_dev.app` のメタデータ検証、および `./scripts/build-app.sh release` で `.build/Wintch.app` のメタデータと `nm -n` による `launchApplication` 完了クロージャシンボル不在確認を実施する（T014 完了後）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし — 即座に開始可能（`T001`）
- **Foundational (Phase 2)**: Phase 1 完了後 — `T002` → `T003` の順で実装（`US2`・`US3` の前提）
- **User Story 1 (Phase 3 - MVP)**: Phase 1 完了後に開始可能 — `T004` → `T005`（`US2`・`US3` と独立しているため並列実行も可能）
- **User Story 2 (Phase 4)**: Phase 2 完了後に開始可能 — `T006`, `T007`, `T010` は並列実行可能、その後 `T008` → `T009`
- **User Story 3 (Phase 5)**: `T005`・`T008` 完了後 — `T011`, `T012` は並列実行可能
- **Polish (Phase 6)**: Phase 3〜5 完了後 — `T013` → `T014` → `T015`

### User Story Dependencies

- **User Story 1 (P1)**: `InstalledAppService.swift` のみに閉じるため、`AppIdentity` 実装（Phase 2）に依存せず単独で実装・検証可能。
- **User Story 2 (P2)**: Phase 2（`T003` `AppIdentity`）完了後に開始可能。`T010`（`scripts/build-app.sh`）は独立ファイルのため並行可能。
- **User Story 3 (P3)**: `T005`（`InstalledAppService`）および `T008`（`AppCoordinator`）の完了後に統合検証テストとして実施。

### Parallel Opportunities

- Phase 3（`T004`→`T005`）と Phase 2（`T002`→`T003`）は扱うファイルが重複しないため並列進行可能。
- Phase 4 内の `T006`（`AboutView.swift`）、`T007`（`PermissionGuideView.swift`）、`T010`（`scripts/build-app.sh`）は互いに独立ファイルのため並列実行可能。
- Phase 5 の `T011`（`InstalledAppServiceTests.swift`）と `T012`（`AppCoordinatorTests.swift`）は独立ファイルのため並列実行可能。

```bash
# Phase 4 の並列タスク例:
Task: "T006 [P] [US2] AboutView.swift のアプリ名を AppIdentity 由来に更新"
Task: "T007 [P] [US2] PermissionGuideView.swift の手順文言を AppIdentity 由来に更新"
Task: "T010 [P] [US2] scripts/build-app.sh の debug 時 Wintch_dev 出力対応"
```

---

## Implementation Strategy

### MVP First (Phase 1 → Phase 3: US1)

1. Phase 1 でベースラインテスト合格を確認する（`T001`）。
2. Phase 3（User Story 1）で `InstalledAppService.launchApplication(_:)` のクラッシュ修正とテストを実施し、最優先不具合を解消する（`T004` → `T005`）。

### Incremental Delivery

3. Phase 2 で `AppIdentity` ドメインモデルと単体テストを構築する（`T002` → `T003`）。
4. Phase 4（User Story 2）で UI 全箇所（`AboutView` / `PermissionGuideView` / `AppCoordinator` / `WintchApp`）および `scripts/build-app.sh` の `Wintch_dev` 対応を実装する（`T006`〜`T010`）。
5. Phase 5（User Story 3）で開発版・配布版共存時のテストを拡充する（`T011`〜`T012`）。
6. Phase 6 で日本語コメント・憲章レビュー、`swift test`、および `Wintch_dev.app` / `Wintch.app` 両バンドルのビルド検証を完了する（`T013`〜`T015`）。
