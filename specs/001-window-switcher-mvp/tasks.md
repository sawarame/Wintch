---

description: "Wintch MVP 実装のための依存関係順タスクリスト"
---

# Tasks: Wintch ウィンドウ単位スイッチャー (MVP)

**Input**: 設計ドキュメント `/specs/001-window-switcher-mvp/`  
**Prerequisites**: [plan.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/001-window-switcher-mvp/plan.md), [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/001-window-switcher-mvp/spec.md), [research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/001-window-switcher-mvp/research.md), [data-model.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/001-window-switcher-mvp/data-model.md), [service-contracts.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/001-window-switcher-mvp/contracts/service-contracts.md), [ui-contracts.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/001-window-switcher-mvp/contracts/ui-contracts.md)

**Tests**: プロジェクト憲章（テスト可能性）に基づき、純粋なビジネスロジック（ノイズ除外、MRUソート、選択計算、ショートカット判定）および ViewModel 状態遷移のユニットテスト（Swift Testing）を含みます。

**Organization**: ユーザーストーリー単位（US1, US2, US3）にフェーズを分割し、各ストーリーが独立して実装・テスト・検証可能な構成としています。すべてのコードは日本語ドキュメントコメントおよび日本語インラインコメントを必須とします。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並列実行可能（異なるファイルで未完了タスクへの依存なし）
- **[Story]**: 所属するユーザーストーリー（`[US1]`, `[US2]`, `[US3]`）
- すべてのタスクに具体的なファイルパスを記載

---

## Phase 1: Setup（プロジェクト初期化と基盤構築）

**Purpose**: 外部依存ゼロの Swift Package プロジェクトおよび `.app` バンドル生成基盤を構築する

- [ ] T001 `WintchCore`（ライブラリ）、`Wintch`（実行可能ターゲット）、`WintchCoreTests`（Swift Testing テストターゲット）を定義した macOS 14.0+ 向けパッケージ定義とディレクトリ構造を `Package.swift` に作成する（`dependencies: []`）
- [ ] T002 [P] `LSUIElement = YES`（Dock 非表示）、バンドル識別子、アプリ基本メタデータを定義した `Resources/Info.plist` を作成する
- [ ] T003 [P] `swift build` 成果物を `.build/Wintch.app` として組み立て・アドホック署名を行うビルドスクリプトを `scripts/build-app.sh` に作成し実行権限を付与する

---

## Phase 2: Foundational（全ストーリー共通の前提基盤）

**Purpose**: すべてのユーザーストーリーが依存するドメインモデル、サービス契約プロトコル、テスト用モック、アプリ統括基盤を整備する

**⚠️ CRITICAL**: このフェーズが完了するまでユーザーストーリーフェーズへ進めない

- [ ] T004 [P] 修飾キー選択肢（`Option`/`Control`/`Command`）、トリガーキー選択肢（`Tab`=48/`Space`=49/`Grave`=50/`Backslash`=42）、デフォルト `Option + Tab`、単体キー禁止および `Command + Tab` 競合フラグを持つ `ShortcutPreference` を `Sources/WintchCore/Domain/ShortcutPreference.swift` に実装する
- [ ] T005 [P] 収集用候補値型 `RawWindowCandidate` および表示用純粋値型 `WindowEntry`（`Identifiable`, `Equatable`, `Sendable`）を `Sources/WintchCore/Domain/RawWindowCandidate.swift` および `Sources/WintchCore/Domain/WindowEntry.swift` に実装する
- [ ] T006 [P] 権限状態列挙型 `AccessibilityPermissionStatus`（`.granted`, `.denied`）を `Sources/WintchCore/Domain/AccessibilityStatus.swift` に実装する
- [ ] T007 [P] `Services/` 層の境界プロトコル（`WindowServicing`, `HotKeyMonitoring`, `AccessibilityPermissionServicing`, `PreferencesStoring`, `LaunchAtLoginServicing`, `IconProviding`）を `Sources/WintchCore/Services/Protocols/WindowServicing.swift`, `HotKeyMonitoring.swift`, `AccessibilityPermissionServicing.swift`, `PreferencesStoring.swift`, `LaunchAtLoginServicing.swift`, `IconProviding.swift` に定義する
- [ ] T008 テスト用モックサービス群（`MockWindowService`, `MockHotKeyMonitor`, `MockAccessibilityPermissionService`, `MockPreferencesStore`, `MockLaunchAtLoginService`, `MockIconProvider`）を `Tests/WintchCoreTests/Mocks/MockServices.swift` に実装する（T004〜T007 依存）
- [ ] T009 DI コンテナ兼アプリ状態統括を行う `AppCoordinator` の骨格を `Sources/WintchCore/App/AppCoordinator.swift` に作成し、`@main` エントリポイント骨格を `Sources/Wintch/WintchApp.swift` に作成する（T004〜T007 依存）

