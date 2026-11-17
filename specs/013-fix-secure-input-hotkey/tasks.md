---

description: "セキュア入力フォーカス中のショートカット起動と安定復帰 実装タスク一覧"
---

# Tasks: セキュア入力（パスワード入力欄等）フォーカス中のショートカット起動と安定復帰

**Input**: Design documents from `/specs/013-fix-secure-input-hotkey/`
**Prerequisites**: [plan.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/013-fix-secure-input-hotkey/plan.md), [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/013-fix-secure-input-hotkey/spec.md), [research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/013-fix-secure-input-hotkey/research.md), [data-model.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/013-fix-secure-input-hotkey/data-model.md), [hotkey-secure-input-contracts.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/013-fix-secure-input-hotkey/contracts/hotkey-secure-input-contracts.md)

**Tests**: 仕様書の成功基準（SC-005）およびプロジェクト憲章・`AGENTS.md` のテスト規約に基づき、純粋ロジックおよび ViewModel 連携の Swift Testing ユニットテストを含めています。

**Organization**: ユーザーストーリー単位（P1 → P2）で独立実装・独立検証可能なフェーズ構成としています。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 別ファイルかつ未完了タスクへの依存がなく並列実行可能
- **[Story]**: 対応するユーザーストーリー（`[US1]`, `[US2]`, `[US3]`, `[US4]`）
- 説明には必ず対象ファイルの正確なパスを記載

---

## Phase 1: Setup（ベースライン確認）

**Purpose**: 既存テストスイートの健全性と macOS SDK の `Carbon` フレームワーク利用可否を確認する

- [X] T001 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行して既存テスト全件の合格を確認し、`Package.swift` の構成変更なしで `WintchCore` から `Carbon`（`RegisterEventHotKey` / `IsSecureEventInputEnabled`）がインポート可能であることを確認する

---

## Phase 2: Foundational（全ストーリー共通の純粋ロジックとサービス契約基盤）

**Purpose**: 全ユーザーストーリーが依存する重複排除・Carbon 登録計画・解放誤検知防止ガードの純粋ドメイン型と、`HotKeyMonitoring` プロトコル拡張を整備する

**⚠️ CRITICAL**: User Story 1〜4 の実装開始前に完了している必要がある

- [X] T002 [P] `Sources/WintchCore/Domain/HotKeyFallbackSupport.swift` を新規作成し、`HotKeyTriggerSource`（`.cgEventTap`, `.carbonHotKey`）、`HotKeyTriggerKind`（`.normalForward`, `.normalReverse`, `.launcher`）、`HotKeyTriggerDeduplicator`（`deduplicationWindowSeconds = 0.15` で異種経路かつ同一種別の重複を排除し、同一経路の連続入力は受理）、`CarbonHotKeySpec` / `CarbonHotKeyRegistrationPlan`（識別 ID `1: normalForward` / `2: normalReverse` / `3: launcher`、`cmdKey = 0x0100` / `shiftKey = 0x0200` / `optionKey = 0x0800` / `controlKey = 0x1000` 変換、必須修飾キーなしまたは `isSuspendedForRecording == true` で空配列）、および `shouldTreatModifiersAsReleased`（`isSecureInputEnabled && !isAppActive` 中は `false` を返してゼロ化フラグによる誤確定を防ぐ）を日本語ドキュメントコメント付きで実装する
- [X] T003 [P] `Sources/WintchCore/Services/Protocols/HotKeyMonitoring.swift` に `var requiresAppActivationOnPresentation: Bool { get }` を追加し、`Tests/WintchCoreTests/Mocks/MockServices.swift` の `MockHotKeyMonitor` に `requiresAppActivationOnPresentation` プロパティ（既定値 `false`）を追加する
- [X] T004 [P] `Tests/WintchCoreTests/HotKeyFallbackSupportTests.swift` を新規作成し、`HotKeyTriggerDeduplicator`（`0.15` 秒窓内の異種経路重複排除・窓経過後受理・同種経路連打受理・`reset()`）、`CarbonHotKeyRegistrationPlan`（順方向・逆順 `.shift` 合成・ランチャーの 3 件生成、修飾キーマスク変換、`isSuspendedForRecording == true` での空配列、必須修飾キー欠如時の除外）、および `shouldTreatModifiersAsReleased`（セキュア入力中の誤確定抑止ガード）の単体テストを実装する

**Checkpoint**: 共通ドメインロジックとテスト・プロトコル契約が整い、各ユーザーストーリーの実装へ進める状態

---

## Phase 3: User Story 1 - パスワード入力欄にフォーカス中でも通常スイッチャーを起動して全操作・切り替えできる (Priority: P1) 🎯 MVP

