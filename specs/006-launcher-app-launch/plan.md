# 実装計画 (Implementation Plan): 検索ランチャーでの検索入力時におけるアプリ起動候補の併用表示

**Branch**: `006-launcher-app-launch` | **Date**: 2026-11-15 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/006-launcher-app-launch/spec.md)

**Input**: Feature specification from `/specs/006-launcher-app-launch/spec.md`

## Summary

検索ランチャーモードで空欄以外の検索キーワードが入力されたとき、既存ウィンドウの検索結果が 0 件か 1 件以上かにかかわらず、インストール済みアプリケーションから一致候補をファジー検索し、**上のウィンドウ候補に既に表示されているアプリを重複除外した上で**ウィンドウ候補の下に「アプリを起動」セクションとして併用表示する。`SwitcherViewModel` と `SwitcherListView` によりウィンドウ候補とアプリ起動候補を単一の連続した選択カーソル・単一スクロール領域で貫通操作でき、`Enter` やクリックで選択対象に応じた切り替えまたはアプリ起動を実行する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`SwiftUI`, `AppKit`, `Foundation`, `Observation`）。外部サードパーティ依存ゼロ。  
**Storage**: 新規永続ストレージなし。インストール済みアプリ一覧およびアプリアイコンはメモリキャッシュのみ保持。  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`LSUIElement = YES`、`WintchCore` + `Wintch` 構成）  
**Performance Goals**: 1文字入力・削除ごとのウィンドウ検索＋アプリ検索＋重複除外＋再描画を 100ms 以内に完了（アプリ走査は起動時事前ロード＋バックグラウンド更新により、検索時はメモリキャッシュ同期参照のみ）。  
**Constraints**: 画面収録権限不使用、非公開 API（`CGS*` 等）不使用、日本語ドキュメントコメント・インラインコメント必須、`@Observable` 使用、検索結果の重複アプリ除外、アプリ候補上での終了操作（`修飾キー + Q`）安全無視、パネル上端位置固定。  
**Scale/Scope**: `Domain/`（`FuzzySearchMatcher`, `WindowSearchEngine`, `LaunchableApp`, `AppSearchResult`, `AppSearchEngine`, `WindowEntry`, `WindowFilter`）、`Services/`（`InstalledAppServicing`, `InstalledAppService`, `IconProviding`, `IconProviderService`）、`ViewModels/`（`SwitcherViewModel`）、`App/`（`AppCoordinator`）、`Views/`（`SwitcherListView`, `LauncherSearchField`）、および関連テスト。

## Constitution Check

*GATE: Phase 0 / Phase 1 設計完了後の最終検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限の原則（Privacy by Design）** | 画面収録権限や追加のプライバシー権限を一切要求せず、標準ディレクトリ走査と既存のアクセシビリティ権限のみで完結する | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | 検索未入力時は従来通りウィンドウ一覧のみを維持し、検索入力時のみ未表示アプリ起動候補を下欄へ追加表示する最小・直感的な統合 UX とする | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | アプリ収集はバックグラウンド非同期処理＋メモリキャッシュで行い、検索時は同期 DP マッチングのみ実行する | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | Apple 標準フレームワーク（`Foundation`, `AppKit`, `SwiftUI`, `Observation`）のみ使用 | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。アプリ起動は公開 `NSWorkspace.shared.openApplication` を用い、不完全バンドル・非対話ヘルパー・重複リンクは安全に除外する | PASS |
| **6. 技術スタック・MVVM + Services** | ファイルシステム走査および `NSWorkspace` 呼び出しは `Services/` 層（`InstalledAppService`, `IconProviderService`）に完全隔離する | PASS |
| **7. 可読性・テスト可能性・ライセンス** | ファジー検索・重複除外ロジックは `Domain/` へ純粋関数として切り出し、モック差し替えおよび仮ディレクトリテストで 100% 検証可能とし、日本語コメント規約を遵守する | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/006-launcher-app-launch/
├── spec.md                                         # 機能仕様書
├── plan.md                                         # 本実装計画書
├── research.md                                     # 技術調査・意思決定記録
├── data-model.md                                   # データモデル・統合選択状態遷移
├── quickstart.md                                   # 検証手順書
├── checklists/
│   └── requirements.md                             # 仕様品質チェックリスト
└── contracts/
    └── launcher-app-launch-contracts.md            # ドメイン・サービス・UI 契約定義
```

### Source Code (repository root)

```text
Sources/WintchCore/
├── App/
│   └── AppCoordinator.swift                        # [更新] InstalledAppService 生成・注入および起動時プリロード
├── Domain/
│   ├── FuzzySearchMatcher.swift                    # [新規] 共通2フィールドファジー検索コア
│   ├── WindowSearchEngine.swift                    # [更新] FuzzySearchMatcher 利用へリファクタ
│   ├── WindowEntry.swift                           # [更新] bundleIdentifier 保持追加（重複除外用）
│   ├── WindowFilter.swift                          # [更新] RawWindowCandidate.bundleIdentifier の引き継ぎ
│   ├── LaunchableApp.swift                         # [新規] 起動可能アプリモデル
│   ├── AppSearchResult.swift                       # [新規] アプリ検索結果・ハイライト範囲モデル
│   └── AppSearchEngine.swift                       # [新規] 既出ウィンドウアプリ重複除外付きアプリ検索エンジン
├── Services/
│   ├── Protocols/
│   │   ├── IconProviding.swift                     # [更新] icon(forAppURL:) 追加
│   │   └── InstalledAppServicing.swift             # [新規] アプリ収集・キャッシュ・起動契約
│   ├── IconProviderService.swift                   # [更新] アプリ URL 単位のアイコンキャッシュ実装
│   └── InstalledAppService.swift                   # [新規] アプリディレクトリ走査・重複排除・起動実装
├── ViewModels/
│   └── SwitcherViewModel.swift                     # [更新] 統合検索・統合選択インデックス貫通制御・起動実行
└── Views/
    ├── LauncherSearchField.swift                   # [更新] 検索プレースホルダー文言更新
    └── SwitcherListView.swift                      # [更新] 単一スクロール領域での上下セクション併用表示とスクロール追従

Tests/WintchCoreTests/
├── Mocks/
│   └── MockServices.swift                          # [更新] MockIconProvider 拡張・MockInstalledAppService 追加
├── AppSearchEngineTests.swift                      # [新規] 検索・日本語/英語マッチ・重複除外・ソート検証
├── InstalledAppServiceTests.swift                  # [新規] 仮ディレクトリ走査・シンボリックリンク・除外検証
└── SwitcherViewModelTests.swift                    # [更新] 混在表示・貫通移動・重複除外・終了無視・非同期更新検証
```

**Structure Decision**: 既存の MVVM + Services 構成（`WintchCore` ライブラリターゲット＋`WintchCoreTests` テストターゲット）を踏襲し、OS 依存を `Services/` に閉じ込め、検索・重複除外ロジックはすべて `Domain/` へ配置する。

## Complexity Tracking

> 憲章違反は存在しないため、該当なし。
