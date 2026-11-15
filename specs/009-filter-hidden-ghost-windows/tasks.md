---

description: "Task list for 009-filter-hidden-ghost-windows"
---

# Tasks: メモ等の非表示内部補助ウィンドウによる重複・ゴースト表示の除外

**Input**: Design documents from `/specs/009-filter-hidden-ghost-windows/`  
**Prerequisites**: `plan.md`（必須）, `spec.md`（必須）, `research.md`, `data-model.md`, `contracts/window-filtering-contracts.md`, `quickstart.md`

**Tests**: 本機能は憲章（ユニットテスト可能性の維持）および `quickstart.md` に従い、基盤プロファイルテストおよび各ユーザーストーリーの単体テストタスクを含める。

**Organization**: 共通基盤となる宣言的プロファイル構造（`AppWindowProfile.swift`）を Phase 2 で構築した上で、各ユーザーストーリー（`US1`, `US2`, `US3`）ごとにテストと統合検証を整理している。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 依存関係がなく別ファイルを扱うため並列実行可能なタスク
- **[Story]**: 対応するユーザーストーリー（`US1`, `US2`, `US3`）。Setup / Foundational / Polish フェーズには付与しない
- すべてのタスクに正確なファイルパスと制約を明記している

## Path Conventions

- ソースコード: `Sources/WintchCore/`
- ユニットテスト: `Tests/WintchCoreTests/`
- 仕様ドキュメント: `specs/009-filter-hidden-ghost-windows/`

---

## Phase 1: Setup（ベースライン確認）

**Purpose**: 既存ビルドおよび全ユニットテストのベースライン状態を確認する

- [X] T001 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行し、`Package.swift` および `Tests/WintchCoreTests/` の現状テストベースラインが全件合格することを確認する

---

## Phase 2: Foundational（アプリ別ウィンドウプロファイル基盤の構築）

**Purpose**: 個別アプリ特例の増加に耐える宣言的プロファイル／レジストリ構造を `Domain/` 層に新設し、既存のハードコードされた個別判定を統一パイプラインへ置き換える土台を作る

**⚠️ CRITICAL**: すべてのユーザーストーリーは `AppWindowProfileRegistry` および統一化された `WindowFilter` に依存するため、Phase 2 完了後に各ストーリー検証へ進む

- [X] T002 `Tests/WintchCoreTests/AppWindowProfileTests.swift` を新規作成し、`AppWindowProfileRegistry.profile(for:)` の既定プロファイルフォールバック（未登録または `nil` で `.allow`・空シグネチャ配列）、登録済みアプリ（`com.apple.systempreferences` / `com.apple.Notes`）の解決、および `HiddenBackingWindowSignature.matches(_:)` の安全ガード（`!candidate.hasAXInfo` かつ `candidate.isOnScreen != true` かつタイトル空/nil かつ幅・高さ・任意 `x ≈ 0` が `tolerance: 2.0` 以内のみ `true`、`hasAXInfo == true` / `isOnScreen == true` / 非空タイトル時は必ず `false`）を検証する単体テストを先行記述する
- [X] T003 `Sources/WintchCore/Domain/AppWindowProfile.swift` を新規作成し、`OffscreenCGFallbackPolicy`（`.allow` / `.singleRepresentativeOnly` / `.requireAXOrMenuTitle`）、`HiddenBackingWindowSignature`（`width`, `height`, `requiresZeroOriginX`, `tolerance = 2.0`, 誤除外防止ガード付き `matches(_:)`）、`AppWindowProfile`（`bundleIdentifier`, `offscreenCGPolicy`, `hiddenBackingSignatures`, `rationale`）、および `AppWindowProfileRegistry`（全アプリ共通 `commonHiddenBackingSignatures` に `(width: 500, height: 500, requiresZeroOriginX: true)`、`profilesByBundleIdentifier` に `com.apple.systempreferences`（`.singleRepresentativeOnly`）と `com.apple.Notes`（`.requireAXOrMenuTitle` ＋ `HiddenBackingWindowSignature(width: 475, height: 600, requiresZeroOriginX: false)`））を日本語ドキュメントコメント・インラインコメント付きで実装する（T002 に依存）
- [X] T004 `Sources/WintchCore/Domain/WindowFilter.swift` をリファクタリングし、ハードコードされていた `systemPreferencesBundleID` / `singleWindowBundleIdentifiers` / `isHiddenSystemSettingsBackingWindow` を削除して、`passesCommonGuards(_:)` では `AppWindowProfileRegistry.isHiddenBackingWindow(_:)` を、`filterAndMap(_:screenBounds:)` では `AppWindowProfileRegistry.profile(for:)` の `offscreenCGPolicy`（`.allow` / `.singleRepresentativeOnly` / `.requireAXOrMenuTitle`）を参照する統一ロジックへ統合する（T003 に依存）

