---

description: "検索ランチャー表示中の通常スイッチャーショートカットによる候補移動実装のための依存関係順タスクリスト"
---

# Tasks: 検索ランチャー表示中の通常スイッチャーショートカットによる候補移動

**Input**: 設計ドキュメント `/specs/004-launcher-switcher-nav/`  
**Prerequisites**: [plan.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/004-launcher-switcher-nav/plan.md), [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/004-launcher-switcher-nav/spec.md), [research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/004-launcher-switcher-nav/research.md), [data-model.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/004-launcher-switcher-nav/data-model.md), [service-contracts.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/004-launcher-switcher-nav/contracts/service-contracts.md), [quickstart.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/004-launcher-switcher-nav/quickstart.md)

**Tests**: プロジェクト憲章（テスト可能性）に基づき、モード別キー入力判定（`HotKeyMonitorDecisionTests`）および ViewModel 状態遷移・選択移動（`SwitcherViewModelTests`）の Swift Testing ユニットテストを含みます。

**Organization**: ユーザーストーリー単位（US1, US2）にフェーズを分割し、各ストーリーが独立して実装・テスト・検証可能な構成としています。すべてのコードは日本語ドキュメントコメント（概要・`@param`・`@returns`）および日本語インラインコメントを必須とします。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並列実行可能（異なるファイルで未完了タスクへの依存なし）
- **[Story]**: 所属するユーザーストーリー（`[US1]`, `[US2]`）
- すべてのタスクに具体的なファイルパスを記載

---

## Phase 1: Setup（ベースライン確認）

**Purpose**: 既存実装と Swift Testing テストスイートが健全であることを確認し、安全に変更を開始する

- [X] T001 リポジトリルートで `swift test` を実行し、既存のテストスイートおよびビルドがクリーンに通るベースラインを確認する（`Package.swift` 変更なし）

---

## Phase 2: Foundational（テスト可能な判定基盤の整備）

**Purpose**: US1・US2 の双方で共有するサービスプロトコルのドキュメント整合と、`HotKeyMonitorService` の純粋キー判定ロジック分離を行う

**⚠️ CRITICAL**: このフェーズが完了するまでユーザーストーリーの実装・単体テストフェーズへ進めない

- [X] T002 [P] `HotKeyMonitorMode`（`.launcher` の説明）および `HotKeyEvent.triggerPressed(isShiftPressed:)` の日本語ドキュメントコメントを新仕様に合わせて更新する（`Sources/WintchCore/Services/Protocols/HotKeyMonitoring.swift`）
- [X] T003 `HotKeyKeyDownDecision`（`event: HotKeyEvent?`, `shouldConsume: Bool`）および静的純粋判定メソッド `HotKeyMonitorService.resolveKeyDown(mode:keyCode:modifiers:shortcut:launcherShortcut:)` を抽出し、`handleCGEvent` の `.keyDown` 分岐が重複なくこの判定結果に従うようリファクタリングする（`Sources/WintchCore/Services/HotKeyMonitorService.swift`）

**Checkpoint**: `HotKeyMonitorService` の `keyDown` 判定が `CGEvent` から分離され、単体テストおよび US1/US2 実装の基盤が整う

---

## Phase 3: User Story 1 - 検索ランチャー表示中に通常スイッチャーショートカットで候補を次へ・前へ移動する (Priority: P1) 🎯 MVP

**Goal**: 検索ランチャー表示中に通常スイッチャーの順方向・逆方向ショートカット（デフォルト `Option + Tab` / `Option + Shift + Tab`）を入力した際、キー入力を消費して検索欄や背面アプリへ漏らさず、表示中の候補リスト（未絞り込み・絞り込み後・循環・0件/1件）を「次へ」「前へ」に移動でき、修飾キー解放でもパネルが閉じない状態を確立する

