# 実装計画 (Implementation Plan): メニューバーから開く設定画面等の最前面表示修正

**Branch**: `015-fix-settings-frontmost` | **Date**: 2026-11-17 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/015-fix-settings-frontmost/spec.md)

**Input**: Feature specification from `/specs/015-fix-settings-frontmost/spec.md`

## Summary

メニューバーアイコン（`MenuBarExtra`）から「設定を開く...」等を実行した際に、設定画面が他のアプリケーションウィンドウの背後に隠れてしまう不具合（GitHub Issue #18）を修正する。

原因調査（[research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/015-fix-settings-frontmost/research.md)）に基づき、`.accessory`（Dock アイコン非表示）ポリシーを維持したまま確実な最前面表示とアクティブ化を実現するため、以下を実施する：

1. **アクティブ画面中央配置の純粋計算（`Domain/WindowPlacement.swift`）**: マルチディスプレイ・カーソル所在ディスプレイを考慮した中央配置座標計算を純粋関数として切り出し、単体テスト可能にする。
2. **前面表示サービスの抽出（`Services/Protocols/WindowFrontPresenting.swift` / `Services/WindowFrontPresenter.swift`）**: `.moveToActiveSpace` 設定、最小化解除、`activate(ignoringOtherApps: true)`、`orderFrontRegardless()`、`makeKeyAndOrderFront(nil)`、および `MenuBarExtra` メニュー閉鎖後の次ランループ再前面化を一元実行するサービスを導入する。
3. **`AppCoordinator` の統合（`App/AppCoordinator.swift`）**: `openSettings()`、`openAbout()`、`presentPermissionGuideWindow()` の重複していた前面表示処理を `WindowFrontPresenting` 呼び出しへ統一する。
4. **ユニットテストの追加（`Tests/WintchCoreTests/`）**: 配置座標計算、プレゼンターの同期／次ランループ動作（最小化解除・スペース設定・表示継続ガード・レベル維持）、および `AppCoordinator` から各画面表示メソッドが正しくプレゼンターへ委譲されることを Swift Testing で検証する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`, Strict Concurrency 準拠）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`Foundation`, `AppKit`, `SwiftUI`, `Observation`）。外部サードパーティ依存ゼロ。  
**Storage**: N/A（新規の永続化データはなし）  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`WintchCore` + `Wintch`）  
**Performance Goals**: メニューバー項目選択から体感遅延ゼロ（即時＋次ランループ 1 回のみ）で最前面表示を完了し、常駐時の追加 CPU/メモリ負荷を発生させない。  
**Constraints**:
- `LSUIElement` / `.accessory` ポリシーを維持し、設定画面開閉時に Dock アイコンを増やさない。
- 設定画面のウィンドウレベルは通常（`.normal`）に維持し、システム設定や他アプリへの切り替えを妨げない。
- 非公開 API（`CGS*` 等）は一切使用しない。
- 画面収録権限を一切要求・使用しない。
- コード内のインラインコメントおよびドキュメントコメント（`///`）はすべて日本語で記述する。

**Scale/Scope**: `Domain/` に 1 ファイル、`Services/Protocols/` に 1 ファイル、`Services/` に 1 ファイル新規追加、`App/AppCoordinator.swift` のピンポイント更新、および `Tests/WintchCoreTests/` のテスト追加・モック更新。

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限およびオプトインの原則（Privacy by Design）** | 画面収録権限および追加 OS 権限を一切要求・使用しない | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | UI や設定項目を増やさず、最小限の前面表示サービスと配置計算のみ追加する | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | ポーリングや重い遅延タイマーを置かず、即時表示＋次ランループ 1 回のみの後処理で完結する | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | Apple 標準フレームワーク（`Foundation` / `AppKit`）のみを使用する | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 公開 AppKit API のみを使用し、最小化・スクリーン未検出時も安全にフォールバックする | PASS |
| **6. 技術スタック・MVVM + Services** | 座標計算は `Domain/`、OS ウィンドウ操作は `Services/` へ分離し、`AppCoordinator` から DI で利用する | PASS |
| **7. 可読性・テスト可能性・ライセンス** | プロトコル＋純粋関数設計によりモックテスト・境界値テストが可能。全コメント日本語 | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/015-fix-settings-frontmost/
├── spec.md                                      # 機能仕様書
├── plan.md                                      # 本実装計画書
├── research.md                                  # Phase 0 技術調査・設計判断レポート
├── data-model.md                                # Phase 1 状態・配置モデル設計
├── quickstart.md                                # Phase 1 ビルド・自動テスト・手動検証ガイド
├── contracts/
│   └── window-presentation-contracts.md         # Phase 1 サービス・コーディネーター契約仕様
└── checklists/
    └── requirements.md                          # 仕様品質チェックリスト
```

### Source Code (repository root)

```text
Sources/WintchCore/
├── Domain/
│   └── WindowPlacement.swift                    # [新規] カーソル所在スクリーン等の中央配置計算（純粋関数）
├── Services/
│   ├── Protocols/
│   │   └── WindowFrontPresenting.swift          # [新規] 標準ウィンドウ最前面表示プロトコル
│   └── WindowFrontPresenter.swift               # [新規] AppKit アクティブ化・orderFrontRegardless・次ランループ保証実装
└── App/
    └── AppCoordinator.swift                     # [更新] WindowFrontPresenting DI と openSettings/openAbout/presentPermissionGuideWindow 統合

Tests/WintchCoreTests/
├── Mocks/
│   └── MockServices.swift                       # [更新] MockWindowFrontPresenter 追加
├── WindowFrontPresenterTests.swift              # [新規] WindowPlacement・WindowFrontPresenter の単体テスト
└── AppCoordinatorTests.swift                    # [更新] openSettings/openAbout/openPermissionGuide の前面表示委譲テスト追加
```

**Structure Decision**:
- `AppCoordinator.init` の `windowFrontPresenter` 引数には既定値 `WindowFrontPresenter()` を設定するため、既存の呼び出し元（`WintchApp.swift` や既存テスト）への破壊的変更は発生しない。
- `WindowPlacement` を `Domain/` に分離することで、`NSScreen` 実機に依存せずマルチディスプレイの矩形計算を高速かつ決定論的にテストできる。

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
