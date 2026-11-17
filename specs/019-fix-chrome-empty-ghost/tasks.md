---

description: "Chrome等のタブ全閉によるウィンドウ閉鎖後に空の表示が残る問題の修正 タスク一覧"
---

# Tasks: Chrome等のタブ全閉によるウィンドウ閉鎖後に空の表示が残る問題の修正

**Input**: Design documents from `/specs/019-fix-chrome-empty-ghost/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: 機能仕様（SC-004）およびプロジェクト憲章（テスト可能性規約）に基づき、各ユーザーストーリーの単体テストタスクを含める。

**Organization**: ユーザーストーリー単位（US1, US2, US3）でフェーズを分割し、独立して実装・検証可能な構成とする。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 異なるファイルかつ未完了タスクへの依存がなく並列実行可能
- **[Story]**: 対応するユーザーストーリー（US1, US2, US3）
- すべてのタスク説明に対象ファイルパスを明記

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 作業ブランチ環境および既存コードベース構造の確認

- [x] T001 実装計画に基づき対象ファイル（`Sources/WintchCore/Domain/AppWindowProfile.swift`, `Sources/WintchCore/Domain/WindowMenuPairing.swift`, `Sources/WintchCore/Services/WindowService.swift`）の現行実装を確認する

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 全ユーザーストーリーで共有するプロファイル定義および純粋判定ヘルパーの基盤整備

**⚠️ CRITICAL**: ユーザーストーリーの実装前に完了させる

- [x] T002 `Sources/WintchCore/Domain/AppWindowProfile.swift` の `AppWindowProfileRegistry.profilesByBundleIdentifier` に `"com.google.Chrome"`（`offscreenCGPolicy: .requireAXOrMenuTitle`）を追加する
- [x] T003 `Sources/WintchCore/Services/WindowService.swift` に閉鎖済み `CachedAXWindow` 保持判定の純粋静的メソッド `shouldRetainCachedAXWindow(isPresentInLatestAXScan:knownCGWindowID:axRoleCheckResult:survivingCGWindowIDs:hasSubstantialCGWindow:)` を実装し、`cleanupClosedWindows` から呼び出すよう更新する

**Checkpoint**: ドメインプロファイルとサービス層のキャッシュ生存判定基盤が完了

---

## Phase 3: User Story 1 - タブをすべて閉じてウィンドウを閉じた待機中ブラウザの空表示を残さない (Priority: P1) 🎯 MVP

**Goal**: Google Chrome のすべてのタブ・ウィンドウを閉じた（アプリ未終了）際に、画面外の無名空き殻 `CGWindow` や古いメニューキャッシュによって空のウィンドウ表示（真っ白なプレビューや `Google Chrome (タイトルなし)`）が残らないようにする。

**Independent Test**: Chrome の全ウィンドウ閉鎖状態（直後の 2 秒以内を含む）を模した候補データおよびキャッシュ状態に対し、フィルタリング結果が 0 件になることを単体テストで検証できる。

### Implementation for User Story 1

- [x] T004 [US1] `Sources/WintchCore/Services/WindowService.swift` の `handleAXNotification`（`kAXUIElementDestroyedNotification` 受信時）および `applyAXWindowSnapshots`（スナップショット空化またはスキャン不在要素発生時）において `cachedWindowMenuByPID.removeValue(forKey: pid)` を呼び出し、ウィンドウ閉鎖時の古いメニューキャッシュを即時無効化する
- [x] T005 [P] [US1] `Tests/WintchCoreTests/AppWindowProfileTests.swift` に `"com.google.Chrome"` のプロファイル解決テスト（`offscreenCGPolicy == .requireAXOrMenuTitle`）を追加する
- [x] T006 [P] [US1] `Tests/WintchCoreTests/WindowFilterTests.swift` に Chrome のタブ・ウィンドウ全閉後に残存する無名空き殻 `CGWindow`（`1920x1042` 純白窓および `1344x378` 予測変換窓）がすべて除外されて 0 件になることを検証するテストを追加する

**Checkpoint**: User Story 1（全ウィンドウ閉鎖時の空表示除外）が独立して動作・検証可能

---

## Phase 4: User Story 2 - 複数ウィンドウのうち1枚のタブをすべて閉じた際に閉じた側の空表示を残さない (Priority: P1)

**Goal**: 複数ウィンドウのうち 1 枚のタブをすべて閉じて閉じた際、対応する `cgWindowID` を失った古い `CachedAXWindow` が裏方の無名空き殻 `CGWindow` に乗り換えて残留することを防ぎ、開いている実ウィンドウのみを表示する。

**Independent Test**: 閉鎖されて `survivingCGWindowIDs` から消滅した `knownCGWindowID` を持つ非現在スキャン要素が `shouldRetainCachedAXWindow` で破棄され、生存している別スペースウィンドウのみが保持されることを単体テストで検証できる。

### Implementation for User Story 2

- [x] T007 [P] [US2] `Tests/WintchCoreTests/WindowCaptureAndMatchingTests.swift` に `WindowService.shouldRetainCachedAXWindow` の単体テスト（最新スキャン不在かつ `knownCGWindowID` 消滅時の即時破棄、別スペース生存時の保持、`.cannotComplete` 時の非延命）を追加する
- [x] T008 [P] [US2] `Tests/WintchCoreTests/WindowFilterTests.swift` に Chrome で複数ウィンドウのうち 1 枚を閉じた状態（残存実ウィンドウ 1 枚＋無名空き殻 `CGWindow` 混在）で実ウィンドウ 1 件のみが返されることを検証するテストを追加する

**Checkpoint**: User Story 1 および User Story 2 がともに独立して動作・検証可能

---

## Phase 5: User Story 3 - 別スペースや「新しいタブ」を含む実在ウィンドウの正確なタイトル表示と切り替えを維持する (Priority: P2)

**Goal**: 別操作スペースやフルスクリーンで「新しいタブ」等を開いている実 `AXWindow` で一時的に `kAXTitleAttribute` が空文字列を返す場合でも、メニュー項目や `cgWindowName` からタイトルを補完して `(タイトルなし)` 化を防ぎ、選択時に別スペース遷移を確実に実行する。

**Independent Test**: 未マッチ `cg-*` 候補が存在しない状態でタイトルが空の標準 `AXWindow` に対して `needsMenuEnrichment` と `applyMenuTitles` がタイトルを補完すること、および別スペース上の `kAXFocusedWindow` 補完ウィンドウに対して `isWindowInCurrentSpace` が `false` を返すことを単体テストで検証できる。

### Implementation for User Story 3

- [x] T009 [P] [US3] `Sources/WintchCore/Domain/WindowMenuPairing.swift` に `WindowMenuCandidatePairing.needsMenuEnrichment(_:)` を追加し、かつ `applyMenuTitles(to:menuItems:)` で `menuItems` が空の場合でも空タイトルの標準 AX 候補へ非空の `cgWindowName` を補完するよう拡張する
- [x] T010 [US3] `Sources/WintchCore/Services/WindowService.swift` の `enrichCandidatesWithWindowMenu` で `WindowMenuCandidatePairing.needsMenuEnrichment` を用いて対象 PID を抽出し、メニュー項目が空の場合でも `applyMenuTitles` による `cgWindowName` 補完を通すよう更新する
- [x] T011 [US3] `Sources/WintchCore/Services/WindowService.swift` に `isWindowInCurrentSpace(isPresentInLatestAXScan:isOnScreen:isMinimized:)` を実装し、`activateWindow` で画面外（`isOnScreen == false && !isMinimized`）のウィンドウを現在スペース不在として扱いメニュー遷移・段階的フォローアップを実行するよう更新する
- [x] T012 [P] [US3] `Tests/WintchCoreTests/WindowMenuPairingTests.swift` に `needsMenuEnrichment`（空タイトル標準 AX 候補の検知）および `menuItems` 空時の `cgWindowName` 補完テストを追加する
- [x] T013 [P] [US3] `Tests/WintchCoreTests/WindowCaptureAndMatchingTests.swift` に `WindowService.isWindowInCurrentSpace` の単体テスト（別スペース上の `isOnScreen == false` かつ非最小化ウィンドウで `false` を返すこと等）を追加する

**Checkpoint**: 全ユーザーストーリー（US1, US2, US3）が独立して機能しテストで検証可能

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: 全体テスト・アプリバンドルビルド検証・ドキュメント整合性の最終確認

- [x] T014 `swift test` を実行し、既存の全テストおよび新規追加テストがすべてパスすることを検証する
- [x] T015 `./scripts/build-app.sh` を実行し、`.app` バンドルのビルドとアドホック署名が正常に完了することを検証する

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし
- **Foundational (Phase 2)**: Phase 1 完了後に実行（T002, T003）
- **User Stories (Phase 3〜5)**: Phase 2 完了後に優先度順（US1 → US2 → US3）または並列で進行可能
- **Polish (Phase 6)**: 全ユーザーストーリー完了後に実行（T014, T015）

### User Story Dependencies

- **User Story 1 (P1)**: Phase 2（T002, T003）完了後に開始可能
- **User Story 2 (P1)**: Phase 2（T002, T003）完了後に開始可能
- **User Story 3 (P2)**: Phase 2 完了後に開始可能（T009 → T010, T011 → T012, T013）

### Parallel Opportunities

- T005, T006（US1 テスト）は異なるテストファイルのため並列実行可能
- T007, T008（US2 テスト）は異なるテストファイルのため並列実行可能
- T012, T013（US3 テスト）は異なるテストファイルのため並列実行可能

---

## Parallel Example: User Story 1 & 3

```bash
# User Story 1 のテスト実装を並列実行:
Task: "T005 [P] [US1] Tests/WintchCoreTests/AppWindowProfileTests.swift に Chrome プロファイル解決テストを追加"
Task: "T006 [P] [US1] Tests/WintchCoreTests/WindowFilterTests.swift に Chrome 全閉時の除外テストを追加"

# User Story 3 のテスト実装を並列実行:
Task: "T012 [P] [US3] Tests/WintchCoreTests/WindowMenuPairingTests.swift に needsMenuEnrichment テストを追加"
Task: "T013 [P] [US3] Tests/WintchCoreTests/WindowCaptureAndMatchingTests.swift に isWindowInCurrentSpace テストを追加"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Phase 1 & Phase 2（`com.google.Chrome` プロファイル登録＋`shouldRetainCachedAXWindow` 実装）を完了する
2. Phase 3（US1：メニューキャッシュ即時無効化＋単体テスト）を完了し、Chrome 全閉時の空表示が残らないことを検証する

### Incremental Delivery

1. Phase 1 + Phase 2 → 基盤完成
2. Phase 3 (US1) → 全閉時のゴースト除外完成
3. Phase 4 (US2) → 複数ウィンドウ一部閉鎖時のゾンビ乗り換え防止完成
4. Phase 5 (US3) → 別スペース「新しいタブ」等のタイトル補完・遷移精度向上完成
5. Phase 6 (Polish) → 全テスト＆アプリビルド検証完了