**Independent Test**: `HotKeyMonitorDecisionTests` と `SwitcherViewModelTests` で `.launcher` 中の順/逆移動・循環・修飾キー解放無視・絞り込み中移動・0件安全消費・`Enter` 確定がすべてパスすること

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T004 [P] [US1] `.launcher` モードにおける `resolveKeyDown` の単体テスト（順方向 `isNormalMatch` で `.triggerPressed(isShiftPressed: false)` + `shouldConsume == true`、逆方向 `Shift` 併用で `.triggerPressed(isShiftPressed: true)` + `shouldConsume == true`、ランチャー再押下優先で `.launcherTriggerPressed` + `shouldConsume == true`、`Esc`/`↑`/`↓`/文字キーで `event == nil` + `shouldConsume == false`）を `Tests/WintchCoreTests/HotKeyMonitorDecisionTests.swift` に作成する（T003 依存）
- [X] T005 [P] [US1] `SwitcherViewModel` のランチャー内通常ショートカット移動テスト（`launcherModeSearchMoveConfirmAndMutualExclusion` 内の旧「無視」アサーション更新に加え、順方向「次へ」・末尾→先頭循環・`Shift` 併用「前へ」・先頭→末尾循環・移動後の `.modifierReleased` 無視・絞り込み後リスト内移動・0件/1件時安全動作・`Enter` 確定）を `Tests/WintchCoreTests/SwitcherViewModelTests.swift` に追加・更新する

### Implementation for User Story 1

- [X] T006 [US1] `HotKeyMonitorService.resolveKeyDown` の `.launcher` 分岐で `isLauncherMatch` 判定後に `isNormalMatch`（`keyCode == shortcut.keyCode && modifiers.subtracting(.shift) == shortcut.modifiers`）に一致した場合、`HotKeyKeyDownDecision(event: .triggerPressed(isShiftPressed: modifiers.contains(.shift)), shouldConsume: true)` を返すよう実装する（`Sources/WintchCore/Services/HotKeyMonitorService.swift`、T003, T004 依存）
- [X] T007 [US1] `SwitcherViewModel.handleTriggerPressed(isShiftPressed:)` を更新し、`mode == .launcher` を `mode == .normal` と統合して `moveSelection(isShiftPressed ? .up : .down)` を実行（`searchQuery`・`displayedResults`・`.launcher` モードを維持し、0件時は安全に無操作）するよう実装する（`Sources/WintchCore/ViewModels/SwitcherViewModel.swift`、T005 依存）

**Checkpoint**: User Story 1 が完全に動作し、US1 のユニットテスト（`HotKeyMonitorDecisionTests`, `SwitcherViewModelTests`）がすべてパスする

---

## Phase 4: User Story 2 - カスタマイズ済みショートカットへの追従と通常モード共存の維持 (Priority: P2)

**Goal**: 設定画面でカスタマイズした通常スイッチャーショートカット（任意の修飾キー・トリガーキー）にもランチャー内の「次へ」「前へ」移動が即座に追従し、同時に通常スイッチャー表示中のランチャーショートカット無視など既存のモード共存ルールが損なわれないことを保証する

**Independent Test**: カスタムショートカット設定時の `.launcher` 内順逆判定テストおよび `.normal` モード表示中の `.launcherTriggerPressed` 無視・消費テストが独立してパスすること

### Tests for User Story 2 ⚠️

- [X] T008 [P] [US2] カスタマイズ済み通常ショートカット（例：`Control + ` `` や複数修飾キー組み合わせ）での `.launcher` 内順/逆判定テスト、外部改変等で設定重複時のランチャー優先（`.launcherTriggerPressed`）テスト、および `.normal` モード中のランチャーショートカット無視（`event == nil`, `shouldConsume == true`）テストを `Tests/WintchCoreTests/HotKeyMonitorDecisionTests.swift` に追加する（T006 依存）
- [X] T009 [P] [US2] `SwitcherViewModel` の `.normal` モード表示中における `.launcherTriggerPressed` 無視と通常モード維持の検証を `Tests/WintchCoreTests/SwitcherViewModelTests.swift` で確認・補強する（T007 依存）

### Implementation for User Story 2

- [X] T010 [US2] `HotKeyMonitorService` の `updateShortcut(_:)` と `TapState` 同期経路、および `AppCoordinator` / `SettingsViewModel` からの設定反映時に `.launcher` モードでも常に最新の `shortcut` が参照されることを確認し、`.launcher` 分岐での判定優先順（`isLauncherMatch` → `isNormalMatch`）と関連日本語コメントを明文化する（`Sources/WintchCore/Services/HotKeyMonitorService.swift`、T006, T008 依存）

**Checkpoint**: User Story 1 と User Story 2 の双方が独立して機能し、カスタマイズ設定・通常モード排他を含む全単体テストがパスする

---

## Phase 5: Polish & Cross-Cutting Concerns（品質・ドキュメント・全体検証）