**Checkpoint**: ドメイン型・サービスプロトコル・アプリ骨格が完成し、各ユーザーストーリーの並列/順次実装が可能になる

---

## Phase 3: User Story 1 - キーボード操作によるウィンドウ単位の高速切り替え (Priority: P1) 🎯 MVP

**Goal**: デフォルトショートカット（`Option + Tab`）によるフローティングパネル表示、MRU順リスト（アプリアイコン・アプリ名・ウィンドウタイトル、初期選択2番目）、`Shift` 併用での逆順移動、修飾キー解放での操作スペース横断アクティブ化、`Esc` キャンセル、ノイズウィンドウ除外を提供する

**Independent Test**: 複数アプリおよび同一アプリの複数ウィンドウ（別操作スペース含む）を開いた状態で `Option + Tab` 押下〜`Tab`/`Shift+Tab` 選択移動〜`Option` 解放での確定移動・`Esc` キャンセルが動作し、かつ全ユニットテスト（`WindowFilterTests`, `WindowSorterTests`, `SwitcherSelectionTests`, `SwitcherViewModelTests`）がパスすること

### Tests for User Story 1 ⚠️

> **NOTE**: 純粋ロジックおよび ViewModel のテストを先に記述し、実装前に失敗することを確認する

- [ ] T010 [P] [US1] ノイズ除外ルール（`isSelf == false`, `isRegularApplication == true`, `layer == 0`, `alpha > 0.0`, `bounds.width >= 50 && bounds.height >= 50`, `axSubrole` チェック）の境界値テストを `Tests/WintchCoreTests/WindowFilterTests.swift` に作成する
- [ ] T011 [P] [US1] MRU順（`lastActivatedAt` 降順優先）および未記録時の `zOrderIndex` 昇順フォールバックのテストを `Tests/WintchCoreTests/WindowSorterTests.swift` に作成する
- [ ] T012 [P] [US1] 初期選択インデックス算出（0件→nil, 1件→0, 2件以上→1）と Wrap-Around 次/前移動計算のテストを `Tests/WintchCoreTests/SwitcherSelectionTests.swift` に作成する
- [ ] T013 [P] [US1] `MockServices` を用いた `SwitcherViewModel` の状態遷移（`.idle` ⇄ `.active`、確定、キャンセル、フォーカス喪失、権限未許可ガード）のテストを `Tests/WintchCoreTests/SwitcherViewModelTests.swift` に作成する

### Implementation for User Story 1

- [ ] T014 [P] [US1] ノイズウィンドウ除外純粋ロジック `WindowFilter`（`RawWindowCandidate` から有効な `WindowEntry` への変換含む）を `Sources/WintchCore/Domain/WindowFilter.swift` に実装する
- [ ] T015 [P] [US1] MRU＋Zオーダーソート純粋ロジック `WindowSorter` を `Sources/WintchCore/Domain/WindowSorter.swift` に実装する
- [ ] T016 [P] [US1] 初期選択および Wrap-Around 選択計算純粋ロジック `SwitcherSelection` を `Sources/WintchCore/Domain/SwitcherSelection.swift` に実装する
- [ ] T017 [US1] `@Observable` な `SwitcherViewModel`（`.idle`/`.active` 状態管理、キーイベント処理、クリック確定、外部フォーカス喪失キャンセル）を `Sources/WintchCore/ViewModels/SwitcherViewModel.swift` に実装する（T014〜T016 依存）
- [ ] T018 [P] [US1] `NSRunningApplication` ベースのアプリアイコンキャッシュサービス `IconProviderService` を `Sources/WintchCore/Services/IconProviderService.swift` に実装する
- [ ] T019 [US1] `CGWindowListCopyWindowInfo`（全操作スペース・Zオーダー）＋ `AXUIElement` / `AXObserver`（タイトル取得・MRUキャッシュ・`activate(options: [])`＋`kAXRaiseAction`＋スペース移動後再照合フォールバック、非公開API・画面収録権限一切不使用）を実装した `WindowService` を `Sources/WintchCore/Services/WindowService.swift` に実装する
- [ ] T020 [US1] `CGEventTap`（`keyDown`/`flagsChanged` 監視、設定ショートカット・スイッチャー表示中 `Esc`/上下矢印のイベント横取り消費、タイムアウト無効化時の自動再有効化）を実装した `HotKeyMonitorService` を `Sources/WintchCore/Services/HotKeyMonitorService.swift` に実装する
- [ ] T021 [P] [US1] SwiftUI 縦型リスト UI `SwitcherListView`（24x24アイコン・アプリ名・1行省略タイトル、ハイライト表示、`ScrollViewReader` 追従、サムネイルや操作ボタンなし）を `Sources/WintchCore/Views/SwitcherListView.swift` に実装する
- [ ] T022 [US1] `NSPanel`（`.nonactivatingPanel`, `.floating`, `.canJoinAllSpaces`, `.fullScreenAuxiliary`、アクティブスクリーン中央配置、フォーカス喪失時キャンセルコールバック）ラッパー `SwitcherPanel` を `Sources/WintchCore/Views/SwitcherPanel.swift` に実装する（T021 依存）
- [ ] T023 [US1] `AppCoordinator` に `WindowService`, `HotKeyMonitorService`, `IconProviderService`, `SwitcherViewModel`, `SwitcherPanel` を接続して US1 の一連の切り替えフローを統合する（`Sources/WintchCore/App/AppCoordinator.swift`）

