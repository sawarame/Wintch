# 実装計画 (Implementation Plan): 通常スイッチャーのウィンドウキャプチャ表示型および表示形式切替設定

**Branch**: `007-window-capture-switcher` | **Date**: 2026-11-15 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/007-window-capture-switcher/spec.md)

**Input**: Feature specification from `/specs/007-window-capture-switcher/spec.md`

## Summary

通常スイッチャー（ホールド式）に表示形式設定（`SwitcherDisplayStyle`: 初期値 `.list`／オプトイン `.capture`）を導入し、設定画面で切り替えられるようにする。`.list` 選択時および検索ランチャー（`.launcher`）利用時は画面収録権限の確認・要求・キャプチャ処理を一切行わず従来通りのゼロ画面収録権限動作を維持する。`.capture` 選択時は `ScreenCaptureKit`（`SCShareableContent` + `SCScreenshotManager`）および `CGPreflightScreenCaptureAccess` を `Services/` 層に隔離し、起動時に直前キャッシュまたはアプリアイコンのプレースホルダーで即座に複数行カードグリッド（`SwitcherCaptureGridView`）を表示したうえで非同期に最新サムネイルを差し替え、上下左右矢印キー・トリガーキーによる 4 方向グリッド移動および権限未許可・取得不能時の安全なフォールバックを提供する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`、Strict Concurrency 準拠）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`SwiftUI`, `AppKit`, `Foundation`, `Observation`, `CoreGraphics`, `ScreenCaptureKit`）。外部サードパーティ依存ゼロ。  
**Storage**: 表示形式設定（`SwitcherDisplayStyle`）のみ `UserDefaults`（`PreferencesStore`）に永続化。ウィンドウキャプチャ画像はメモリ上の上限付き一時キャッシュ（最大 50 件の LRU）のみ保持し、ディスク保存・外部送信は行わない。  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`LSUIElement = YES`、`WintchCore` + `Wintch` 構成）  
**Performance Goals**: 通常スイッチャー起動から 100ms 以内にパネルと初期カード（プレースホルダーまたはキャッシュ）を表示し、画面収録権限許可済みの表示中ウィンドウは 500ms 以内に非同期最新キャプチャへ更新する。  
**Constraints**: リスト型・検索ランチャーでの画面収録権限不使用、オプトイン時のみ権限使用、非公開 API（`CGS*` 等）不使用、日本語ドキュメントコメント・インラインコメント必須、`@Observable` / `@MainActor` 遵守、セッション世代検証による非同期競合防止。  
**Scale/Scope**: `Domain/`（`SwitcherDisplayStyle`, `ScreenRecordingPermissionStatus`, `SwitcherGridLayout`）、`Services/`（`PreferencesStoring`/`PreferencesStore`, `ScreenRecordingPermissionServicing`/`ScreenRecordingPermissionService`, `WindowCaptureServicing`/`WindowCaptureService`, `HotKeyMonitoring`/`HotKeyMonitorService`）、`ViewModels/`（`SettingsViewModel`, `SwitcherViewModel`）、`App/`（`AppCoordinator`）、`Views/`（`SettingsView`, `PermissionGuideView`, `SwitcherPanel`, `SwitcherCaptureGridView`, `SwitcherContentView`）、および関連ユニットテスト。

## Constitution Check

*GATE: Phase 0 / Phase 1 設計完了後の最終検証済み（[constitution.md](file:///Users/sawarame_yasushi/dev/Wintch/.specify/memory/constitution.md) v2.0.0 準拠）。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限およびオプトインの原則（Privacy by Design）** | 初期値 `.list` および検索ランチャーでは `ScreenRecordingPermissionService`・`WindowCaptureService` を一切呼び出さず画面収録権限ゼロを維持する。`.capture` 選択時のみオプトインで使用し、取得画像はメモリ上の一時キャッシュ限定でディスク保存・外部送信を行わない | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | 設定追加は「リスト型」／「キャプチャ表示型」の 2 択のみにとどめ、サムネイルサイズや角丸等の細かな装飾設定を増やさない | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | パネル表示はキャプチャ完了を待たず即時実行し、バックグラウンドで縮小解像度の非同期取得・世代チェック付き差分反映・最大 50 件 LRU 上限管理を行う | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | Apple 標準フレームワーク（`ScreenCaptureKit`, `CoreGraphics`, `SwiftUI`, `AppKit`, `Observation`）のみ使用 | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。画面収録権限未許可時や最小化・別スペース等で取得不能時はアイコンプレースホルダーまたは直前キャッシュと権限案内を表示し、通常通りウィンドウ切り替え・終了が可能。`PermissionGuideView` 文言も新方針へ整合する | PASS |
| **6. 技術スタック・MVVM + Services** | `CGPreflightScreenCaptureAccess`, `CGRequestScreenCaptureAccess`, `SCShareableContent`, `SCScreenshotManager`, `CGEventTap` はすべて `Services/` に隔離し、プロトコル経由でテスト可能にする | PASS |
| **7. 可読性・テスト可能性・ライセンス** | グリッド列数算出・4 方向カーソル移動・キー判定は `Domain/` へ純粋関数として切り出し、モックサービスを用いて `ViewModel` / `AppCoordinator` を 100% 検証可能とし、日本語コメント規約を遵守する | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/007-window-capture-switcher/
├── spec.md                                         # 機能仕様書
├── plan.md                                         # 本実装計画書
├── research.md                                     # Phase 0 技術調査・意思決定記録
├── data-model.md                                   # Phase 1 データモデル・状態遷移設計
├── quickstart.md                                   # Phase 1 検証手順書
├── checklists/
│   └── requirements.md                             # 仕様品質チェックリスト
└── contracts/
    └── window-capture-switcher-contracts.md        # Phase 1 サービス・ViewModel・UI 契約定義
```