**Checkpoint**: `AppWindowProfileTests` および既存の `WindowFilterTests`（`systemSettingsExcludesHiddenBackingWindowInAllStates` 等）が合格し、基盤プロファイル構造が機能する状態になる

---

## Phase 3: User Story 1 - 単一ウィンドウのみ開いているアプリで実ウィンドウ1件だけを表示する (Priority: P1) 🎯 MVP

**Goal**: Mac 標準「メモ」アプリ等で 1 枚しかウィンドウを開いていないとき（同スペース・別スペース双方）、通常スイッチャー（リスト型・キャプチャ表示型）と検索ランチャーの両方で実ウィンドウ 1 件のみが表示され、「(タイトルなし)」の重複表示およびウィンドウ終了時の複数枚誤判定が起きないことを保証する

**Independent Test**: `WindowFilterTests` と `SwitcherViewModelTests` で、メモアプリ（`com.apple.Notes`）の AX 実ウィンドウ 1 件＋`475x600` 補助窓＋`500x500` バックキング窓が混在する入力に対し、フィルタ結果およびスイッチャー／ランチャーの表示一覧が 1 件のみとなり、閉じる操作で単一ウィンドウ終了（`terminateApplication`）が選ばれることを独立して検証できる

### Tests for User Story 1

> **NOTE: 対象テストを追加し、期待される挙動が検証できる状態にする**

- [X] T005 [P] [US1] `Tests/WintchCoreTests/WindowFilterTests.swift` に、メモアプリ（`com.apple.Notes`）で AX 実ウィンドウ 1 件（`1157x1046`）に加えて `475x600`（`isOnScreen: false, title: nil`）と `500x500`（`x: 0, isOnScreen: false, title: nil`）およびその他のタイトルなし画面外 `cg-*` が混在しても実ウィンドウ 1 件のみが返ること（現在スペース・別スペース双方）を検証するテストを追加する
- [X] T006 [P] [US1] `Tests/WintchCoreTests/SwitcherViewModelTests.swift` に、メモアプリの 1 実ウィンドウ＋非表示裏方 `cg-*` 候補が存在する状態で通常スイッチャー（リスト型・キャプチャ表示型）および検索ランチャーを起動した際に双方の表示件数が実ウィンドウ 1 件のみになり、選択中ウィンドウを閉じる操作で `terminateApplication` が呼ばれることを検証する統合テストを追加する

### Implementation verification for User Story 1

- [X] T007 [US1] `Sources/WintchCore/Services/WindowService.swift` の `enrichCandidatesWithWindowMenu(_:)` と `Sources/WintchCore/Domain/WindowFilter.swift` の `isValid(_:)` / `filterAndMap(_:screenBounds:)` の呼び出し順序整合を確認し、メニュー補完前の `isValid` で既知ノイズ（`500x500`・`475x600`）を除外しつつ `.requireAXOrMenuTitle` 判定はメニュー補完後の `filterAndMap` で適用されることを検証して `WindowFilterTests` / `SwitcherViewModelTests` を合格させる（T004, T005, T006 に依存）