**Checkpoint**: User Story 1（中核MVP）が単独で動作し、純粋ロジックおよび ViewModel テストがすべてパスする状態

---

## Phase 4: User Story 2 - アクセシビリティ権限の確認と安全な誘導 (Priority: P1)

**Goal**: アクセシビリティ権限の状態を検知し、未許可でもクラッシュせず手順案内とシステム設定への誘導画面を表示し、許可を検知したら自動的に通常機能を有効化する

**Independent Test**: システム設定でアクセシビリティ権限をオフにして起動した際、誘導画面が表示され「システム設定を開く」ボタンで設定画面へ遷移でき、権限オン後に自動で誘導画面が閉じて切り替え可能になること

### Tests for User Story 2 ⚠️

- [ ] T024 [P] [US2] `PermissionGuideViewModel` の権限状態検知、システム設定起動呼び出し、許可遷移時の自動クローズ通知テストを `Tests/WintchCoreTests/PermissionGuideViewModelTests.swift` に作成する

### Implementation for User Story 2

- [ ] T025 [P] [US2] `AXIsProcessTrusted()` の確認・変更監視（ポーリング）および「システム設定 > プライバシーとセキュリティ > アクセシビリティ」ディープリンクを開く `AccessibilityPermissionService` を `Sources/WintchCore/Services/AccessibilityPermissionService.swift` に実装する
- [ ] T026 [US2] `@Observable` な `PermissionGuideViewModel` を `Sources/WintchCore/ViewModels/PermissionGuideViewModel.swift` に実装する（T025 依存）
- [ ] T027 [US2] 3ステップ手順案内、画面収録権限不使用の安心説明、「システム設定を開く」ボタンを含む `PermissionGuideView` を `Sources/WintchCore/Views/PermissionGuideView.swift` に実装する（T026 依存）
- [ ] T028 [US2] `AppCoordinator` および `WintchApp` に起動時・常駐中の権限状態監視、未許可時の誘導画面自動表示、許可後の `HotKeyMonitorService` / `WindowService` 自動開始ロジックを統合する（`Sources/WintchCore/App/AppCoordinator.swift`, `Sources/Wintch/WintchApp.swift`）

**Checkpoint**: 権限許可・未許可のいずれの環境でもクラッシュせず安全に誘導・復帰できる状態（US1 + US2 完了）

---

## Phase 5: User Story 3 - メニューバー常駐と基本設定のカスタマイズ (Priority: P2)

**Goal**: Dock 非表示・メニューバー常駐から「設定を開く...」「Wintch を終了」を提供し、設定画面からショートカット変更・永続化と「ログイン時に自動起動」の ON/OFF 切り替えを行えるようにする

**Independent Test**: Dock にアイコンが出ずメニューバーにアイコンが表示され、設定画面で `Control + Space`・自動起動 ON に変更後、変更したショートカットでスイッチャーが起動し、メニューから終了できること

### Tests for User Story 3 ⚠️

- [ ] T029 [P] [US3] `ShortcutPreference` のシリアライズ・デフォルト値復元および `SettingsViewModel` の変更即時反映・エラー表示テストを `Tests/WintchCoreTests/ShortcutPreferenceTests.swift` および `Tests/WintchCoreTests/SettingsViewModelTests.swift` に作成する

### Implementation for User Story 3

