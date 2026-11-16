---

description: "Task list for 012-fix-chrome-window-switch"
---

# Tasks: 複数ウィンドウを持つブラウザ（Chrome 等）の正確な切り替えと一覧・キャプチャ整合性の確保

**Input**: Design documents from `/specs/012-fix-chrome-window-switch/`  
**Prerequisites**: `plan.md`（必須）, `spec.md`（必須）, `research.md`, `data-model.md`, `contracts/window-switching-contracts.md`, `quickstart.md`

**Tests**: 本機能は憲章（テスト可能性）および `quickstart.md` に従い、各ユーザーストーリーに先立って Swift Testing ユニットテストを追加・確認する（TDD アプローチ）。

**Organization**: 基盤純粋ヘルパーの定義を Phase 2 で整えた上で、ユーザーストーリー（`US1`: 確実なウィンドウ切り替え、`US2`: 補助 CGWindow からの枠保護、`US3`: 省略タイトル・メニュー鮮度・競合耐性）ごとに独立して実装・テストできるよう構成している。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 異なるファイルを扱い、未完了タスクへの依存がなく並列実行可能なタスク
- **[Story]**: 対応するユーザーストーリー（`US1`, `US2`, `US3`）。Setup / Foundational / Polish フェーズには付与しない
- すべてのタスクに正確なファイルパスと契約仕様上の制約を明記している

## Path Conventions

- ソースコード: `Sources/WintchCore/`
- ユニットテスト: `Tests/WintchCoreTests/`
- 仕様ドキュメント: `specs/012-fix-chrome-window-switch/`

---

## Phase 1: Setup（ベースライン確認）

**Purpose**: 既存コードと全ユニットテストのベースライン状態を確認する

- [X] T001 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行し、`Package.swift` および `Tests/WintchCoreTests/` の既存テストベースラインが全件合格することを確認する

---

## Phase 2: Foundational（サービス層純粋判定ヘルパーの基盤定義）

**Purpose**: `Services/WindowService.swift` の非公開 OS 制御から独立してユニットテスト可能な純粋判定ヘルパーと状態モデルを定義し、各ユーザーストーリーの実装・検証の土台を整える

**⚠️ CRITICAL**: User Story 1 および User Story 3 は `WindowService` 上の共通純粋判定ヘルパーを利用するため、Phase 2 完了後にストーリー実装へ進む（User Story 2 の `Domain/WindowMenuPairing.swift` テスト作成は並列着手可能）

- [X] T002 `Sources/WintchCore/Services/WindowService.swift` に、`ActivationPlan` 構造体（同スペース即時前面化 / メニュー遷移成功時非競合 / メニュー失敗時フォールバックを表現する内部値型）、`isMenuCacheFresh(fetchedAt:now:ttl:)`（`now.timeIntervalSince(fetchedAt)` が `0...ttl` 範囲のみ `true`）、および `shouldEvictCachedWindowAsReplacedTab(...)`（`allowDisplaySpanningReplacement == true` かつ `isReplacedTabBounds == true` かつ独立生存 `CGWindowID` 不在のみ `true`）を `nonisolated static` 純粋ヘルパーとして日本語ドキュメントコメント付きで定義する

**Checkpoint**: 基盤の純粋判定ヘルパーおよび値型がコンパイル可能となり、US1〜US3 のテスト先行記述・実装に進める状態になる

---

## Phase 3: User Story 1 - 複数ウィンドウを開いている状態で、選択した対象ウィンドウへ確実に切り替える (Priority: P1) 🎯 MVP

**Goal**: 同一位置・同一サイズや別操作スペースに複数の Chrome ウィンドウが開かれていても、別スペース側の `CachedAXWindow` を誤削除せず、さらにメニュー押下直後の同期 `app.activate()` 競合を排除して、選択した対象ウィンドウへ確実に移動・フォーカスできるようにする

**Independent Test**: `WindowCaptureAndMatchingTests` にて、(1) スペース移動時や同位置・同サイズかつ独立生存 `CGWindowID` を持つ別スペースウィンドウが `shouldEvictCachedWindowAsReplacedTab` で保護されること、および (2) `ActivationPlan` がメニュー押下成功時に同期的な `app.activate` 併走を抑止し、フォローアップ後に確定することを独立して検証できる

### Tests for User Story 1 ⚠️