**Checkpoint**: User Story 1（MVP）が完結し、メモアプリ 1 ウィンドウ時のスイッチャー・ランチャー重複表示および終了判定誤動作が解消される

---

## Phase 4: User Story 2 - ウィンドウをすべて閉じている待機中アプリの非表示補助ウィンドウを表示しない (Priority: P2)

**Goal**: ウィンドウを 1 枚も開いていない待機中アプリ（Gemini、全閉後のメモ、システム設定等）の画面外裏方ウィンドウが「(タイトルなし)」として一覧に紛れ込まないことを保証する

**Independent Test**: `WindowFilterTests` で、実ウィンドウ 0 件かつ `x ≈ 0, 500x500` やメモの `475x600` 等の未表示 `cg-*` のみを保持するアプリ入力に対し、フィルタ出力が空配列 `[]` となることを独立して検証できる

### Tests & Verification for User Story 2

- [X] T008 [P] [US2] `Tests/WintchCoreTests/WindowFilterTests.swift` に、ウィンドウ全閉後のメモアプリ（`com.apple.Notes` で `475x600` と `500x500` のみ残存）およびウィンドウ未表示の Gemini（`com.google.GeminiMacOS` で `x: 0, 500x500` のみ残存）や汎用アプリ（`x: 0, 500x500, title: nil, isOnScreen: false` のみ残存）がすべて 0 件として除外され、かつ Gemini の `isOnScreen: true` 実チャットウィンドウ救済テスト（`onScreenFallbackRescuesUncoveredAppWithoutLeakingCoveredOverlays`）が引き続き通過することを検証するテストを追加する
- [X] T009 [US2] `Tests/WintchCoreTests/SwitcherViewModelTests.swift` に、待機中アプリ（実ウィンドウ 0 件）のゴースト候補が除外された状態で検索ランチャーを起動・検索した際、「(タイトルなし)」ウィンドウではなくアプリ起動候補（`displayedAppResults`）として適切に扱われることを検証するテストを追加する（T004, T008 に依存）

**Checkpoint**: User Stories 1 と 2 の双方が独立して機能・テスト合格する

---

## Phase 5: User Story 3 - 実在する複数ウィンドウや別操作スペースのウィンドウ表示を維持する (Priority: P2)

**Goal**: ノイズ除外の強化によって、メモアプリで複数開いた実ウィンドウ・タイトル空のユーザー実ウィンドウ・別操作スペースの一般アプリ実ウィンドウが誤って除外されないことを保証する

**Independent Test**: `WindowFilterTests` で、メモアプリの複数 AX 実ウィンドウ／メニュータイトル付き `cg-*` ウィンドウ・偶然 `x: 0, 500x500` でユーザーが実際に開いているタイトルあり/AX 捕捉済み/`isOnScreen: true` ウィンドウ・既存他アプリ（Chrome / VS Code / Finder / Terminal / WezTerm）の別スペースウィンドウが 100% 保持されることを検証できる

### Tests & Verification for User Story 3

- [X] T010 [P] [US3] `Tests/WintchCoreTests/WindowFilterTests.swift` に、メモアプリで複数実ウィンドウ（複数 `hasAXInfo == true` 候補、またはメニュー補完によりタイトルが付与された画面外 `cg-*` 候補）が開かれている場合に全実ウィンドウが保持されること、およびユーザーが意図的に開いている空タイトルの標準 AX ウィンドウ（`hasAXInfo: true, title: ""`）や偶然 `x: 0, 500x500` に配置された `hasAXInfo: true` / `isOnScreen: true` ウィンドウが誤除外されないことを検証するテストを追加する
- [X] T011 [US3] `Tests/WintchCoreTests/WindowMenuPairingTests.swift` と `Tests/WintchCoreTests/WindowFilterTests.swift` を通しで実行し、別スペースの Chrome / VS Code / Finder / WezTerm / Terminal の既存テストに一切の退行がないことを確認する（T004, T010 に依存）

