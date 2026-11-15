# 実装計画 (Implementation Plan): スイッチャーおよび検索ランチャーからの選択中ウィンドウ終了

**Branch**: `005-close-selected-window` | **Date**: 2026-11-15 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/005-close-selected-window/spec.md)

**Input**: Feature specification from `/specs/005-close-selected-window/spec.md`

## Summary

通常スイッチャー（ホールド式）および検索ランチャー（トグル式）の双方において、現在設定されている通常スイッチャーの必須修飾キーと `Q` キーの組み合わせ（デフォルト `Option + Q`）が押された際に、現在選択中のウィンドウ **1 枚のみ**を安全に閉じ、パネルを開いたまま残りの候補一覧と選択位置を更新維持する機能を追加する（最後の 1 件が閉じられて全ウィンドウが 0 件になった場合のみパネルを自動終了する）。

技術的には、`HotKeyMonitorService` の純粋判定関数 `resolveKeyDown` にて仮想キーコード `12`（`Q`）と必須修飾キー一致を検知して `.closeSelectedWindowPressed` を通知・消費（検索欄への特殊文字入力や `Command + Q` 誤終了、背面アプリ漏洩を防止）し、`WindowService` に `kAXCloseButtonAttribute` + `kAXPressAction` による単一ウィンドウクローズおよび消滅確認メソッド `closeWindow(_:) async -> Bool` を追加し、`SwitcherViewModel` で再入制御付きの除外・インデックス補正・パネル高さ更新を実装する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`SwiftUI`, `AppKit`, `ApplicationServices`, `CoreGraphics`, `Observation`, `Foundation`, `os`）。外部サードパーティ依存ゼロ。  
**Storage**: 新規ストレージキーなし。既存の `UserDefaults`（`dev.wintch.shortcutPreference`）から読み込まれた通常スイッチャー必須修飾キー設定をそのまま参照する。  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`LSUIElement = YES`、`WintchCore` + `Wintch` 構成）  
**Performance Goals**: `修飾キー + Q` の入力から対象ウィンドウへのクローズ指示・消滅確認・候補一覧およびパネル高さの更新完了まで、通常ウィンドウにおいて 200ms 以内の即時応答を達成する（キー判定自体は O(1) 比較、クローズ確認は早期脱出ポーリング）。  
**Constraints**: 画面収録権限不使用、非公開 API（`CGS*` 等）不使用、日本語ドキュメントコメント・インラインコメント必須、`@Observable` 使用、単体 `Q` / `Shift + Q` の検索文字入力を阻害しないこと、未保存確認ダイアログの強制破棄や `Command + Q` によるアプリ誤終了を起こさないこと。  
**Scale/Scope**: `HotKeyMonitoring` / `HotKeyMonitorService`、`WindowServicing` / `WindowService`、`SwitcherSelection`、`SwitcherViewModel`、`SwitcherPanel`、および対応ユニットテスト（`HotKeyMonitorDecisionTests`、`SwitcherSelectionTests`、`SwitcherViewModelTests`、`MockServices`）に限定した最小変更。

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限の原則（Privacy by Design）** | 画面収録権限は一切使用せず、既存のアクセシビリティ権限（`AXUIElement` の `kAXCloseButtonAttribute` + `CGEventTap`）のみで完結する | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | 設定画面へ新項目を増やさず、既存の通常スイッチャー修飾キー + `Q` の固定割り当てとして直感的に提供する | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | ホットキー判定は O(1) のビット集合比較、クローズ確認は早期終了ポーリングにより 200ms 以内で完了する | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | Apple 標準フレームワークのみを使用し、外部パッケージは一切導入しない | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。`kAXCloseButtonAttribute` 非対応ウィンドウや未保存ダイアログ時はクラッシュや強制破棄をせず安全に状態を維持する | PASS |
| **6. 技術スタック・MVVM + Services** | `CGEventTap` と `AXUIElement` 操作はすべて `Services/` 層に隔離し、`ViewModels/` / `Views/` から低レイヤー API を直接呼び出さない | PASS |
| **7. 可読性・テスト可能性・ライセンス** | キー判定（`resolveKeyDown`）、インデックス補正（`SwitcherSelection.indexAfterRemoval`）、状態遷移（`SwitcherViewModel` + `MockWindowService`）をすべて `swift test` で単体テスト可能に設計し、日本語コメント規約を遵守する | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/005-close-selected-window/
├── spec.md                          # 機能仕様書
├── plan.md                          # 本実装計画書
├── research.md                      # Phase 0 技術調査・設計判断レポート
├── data-model.md                    # Phase 1 データモデル・状態遷移設計
├── quickstart.md                    # Phase 1 ビルド・テスト・手動検証ガイド
├── contracts/                       # Phase 1 サービス・ViewModel・UI 契約
│   └── service-contracts.md
└── checklists/
    └── requirements.md              # 仕様品質チェックリスト
```

### Source Code (repository root)

既存の `WintchCore` + `Wintch` パッケージ構造を維持し、以下のファイルのみを更新する。

```text
Sources/WintchCore/
├── Domain/
│   └── SwitcherSelection.swift             # [更新] 1件除外後のインデックス補正 indexAfterRemoval(current:remainingCount:) 追加
├── Services/
│   ├── Protocols/
│   │   ├── HotKeyMonitoring.swift          # [更新] HotKeyEvent に .closeSelectedWindowPressed 追加
│   │   └── WindowServicing.swift           # [更新] closeWindow(_ entry: WindowEntry) async -> Bool 追加
│   ├── HotKeyMonitorService.swift          # [更新] .normal / .launcher での修飾キー + Q 判定・消費・イベント配送追加
│   └── WindowService.swift                 # [更新] kAXCloseButtonAttribute + kAXPressAction によるクローズおよび消滅確認実装
├── ViewModels/
│   └── SwitcherViewModel.swift             # [更新] closeSelectedWindow()、再入防止、モード別一覧再計算、0件終了処理追加
└── Views/
    └── SwitcherPanel.swift                 # [更新] .normal モードでのリスト縮小に追従する高さリサイズ対応

Tests/WintchCoreTests/
├── Mocks/
│   └── MockServices.swift                  # [更新] MockWindowService に closeWindow スタブ・履歴追加
├── HotKeyMonitorDecisionTests.swift        # [更新] 修飾キー + Q 判定、単体 Q 通過、優先順位、Command+Q 消費テスト追加
├── SwitcherSelectionTests.swift            # [更新] indexAfterRemoval の境界値テスト追加
└── SwitcherViewModelTests.swift            # [更新] 通常/ランチャー双方でのクローズ・連続操作・0件終了・未クローズ維持テスト追加
```

**Structure Decision**:
- 既存の `Domain/`（純粋計算）・`Services/`（低レイヤー OS API 隔離）・`ViewModels/`（状態遷移）・`Views/`（UI 表示）の 4 層構造を厳守する。
- 新しい設定項目や新しい View ファイルは増やさず、既存コンポーネントへの最小限かつ凝集度の高い拡張として設計する。

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