> **NOTE: 先にテストを追加・更新し、期待挙動の未実装部分が失敗することを確認してから実装する**

- [X] T003 [P] [US1] `Tests/WintchCoreTests/WindowCaptureAndMatchingTests.swift` の `replacedTabBoundsDetectsTabSwitchWithoutEvictingOtherSpaceFullscreen` を更新・拡充し、通常サイズ（非フルスクリーン）の同矩形ウィンドウであっても `allowDisplaySpanningReplacement == false`（スペース移動・全体スキャン時）または独立して生存中の `cgWindowID` がある場合は `shouldEvictCachedWindowAsReplacedTab` が `false` となり、同一スペース内イベント（`allowDisplaySpanningReplacement == true` かつ独立 `cgWindowID` なし）のときのみ `true` となることを検証するテストを追加する
- [X] T004 [P] [US1] `Tests/WintchCoreTests/WindowCaptureAndMatchingTests.swift` に、`WindowService.makeActivationPlan(hasTargetAX:isPresentInCurrentSpace:menuNavigationSucceeded:)` 相当の純粋プラン判定（同スペース時は即時 `raiseAXWindow` + 即時 `app.activate`、別スペースかつメニュー押下成功時は同期 `app.activate` なし＋段階フォローアップあり、別スペースかつメニュー失敗時は即時フォールバック `app.activate`）を検証する単体テストを追加する

### Implementation for User Story 1

- [X] T005 [US1] `Sources/WintchCore/Services/WindowService.swift` の `applyAXWindowSnapshots(_:for:markFrontmostAsActive:allowDisplaySpanningReplacement:survivingCGWindowIDs:)` および `fetchRawWindowCandidates()` を更新し、現在の CGWindow 一覧の生存 `CGWindowID` 集合（新ウィンドウが引き継いだ ID を除く独立ウィンドウ群）を参照して `shouldEvictCachedWindowAsReplacedTab` を適用し、別スペースの同矩形通常ウィンドウが `cg-*` へ誤降格するのを防止する（T002, T003 に依存）
- [X] T006 [US1] `Sources/WintchCore/Services/WindowService.swift` に `pendingActivationFollowUpTask: Task<Void, Never>?` を追加して `activateWindow(_:)` を更新し、連続実行時の前回フォローアップキャンセル、`ActivationPlan` に従った非競合アクティブ化（メニュー押下成功時は即時の同期 `app.activate(options: [])` を行わない）、および段階ポーリング（60ms / 140ms / 280ms / 450ms 相当）による別スペース遷移検知後の安全な `app.activate(options: [])`・`raiseAXWindow`・MRU 時刻更新を実装する（T002, T004, T005 に依存）

**Checkpoint**: User Story 1（MVP）が完了し、同位置・別スペース・プレースホルダー状態を含む複数ウィンドウ選択時の別ウィンドウ誤遷移が解消される

---

## Phase 4: User Story 2 - 内部補助ウィンドウに実ウィンドウの枠を奪われず、正しいウィンドウ実体とキャプチャを対応付ける (Priority: P1)

**Goal**: Chrome のアドレスバー予測変換ポップアップ等の非表示内部補助 CGWindow（`1344x378` 等）が、本物の別スペースウィンドウより Z オーダー上位に出現しても、実ウィンドウのタイトルとキャプチャ枠を奪わないようにする

**Independent Test**: `WindowMenuPairingTests` にて、Z オーダー上位のオフスクリーン横長補助 CGWindow（`1344x378`）と Z オーダー下位の本物サイズ CGWindow（`1920x992` / `1200x800`）が混在する入力に対し、`applyMenuTitles` が本物のウィンドウ側へメニュータイトルを割り当て、補助 CGWindow を除外することを独立して検証できる

### Tests for User Story 2 ⚠️

- [X] T007 [P] [US2] `Tests/WintchCoreTests/WindowMenuPairingTests.swift` に、Z オーダー上位にあるオフスクリーンの横長扁平補助 CGWindow（例: `1344x378`, `isOnScreen: false`, `zOrder: 5`）と、Z オーダー下位にある本物の別スペースウィンドウ（例: `1920x992` または `1200x800`, `isOnScreen: false`, `zOrder: 30`）が混在しメニュー項目が 1 件のとき、本物のウィンドウがタイトルを獲得して残り、補助 CGWindow が除外されることを検証する単体テストを追加する（並行して、他に本物がない場合は補助形状でも単独通過することも検証する）

