# Tasks: メニューバーから開く設定画面等の最前面表示修正

**Input**: Design documents from `/specs/015-fix-settings-frontmost/`
**Prerequisites**: [plan.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/015-fix-settings-frontmost/plan.md)（必須）, [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/015-fix-settings-frontmost/spec.md)（必須）, [research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/015-fix-settings-frontmost/research.md), [data-model.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/015-fix-settings-frontmost/data-model.md), [window-presentation-contracts.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/015-fix-settings-frontmost/contracts/window-presentation-contracts.md)

**Tests**: テスト駆動および `AppCoordinatorTests`・`WindowFrontPresenterTests` による検証を含める。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 異なるファイルへの作業であり、未完了タスクへの依存がなく並列実行可能
- **[Story]**: 対応するユーザーストーリー（`[US1]`, `[US2]`, `[US3]`）
- 説明には対象ファイルの正確なパスを含める

---

## Phase 1: Setup（事前確認）

**Purpose**: 既存テストおよびビルド環境の健全性を確認する

- [x] T001 既存ユニットテストを実行しベースラインの通過を確認する（`Tests/WintchCoreTests/`）

---

## Phase 2: Foundational（共通基盤：配置計算・前面表示サービス契約）

**Purpose**: 全標準ウィンドウ（設定画面・「Wintchについて」画面・権限誘導画面）の最前面表示を支えるドメイン計算およびサービスプロトコルを整備する

**⚠️ CRITICAL**: ユーザーストーリーの実装は本フェーズ完了後に開始する

- [x] T002 [P] アクティブディスプレイ判定および中央配置座標計算の純粋モデルを実装する（`Sources/WintchCore/Domain/WindowPlacement.swift`）
- [x] T003 [P] 標準ウィンドウ最前面表示プロトコルを定義する（`Sources/WintchCore/Services/Protocols/WindowFrontPresenting.swift`）
- [x] T004 [P] テスト用モック `MockWindowFrontPresenter` を追加する（`Tests/WintchCoreTests/Mocks/MockServices.swift`）
- [x] T005 AppKit による最前面表示・強制アクティブ化・スペース移動・次ランループ再前面化を実装する（`Sources/WintchCore/Services/WindowFrontPresenter.swift`）

**Checkpoint**: 基盤となる配置計算・前面表示サービスおよびモックが揃った状態

---

## Phase 3: User Story 1 - 他アプリ作業中でもメニューバーから設定画面を一番手前に開ける (Priority: P1) 🎯 MVP

**Goal**: 他アプリが前面でアクティブな状態からメニューバーで「設定を開く...」を実行した際、設定画面を現在のスペース・ディスプレイ中央の一番手前へキーウィンドウとして表示し、表示後は通常ウィンドウレベルを保つ

**Independent Test**: `WindowPlacement`・`WindowFrontPresenter` の単体テストおよび `AppCoordinator.openSettings()` が `WindowFrontPresenting.presentFrontmost(_:)` を通じて設定ウィンドウを最前面表示する検証が通ること

### Tests for User Story 1

- [x] T006 [P] [US1] `WindowPlacement`（単一・マルチディスプレイ・画面外クランプ）と `WindowFrontPresenter`（`.moveToActiveSpace`・最小化解除・通常レベル維持・即時および次ランループのアクティブ化／前面化・非表示時スキップ）の単体テストを作成する（`Tests/WintchCoreTests/WindowFrontPresenterTests.swift`）
- [x] T007 [P] [US1] `AppCoordinator.openSettings()` の初回表示・状態更新・同一ウィンドウ再利用での前面表示委譲テストを追加する（`Tests/WintchCoreTests/AppCoordinatorTests.swift`）

### Implementation for User Story 1

- [x] T008 [US1] `AppCoordinator` に `WindowFrontPresenting` DI を追加し、`openSettings()` で `windowFrontPresenter.presentFrontmost(window)` を使用するよう更新する（`Sources/WintchCore/App/AppCoordinator.swift`）

**Checkpoint**: 設定画面の最前面表示と再表示・通常レベル維持が単体テストで検証可能な状態

