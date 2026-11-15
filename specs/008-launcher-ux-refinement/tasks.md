---

description: "Task list for 008-launcher-ux-refinement"
---

# Tasks: ランチャー起動時の初期フォーカス位置変更と検索プレースホルダーの視認性改善

**Input**: Design documents from `/specs/008-launcher-ux-refinement/`  
**Prerequisites**: `plan.md`（必須）, `spec.md`（必須）, `research.md`, `data-model.md`, `contracts/ui-and-selection-contracts.md`, `quickstart.md`

**Tests**: 本機能は憲章（ユニットテスト可能性の維持）および `quickstart.md` の方針に従い、各ユーザーストーリーにユニットテストの追加・更新タスクを含める。

**Organization**: タスクは独立した実装・検証が可能な単位としてユーザーストーリー（`US1`, `US2`）ごとに整理している。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 依存関係がなく別ファイルを扱うため並列実行可能なタスク
- **[Story]**: 対応するユーザーストーリー（`US1`: 初期選択 1 番目維持、`US2`: プレースホルダー視認性改善）
- 各タスクに正確なファイルパスを明記している

## Path Conventions

- ソースコード: `Sources/WintchCore/`
- ユニットテスト: `Tests/WintchCoreTests/`
- 仕様ドキュメント: `specs/`

---

## Phase 1: Setup（ベースライン確認）

**Purpose**: 既存ビルドおよびテストのベースライン状態を確認する

- [ ] T001 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行して `Package.swift` と `Tests/WintchCoreTests/` の現状テストベースラインを確認する

---

## Phase 2: Foundational（共通基盤）

**Purpose**: 全ユーザーストーリーに先行する共通基盤作業

> 本機能は既存の `Domain/`・`ViewModels/`・`Views/` 構造内で完結し、US1 と US2 の間に共通のブロッキング基盤変更は存在しないため、Phase 1 完了後に US1・US2 へ直接進める。

---

## Phase 3: User Story 1 - 検索ランチャー起動時に先頭項目（1番目）を初期選択する (Priority: P1) 🎯 MVP

**Goal**: 検索ランチャー起動時（ウィンドウ 1 件以上）の初期選択を常に 1 番目（インデックス `0`）とし、通常スイッチャー（リスト型・キャプチャ表示型）の初期選択規則（1 件なら `0`、2 件以上なら `1`）をそのまま維持する。

**Independent Test**: `SwitcherSelectionTests` および `SwitcherViewModelTests` で、ランチャー起動時の `selectedIndex == 0`・起動直後の順逆移動（`0 -> 1` および `0 -> 末尾`）・通常スイッチャー起動時の `selectedIndex == 1` が独立して検証できる。

### Tests for User Story 1

> **NOTE: 実装前にテストを追加・更新し、実装前の状態で失敗することを確認する**

- [ ] T002 [P] [US1] `Tests/WintchCoreTests/SwitcherSelectionTests.swift` に `initialIndex(count:preferSecondItem:)` の `true`（0件->nil, 1件->0, 2件以上->1）および `false`（0件->nil, 1件->0, 2件以上->0）の境界値テストを追加する
- [ ] T003 [P] [US1] `Tests/WintchCoreTests/SwitcherViewModelTests.swift` のランチャー起動テストを更新・拡充し、2件以上のウィンドウ存在下でランチャー起動直後に `selectedIndex == 0` となること、起動直後の「次へ」で `1`・「前へ」で末尾へ循環すること、および通常スイッチャー（リスト型・キャプチャ表示型）起動時は `selectedIndex == 1` を維持することを検証する

### Implementation for User Story 1

- [ ] T004 [US1] `Sources/WintchCore/Domain/SwitcherSelection.swift` の `initialIndex(count: Int, preferSecondItem: Bool = true) -> Int?` を実装し（`count <= 0` は `nil`、`count == 1` は `0`、`count >= 2` は `preferSecondItem ? 1 : 0`）、日本語ドキュメントコメントおよびインラインコメントを更新する
- [ ] T005 [US1] `Sources/WintchCore/ViewModels/SwitcherViewModel.swift` の `present(targetMode:)` で `SwitcherSelection.initialIndex(count: sorted.count, preferSecondItem: targetMode != .launcher)` を呼び出すように更新し、ランチャー起動時のみ初期選択を `0` に設定する（T004 に依存）

**Checkpoint**: User Story 1 が単体で完結・テスト可能になる（`SwitcherSelectionTests` / `SwitcherViewModelTests` 合格）

---

## Phase 4: User Story 2 - 検索ランチャーのプレースホルダー文字列を明確に視認できる (Priority: P2)

**Goal**: 検索入力欄のプレースホルダー `"ウィンドウまたはアプリを検索..."` を、`NSColor.secondaryLabelColor`（15pt Regular）を用いた `placeholderAttributedString` により、ライト／ダーク双方の背景上で明確に判読でき、かつ入力文字（`NSColor.labelColor`）および IME 未確定文字と干渉しない表示へ改善する。

