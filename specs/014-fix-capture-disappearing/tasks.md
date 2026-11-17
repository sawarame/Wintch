---

description: "Task list for preventing disappearing window thumbnails in capture switcher"
---

# Tasks: キャプチャ表示型スイッチャーにおけるサムネイル消失の防止とキャッシュ整合性改善

**Input**: Design documents from `/specs/014-fix-capture-disappearing/`
**Prerequisites**: [plan.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/014-fix-capture-disappearing/plan.md), [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/014-fix-capture-disappearing/spec.md), [research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/014-fix-capture-disappearing/research.md), [data-model.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/014-fix-capture-disappearing/data-model.md), [capture-cache-and-matching.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/014-fix-capture-disappearing/contracts/capture-cache-and-matching.md)

**Tests**: テスト駆動および品質保証のため、各ユーザーストーリーにユニットテストタスクを含める（Swift Testing 使用）。

**Organization**: タスクは各ユーザーストーリー（P1 → P2）を独立して実装・検証できるよう構成している。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並列実行可能（別ファイルで未完了タスクへの依存なし）
- **[Story]**: 対応するユーザーストーリー（例: `US1`, `US2`, `US3`）
- 各タスクに正確なファイルパスを明記する

## Phase 1: Setup（事前確認）

**Purpose**: 既存テストのベースライン確認と契約変更箇所の把握

- [ ] T001 既存のテストスイートを実行しベースラインが通過することを確認する (`Tests/WintchCoreTests/`)

---

## Phase 2: Foundational（サービスプロトコル・テストモック基盤）

**Purpose**: 全ユーザーストーリーの前提となる `WindowCaptureServicing` プロトコルおよびテストモックの契約追加

**⚠️ CRITICAL**: 以降のユーザーストーリー実装前に完了すること

- [ ] T002 `WindowCaptureServicing` プロトコルに `pruneCache(keeping activeCGWindowIDs: Set<UInt32>)` を追加する (`Sources/WintchCore/Services/Protocols/WindowCaptureServicing.swift`)
- [ ] T003 `MockWindowCaptureService` に `pruneCache(keeping:)` 実装と呼び出し記録プロパティ（`prunedKeepingWindowIDsHistory`）を追加する (`Tests/WintchCoreTests/Mocks/MockServices.swift`)

**Checkpoint**: プロトコルおよびモック基盤の準備完了

---

## Phase 3: User Story 1 - 多数のウィンドウを開閉する長時間利用でも既存ウィンドウのキャプチャが消えない (Priority: P1) 🎯 MVP

**Goal**: 閉じ済みウィンドウのキャッシュ自動整理（`pruneCache`）、LRU 順逆転の是正（`sorted.reversed()`）、および保持上限 100 件化を実現する

**Independent Test**: `WindowCaptureService` の上限 100 件・`pruneCache` 挙動と、`SwitcherViewModel` で大量ウィンドウ開閉後に生存ウィンドウが維持され `sorted.reversed()` により MRU 上位が追い出されないことを Swift Testing で検証できる

### Tests for User Story 1

- [ ] T004 [P] [US1] `WindowCaptureService` の `pruneCache(keeping:)` が閉じ済み ID のみ削除し生存 ID の LRU 順を維持すること、およびデフォルト上限 100 件・カスタム上限（`maxCacheCount >= 1`、制約: `thumbnailCache.count <= maxCacheCount`）での LRU 追い出しを検証するテストを追加する (`Tests/WintchCoreTests/WindowCaptureAndMatchingTests.swift`)
- [ ] T005 [P] [US1] `SwitcherViewModel` で `.capture` 起動時に `pruneCache(keeping:)` が現在生存ウィンドウ ID 集合のみで呼ばれること、および初期サムネイル読み込みが `sorted.reversed()` 順で行われ直近利用ウィンドウが追い出されないことを検証するテストを追加する (`Tests/WintchCoreTests/SwitcherViewModelTests.swift`)

### Implementation for User Story 1

- [ ] T006 [US1] `WindowCaptureService` に `defaultMaxCacheCount = 100`・注入可能な `init(..., maxCacheCount: Int = defaultMaxCacheCount)`（`max(maxCacheCount, 1)` 正規化）・`pruneCache(keeping:)`（`thumbnailCache` / `cacheOrder` から非含有 ID を除去し `invalidatedWindowIDsDuringCapture` へ登録）を実装する (`Sources/WintchCore/Services/WindowCaptureService.swift`)
- [ ] T007 [US1] `SwitcherViewModel.present(targetMode:)` の `shouldUseCapture && granted` 分岐内で `windowCaptureService.pruneCache(keeping: Set(sorted.compactMap(\.cgWindowID)))` を呼び出し、キャッシュ参照ループを `for entry in sorted.reversed()` へ修正する (`Sources/WintchCore/ViewModels/SwitcherViewModel.swift`)

**Checkpoint**: User Story 1 が単独で機能・テスト通過することを確認

---

## Phase 4: User Story 2 - ウィンドウの状態・タイトル変化や再照合時にもキャプチャの紐付けが失われない (Priority: P1)

