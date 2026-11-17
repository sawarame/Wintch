# 実装計画 (Implementation Plan): Chrome等のタブ全閉によるウィンドウ閉鎖後に空の表示が残る問題の修正

**Branch**: `019-fix-chrome-empty-ghost` | **Date**: 2026-11-18 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/.worktrees/Wintch-issue-27/specs/019-fix-chrome-empty-ghost/spec.md)

**Input**: Feature specification from `/specs/019-fix-chrome-empty-ghost/spec.md` (Related Issue: [#27](https://github.com/sawarame/Wintch/issues/27))

## Summary

Google Chrome のタブをすべて閉じてウィンドウを閉じた（アプリ自体は未終了）際に、スイッチャーおよび検索ランチャーに真っ白なプレビューの `Google Chrome (タイトルなし)` が残り続け、選択しても何も起こらない不具合（Issue #27）を修正する。
具体的には、(1) `AppWindowProfileRegistry` に `com.google.Chrome`（`offscreenCGPolicy: .requireAXOrMenuTitle`）を追加してウィンドウ全閉後に画面外へ残る無名空き殻・補助 `CGWindow` を除外し、(2) `WindowService.cleanupClosedWindows` で最新 AX スキャンに不在かつ対応 `cgWindowID` が WindowServer 上から消滅した `CachedAXWindow` を確実に破棄して空き殻 `CGWindow` への乗り換え（ゾンビ化）を防ぎ、(3) ウィンドウ破棄・減少時に「ウィンドウ」メニューキャッシュを即時無効化し、(4) 空タイトルの捕捉済み標準 AX ウィンドウ（別スペースの「新しいタブ」等）にもメニュー・`cgWindowName` からのタイトル補完と正確な別スペース遷移判定を適用する。

## Technical Context

**Language/Version**: Swift 6.0 (Strict Concurrency)

**Primary Dependencies**: Apple 標準フレームワークのみ（`AppKit`, `SwiftUI`, `ApplicationServices`, `CoreGraphics`, `ScreenCaptureKit`, `Foundation`）

**Storage**: N/A（インメモリのウィンドウ／メニューキャッシュのみ）

**Testing**: Swift Testing (`swift test`)

**Target Platform**: macOS 14.0 (Sonoma) 以降

**Project Type**: desktop-app (macOS メニューバー常駐ウィンドウスイッチャー＆ランチャー)

**Performance Goals**: ショートカット押下からパネル表示まで体感遅延ゼロを維持（既存のキャッシュ・差分走査設計を維持）

**Constraints**: リスト型・検索ランチャーでは画面収録権限を一切要求・使用しない。サードパーティ製ライブラリ不使用。非公開 API 不使用。

**Scale/Scope**: `Domain/` 層 2 ファイル（`AppWindowProfile.swift`, `WindowMenuPairing.swift`）、`Services/` 層 1 ファイル（`WindowService.swift`）、および対応するユニットテスト群の拡張。

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **1. 最小権限およびオプトインの原則（Privacy by Design）**: PASS — 画面収録権限の要求・使用範囲は一切変更しない。アクセシビリティ情報、`CGWindowListCopyWindowInfo` の既存メタデータ、および「ウィンドウ」メニュー情報のみで完結する。
- **2. 過剰機能の排除（シンプルさの徹底）**: PASS — 新規の設定項目や UI 要素は一切追加しない。
- **3. 起動と応答の高速性（ゼロレイテンシ）**: PASS — ウィンドウ閉鎖通知時およびウィンドウ減少時のみメニューキャッシュを無効化し、必要な PID に限って補完を行うため、表示遅延を発生させない。
- **4. 依存関係の最小化（外部ライブラリ依存ゼロ）**: PASS — Apple 標準フレームワークのみを使用する。
- **5. 非公開APIの禁止と安全なフォールバック**: PASS — 非公開 API（`CGS*` 等）は一切使用しない。
- **アーキテクチャ・テスト可能性規約**: PASS — フィルタリング・プロファイル定義・メニュー補完判定・キャッシュ保持判定・現在スペース判定をすべて純粋関数として切り出し、単体テストで検証可能にする。

## Project Structure

### Documentation (this feature)

```text
specs/019-fix-chrome-empty-ghost/
├── plan.md              # 本実装計画
├── research.md          # Phase 0 原因調査および設計判断レポート
├── data-model.md        # Phase 1 データモデル・純粋関数設計
├── quickstart.md        # Phase 1 検証・ビルド実行ガイド
├── contracts/           # Phase 1 ドメイン・サービス層コントラクト定義
│   └── window-closure-and-enrichment-contracts.md
├── checklists/          # 仕様品質チェックリスト
│   └── requirements.md
└── tasks.md             # Phase 2 実装タスク一覧 (/speckit-tasks で生成)
```

### Source Code (repository root)

```text
Sources/
├── Wintch/
│   └── WintchApp.swift
└── WintchCore/
    ├── Domain/
    │   ├── AppWindowProfile.swift       # com.google.Chrome プロファイル追加
    │   ├── WindowFilter.swift           # プロファイルに基づく画面外無名候補の除外
    │   └── WindowMenuPairing.swift      # 空タイトルAX候補のメニュー/cgWindowName補完拡張
    └── Services/
        └── WindowService.swift          # 閉鎖済みAXキャッシュ除去・メニューキャッシュ即時無効化・別スペース判定修正

Tests/
└── WintchCoreTests/
    ├── AppWindowProfileTests.swift      # Chrome プロファイル解決テスト追加
    ├── WindowFilterTests.swift          # Chrome 全閉時・複数窓閉鎖時の除外テスト追加
    ├── WindowMenuPairingTests.swift     # 空タイトルAX補完・needsMenuEnrichment テスト追加
    └── WindowCaptureAndMatchingTests.swift # shouldRetainCachedAXWindow・isWindowInCurrentSpace テスト追加
```

**Structure Decision**: 既存の MVVM + Services 構成（`Sources/WintchCore/Domain` および `Sources/WintchCore/Services`）を維持し、純粋ビジネスロジックは `Domain/` と `WindowService` の `nonisolated static` 純粋ヘルパーに配置して `Tests/WintchCoreTests/` で網羅的に単体テストする。

## Complexity Tracking

憲章違反なし（該当なし）。
