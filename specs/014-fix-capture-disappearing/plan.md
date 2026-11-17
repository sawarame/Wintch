# 実装計画 (Implementation Plan): キャプチャ表示型スイッチャーにおけるサムネイル消失の防止とキャッシュ整合性改善

**Branch**: `014-fix-capture-disappearing` | **Date**: 2026-11-17 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/014-fix-capture-disappearing/spec.md)  
**Related Issue**: [#16](https://github.com/sawarame/Wintch/issues/16)

**Input**: Feature specification from `/specs/014-fix-capture-disappearing/spec.md`

## Summary

キャプチャ表示型スイッチャーで多数のウィンドウを開閉しながら長時間利用した際に、取得済みサムネイルが消えてアイコン表示に戻ってしまう不具合（Issue #16）を解消する。具体的には、(1) `WindowCaptureServicing` / `WindowCaptureService` に生存ウィンドウ ID 集合に基づく閉じ済みキャッシュ自動破棄（`pruneCache(keeping:)`）を追加し保持上限を 50 件から 100 件へ緩和、(2) `SwitcherViewModel.present()` でのキャッシュ参照順を `sorted.reversed()` にして LRU 順序逆転を是正（直近アクティブウィンドウを末尾＝最新保持側へ維持）、(3) `WindowService.selectBestCGWindowMatch` の近接一致および包含フォールバック双方で `preferredCGWindowID` 連続性と非空 `cgWindowName` 優先を強化し、`cgWindowID` の誤乗り換え・欠落を防止する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`、Strict Concurrency 準拠）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`SwiftUI`, `AppKit`, `Foundation`, `Observation`, `CoreGraphics`, `ScreenCaptureKit`）。外部サードパーティ依存ゼロ。  
**Storage**: 永続ストレージ変更なし。ウィンドウサムネイルは `WindowCaptureService` のメモリ上 LRU キャッシュ（上限 100 件、1 枚約 0.45 MB 相当）のみに保持し、ディスク保存・外部送信は行わない。  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `swift test`（必要時 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`）  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`WintchCore` + `Wintch` 構成）  
**Performance Goals**: パネル即時表示（100ms 以内）を維持し、`pruneCache` および `reversed()` による初期キャッシュロードを O(N) の軽量メモリ操作のみで完結させる。  
**Constraints**: 憲章 v2.0.0 準拠（`.list` モードおよび `.launcher` モードでは画面収録権限・キャプチャ API を一切呼ばない、非公開 API 不使用、外部依存ゼロ、日本語ドキュメントコメント・インラインコメント必須、`@Observable` / `@MainActor` 厳守）。  
**Scale/Scope**: `Services/Protocols/WindowCaptureServicing.swift`, `Services/WindowCaptureService.swift`, `Services/WindowService.swift`, `ViewModels/SwitcherViewModel.swift`, `Tests/WintchCoreTests/Mocks/MockServices.swift`, `Tests/WintchCoreTests/WindowCaptureAndMatchingTests.swift`, `Tests/WintchCoreTests/SwitcherViewModelTests.swift`。

## Constitution Check

*GATE: Phase 0 / Phase 1 設計完了後の検証済み（[constitution.md](file:///Users/sawarame_yasushi/dev/Wintch/.specify/memory/constitution.md) v2.0.0 準拠）。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限およびオプトインの原則（Privacy by Design）** | `pruneCache(keeping:)` を含むすべての `WindowCaptureService` 呼び出しは `targetMode == .normal && normalDisplayStyle == .capture && isScreenRecordingGranted` のオプトイン条件内に限定し、`.list` および `.launcher` 時は一切呼び出さない。画像はメモリ限定・ディスク非保存を維持 | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | UI や設定項目を増やさず、既存のキャッシュ管理・識別照合の不具合修正のみに限定する | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | `pruneCache(keeping:)` と `sorted.reversed()` 読み込みは純粋なメモリ集合・辞書操作であり体感遅延ゼロ。閉じ済みウィンドウの即時整理により不要メモリ消費も削減する | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | Apple 標準フレームワークのみ使用 | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。`captureSingleWindow` の空画像ガードおよび取得失敗時の既存キャッシュ維持により安全なフォールバックを強化 | PASS |
| **6. 技術スタック・MVVM + Services** | `ScreenCaptureKit` / `CGWindowListCopyWindowInfo` は `Services/` に隔離され、`ViewModel` は `WindowCaptureServicing` プロトコル経由でのみ操作する | PASS |
| **7. 可読性・テスト可能性・ライセンス** | `WindowCaptureService` の上限値注入対応、`MockWindowCaptureService` 拡張、`selectBestCGWindowMatch` の純粋静的関数化により、OS 権限ダイアログなしで全要件を単体テスト可能。日本語コメント規約を厳守 | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/014-fix-capture-disappearing/
├── plan.md                                         # 本実装計画書
├── research.md                                     # Phase 0 調査・意思決定記録
├── data-model.md                                   # Phase 1 キャッシュ状態・識別連続性モデル
├── quickstart.md                                   # Phase 1 検証手順書
├── checklists/
│   └── requirements.md                             # 仕様品質チェックリスト
├── contracts/
│   └── capture-cache-and-matching.md               # Phase 1 サービス・照合契約定義
└── tasks.md                                        # Phase 2 タスク一覧（/speckit-tasks で生成）
```

### Source Code (repository root)

```text
Sources/WintchCore/
├── Services/
│   ├── Protocols/
│   │   └── WindowCaptureServicing.swift            # [更新] pruneCache(keeping:) プロトコル要件追加
│   ├── WindowCaptureService.swift                  # [更新] 上限 100 件化・注入対応、pruneCache(keeping:) 実装、空 CGImage ガード
│   └── WindowService.swift                         # [更新] selectBestCGWindowMatch（近接・包含双方）に continuity / nonEmptyName 優先追加
└── ViewModels/
    └── SwitcherViewModel.swift                     # [更新] present() でオプトイン時 pruneCache 呼び出しと sorted.reversed() でのキャッシュ取得

Tests/WintchCoreTests/
├── Mocks/
│   └── MockServices.swift                          # [更新] MockWindowCaptureService に pruneCache(keeping:) 実装・記録追加
├── WindowCaptureAndMatchingTests.swift             # [更新] pruneCache / 上限 100 件 LRU / 包含・無名窓照合連続性テスト追加
└── SwitcherViewModelTests.swift                    # [更新] 大量開閉後キャッシュ維持・MRU 逆順更新による追い出し防止・非オプトイン非呼出テスト追加
```

**Structure Decision**: 既存の MVVM + Services 構成とプロトコル境界をそのまま維持し、UI 層（`Views/`）には変更を加えない。テスト容易性のため `WindowCaptureService.init` に `maxCacheCount` デフォルト引数を導入する以外は既存の公開呼び出し互換性を維持する。

## Complexity Tracking

> 憲章 v2.0.0 への違反は存在しないため、該当なし。