- [ ] T030 [P] [US3] `UserDefaults` を用いた設定永続化ストア `PreferencesStore` を `Sources/WintchCore/Services/PreferencesStore.swift` に実装する
- [ ] T031 [P] [US3] `SMAppService.mainApp` を用いたログイン時自動起動管理サービス `LaunchAtLoginService` を `Sources/WintchCore/Services/LaunchAtLoginService.swift` に実装する
- [ ] T032 [US3] `@Observable` な `SettingsViewModel`（修飾キー・トリガーキー変更の保存と `HotKeyMonitorService` への即時反映、自動起動トグル＋エラーメッセージ、権限状態表示）を `Sources/WintchCore/ViewModels/SettingsViewModel.swift` に実装する（T030, T031 依存）
- [ ] T033 [US3] ショートカットピッカー（`Command + Tab` 競合警告表示含む）、自動起動トグル、権限状態表示のみのシンプル構成の `SettingsView` を `Sources/WintchCore/Views/SettingsView.swift` に実装する（T032 依存）
- [ ] T034 [US3] `WintchApp.swift` の `MenuBarExtra`（「設定を開く...」「Wintch を終了」、権限未許可時の案内メニュー）および設定ウィンドウ表示制御を `AppCoordinator` に統合する（`Sources/Wintch/WintchApp.swift`, `Sources/WintchCore/App/AppCoordinator.swift`）

**Checkpoint**: すべてのユーザーストーリー（US1, US2, US3）が統合され、独立して検証可能な完全な MVP 構成になる

---

## Phase 6: Polish & Cross-Cutting Concerns（仕上げと品質監査）

**Purpose**: プロジェクト憲章のコーディング規約・プライバシー/API制約の最終確認と E2E 検証

- [ ] T035 [P] `Sources/` 配下の全クラス・構造体・関数・メソッドについて、日本語ドキュメントコメント（概要・`@param`・`@returns`）および日本語インラインコメントの記載漏れを監査・補完する
- [ ] T036 [P] プロジェクト憲章違反チェック（`ScreenCaptureKit`, `CGS*`, `_AXUIElementGetWindow`, `ObservableObject`, `@Published`, 外部依存、`Services/` 外での低レイヤーAPIインポートの不在）を実施する
- [ ] T037 `swift build` および `swift test` を実行して全テストパスを確認し、`./scripts/build-app.sh` で生成した `.build/Wintch.app` に対して [quickstart.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/001-window-switcher-mvp/quickstart.md) のシナリオ A〜C を検証する

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし — 即座に開始可能
- **Foundational (Phase 2)**: Phase 1 完了後に開始 — すべてのユーザーストーリーをブロックする
- **User Story 1 (Phase 3 - P1)**: Phase 2 完了後に開始可能（MVPの核）
- **User Story 2 (Phase 4 - P1)**: Phase 2 完了後に開始可能（US1と並列開発可、統合時は `AppCoordinator` で接続）
- **User Story 3 (Phase 5 - P2)**: Phase 2 完了後に開始可能（US1/US2と並列開発可、統合時は `WintchApp` / `AppCoordinator` で接続）
- **Polish (Phase 6)**: Phase 3〜5 完了後に実行

### Within Each User Story

- テスト（`Tests/WintchCoreTests/`）を先に記述し、実装前の失敗を確認する
- 純粋ドメインロジック（`Domain/`）→ ViewModel（`ViewModels/`）と低レイヤーサービス（`Services/`）を並列構築 → UI（`Views/`）→ `AppCoordinator` 統合の順に進める

---

## Parallel Example: User Story 1

```bash
# US1 のテストと純粋ドメインロジック・独立サービス・リストUIを並列実装:
- T010: Tests/WintchCoreTests/WindowFilterTests.swift
- T011: Tests/WintchCoreTests/WindowSorterTests.swift
- T012: Tests/WintchCoreTests/SwitcherSelectionTests.swift
- T014: Sources/WintchCore/Domain/WindowFilter.swift
- T015: Sources/WintchCore/Domain/WindowSorter.swift
- T016: Sources/WintchCore/Domain/SwitcherSelection.swift
- T018: Sources/WintchCore/Services/IconProviderService.swift
- T021: Sources/WintchCore/Views/SwitcherListView.swift
```

---

## Implementation Strategy

### MVP First（まず User Story 1 + 最低限の権限ガード）

1. Phase 1（Setup）および Phase 2（Foundational）を完了する
2. Phase 3（User Story 1）を完了し、`swift test` および単体ウィンドウ切り替えを検証する
3. Phase 4（User Story 2）を完了し、初回起動時の権限未許可環境での安全な誘導を検証する
4. Phase 5（User Story 3）でメニューバー常駐・ショートカット変更・自動起動を追加する
5. Phase 6（Polish）で憲章監査・日本語コメント確認・`quickstart.md` 実機シナリオを完走する
