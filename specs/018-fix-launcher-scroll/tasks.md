# Tasks: ランチャーおよびリスト型スイッチャーの選択候補スクロール追従修正

**Input**: Design documents from `specs/018-fix-launcher-scroll/`  
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/launcher-scroll-contract.md](contracts/launcher-scroll-contract.md)

**Organization**: 基盤となる統一リスト行モデル（Phase 2）を整備した上で、ユーザーストーリー単位（US1 → US2）に実装と実スクロール検証テストを段階的に進める。

## Phase 1: Setup（現状確認）

**Purpose**: 既存コードとテストのベースラインを確認し、修正対象箇所を確定する。

- [x] T001 変更前ベースライン確認として `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行し、現行コードのテスト状態と `Sources/WintchCore/Views/SwitcherListView.swift` の構成を確認する

---

## Phase 2: Foundational（統一リスト行モデルの構築）

**Purpose**: ウィンドウ候補・セクション見出し・アプリ起動候補を単一の `Identifiable` 識別契約で扱う純粋ドメインモデルを構築する。

- [x] T002 `Sources/WintchCore/Domain/SwitcherListRow.swift` を新規作成し、`SwitcherListRow` 列挙型（`.window`, `.launchSectionHeader`, `.appLaunch`）、配列構築関数 `buildRows(...)`、および `scrollTargetID(for:...)` を日本語ドキュメントコメント付きで実装する
- [x] T003 [P] `Tests/WintchCoreTests/SwitcherListRowTests.swift` を新規作成し、行構築順序・`"window-"` / `"app-"` 接頭辞による一意性保証（同値 ID の非衝突）・`scrollTargetID(for:)` と `row.id` の完全一致・境界外インデックスの `nil` 返却を検証する

**Checkpoint**: `SwitcherListRow` の単体テストがパスし、View 層から利用可能な状態。

---

## Phase 3: User Story 1 - 検索ランチャーで選択候補の移動に合わせてリストが自動スクロールする (Priority: P1) 🎯 MVP

**Goal**: 検索ランチャーで最大高さを超える候補一覧が表示されている状態において、方向キーやショートカットによる選択移動（ウィンドウセクション内、アプリ起動セクションへの横断、先頭⇔末尾の循環移動）に連動してリストが自動スクロール追従するようにする。

**Independent Test**: `NSHostingView` 上に `SwitcherListView` を配置し、ウィンドウ候補・アプリ起動候補の合計が表示高さを超える状態で `moveSelection(.down)` / `moveSelection(.up)` 等を実行した際、`NSScrollView.contentView.bounds.origin.y` が選択候補に応じて変化することを自動テストで検証する。

### Implementation & Tests for User Story 1

- [x] T004 [US1] `Sources/WintchCore/Views/SwitcherListView.swift` の `resultListView` を `SwitcherListRow.buildRows(...)` を用いた単一 `ForEach(rows)` 構造へ書き換え、`ForEach` 要素の `id` と `proxy.scrollTo(targetID, anchor: .center)` に渡す識別子を一致させる（`ForEach` 要素直下の別 ID `.id(...)` 上書きを廃止する）
- [x] T005 [US1] `Tests/WintchCoreTests/SwitcherListViewTests.swift` を新規作成し、`NSHostingView` + `NSPanel` 上で `SwitcherListView` をホストして `NSScrollView` の `contentView.bounds.origin.y` を実測し、ランチャーモードでの下方向連続移動・アプリ起動セクション跨ぎ移動・上方向移動・先頭⇔末尾の循環移動で実際にスクロール追従することを検証する

**Checkpoint**: User Story 1 の実装および実スクロール追従テストが単独で完結・パスする状態。

---

## Phase 4: User Story 2 - 検索絞り込み・再表示・通常リスト型スイッチャーでもスクロール追従と初期位置の整合性を維持する (Priority: P2)

**Goal**: 検索クエリ更新時（同インデックスでの手動スクロール後含む）、パネル非表示後の再表示時、および通常スイッチャー（リスト型）表示時にも、選択候補とスクロール位置が常に一致することを保証する。

**Independent Test**: `SwitcherListViewTests` に検索更新による先頭復帰テスト、パネル再表示時の位置整合テスト、および通常モード（リスト型）のスクロール追従テストを追加し、すべてパスすることで検証する。

### Implementation & Tests for User Story 2

- [x] T006 [US2] `Sources/WintchCore/Views/SwitcherListView.swift` の `resultListView` に `onChange(of: viewModel.searchQuery)`、`onChange(of: viewModel.mode)`、および `onAppear` のスクロール追従・初期位置整合処理を追加する
- [x] T007 [US2] `Tests/WintchCoreTests/SwitcherListViewTests.swift` に、手動スクロール状態からの検索クエリ更新による先頭復帰・パネル非表示から再表示した際の先頭復帰・通常スイッチャー（リスト型）での多数ウィンドウ選択移動によるスクロール追従の検証テストを追加する

**Checkpoint**: User Story 1 と User Story 2 の双方が独立して検証済み。

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: 全体の整合性・日本語ドキュメント規約・全ユニットテスト・アプリビルドの検証を完了する。

- [x] T008 変更・追加した全ファイルの日本語コメント・SwiftDoc（`///`）規約および Wintch 憲章 v2.0.0 準拠を確認する（`Sources/WintchCore/Domain/SwitcherListRow.swift`, `Sources/WintchCore/Views/SwitcherListView.swift`, `Tests/WintchCoreTests/SwitcherListRowTests.swift`, `Tests/WintchCoreTests/SwitcherListViewTests.swift`）
- [x] T009 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行し、全ユニットテストがエラー・スキップなしでパスすることを確認する
- [x] T010 `./scripts/build-app.sh` を実行し、`.build/Wintch.app` のビルドがエラーなく成功することを確認する

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: 依存なし — 最初にベースライン確認を実施
- **Phase 2 (Foundational)**: Phase 1 完了後に着手。T002 完了後に T003 を実施（T002 設計確定後であれば並列記述可）
- **Phase 3 (US1)**: Phase 2 完了後に着手。T004 完了後に T005 で実スクロール追従を検証
- **Phase 4 (US2)**: Phase 3 完了後に着手。T006 完了後に T007 で追加シナリオを検証
- **Phase 5 (Polish)**: Phase 3・Phase 4 完了後に最終ビルド・全テスト検証を実施
