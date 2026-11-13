# 実装計画 (Implementation Plan): Wintch ウィンドウ単位スイッチャー (MVP)

**Branch**: `001-window-switcher-mvp` | **Date**: 2026-11-13 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/001-window-switcher-mvp/spec.md)

**Input**: Feature specification from `/specs/001-window-switcher-mvp/spec.md`

## Summary

macOS 14.0+ 向けの軽量・最小権限なウィンドウ単位スイッチャー「Wintch」の MVP を構築する。画面収録権限および非公開APIを一切使用せず、`CGWindowListCopyWindowInfo`（全操作スペースのウィンドウメタデータおよびZオーダー）と `AXUIElement` / `AXObserver`（タイトル取得・MRU追跡・アクティブ化）のハイブリッド構成により、操作スペース横断のウィンドウ切り替えを実現する。UI は SwiftUI（`@Observable` 状態管理）を中心に構築し、フローティングパネル（`NSPanel`）およびグローバルキー監視（`CGEventTap`）の低レイヤー処理は `Services/` 層および最小限のパネルラッパーへ隔離する。

## Technical Context

**Language/Version**: Swift 6（Swift 6.4.2 ツールチェーン / macOS SDK 27.2 環境で確認済み）  
**Primary Dependencies**: Apple標準フレームワークのみ（`SwiftUI`, `AppKit`, `ApplicationServices`, `CoreGraphics`, `ServiceManagement`, `Observation`）。外部サードパーティ依存ゼロ。  
**Storage**: `UserDefaults`（ショートカット設定の永続化）および OS `SMAppService.mainApp`（ログイン時自動起動状態）  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`LSUIElement = YES`）  
**Performance Goals**: ショートカット入力からパネル表示まで 100ms 未満、確定からウィンドウ切り替え開始まで 200ms 未満、待機時 CPU 使用率 1% 未満  
**Constraints**: 画面収録権限（ScreenCaptureKit 等）不使用、非公開API（`CGS*`, `_AXUIElementGetWindow` 等）不使用、MIT License  
**Scale/Scope**: 単一ユーザー向けローカルユーティリティ（MVP 4画面/コンポーネント：メニューバー、スイッチャーパネル、設定画面、権限誘導画面）

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限の原則（Privacy by Design）** | ScreenCaptureKit や画面収録権限を一切使わず、`AXUIElement` とウィンドウメタデータのみで実装 | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | 縦型リスト（アイコン・アプリ名・タイトルのみ）と最小限の設定2項目（ショートカット・自動起動）に限定 | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | `AXObserver` によるキャッシュ活用と軽量 `CGEventTap`（非ブロッキング）により即時応答を維持 | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | `Package.swift` の `dependencies` は空。Apple標準フレームワークのみで完結 | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | `CGS*` や `_AXUIElementGetWindow` 等の私的APIを使用せず、権限未許可時は誘導画面へフォールバック | PASS |
| **6. 技術スタック・MVVM + Services** | macOS 14.0+ / Swift、SwiftUI + 最小限の `NSPanel`、`@Observable` 採用、低レイヤーAPIを `Services/` に隔離 | PASS |
| **7. 可読性・テスト可能性・ライセンス** | `@main` 衝突を避ける `WintchCore` + `Wintch` の2ターゲット構成で純粋ロジックを `swift test` 可能にし、日本語ドキュメントコメント・MIT License に準拠 | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/001-window-switcher-mvp/
├── plan.md              # 本実装計画書
├── research.md          # Phase 0 技術調査レポート
├── data-model.md        # Phase 1 データモデル・状態遷移設計
├── quickstart.md        # Phase 1 ビルド・実機検証ガイド
├── contracts/           # Phase 1 サービス・UIコントラクト
│   ├── service-contracts.md
│   └── ui-contracts.md
└── checklists/
    └── requirements.md  # 仕様品質チェックリスト
```

### Source Code (repository root)

Swift Package Manager において `@main` エントリポイントとテストターゲットのリンク衝突を防ぐため、実装本体を `WintchCore`（ライブラリターゲット）、起動エントリポイントを `Wintch`（実行可能ターゲット）とするシンプルかつ標準的な2ターゲット構成を採用する。

```text
Package.swift
Resources/
└── Info.plist                   # LSUIElement = YES, Bundle Identifier 等
scripts/
└── build-app.sh                 # swift build 成果物を .app バンドル化するスクリプト

