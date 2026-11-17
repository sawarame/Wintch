# Tasks: アクセシビリティ権限誘導ダイアログの説明文全文表示修正

**Input**: Design documents from `/specs/016-fix-permission-guide-text/`
**Prerequisites**: [plan.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/016-fix-permission-guide-text/plan.md)（必須）, [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/016-fix-permission-guide-text/spec.md)（必須）, [research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/016-fix-permission-guide-text/research.md), [data-model.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/016-fix-permission-guide-text/data-model.md), [permission-guide-layout-contract.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/016-fix-permission-guide-text/contracts/permission-guide-layout-contract.md)

**Tests**: `PermissionGuideViewModelTests`（または専用のビュー配置テスト）および `AppCoordinatorTests` によりレイアウト必要高さ・ウィンドウサイズ整合性を検証する。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 異なるファイルへの作業であり、未完了タスクへの依存がなく並列実行可能
- **[Story]**: 対応するユーザーストーリー（`[US1]`, `[US2]`）
- 説明には対象ファイルの正確なパスを含める

---

## Phase 1: Setup（事前確認）

**Purpose**: 既存のテストとビルド環境が正常であることを確認する

- [x] T001 既存ユニットテストを実行しベースラインの通過を確認する（`Tests/WintchCoreTests/`）

---

## Phase 2: Foundational（基準寸法定数の定義）

**Purpose**: `PermissionGuideView` と `AppCoordinator` の双方で共有する権限誘導ダイアログの幅・最小高さ定数を整備する

- [ ] T002 `PermissionGuideView` に基準横幅（`preferredWidth: CGFloat = 460`）および最小高さ（`minimumHeight: CGFloat = 280`）の公開定数を追加する（`Sources/WintchCore/Views/PermissionGuideView.swift`）

**Checkpoint**: ビューとウィンドウ生成処理が同一の基準寸法定数を参照できる状態

---

## Phase 3: User Story 1 - アクセシビリティ権限誘導ダイアログの説明文を途切れなく全文読める (Priority: P1) 🎯 MVP

**Goal**: 補足説明（「※ リスト型および検索ランチャーでは「画面収録」権限を使用しません（キャプチャ表示型を選択した場合のみ任意で使用します）。」）を含むすべてのテキストが省略記号（`...`）で途切れることなく全文表示されるようにする

**Independent Test**: `NSHostingView` 上の `PermissionGuideView` の `fittingSize` が幅 `460pt`・必要高さ（`280pt` 超）となり、`AppCoordinator.openPermissionGuide()` が生成する `NSWindow` のコンテンツ高さが `fittingSize.height` 以上であることを検証できること

### Tests for User Story 1

- [ ] T003 [P] [US1] `PermissionGuideView` の `NSHostingView.fittingSize` が幅 `460pt`・高さ `280pt` 超で計算され、垂直圧縮されないことを検証するテストを追加する（`Tests/WintchCoreTests/PermissionGuideViewModelTests.swift`）
- [ ] T004 [P] [US1] `AppCoordinator.openPermissionGuide()` が生成する権限誘導ウィンドウのコンテンツ領域サイズが `NSHostingView.fittingSize` 以上であることを検証するテストを追加する（`Tests/WintchCoreTests/AppCoordinatorTests.swift`）

### Implementation for User Story 1

- [ ] T005 [US1] `PermissionGuideView` 内の見出し・サブタイトル・手順ラベル・補足説明 `Text` に `.fixedSize(horizontal: false, vertical: true)` を適用し、垂直方向の圧縮による省略（`...`）を防止する（`Sources/WintchCore/Views/PermissionGuideView.swift`）
- [ ] T006 [US1] `AppCoordinator.ensurePermissionWindow()` で `NSHostingView.fittingSize`（`layoutSubtreeIfNeeded()` 後）に基づき `NSWindow` の `contentRect` および `setContentSize(_:)` を設定するよう修正する（`Sources/WintchCore/App/AppCoordinator.swift`）

**Checkpoint**: 補足説明文およびすべてのテキストが垂直圧縮されず、権限誘導ウィンドウに十分な高さが割り当てられている状態

---

## Phase 4: User Story 2 - ダイアログ内の見出し・手順・操作ボタンとのレイアウト調和を保つ (Priority: P2)

**Goal**: 配布版（`Wintch`）および開発版（`Wintch_dev`）の双方で手順文言・補足説明・下部操作ボタンが十分な余白を保って収まり、ウィンドウ再利用や最前面表示の既存動作も損なわれないことを保証する

**Independent Test**: 配布版・開発版の `AppIdentity` それぞれで `PermissionGuideView` の `fittingSize` と `AppCoordinator` の再利用・最前面表示動作が正しく機能することを検証できること

### Tests for User Story 2

- [ ] T007 [P] [US2] 配布版（`Wintch`）および開発版（`Wintch_dev`）双方の `AppIdentity` 条件で `PermissionGuideView` の必要サイズが有効値かつ切り詰めなし（`height > 280`・`width == 460`）となることを検証するテストを追加する（`Tests/WintchCoreTests/PermissionGuideViewModelTests.swift`）
- [ ] T008 [P] [US2] `AppCoordinator` の権限誘導ウィンドウ再利用および既存最前面表示契約が維持されることを確認する（`Tests/WintchCoreTests/AppCoordinatorTests.swift`）

---

## Phase 5: Polish & Cross-Cutting Concerns（仕上げと全体検証）

**Purpose**: 日本語ドキュメントコメント規約の遵守確認、全テスト実行、および `.app` バンドルビルド確認を行う

- [ ] T009 新規・変更コードすべての日本語ドキュメントコメント（`///`）およびインラインコメント規約を確認する（`Sources/WintchCore/Views/PermissionGuideView.swift`, `Sources/WintchCore/App/AppCoordinator.swift`）
- [ ] T010 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` で全ユニットテストを実行し全件通過を確認する
- [ ] T011 `./scripts/build-app.sh` で `.app` バンドルをビルドし、警告・エラーがないことを確認する

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: 完了済み（T001）
- **Phase 2 (Foundational)**: T002 は直ちに実施可能
- **Phase 3 (US1 - MVP)**: T002 完了後に T005・T006 を実装し、T003・T004 で検証する
- **Phase 4 (US2)**: T005・T006 完了後に T007・T008 で配布版・開発版・再利用性を検証する
- **Phase 5 (Polish)**: 全実装・テスト完了後に T009 → T010 → T011 の順で実行する

### Implementation Strategy

1. `PermissionGuideView.swift` に基準寸法定数と `.fixedSize(horizontal: false, vertical: true)` を適用し、SwiftUI 側でのテキスト省略を根絶する。
2. `AppCoordinator.swift` の `ensurePermissionWindow()` で `NSHostingView.fittingSize` を計測し、動的に十分なコンテンツ高さで `NSWindow` を生成する。
3. `PermissionGuideViewModelTests.swift` と `AppCoordinatorTests.swift` で回帰テストを追加し、全テスト・`.app` ビルドを通した上でコミット・プッシュ・PR 作成を行う。