**Purpose**: コーディング規約の遵守確認、全体テスト実行、`quickstart.md` に沿った最終確認を行う

- [X] T011 [P] 変更・新規作成した全ファイル（`Sources/WintchCore/Services/Protocols/HotKeyMonitoring.swift`, `Sources/WintchCore/Services/HotKeyMonitorService.swift`, `Sources/WintchCore/ViewModels/SwitcherViewModel.swift`, `Tests/WintchCoreTests/HotKeyMonitorDecisionTests.swift`, `Tests/WintchCoreTests/SwitcherViewModelTests.swift`）の日本語ドキュメントコメント（概要・`@param`・`@returns`）およびインラインコメントがプロジェクト規約に準拠しているか点検する
- [X] T012 リポジトリルートで `swift test` を実行して全テストスイートのパスを確認し、`specs/004-launcher-switcher-nav/quickstart.md` に記載された自動テスト・実機検証観点との整合を最終確認する

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし — 即時実行可能（T001）
- **Foundational (Phase 2)**: Setup 完了後 — T002 と T003 は並列実行可能（異なるファイル）
- **User Story 1 (Phase 3)**: Foundational 完了後（特に T003 完了後）
  - テスト T004・T005 を並列作成して失敗確認 → 実装 T006・T007 を並列実施可能（異なるファイル）
- **User Story 2 (Phase 4)**: User Story 1 完了後（または T006/T007 完了後に T008/T009 並列作成 → T010 検証）
- **Polish (Phase 5)**: US1・US2 完了後に T011・T012 を実施

### User Story Dependencies

- **User Story 1 (P1)**: Foundational 完了後に着手可能。他ストーリーへの依存なし（MVP）。
- **User Story 2 (P2)**: US1 で整備した `resolveKeyDown` / `handleTriggerPressed` の動作に対して、カスタム設定追従および通常モード共存境界の回帰・検証を行うため US1 完了後に着手する。

### Parallel Opportunities

- **Phase 2**: T002（`HotKeyMonitoring.swift`）と T003（`HotKeyMonitorService.swift`）は別ファイルのため並列実行可能。
- **Phase 3 (US1)**:
  - テスト作成：T004（`HotKeyMonitorDecisionTests.swift`）と T005（`SwitcherViewModelTests.swift`）は別ファイルのため並列実行可能。
  - 実装：T006（`HotKeyMonitorService.swift`）と T007（`SwitcherViewModel.swift`）は別ファイルのため並列実行可能。
- **Phase 4 (US2)**: T008（`HotKeyMonitorDecisionTests.swift`）と T009（`SwitcherViewModelTests.swift`）は並列実行可能。

---

## Parallel Example: User Story 1

```bash
# US1 のテストを並列で追加（実装前に失敗を確認）:
Task: "T004 HotKeyMonitorDecisionTests.swift に .launcher モードの順/逆/優先/通過テストを作成"
Task: "T005 SwitcherViewModelTests.swift にランチャー内通常ショートカット移動テストを追加・更新"

# US1 の実装を並列で適用:
Task: "T006 HotKeyMonitorService.swift の resolveKeyDown(.launcher) で isNormalMatch を通知・消費"
Task: "T007 SwitcherViewModel.swift の handleTriggerPressed で .launcher 時に moveSelection を実行"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1（T001）で既存テストが通るベースラインを確認する
2. Phase 2（T002〜T003）で純粋判定ヘルパーを抽出する
3. Phase 3（T004〜T007）で US1 をテスト先行で実装・検証する
4. **STOP and VALIDATE**: `swift test` で US1 の全テストがパスすることを確認する

### Incremental Delivery

1. MVP（US1）完了後、Phase 4（T008〜T010）でカスタマイズショートカット追従・重複優先・通常モード側排他のテストと確認を追加する
2. Phase 5（T011〜T012）で日本語コメント規約点検と最終 `swift test`・実機確認を実施する

---

## Notes

- すべての新規・更新関数・メソッドには日本語ドキュメントコメント（概要、`@param`、`@returns`）と日本語インラインコメントを記述すること
- `HotKeyMonitorService` のユニットテストは `CGEventTap` やアクセシビリティ権限に依存しない `resolveKeyDown` 経由で行うこと
- 既存の `Esc` / `↑` / `↓` / `Ctrl+N` / `Ctrl+P` / 日本語 IME 変換優先の挙動を変更・破壊しないこと