Sources/
├── Wintch/
│   └── WintchApp.swift          # @main エントリポイント、MenuBarExtra、Settings/誘導シーン定義
└── WintchCore/
    ├── App/
    │   └── AppCoordinator.swift # アプリ全体の起動制御・権限監視・パネル/設定画面の統括
    ├── Domain/
    │   ├── WindowEntry.swift        # 確定済みウィンドウ項目（純粋値型）
    │   ├── RawWindowCandidate.swift # サービス層から受け取るフィルタ前ウィンドウ候補
    │   ├── ShortcutPreference.swift # 修飾キー・トリガーキー定義と永続化用モデル
    │   ├── AccessibilityStatus.swift# 権限状態モデル
    │   ├── WindowFilter.swift       # 純粋関数：ノイズウィンドウ除外ロジック
    │   ├── WindowSorter.swift       # 純粋関数：MRU＋Zオーダーソートロジック
    │   └── SwitcherSelection.swift  # 純粋関数：初期インデックス算出・次/前選択計算
    ├── Services/
    │   ├── Protocols/
    │   │   ├── WindowServicing.swift
    │   │   ├── HotKeyMonitoring.swift
    │   │   ├── AccessibilityPermissionServicing.swift
    │   │   ├── PreferencesStoring.swift
    │   │   ├── LaunchAtLoginServicing.swift
    │   │   └── IconProviding.swift
    │   ├── WindowService.swift                  # CGWindow + AXUIElement + AXObserver 実装
    │   ├── HotKeyMonitorService.swift           # CGEventTap 実装
    │   ├── AccessibilityPermissionService.swift # AXIsProcessTrusted + 設定画面遷移
    │   ├── PreferencesStore.swift               # UserDefaults 実装
    │   ├── LaunchAtLoginService.swift           # SMAppService.mainApp 実装
    │   └── IconProviderService.swift            # NSRunningApplication アイコンキャッシュ
    ├── ViewModels/
    │   ├── SwitcherViewModel.swift              # @Observable スイッチャー状態・操作制御
    │   ├── SettingsViewModel.swift              # @Observable 設定画面状態制御
    │   └── PermissionGuideViewModel.swift       # @Observable 権限誘導画面状態制御
    └── Views/
        ├── SwitcherPanel.swift                  # NSPanel (.nonactivatingPanel) ラッパー
        ├── SwitcherListView.swift               # スイッチャー縦型リスト UI (SwiftUI)
        ├── SettingsView.swift                   # 設定画面 UI (SwiftUI)
        └── PermissionGuideView.swift            # アクセシビリティ権限誘導画面 UI (SwiftUI)

Tests/
└── WintchCoreTests/
    ├── Mocks/
    │   └── MockServices.swift                   # テスト用モックサービス群
    ├── WindowFilterTests.swift                  # ノイズ除外の網羅テスト
    ├── WindowSorterTests.swift                  # MRU・Zオーダーソートのテスト
    ├── SwitcherSelectionTests.swift             # 0/1/2件以上の初期選択・Wrap-Aroundテスト
    ├── ShortcutPreferenceTests.swift            # ショートカット設定・デフォルト値・Codableテスト
    └── SwitcherViewModelTests.swift             # 状態遷移・権限フォールバックのテスト
```

**Structure Decision**:
- Apple標準の Swift Package 構成を採用し、`WintchCore` 内に `Domain/`、`Services/`、`ViewModels/`、`Views/` を明確に分離する。
- 低レイヤーAPI（CoreGraphics / ApplicationServices / ServiceManagement）の `import` および呼び出しは `Sources/WintchCore/Services/` 配下の具象クラスのみに限定し、`Domain/`・`ViewModels/`・`Views/` への漏洩を完全に防ぐ。
- `.app` バンドル生成スクリプト（`scripts/build-app.sh`）を用意することで、Xcode なしの CLI 環境でも `LSUIElement` や `SMAppService` を含む完全な実機テストが可能になる。

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