**Goal**: `WindowService.selectBestCGWindowMatch` の近接判定・包含フォールバック双方で `preferredCGWindowID` 連続性と非空 `cgWindowName` 優先を強化し、`cgWindowID` の誤乗り換え・欠落を防ぐ

**Independent Test**: `WindowService.selectBestCGWindowMatch` に対し、タイトル変化・無名空き殻窓共存・`boundsDistance > 40pt` の包含フォールバック条件下でも `preferredCGWindowID` および非空 `cgWindowName` が維持されることを Swift Testing で検証できる

### Tests for User Story 2

- [ ] T008 [P] [US2] `selectBestCGWindowMatch` がタイトル一時不一致時の近接比較および `containmentMatch` 包含比較の双方で `preferredCGWindowID` 連続性と非空 `cgWindowName`（空き殻 CGWindow 劣後）を優先することを検証するテストを追加する (`Tests/WintchCoreTests/WindowCaptureAndMatchingTests.swift`)

### Implementation for User Story 2

- [ ] T009 [US2] `WindowService.matchPriorityTuple` に `nonEmptyNamePriority` を `continuityPriority` の直後へ追加し、`containmentMatch` 比較へ `onscreenRank` → `titleRank` → `continuityRank` → `nonEmptyNameRank` → `intersectionArea` の優先順を実装する (`Sources/WintchCore/Services/WindowService.swift`)

**Checkpoint**: User Story 1 および User Story 2 がともに独立してテスト通過することを確認

---

## Phase 5: User Story 3 - 再取得が一時的に遅延・失敗する状況でも既存プレビューを維持し最小権限原則を守る (Priority: P2)

**Goal**: 異常サイズ（`width <= 0` または `height <= 0`）のキャプチャ結果による既存キャッシュ上書き防止、失敗時既存キャッシュ維持、および `.list` / `.launcher` / 権限未許可時の非呼出を維持する

**Independent Test**: 無効サイズガード・再取得失敗時の既存キャッシュ維持・`.list` / `.launcher` モードでの `pruneCache` 非呼出が Swift Testing で検証できる

### Tests for User Story 3

- [ ] T010 [P] [US3] `WindowCaptureService.isValidCapturedImageSize(_:)`（または同等の画像サイズ検証ヘルパー）が `0x0` 等の無効サイズを拒否し有効サイズのみ許可することを検証するテストを追加する (`Tests/WintchCoreTests/WindowCaptureAndMatchingTests.swift`)
- [ ] T011 [P] [US3] `.list` モード・`.launcher` モード・画面収録権限未許可時に `pruneCache(keeping:)` を含むキャプチャサービスメソッドが一切呼ばれず、再取得失敗時にも既存サムネイルが保持されることを検証するテストを追加する (`Tests/WintchCoreTests/SwitcherViewModelTests.swift`)

### Implementation for User Story 3

- [ ] T012 [US3] `WindowCaptureService.captureSingleWindow` に `CGImage` サイズ検証（`width > 0 && height > 0`）を追加し、無効画像時は `.failed` として既存キャッシュを上書きしないよう実装する (`Sources/WintchCore/Services/WindowCaptureService.swift`)

**Checkpoint**: すべてのユーザーストーリーが独立して動作・テスト通過することを確認

---

## Phase 6: Polish & Cross-Cutting Concerns（最終検証・品質確認）

**Purpose**: 日本語ドキュメントコメント規約確認、全テスト通過、および `.app` バンドルビルド確認

- [ ] T013 [P] 変更ファイルのすべての新規・修正クラス／メソッド／関数に日本語ドキュメントコメントと日本語インラインコメントが揃っていることを確認する (`Sources/WintchCore/`)
- [ ] T014 全ユニットテスト（`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`）およびアプリビルド（`./scripts/build-app.sh`）を実行して成功を確認する

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: 即時開始可能
- **Phase 2 (Foundational)**: Phase 1 完了後に開始（全ストーリーをブロック）
- **Phase 3 (US1)**, **Phase 4 (US2)**, **Phase 5 (US3)**: Phase 2 完了後に並列または P1→P2 順で実施可能（US2 は `WindowService.swift` のみ変更のため US1 とファイル競合なし）
- **Phase 6 (Polish)**: 全ユーザーストーリー完了後に実施

### Parallel Opportunities

- Phase 3 の `T004` と `T005` は別ファイルのため並列実行可能
- Phase 4 (`T008`, `T009`) は `WindowService.swift` 中心のため Phase 3 と並列実施可能
- Phase 5 の `T010` と `T011` は別ファイルのため並列実行可能

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1（ベースライン確認）＋ Phase 2（プロトコル・モック追加）を完了
2. Phase 3（US1: `pruneCache`・`sorted.reversed()`・上限 100 件化）を実装・検証
3. 続けて Phase 4（US2: `WindowService` 照合安定化）・Phase 5（US3: 異常画像ガードとオプトイン境界確認）・Phase 6（全テスト・ビルド検証）を順次完了する
