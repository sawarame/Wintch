# Tasks: 画面収録権限未許可時のスイッチャー内設定リンク削除

**Input**: Design documents from `/specs/017-remove-switcher-permission-link/`  
**Prerequisites**: [plan.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/017-remove-switcher-permission-link/plan.md), [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/017-remove-switcher-permission-link/spec.md), [research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/017-remove-switcher-permission-link/research.md), [data-model.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/017-remove-switcher-permission-link/data-model.md), [contracts/switcher-permission-banner-contract.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/017-remove-switcher-permission-link/contracts/switcher-permission-banner-contract.md)

**Organization**: ユーザーストーリー単位（US1 → US2）にタスクを整理し、各ストーリーを独立して検証可能にする。

## Phase 1: Setup（現状確認）

**Purpose**: 既存コードとテストのベースラインを確認し、修正対象箇所を確定する。

- [ ] T001 変更前ベースライン確認として `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行し、現行コードのテスト状態を確認する（`Sources/WintchCore/Views/SwitcherCaptureGridView.swift`, `Sources/WintchCore/ViewModels/SwitcherViewModel.swift`）

---

## Phase 2: User Story 1 - 画面収録権限未許可のキャプチャ表示型スイッチャーからクリック不能な設定リンクをなくす (Priority: P1) 🎯 MVP

**Goal**: 画面収録権限が未許可の状態で「キャプチャ表示型」通常スイッチャーを開いた際、パネル上部の案内バナーから「設定を開く」リンクを削除して非インタラクティブな案内文のみを表示し、不要となった ViewModel の設定遷移メソッドも整理する。

**Independent Test**: `isScreenRecordingGranted == false` の状態で `SwitcherCaptureGridView` を描画した際、ビュー階層にクリック可能なボタン・リンクが存在せず案内文が省略されずに配置されること、および `SwitcherViewModel` でプレースホルダー表示のままウィンドウ切り替え・キャンセルが完了することを自動テストで検証する。

### Implementation & Tests for User Story 1

- [ ] T002 [US1] `Sources/WintchCore/Views/SwitcherCaptureGridView.swift` の `permissionBannerView` から `Button("設定を開く")`（`.buttonStyle(.link)`）および `Spacer(minLength: 4)` を削除し、定数 `permissionBannerMessage` を定義して `.fixedSize(horizontal: false, vertical: true)` と `.frame(maxWidth: .infinity, alignment: .leading)` による非インタラクティブ・非省略レイアウトへ更新する
- [ ] T003 [US1] `Sources/WintchCore/ViewModels/SwitcherViewModel.swift` からスイッチャーパネル専用で不要となった `onOpenScreenRecordingSettingsRequested` プロパティおよび `openScreenRecordingSettings()` メソッドを削除する
- [ ] T004 [P] [US1] `Tests/WintchCoreTests/SwitcherViewModelTests.swift` の `captureStyleFallbackSessionSafetyAndOptInIsolation()` から削除対象 `openScreenRecordingSettings()` 呼び出し部分を整理し、未許可状態でのフォールバック表示・ウィンドウ切り替え・ランチャー非介入の検証を維持する
- [ ] T005 [P] [US1] `Tests/WintchCoreTests/SwitcherCaptureGridViewTests.swift` を新規作成し、`isScreenRecordingGranted == false` の状態で `NSHostingView` にホストした際にクリック可能な `NSButton`（設定リンク）が生成されないこと、最小幅 `360pt` 以上で正の `fittingSize` を持つこと、および `isScreenRecordingGranted == true` 時はバナー分だけ高さが抑えられることを検証する

**Checkpoint**: User Story 1 の実装およびテストが単体で完結・パスする状態。

---

## Phase 3: User Story 2 - 設定画面からの画面収録権限設定導線は維持する (Priority: P2)

**Goal**: スイッチャーパネル上の設定リンク削除後も、メニューバーから開ける設定画面の画面収録権限案内・リクエスト・システム設定を開く操作導線がそのまま機能することを保証する。

**Independent Test**: `SettingsViewModelTests` および `SettingsView.swift` の確認により、`SettingsViewModel.openScreenRecordingSettings()` 等の挙動が影響を受けずに動作することを検証する。

### Verification for User Story 2

- [ ] T006 [US2] `Sources/WintchCore/Views/SettingsView.swift` および `Tests/WintchCoreTests/SettingsViewModelTests.swift` を確認・実行し、設定画面における画面収録権限の状態表示・権限リクエスト・システム設定を開く動作が従来通りパスすることを確認する

**Checkpoint**: User Story 1 と User Story 2 の双方が独立して検証済み。

---

## Phase 4: Polish & Cross-Cutting Concerns

**Purpose**: 全体の整合性・日本語ドキュメント規約・全ユニットテスト・アプリビルドの検証を完了する。

- [ ] T007 変更ファイル全体の日本語コメント・SwiftDoc（`///`）規約および Wintch 憲章 v2.0.0 準拠を確認する（`Sources/WintchCore/Views/SwitcherCaptureGridView.swift`, `Sources/WintchCore/ViewModels/SwitcherViewModel.swift`, `Tests/WintchCoreTests/`）
- [ ] T008 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` を実行し、全ユニットテストがエラー・スキップなしでパスすることを確認する
- [ ] T009 `./scripts/build-app.sh` を実行し、`.build/Wintch.app` のビルドがエラーなく成功することを確認する

---

## Dependencies & Execution Order

### Phase Dependencies
- **Phase 1 (Setup)**: 依存なし — 最初にベースライン確認を実施
- **Phase 2 (US1)**: Phase 1 完了後に着手。T002 と T003 は別ファイルだが独立に実施可能、T004・T005 は T002・T003 完了後に並列実行可能
- **Phase 3 (US2)**: Phase 2 完了後に回帰確認を実施
- **Phase 4 (Polish)**: Phase 2・Phase 3 完了後に最終ビルド・全テスト検証を実施
