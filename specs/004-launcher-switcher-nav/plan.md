# 実装計画 (Implementation Plan): 検索ランチャー表示中の通常スイッチャーショートカットによる候補移動

**Branch**: `004-launcher-switcher-nav` | **Date**: 2026-11-14 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/004-launcher-switcher-nav/spec.md)

**Input**: Feature specification from `/specs/004-launcher-switcher-nav/spec.md`

## Summary

検索ランチャーモード（`.launcher`）表示中に通常スイッチャーのショートカット（順方向：設定済み修飾キー + トリガーキー / デフォルト `Option + Tab`、逆方向：`Shift` 併用 / デフォルト `Option + Shift + Tab`）が入力された場合、モード切り替えやキーイベントの漏洩を行わずに、現在表示中のランチャー候補リストの選択カーソルを「次へ」または「前へ」に循環移動させる。
実装は、`HotKeyMonitorService` 内の `.launcher` モード分岐で通常ショートカットを `.triggerPressed(isShiftPressed:)` として通知・消費する変更、判定ロジックを `CGEventTap` から分離して単体テスト可能にする純粋ヘルパーの抽出、および `SwitcherViewModel.handleTriggerPressed(isShiftPressed:)` で `.launcher` を `.normal` と同じ `moveSelection` 経路に統合する変更の最小限の修正で完結する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`SwiftUI`, `AppKit`, `ApplicationServices`, `CoreGraphics`, `Observation`, `Foundation`, `os`）。外部サードパーティ依存ゼロ。  
**Storage**: 既存の `UserDefaults`（`dev.wintch.shortcutPreference` / `dev.wintch.launcherShortcutPreference`）をそのまま参照し、新規ストレージキーは追加しない。  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`LSUIElement = YES`、`WintchCore` + `Wintch` 構成）  
**Performance Goals**: ショートカット押下から選択カーソル更新・スクロール反映まで体感遅延なし（100ms 以内）。ホットキーコールバック内の判定処理はロック内の値スナップショットに対する O(1) 比較のみとする。  
**Constraints**: 画面収録権限不使用、非公開 API（`CGS*` 等）不使用、日本語ドキュメントコメント・インラインコメント必須、`@Observable` 使用、通常スイッチャー側の既存挙動（修飾キー解放確定、ランチャーショートカット無視）およびランチャー側の既存挙動（トグル維持、IME 優先、0件時無操作）を破壊しないこと。  
**Scale/Scope**: `HotKeyMonitorService`・`SwitcherViewModel`・`HotKeyMonitoring`（コメント更新）および対応ユニットテスト（`SwitcherViewModelTests`、新規 `HotKeyMonitorDecisionTests`）に限定した局所的変更。

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限の原則（Privacy by Design）** | 画面収録権限は一切追加・使用せず、既存のアクセシビリティ権限による `CGEventTap` のイベント判定のみを更新する | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | 新しい設定項目や UI 要素は増やさず、既存の通常スイッチャーショートカットをランチャー内の候補移動へ自然に接続するのみ | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | `HotKeyMonitorService` の O(1) キーコード・修飾キー比較と `SwitcherViewModel` のインメモリインデックス更新のみで完了する | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | 外部ライブラリは一切追加せず、Swift 標準ライブラリと既存の `WintchCore` 型のみで完結する | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。候補 0 件・1 件・設定重複時のフォールバック動作も安全に定義済み | PASS |
| **6. 技術スタック・MVVM + Services** | `CGEventTap` 処理は `Services/HotKeyMonitorService.swift` に隔離し、状態遷移と選択インデックス更新は `ViewModels/SwitcherViewModel.swift` に閉じ込める | PASS |
| **7. 可読性・テスト可能性・ライセンス** | キー押下判定ロジックを `CGEvent` 非依存の純粋関数（`resolveKeyDown`）として切り出すことで `swift test` による単体テストを可能にし、日本語コメント規約を遵守する | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/004-launcher-switcher-nav/
├── spec.md                          # 機能仕様書
├── plan.md                          # 本実装計画書
├── research.md                      # Phase 0 技術調査・設計判断レポート
├── data-model.md                    # Phase 1 データモデル・状態遷移設計
├── quickstart.md                    # Phase 1 ビルド・検証ガイド
├── contracts/                       # Phase 1 サービス・ViewModel コントラクト
│   └── service-contracts.md
└── checklists/
    └── requirements.md              # 仕様品質チェックリスト
```

### Source Code (repository root)

既存の `WintchCore` + `Wintch` パッケージ構造を変更せず、以下のファイルのみを更新・追加する。

```text
Sources/WintchCore/
├── Services/
│   ├── Protocols/
│   │   └── HotKeyMonitoring.swift          # [更新] HotKeyMonitorMode / HotKeyEvent のドキュメントコメント整合化
│   └── HotKeyMonitorService.swift          # [更新] .launcher 時 isNormalMatch を .triggerPressed 配送+消費へ変更、純粋判定ヘルパー抽出
└── ViewModels/
    └── SwitcherViewModel.swift             # [更新] handleTriggerPressed で .launcher 時に moveSelection(isShiftPressed ? .up : .down) を実行

Tests/WintchCoreTests/
├── HotKeyMonitorDecisionTests.swift        # [新規] HotKeyMonitorService のモード別キー判定・消費ルール単体テスト
└── SwitcherViewModelTests.swift            # [更新] ランチャー表示中の通常ショートカット（順/逆/循環/絞り込み中/0件/修飾キー解放/通常モード側無視）テスト
```

**Structure Decision**:
- 既存の `Services/`（低レイヤー `CGEventTap` 管理）と `ViewModels/`（表示状態・選択カーソル管理）の責務境界を維持する。
- `HotKeyMonitorService` のキー判定部分を `CGEvent` や実行中タップに依存しない純粋な値判定関数（`HotKeyKeyDownDecision` / `resolveKeyDown`）として分離することで、憲章が求める「OS イベントから切り離されたユニットテスト可能性」を満たす。

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