---

## Phase 4: User Story 2 - 「Wintchについて」画面および権限誘導画面も同様に一番手前に表示される (Priority: P2)

**Goal**: `openAbout()` および `openPermissionGuide()` / `presentPermissionGuideWindow()` も共通の `WindowFrontPresenting` を経由して確実に最前面表示されるようにする

**Independent Test**: `AppCoordinatorTests` において `openAbout()`・`openPermissionGuide()`・権限剥奪検知時表示が `WindowFrontPresenting.presentFrontmost(_:)` へ委譲され、権限許可済み時は誘導画面が表示されないことを検証できること

### Tests for User Story 2

- [x] T009 [P] [US2] `AppCoordinator.openAbout()` と `openPermissionGuide()`（未許可時のみ表示／許可済み時は非表示）・権限剥奪遷移時の前面表示委譲テストを追加する（`Tests/WintchCoreTests/AppCoordinatorTests.swift`）

### Implementation for User Story 2

- [x] T010 [US2] `AppCoordinator` の `openAbout()` および `presentPermissionGuideWindow()` を `windowFrontPresenter.presentFrontmost(window)` 呼び出しへ統一する（`Sources/WintchCore/App/AppCoordinator.swift`）

**Checkpoint**: 全メニューバー起点ウィンドウが同一の前面表示経路で動作する状態

---

## Phase 5: User Story 3 - 常駐アプリとしての非侵襲性（Dock 非表示・既存動作の維持）を保つ (Priority: P2)

**Goal**: `.accessory` ポリシー（`LSUIElement = true`）および `.normal` ウィンドウレベル維持により、設定画面等の開閉で Dock アイコンが増えず、システム設定等への遷移も妨げないことを確認する

**Independent Test**: `WindowFrontPresenterTests` および `WintchApp.swift`・`Info.plist` の設定検証により、ポリシー変更や常時フローティング固定を行わないことを確認できること

- [x] T011 [US3] `WindowFrontPresenter` が `NSApplication.shared.setActivationPolicy` を変更せず、ウィンドウレベル `.normal` を維持することをテストで検証・固定する（`Tests/WintchCoreTests/WindowFrontPresenterTests.swift`）

---

## Phase 6: Polish & Cross-Cutting Concerns（仕上げと全体検証）

**Purpose**: ドキュメントコメントの日本語規約遵守、全テストおよび `.app` ビルドの最終通過確認

- [x] T012 新規・変更ファイルすべての日本語ドキュメントコメント（`///`）およびインラインコメント規約を確認する（`Sources/WintchCore/`）
- [x] T013 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` で全ユニットテストを実行し全件通過を確認する
- [x] T014 `./scripts/build-app.sh` で `.app` バンドルをビルドし、警告・エラーがないことを確認する

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: 完了済み（T001）
- **Phase 2 (Foundational)**: T002, T003, T004 は並列実行可能。T005 は T002, T003 に依存。
- **Phase 3 (US1 - MVP)**: Phase 2 完了後、T008 が `AppCoordinator` を更新し、T006・T007 で検証。
- **Phase 4 (US2)**: Phase 3 と同一ファイル `AppCoordinator.swift` / `AppCoordinatorTests.swift` を扱うため T008 後に T010, T009 を実施。
- **Phase 5 (US3)**: T005・T006 に続き T011 を確認。
- **Phase 6 (Polish)**: 全実装完了後に T012 → T013 → T014 の順で実行。

### Implementation Strategy

1. Phase 2 の基盤ファイル（`WindowPlacement.swift`, `WindowFrontPresenting.swift`, `WindowFrontPresenter.swift`, `MockServices.swift`）を構築する。
2. Phase 3〜5 で `AppCoordinator.swift` へ統合し、`WindowFrontPresenterTests.swift` および `AppCoordinatorTests.swift` を整備する。
3. Phase 6 で全ユニットテストと `./scripts/build-app.sh` を通し、`tasks.md` のチェックを完了してコミット・プッシュ・PR 作成へ進む。