### Implementation for User Story 2

- [X] T008 [US2] `Sources/WintchCore/Domain/WindowMenuPairing.swift` の `WindowMenuCandidatePairing.cgCandidatePriority(_:)` を更新し、オフスクリーンかつ横長扁平な補助形状（`candidate.isOnScreen != true && candidate.bounds.height < 420.0 && (candidate.bounds.width / max(candidate.bounds.height, 1.0)) > 3.0`）に `auxiliaryShapePenalty = 1`（それ以外は `0`）を与える 4 要素タプル `(onScreenPriority, layerPriority, auxiliaryShapePenalty, zOrderIndex)` へ拡張して、既存テストおよび T007 を合格させる（T007 に依存）

**Checkpoint**: User Story 2 が完了し、Chrome の補助 CGWindow によるタイトル奪取とそれに伴うキャプチャ不能項目化が解消される

---

## Phase 5: User Story 3 - タイトルに省略記号が含まれる場合や動的変化がある場合でも正確にウィンドウを識別・遷移する (Priority: P2)

**Goal**: 元のウィンドウタイトル自体に「…」や「...」が含まれている場合の省略照合失敗、同一タイトル複数ウィンドウでの現在スペース側誤選択、および古いメニューキャッシュによる `kAXPressAction` 失敗を解消する

**Independent Test**: `WindowMenuPairingTests` と `WindowCaptureAndMatchingTests` にて、(1) 元タイトルに `…` / `...` を含む多重省略タイトルの一致判定、(2) `preferUnchecked: true` による同名ウィンドウの未チェック項目優先選択、(3) `isMenuCacheFresh` の TTL 境界判定をそれぞれ独立して検証できる

### Tests for User Story 3 ⚠️

- [X] T009 [P] [US3] `Tests/WintchCoreTests/WindowMenuPairingTests.swift` に、(a) 元タイトル自体に `…` または `...` が含まれていてメニュー上でさらに中央省略された場合に `titlesMatch` が `true` を返し無関係なタイトルでは `false` となること、および (b) `WindowMenuCandidatePairing.matchingMenuItemIndex(for:in:preferUnchecked:)` が同名タイトル複数存在時に `preferUnchecked: true` で未チェック項目を優先し、存在しない場合はチェック済みへフォールバックすることを検証するテストを追加する
- [X] T010 [P] [US3] `Tests/WintchCoreTests/WindowCaptureAndMatchingTests.swift` に、`WindowService.isMenuCacheFresh(fetchedAt:now:ttl:)` が `ttl = 2.0` 秒以内で `true`、超過または未来時刻（負経過）時に適切に判定されることを検証する単体テストを追加する

### Implementation for User Story 3

- [X] T011 [P] [US3] `Sources/WintchCore/Domain/WindowMenuPairing.swift` の `matchesEllipsisPattern(candidate:patternWithEllipsis:)` を複数省略記号セグメント対応（`…` / `...` をワイルドカードとして非空セグメント列に分解し、非ワイルドカード総文字数 `>= 4`、先頭／末尾一致、および中間セグメントの順序部分一致を検証）へ拡張し、`matchingMenuItemIndex(for:in:preferUnchecked:)` ヘルパーを追加する（T009 に依存）
- [X] T012 [US3] `Sources/WintchCore/Services/WindowService.swift` の `findMatchingMenuItem`・`resolveWindowMenuItemElement`・メニュー押下処理を、`isMenuCacheFresh`（`windowMenuCacheTTL` = `2.0` 秒）による期限確認、`matchingMenuItemIndex(..., preferUnchecked: true)` への委譲、および `AXUIElementPerformAction(menuItemElement, kAXPressAction)` が `.success` 以外を返した場合のキャッシュ破棄・最新メニュー再取得・1 回リトライ付き実行へ更新する（T002, T006, T010, T011 に依存）

**Checkpoint**: 全ユーザーストーリー（US1, US2, US3）が個別にテスト合格し、相互に退行なく機能する状態になる

---

## Phase 6: Polish & Cross-Cutting Concerns（規約確認・全体検証・ビルド確認）

