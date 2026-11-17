# 実装計画 (Implementation Plan): アクセシビリティ権限誘導ダイアログの説明文全文表示修正

**Branch**: `016-fix-permission-guide-text` | **Date**: 2026-11-17 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/016-fix-permission-guide-text/spec.md)

**Input**: Feature specification from `/specs/016-fix-permission-guide-text/spec.md`

## Summary

アクセシビリティ権限誘導ダイアログにおいて、補足説明文（「※ リスト型および検索ランチャーでは「画面収録」権限を使用しません（キャプチャ表示型を選択した場合のみ任意で使用します）。」）が途中で省略記号（`...`）になって途切れてしまう不具合（GitHub Issue #19）を修正する。

調査結果（[research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/016-fix-permission-guide-text/research.md)）に基づき、以下を実施する：

1. **`PermissionGuideView` の垂直折り返し保護（`Sources/WintchCore/Views/PermissionGuideView.swift`）**: 基準幅・最小高さ定数を定義し、見出し・サブタイトル・手順ラベル・補足説明テキストに `.fixedSize(horizontal: false, vertical: true)` を適用して、SwiftUI による縦方向圧縮・途中省略を防ぐ。
2. **`AppCoordinator` のウィンドウサイズ自動適応（`Sources/WintchCore/App/AppCoordinator.swift`）**: `ensurePermissionWindow()` における固定高さ `280` のハードコードを廃し、`NSHostingView.fittingSize` を計測して必要なコンテンツ高さを `NSWindow` へ設定する。
3. **ユニットテストの追加（`Tests/WintchCoreTests/`）**: `PermissionGuideView` の `fittingSize` が配布版・開発版双方で圧縮されない高さを持つこと、および `AppCoordinator` が生成する権限誘導ウィンドウのコンテンツ領域が `fittingSize` を下回らないことを Swift Testing で検証する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`, Strict Concurrency 準拠）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`SwiftUI`, `AppKit`, `Foundation`, `Observation`）。外部サードパーティ依存ゼロ。  
**Storage**: N/A（永続化データ変更なし）  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`WintchCore` + `Wintch`）  
**Performance Goals**: ダイアログ初回生成時の `fittingSize` 計測 1 回のみであり、常駐時・表示時とも追加負荷ゼロ。  
**Constraints**:
- Wintch 憲章 v2.0.0 の「最小権限およびオプトインの原則」を維持し、画面収録権限を一切要求・確認しない。
- 非公開 API（`CGS*` 等）は一切使用しない。
- 既存の最前面表示（`WindowFrontPresenter`）・再表示再利用（`isReleasedWhenClosed = false`）・権限監視動作を維持する。
- コード内のコメントおよびドキュメントコメント（`///`）はすべて日本語で記述する。

**Scale/Scope**: `Views/PermissionGuideView.swift`、`App/AppCoordinator.swift` のピンポイント修正、および `Tests/WintchCoreTests/` への回帰テスト追加。

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限およびオプトインの原則（Privacy by Design）** | 画面収録権限の要求・確認・誘導を一切行わず、説明文の表示修正のみ行う | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | 設定項目や不要な UI を増やさず、既存ダイアログのレイアウトとウィンドウサイズ算出のみ修正する | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | 生成時 1 回の `fittingSize` 計算のみで完結し、遅延や追加バックグラウンド処理なし | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | Apple 標準フレームワーク（`SwiftUI` / `AppKit`）のみを使用する | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 公開 SwiftUI / AppKit API のみを使用し、最小サイズ下限フォールバックも設ける | PASS |
| **6. 技術スタック・MVVM + Services** | SwiftUI ビューと `AppCoordinator` の `NSWindow` ラッパー責務内で完結し、低レイヤー API 漏洩なし | PASS |
| **7. 可読性・テスト可能性・ライセンス** | ビュー定数とウィンドウサイズの境界テストによりヘッドレスでも自動検証可能。全コメント日本語 | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/016-fix-permission-guide-text/
├── spec.md                                      # 機能仕様書
├── plan.md                                      # 本実装計画書
├── research.md                                  # Phase 0 技術調査・設計判断レポート
├── data-model.md                                # Phase 1 ビュー寸法・ウィンドウサイズ算出モデル
├── quickstart.md                                # Phase 1 ビルド・自動テスト・手動検証ガイド
├── contracts/
│   └── permission-guide-layout-contract.md      # Phase 1 表示・ウィンドウ生成契約
└── checklists/
    └── requirements.md                          # 仕様品質チェックリスト
```

### Source Code (repository root)

```text
Sources/WintchCore/
├── Views/
│   └── PermissionGuideView.swift                # [更新] 基準寸法定数公開およびテキスト .fixedSize(horizontal: false, vertical: true) 適用
└── App/
    └── AppCoordinator.swift                     # [更新] ensurePermissionWindow() で NSHostingView.fittingSize に合わせたウィンドウサイズ設定

Tests/WintchCoreTests/
├── PermissionGuideViewModelTests.swift          # [更新] PermissionGuideView の NSHostingView.fittingSize 全文収容テスト追加
└── AppCoordinatorTests.swift                    # [更新] 権限誘導ウィンドウのコンテンツ領域が fittingSize 以上であることを検証
```

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