**Goal**: パスワード入力フォーム等のセキュア入力保護下でも、`Option + Tab`（`Shift` 逆順含む）で通常スイッチャーを一時アクティブ化して起動し、矢印キー・`Esc` キャンセル（元アプリ復帰）・`Q` ウィンドウ終了・素早い修飾キー解放を含む全操作を完遂できるようにする

**Independent Test**: ユニットテストで一時アクティブ化フラグ連携とセキュア入力中解放ガードを検証し、さらに Chrome / Edge のパスワード入力欄フォーカス中に `Option + Tab` を押して候補選択・矢印移動・`Esc` 復帰・素早い `Option` 解放確定がすべて動作することで独立検証できる

### Tests for User Story 1

- [X] T005 [P] [US1] `Tests/WintchCoreTests/SwitcherViewModelTests.swift` に、`hotKeyMonitor.requiresAppActivationOnPresentation == true` で通常スイッチャーを起動した場合に `shouldActivateAppForCurrentSession == true` となり、`dismiss`（確定・キャンセル）時に `false` へ戻るテスト、および通常時（`false`）は非アクティブ維持（`false`）のままであるテストを追加する

### Implementation for User Story 1

- [X] T006 [US1] `Sources/WintchCore/Views/SwitcherPanel.swift` を更新し、`show(mode: SwitcherMode, activateApp: Bool? = nil)`（`nil` 時は `mode == .launcher` と同等）、`didActivateAppForCurrentSession` の保持、`activateApp == true` 時における `previousFrontmostApp` 記録と `NSApplication.shared.activate()` 実行、`restoreFocusIfNeeded(mode:)` での `didActivateAppForCurrentSession` 考慮、および `hidePanel(restorePreviousApp:)` での元アプリ復元と状態リセットを実装する
- [X] T007 [US1] `Sources/WintchCore/ViewModels/SwitcherViewModel.swift` に `shouldActivateAppForCurrentSession`（`present(targetMode:)` で `targetMode == .launcher || hotKeyMonitor.requiresAppActivationOnPresentation` を設定し、`dismiss(reason:)` で `false` に戻す）を追加し、`Sources/WintchCore/App/AppCoordinator.swift` の `onModePresentationChanged` から `SwitcherPanel.show(mode:activateApp:)` へ伝播させる（T003, T006 に依存）
- [X] T008 [US1] `Sources/WintchCore/Services/HotKeyMonitorService.swift` に `import Carbon` と `InstallEventHandler`（`GetApplicationEventTarget()` / `kEventHotKeyPressed`）・`RegisterEventHotKey`・`UnregisterEventHotKey` を導入し、通常順方向（`id=1`）および逆順（`id=2`）ホットキー受信時に `HotKeyTriggerDeduplicator` で重複排除した上で、フォールバック起動または `IsSecureEventInputEnabled() == true` 下の通常起動で `requiresAppActivationOnPresentation = true` を設定して `.triggerPressed(isShiftPressed:)` を通知する（T002, T003 に依存）
- [X] T009 [US1] `Sources/WintchCore/Services/HotKeyMonitorService.swift` にフォールバック通常セッション（`activeMode == .normal && requiresAppActivationOnPresentation`）中のみ稼働するローカル `NSEvent` モニタ（`NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged])` で `resolveKeyDown` を適用し消費対象を `nil` 返却して警告音抑止）と、`shouldTreatModifiersAsReleased` ガードを用いた約 20ms 周期の修飾キー解放ウォッチドッグ（`activeMode != .normal` または `flagsChanged` 検知で即停止）を実装し、`CGEventTap` との重複排除を統合する（T008 に依存）

**Checkpoint**: User Story 1（MVP）が完結し、パスワード入力欄からの通常スイッチャー全操作が動作・検証可能

---

## Phase 4: User Story 2 - パスワード入力欄にフォーカス中でも検索ランチャーを起動・検索・切り替えできる (Priority: P1)

**Goal**: パスワード入力フォームにフォーカスした状態からでも、検索ランチャーのショートカット（既定 `Option + Space`）でランチャーを起動し、検索・切り替え・`Esc`/再押下キャンセル（元アプリ復帰）ができるようにする

**Independent Test**: ランチャー起動経路の重複排除テストを実行し、Chrome / Edge のパスワード欄フォーカス中に `Option + Space` で検索ランチャー起動・日本語検索・切り替え・キャンセル後のフォーカス復帰が動作することで検証できる

### Tests for User Story 2

- [X] T010 [P] [US2] `Tests/WintchCoreTests/HotKeyFallbackSupportTests.swift`（および必要に応じて `Tests/WintchCoreTests/HotKeyMonitorDecisionTests.swift`）に、`.launcher` トリガー（`id=3`）に対する `.cgEventTap` ⇄ `.carbonHotKey` 間の重複排除テストおよび `.launcher` モード中の順逆移動・トグル終了との整合テストを追加する