### Source Code (repository root)

```text
Sources/WintchCore/
├── App/
│   └── AppCoordinator.swift                        # [更新] 新サービス生成・注入、設定/スイッチャー間の表示形式同期、設定導線接続
├── Domain/
│   ├── SwitcherDisplayStyle.swift                  # [新規] 表示形式列挙型（.list デフォルト / .capture）
│   ├── ScreenRecordingPermissionStatus.swift       # [新規] 画面収録権限ステータス（.granted / .denied）
│   └── SwitcherGridLayout.swift                    # [新規] グリッド列数計算および 4 方向カーソル移動純粋ロジック
├── Services/
│   ├── Protocols/
│   │   ├── PreferencesStoring.swift                # [更新] loadNormalDisplayStyle / saveNormalDisplayStyle 追加
│   │   ├── HotKeyMonitoring.swift                  # [更新] ArrowDirection に .left / .right 追加
│   │   ├── ScreenRecordingPermissionServicing.swift # [新規] 画面収録権限確認・リクエスト・設定遷移プロトコル
│   │   └── WindowCaptureServicing.swift            # [新規] キャッシュ参照・非同期キャプチャ・破棄プロトコル
│   ├── PreferencesStore.swift                      # [更新] 表示形式設定の UserDefaults 永続化
│   ├── HotKeyMonitorService.swift                  # [更新] .normal モードでの左右矢印キー検知・消費追加
│   ├── ScreenRecordingPermissionService.swift      # [新規] CGPreflightScreenCaptureAccess / CGRequestScreenCaptureAccess 実装
│   └── WindowCaptureService.swift                  # [新規] ScreenCaptureKit 非同期サムネイル取得＋上限付き LRU メモリキャッシュ
├── ViewModels/
│   ├── SettingsViewModel.swift                     # [更新] 表示形式選択・画面収録権限状態管理・オプトイン分離
│   └── SwitcherViewModel.swift                     # [更新] キャプチャ表示制御・非同期更新・世代管理・4方向移動・キャッシュ無効化
└── Views/
    ├── SettingsView.swift                          # [更新] 表示形式 Picker・オプトイン権限セクション追加
    ├── PermissionGuideView.swift                   # [更新] 画面収録権限の案内文言を憲章 v2.0.0 準拠に改定
    ├── SwitcherPanel.swift                         # [更新] 可変コンテンツ幅・高さの上端基準リサイズと水平中央調整対応
    ├── SwitcherCaptureGridView.swift               # [新規] Windows Alt+Tab 風複数行カードグリッド・権限未許可バナー
    └── SwitcherContentView.swift                   # [新規] モード／表示形式に応じて SwitcherListView と SwitcherCaptureGridView を切替

Tests/WintchCoreTests/
├── Mocks/
│   └── MockServices.swift                          # [更新] MockScreenRecordingPermissionService / MockWindowCaptureService 追加・拡張
├── SwitcherGridLayoutTests.swift                   # [新規] グリッド列数・上下左右移動・端折り返し循環の純粋ロジックテスト
├── HotKeyMonitorDecisionTests.swift                # [更新] .normal での左右矢印消費・.launcher での非消費テスト追加
├── SettingsViewModelTests.swift                    # [更新] 表示形式永続化・リスト型での権限非プローブ・キャプチャ型での権限操作テスト
├── SwitcherViewModelTests.swift                    # [更新] 即時表示・非同期反映・世代破棄・4方向移動・クローズ更新・リスト復帰時キャッシュ消去
└── AppCoordinatorTests.swift                       # [更新] 表示形式変更の即時反映連携テスト
```

**Structure Decision**: 既存の MVVM + Services 構成（`WintchCore` + `WintchCoreTests`）を維持する。`ScreenCaptureKit` および `CoreGraphics` 権限 API は新規の `Services/` 実装クラスに閉じ込め、`Domain/` の純粋ロジックと `ViewModels/` はモック差し替えにより権限ダイアログなしで単体テストできるように設計する。なお、ドキュメント整合のため [AGENTS.md](file:///Users/sawarame_yasushi/dev/Wintch/AGENTS.md) の旧原則 1 要約箇所も実装フェーズまたは `/speckit-tasks` で同期対象に含める。

## Complexity Tracking

> 憲章 v2.0.0 への違反は存在しないため、該当なし。