**Purpose**: コーディング規約・憲章準拠のレビュー、全自動テスト実行、および `.app` バンドルビルドによる確認を行う

- [X] T013 [P] `Sources/WintchCore/Domain/WindowMenuPairing.swift` および `Sources/WintchCore/Services/WindowService.swift` のすべての型・関数・メソッドに日本語ドキュメントコメント（`///`）および日本語インラインコメントが記載され、英語コメントや憲章違反（外部依存・非公開 API・画面収録権限拡張）がないことをレビュー確認する
- [X] T014 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行し、全ユニットテストスイートが 100% 合格することを確認する（T006, T008, T012, T013 完了後）
- [X] T015 `specs/012-fix-chrome-window-switch/quickstart.md` に従い `./scripts/build-app.sh` で `.build/Wintch_dev.app` をビルドし、エラーなくバンドル生成できることを確認する（T014 完了後）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし — 即座に開始可能
- **Foundational (Phase 2)**: Phase 1 完了後 — `T002`（US1 と US3 の基盤）
- **User Story 1 (Phase 3)**: Phase 2 完了後 — `T003`・`T004`（並列テスト追加） → `T005` → `T006`
- **User Story 2 (Phase 4)**: Phase 1 完了後いつでも着手可能（`Domain/WindowMenuPairing.swift` のみで完結） — `T007` → `T008`
- **User Story 3 (Phase 5)**: Phase 2 完了後（`T012` のみ `T006` 後） — `T009`・`T010`（並列テスト追加） → `T011` → `T012`
- **Polish (Phase 6)**: Phase 3〜5 すべて完了後 — `T013` → `T014` → `T015`

### User Story Dependencies

- **User Story 1 (P1)**: Foundational（`T002`）後に独立実施可能
- **User Story 2 (P1)**: 変更ファイルが `WindowMenuPairing.swift` に閉じているため、US1 と完全に独立して並列実施可能
- **User Story 3 (P2)**: `WindowMenuPairing.swift` 側（`T009`, `T011`）は US2 完了後または直列で即実施可能、`WindowService.swift` 側（`T012`）は US1 の `T006` 完了後に統合

### Parallel Opportunities

- `T003` / `T004` と `T007` / `T009` はそれぞれ別テストファイル（`WindowCaptureAndMatchingTests.swift` と `WindowMenuPairingTests.swift`）のため並列作成可能
- Phase 4（`WindowMenuPairing.swift` の優先順位修正）と Phase 3（`WindowService.swift` のキャッシュ保護・アクティブ化修正）は異なるソースファイルを対象とするため並列実施可能

---

## Parallel Example: User Story 1 & User Story 2

```bash
# US1 のテスト (WindowCaptureAndMatchingTests.swift) と US2 のテスト (WindowMenuPairingTests.swift) を同時着手:
Task: "T003 [US1] WindowCaptureAndMatchingTests.swift に別スペース同矩形保護テストを追加"
Task: "T007 [US2] WindowMenuPairingTests.swift に補助 CGWindow 劣後ペアリングテストを追加"

# US1 (WindowService.swift) と US2 (WindowMenuPairing.swift) の実装を同時進行:
Task: "T005 [US1] WindowService.swift の旧タブ誤削除防止実装"
Task: "T008 [US2] WindowMenuPairing.swift の cgCandidatePriority 更新"
```

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 2)

1. Phase 1（`T001`）でベースライン確認
2. Phase 2（`T002`）で `WindowService` 純粋ヘルパー定義
3. Phase 3（`T003`〜`T006`）と Phase 4（`T007`〜`T008`）を完了し、Issue #13 の中核である「別スペース誤削除・補助窓タイトル奪取・`app.activate` 競合」を解消（**MVP 到達**）
4. Phase 5（`T009`〜`T012`）で「元タイトル内 `…` 省略・同名ウィンドウ・メニュー TTL リトライ」まで網羅
5. Phase 6（`T013`〜`T015`）で規約レビュー・全テスト・`.app` ビルドを完遂する

---

## Notes

- 各タスクのテストは必ず期待失敗または未検証状態を確認してから実装を進めること
- `WindowService.swift` への変更は `T002` → `T005` → `T006` → `T012` の順で直列実行し、コンフリクトを防ぐ
- すべての新規コードには日本語ドキュメントコメント（`///`）および日本語インラインコメントを必須とする