### Implementation for User Story 2

- [X] T011 [US2] `Sources/WintchCore/Services/HotKeyMonitorService.swift` の Carbon ホットキー登録および `kEventHotKeyPressed` ハンドラをランチャーショートカット（`id=3`, `HotKeyTriggerKind.launcher`）へ対応させ、`.inactive` 時の `.launcherTriggerPressed` 起動、`.launcher` 表示中の通常ショートカット順逆移動（`id=1/2`）およびランチャー再押下トグル終了が二重発火なく機能するよう統合する（T008, T009 に依存）

**Checkpoint**: User Story 1 と User Story 2 の双方が独立して動作・検証可能

---

## Phase 5: User Story 3 - フォーカス解除後にセキュア入力状態が残留する場合や監視状態が揺らいだ場合でも使い続けられる (Priority: P1)

**Goal**: ブラウザによるセキュア入力解除の遅延・残留や `CGEventTap` クールダウン中であっても無反応期間を作らず、権限が有効な限り代替経路と通常経路を安全に継続稼働させ、誤った権限停止やリソースリークを防ぐ

**Independent Test**: セキュア入力残留・往復帰境界の単体テストおよび実機でのフォーカス往復テスト（パスワード欄 → 通常欄 → タブ切替）で無反応状態・誤権限誘導が発生しないことで検証できる

### Tests for User Story 3

- [X] T012 [P] [US3] `Tests/WintchCoreTests/HotKeyFallbackSupportTests.swift` に、セキュア入力残留による代替経路連続利用、短時間での有効／無効切り替わり後の `HotKeyTriggerDeduplicator` 状態維持、および `HotKeyMonitorDecisionTests.swift` の既存 `resolveTapDisableDisposition` 契約との非破壊性を確認する境界テストを追加する

### Implementation for User Story 3

- [X] T013 [US3] `Sources/WintchCore/Services/HotKeyMonitorService.swift` において、`CGEventTap` タイムアウトクールダウン中（`pendingCooldownWorkItem != nil`）やセキュア入力解除遅延中も Carbon ホットキー監視が停止せず独立して起動を救済し、かつ `stopMonitoring()`・`terminateMonitoringFromSystem(reason:)`・`deinit` で Carbon ホットキー・イベントハンドラ・ローカル `NSEvent` モニタ・ウォッチドッグが確実にクリーンアップされるようライフサイクルを統合・堅牢化する（T009, T011 に依存）

**Checkpoint**: User Story 1〜3 すべてが安定・継続稼働可能な状態

---

## Phase 6: User Story 4 - 通常時の操作感維持・ショートカット設定変更との整合・二重発火防止 (Priority: P2)

**Goal**: 通常作業時のフォーカス非奪取・単発動作を維持したまま、設定画面でのショートカット変更（通常・ランチャー双方）とショートカット記録中のサスペンド、および `Command + Tab` 等 OS 予約ショートカット設定時の安全性を確保する

**Independent Test**: 設定変更・記録サスペンド時の登録計画テストおよび `SettingsViewModelTests` に加え、設定画面でショートカットを変更／記録中キー入力しても誤起動せず、変更直後から通常時・パスワード欄上の双方で新ショートカットが効くことで検証できる

### Tests for User Story 4

- [X] T014 [P] [US4] `Tests/WintchCoreTests/HotKeyFallbackSupportTests.swift` および `Tests/WintchCoreTests/SettingsViewModelTests.swift` に、通常／ランチャーショートカット変更時の新旧切り替え計画、`isSuspendedForRecording == true` での全登録解除（空配列）、および通常時（非セキュア入力下）に `requiresAppActivationOnPresentation` が `false` のまま維持される検証を追加する

### Implementation for User Story 4

- [X] T015 [US4] `Sources/WintchCore/Services/HotKeyMonitorService.swift` の `updateShortcut(_:)`、`updateLauncherShortcut(_:)`、`isSuspendedForRecording` セッター、および `startMonitoring()` に Carbon ホットキーの動的再同期（`UnregisterEventHotKey` → 最新設定の `RegisterEventHotKey`）を実装し、`isSuspendedForRecording == true` 中は全 Carbon ホットキーを解除するとともに、`RegisterEventHotKey` が `Command + Tab` 等の OS 予約キー衝突で失敗（非 `noErr`）しても監視全体を失敗扱いにせずログ記録のみで安全に継続するよう実装する（T011, T013 に依存）

**Checkpoint**: 全 User Story（US1〜US4）が独立かつ整合した状態で完了

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: 規約準拠確認・全体自動テスト・`.app` ビルドおよび実機検証ガイドに沿った最終確認を行う