**Independent Test**: `LauncherSearchFieldTests` で生成される `placeholderAttributedString` の文言・前景色（`NSColor.secondaryLabelColor`）・フォント（15pt Regular）および `NSTextField` への適用状態を検証でき、実機画面でライト／ダーク両背景上の視認性を確認できる。

### Tests for User Story 2

> **NOTE: 実装前にテストを追加し、実装前の状態で失敗または未定義であることを確認する**

- [ ] T006 [P] [US2] `Tests/WintchCoreTests/LauncherSearchFieldTests.swift` を新規作成し、`LauncherSearchField.makePlaceholderAttributedString` が文字列 `"ウィンドウまたはアプリを検索..."`、`.foregroundColor` に `NSColor.secondaryLabelColor`、`.font` に `NSFont.systemFont(ofSize: 15, weight: .regular)` を設定すること、および `makeNSView` 相当で生成された `NSTextField` の `placeholderAttributedString` に反映されることを検証する単体テストを追加する

### Implementation for User Story 2

- [ ] T007 [US2] `Sources/WintchCore/Views/LauncherSearchField.swift` に静的定数 `placeholderText = "ウィンドウまたはアプリを検索..."` および静的ヘルパー `makePlaceholderAttributedString(_:)`（`.foregroundColor: NSColor.secondaryLabelColor`、`.font: NSFont.systemFont(ofSize: 15, weight: .regular)`）を実装し、`makeNSView(context:)` で `textField.placeholderAttributedString` へ設定する（日本語ドキュメントコメント・インラインコメント必須）

**Checkpoint**: User Story 1 と User Story 2 の双方が独立して機能し、単体テストで検証可能になる

---

## Phase 5: Polish & Cross-Cutting Concerns（仕様整合化・全体検証）

**Purpose**: 過去仕様書との整合化、全テスト実行、および `.app` バンドルビルドと実機動作確認

- [ ] T008 [P] `specs/002-window-search-launcher/spec.md` の User Story 1 受入シナリオ 1 および `FR-006` に `008-launcher-ux-refinement` による改定注記（ランチャー起動時の初期選択は常に 1 番目）を追記して整合化する
- [ ] T009 [P] `specs/004-launcher-switcher-nav/spec.md` の User Story 1 受入シナリオ 1 に `008-launcher-ux-refinement` による改定注記（ランチャー起動時の初期選択は 1 番目）を追記して整合化する
- [ ] T010 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行し、全ユニットテストの 100% 合格を確認する（T005, T007 完了後）
- [ ] T011 `specs/008-launcher-ux-refinement/quickstart.md` に従い `./scripts/build-app.sh` で `.build/Wintch.app` をビルドし、ランチャー起動時 1 番目選択・通常スイッチャー 2 番目選択・ライト／ダーク背景でのプレースホルダー視認性・日本語 IME 入力動作を最終確認する（T010 完了後）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし — 即座に開始可能
- **Foundational (Phase 2)**: 追加タスクなし
- **User Story 1 (Phase 3)**: Phase 1 完了後に開始可能
- **User Story 2 (Phase 4)**: Phase 1 完了後に開始可能（User Story 1 とは編集ファイルが完全に分離されているため並列実行可能）
- **Polish (Phase 5)**: `T008`・`T009` は即時並列実行可能、`T010` は Phase 3・4 完了後、`T011` は `T010` 完了後に実行

### Within Each User Story

- テストタスク（`T002`, `T003`, `T006`）を先に記述し、実装前の失敗を確認する
- `US1`: `T004`（`SwitcherSelection.swift`）→ `T005`（`SwitcherViewModel.swift`）の順に実装する
- `US2`: `T006` → `T007`（`LauncherSearchField.swift`）の順に実装する

### Parallel Opportunities

```bash
# US1 と US2 のテスト作成を並列着手する例:
Task: "T002 [P] [US1] Tests/WintchCoreTests/SwitcherSelectionTests.swift に初期選択テスト追加"
Task: "T003 [P] [US1] Tests/WintchCoreTests/SwitcherViewModelTests.swift のランチャー起動テスト更新"
Task: "T006 [P] [US2] Tests/WintchCoreTests/LauncherSearchFieldTests.swift のプレースホルダー属性テスト新規作成"

# 過去仕様書の整合化タスクを並列実行する例:
Task: "T008 [P] specs/002-window-search-launcher/spec.md の改定注記追記"
Task: "T009 [P] specs/004-launcher-switcher-nav/spec.md の改定注記追記"
```

---

## Implementation Strategy

### MVP First（User Story 1 のみ）

1. Phase 1（`T001`）でベースライン確認
2. Phase 3（`T002`〜`T005`）でランチャー初期選択の 1 番目固定を実装・テスト
3. **STOP and VALIDATE**: `SwitcherSelectionTests` / `SwitcherViewModelTests` 合格を確認

### Incremental Delivery

1. User Story 1 完了後に User Story 2（`T006`〜`T007`）を実装し、プレースホルダー視認性を改善
2. Phase 5（`T008`〜`T011`）で過去仕様書の整合化・全テスト合格・実機 `.app` 検証を完了