**Checkpoint**: 全ユーザーストーリー（US1, US2, US3）が相互に退行なく独立検証可能な状態になる

---

## Phase 6: Polish & Cross-Cutting Concerns（規約確認・全体テスト・実機検証）

**Purpose**: コーディング規約（日本語コメント・ドキュメントコメント・憲章準拠）の最終確認、全自動テスト実行、および `.app` 実機確認を実施する

- [X] T012 `Sources/WintchCore/Domain/AppWindowProfile.swift` および `Sources/WintchCore/Domain/WindowFilter.swift` 内のすべての型・メソッド・インラインコメントが日本語で記述され、不要な重複コードや憲章違反（外部依存・非公開 API・画面収録権限の無断使用）がないことをレビュー確認する
- [X] T013 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行し、全ユニットテストスイートの 100% 合格を確認する（T007, T009, T011, T012 完了後）
- [ ] T014 `specs/009-filter-hidden-ghost-windows/quickstart.md` に従い `./scripts/build-app.sh` で `.build/Wintch.app` をビルドし、メモアプリ 1 ウィンドウ／複数ウィンドウ／全閉状態および Gemini 等待機中アプリの動作をスイッチャー・ランチャー双方で最終確認する（T013 完了後 ※ `.build/Wintch.app` のビルドは完了済み、GUI 実機確認はユーザー操作で実施）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし — 即座に開始可能
- **Foundational (Phase 2)**: Phase 1 完了後 — `T002` → `T003` → `T004` の順で実装（全ストーリーの前提）
- **User Story 1 (Phase 3)**: Phase 2 完了後 — `T005`・`T006` は並列作成可能 → `T007` で結合検証
- **User Story 2 (Phase 4)**: Phase 2 完了後 — `T008`・`T009` で検証（US1 と並列または直列で実施可能）
- **User Story 3 (Phase 5)**: Phase 2 完了後 — `T010` → `T011` で退行検証
- **Polish (Phase 6)**: Phase 3〜5 完了後 — `T012` → `T013` → `T014`

### Parallel Opportunities

- Phase 3 の `T005`（`WindowFilterTests.swift`）と `T006`（`SwitcherViewModelTests.swift`）は別ファイルのため並列実行可能。
- Phase 4（`US2`）と Phase 5（`US3`）はそれぞれ別テスト観点を扱うため、Phase 2 完了後に並行または順次進めても競合しにくい（ただし `WindowFilterTests.swift` を共有するため編集は直列推奨）。

```bash
# Phase 3 (US1) の並列テスト作成例:
Task: "T005 [P] [US1] Tests/WintchCoreTests/WindowFilterTests.swift にメモ1ウィンドウ重複除外テスト追加"
Task: "T006 [P] [US1] Tests/WintchCoreTests/SwitcherViewModelTests.swift にスイッチャー/ランチャー統合テスト追加"
```

---

## Implementation Strategy

### MVP First (Phase 1 → Phase 2 → Phase 3: US1)

1. Phase 1 でベースラインテスト合格を確認する。
2. Phase 2 で `AppWindowProfile.swift`（宣言的プロファイル＆レジストリ）と `WindowFilter.swift` 統合を実装し、`AppWindowProfileTests` と既存 `WindowFilterTests` を通す。
3. Phase 3（User Story 1）でメモアプリ 1 ウィンドウ時のスイッチャー／ランチャー重複解消とウィンドウ終了判定の正確性を単体・統合テストで確定する。

### Incremental Delivery

4. Phase 4（User Story 2）で Gemini や全閉後メモ等の待機中アプリゴースト除外とランチャーアプリ起動候補表示を確認する。
5. Phase 5（User Story 3）でメモ複数ウィンドウや他アプリ別スペース実ウィンドウの非退行を保証する。
6. Phase 6 で日本語コメント規約確認・全 `swift test` 合格・`.app` ビルド検証を完了する。