- [X] T016 [P] 変更した `Sources/WintchCore/` 全ファイル（`Domain/HotKeyFallbackSupport.swift`, `Services/Protocols/HotKeyMonitoring.swift`, `Services/HotKeyMonitorService.swift`, `ViewModels/SwitcherViewModel.swift`, `App/AppCoordinator.swift`, `Views/SwitcherPanel.swift`）について、日本語コメント・SwiftDoc ドキュメントコメント（`///`, `- Parameter`, `- Returns:`）、Swift 6 Strict Concurrency（`@MainActor` / `Sendable`）、および憲章準拠（外部依存ゼロ・非公開 API 不使用・画面収録権限不使用）をレビュー・整理する
- [X] T017 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行し、既存テストおよび新規追加テスト全件が 100% 合格することを確認する
- [ ] T018 `./scripts/build-app.sh` で `.app` バンドルをビルドし、`specs/013-fix-secure-input-hotkey/quickstart.md` の実機 E2E シナリオ（シナリオ A〜D）を実行して動作を検証する（※ `.build/Wintch_dev.app` のビルド成功まで確認済み。Chrome / Edge パスワード入力欄での実機 E2E 操作確認はユーザー手元で実施）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: 依存なし — 即座に開始可能
- **Phase 2 (Foundational)**: Phase 1 完了後に開始 — **すべての User Story（Phase 3〜6）をブロック**
- **Phase 3 (US1 - P1 MVP)**: Phase 2 完了後に開始可能
- **Phase 4 (US2 - P1)**: Phase 2 完了後かつ `HotKeyMonitorService.swift` 競合回避のため T008/T009 完了後に実装統合（T010 のテスト作成は並列可能）
- **Phase 5 (US3 - P1)**: T009, T011 完了後に実装統合（T012 のテスト作成は並列可能）
- **Phase 6 (US4 - P2)**: T011, T013 完了後に実装統合（T014 のテスト作成は並列可能）
- **Phase 7 (Polish)**: Phase 3〜6 完了後に実施

### Within Each User Story

- テストタスクを先に記述・設計意図を明確化してから実装を進める
- `Domain/`（純粋ロジック）→ `Services/Protocols/` → `Views/`・`ViewModels/`・`Services/` → `AppCoordinator` の順で統合する
- `HotKeyMonitorService.swift` は複数ストーリーから更新されるため、同一ファイル編集は直列（T008 → T009 → T011 → T013 → T015）で実施し、テストや別ファイル作業を `[P]` で並列化する

### Parallel Opportunities

- **Phase 2 内並列**: `T002`（`Domain/HotKeyFallbackSupport.swift`）、`T003`（`HotKeyMonitoring.swift` & `MockServices.swift`）、`T004`（`HotKeyFallbackSupportTests.swift`）は互いに別ファイルまたはテスト先行で並列実施可能
- **Phase 3 内並列**: `T005`（`SwitcherViewModelTests.swift`）と `T006`（`SwitcherPanel.swift`）は別ファイルのため並列実施可能
- **Phase 4〜6 のテスト先行並列**: `T010`, `T012`, `T014` のテストタスクは対応実装前に独立して記述可能

---

## Parallel Example: Foundational & User Story 1

```bash
# Phase 2 の並列実行例（すべて別ファイル）:
Task: "T002 [P] Domain/HotKeyFallbackSupport.swift を新規作成"
Task: "T003 [P] HotKeyMonitoring.swift と MockServices.swift へプロパティ追加"
Task: "T004 [P] HotKeyFallbackSupportTests.swift を新規作成"

# Phase 3 (US1) 内の並列実行例:
Task: "T005 [P] [US1] SwitcherViewModelTests.swift に一時アクティブ化フラグ連携テスト追加"
Task: "T006 [US1] SwitcherPanel.swift に show(mode:activateApp:) と元アプリ復元実装"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1（T001）でベースライン確認
2. Phase 2（T002〜T004）で純粋ロジックとプロトコル基盤を確定
3. Phase 3（T005〜T009）を完了し、通常スイッチャー（`Option + Tab`）がパスワード入力欄上で完全動作する MVP を確立
4. ユニットテストおよび実機で MVP を独立検証

### Incremental Delivery

1. MVP（US1）完了後、Phase 4（US2：検索ランチャー `Option + Space` 対応）を追加
2. Phase 5（US3：セキュア入力残留・クールダウン耐性とライフサイクルクリーンアップ）を強化
3. Phase 6（US4：設定変更・記録サスペンド・OS 予約キー安全処理）を統合
4. Phase 7（T016〜T018）で日本語ドキュメント・全テスト合格・実機 E2E 検証を完了
