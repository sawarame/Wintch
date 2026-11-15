# 実装計画 (Implementation Plan): ランチャー起動時の初期フォーカス位置変更と検索プレースホルダーの視認性改善

**Branch**: `008-launcher-ux-refinement` | **Date**: 2026-11-15 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/008-launcher-ux-refinement/spec.md)

**Input**: Feature specification from `/specs/008-launcher-ux-refinement/spec.md`

## Summary

検索ランチャーの操作性と視認性を以下の2点について改善する。
1. **ランチャー起動時の初期フォーカス位置を1番目（先頭）へ変更**: `Domain/SwitcherSelection.swift` の `initialIndex(count:preferSecondItem:)` を追加し、`SwitcherViewModel.present(targetMode:)` で `.launcher` 起動時は `preferSecondItem: false`（常にインデックス `0`）を指定する。`.normal`（通常スイッチャー：リスト型およびキャプチャ表示型）は `preferSecondItem: true` を維持し、従来通り2件以上なら2番目（インデックス `1`）を初期選択する。
2. **検索プレースホルダーの視認性改善**: `Views/LauncherSearchField.swift` の `NSTextField` において、`placeholderString` の代わりに `placeholderAttributedString`（前景色 `NSColor.secondaryLabelColor`、フォント 15pt Regular）を生成・設定し、`.ultraThinMaterial` の半透明パネルおよびライト／ダーク双方の外観環境で虫眼鏡アイコン・一覧の補助文字と調和しつつ明確に判読でき、かつ入力文字（`NSColor.labelColor`）と識別可能にする。

あわせて既存の仕様書（`002-window-search-launcher` および `004-launcher-switcher-nav`）の該当記述を本仕様に合わせて整合化する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`SwiftUI`, `AppKit`, `ApplicationServices`, `CoreGraphics`, `Observation`, `Foundation`, `os`）。外部サードパーティ依存ゼロ。  
**Storage**: N/A（永続化設定の追加・変更なし）  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`LSUIElement = YES`、`WintchCore` + `Wintch` 構成）  
**Performance Goals**: 初期インデックス判定は O(1)、プレースホルダー属性文字列生成はパネル生成時1回のみの定数時間処理であり、既存のゼロレイテンシ起動（100ms 以内）を維持する。  
**Constraints**: 画面収録権限不使用、非公開 API（`CGS*` 等）不使用、日本語ドキュメントコメント・インラインコメント必須、`@Observable` 維持、通常スイッチャーの既存挙動・検索ランチャーの日本語 IME 優先制御・各種ショートカット操作を破壊しないこと。  
**Scale/Scope**: `SwitcherSelection`・`SwitcherViewModel`・`LauncherSearchField`、対応テスト（`SwitcherSelectionTests`・`SwitcherViewModelTests`・新規 `LauncherSearchFieldTests`）、および過去仕様書2件の整合化注記に限定した最小限の局所的変更。

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限およびオプトインの原則（Privacy by Design）** | 画面収録権限には一切触れず、検索ランチャーは従来通り最小権限で完結する | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | 新規設定項目や不要な装飾 UI は増やさず、既定の初期選択位置とプレースホルダー視認性のみを最適化する | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | O(1) の初期インデックス計算と標準 `NSTextField` 属性文字列のみであり、起動遅延・メモリ肥大は発生しない | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | Apple 標準フレームワーク（`AppKit` / `SwiftUI` / `Foundation`）のみを使用し、外部依存は追加しない | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。`count == 0` 時非表示、ライト/ダーク・コントラスト設定への自動追従も標準 API で保証される | PASS |
| **6. 技術スタック・MVVM + Services** | 初期インデックス計算は `Domain/` に保持し、状態更新は `ViewModels/`、AppKit テキストフィールド描画は `Views/LauncherSearchField.swift` に閉じ込める | PASS |
| **7. 可読性・テスト可能性・ライセンス** | 初期選択算出（`SwitcherSelection`）およびプレースホルダー属性文字列生成（`LauncherSearchField.makePlaceholderAttributedString`）を純粋関数として切り出して単体テスト可能にし、日本語コメント規約を遵守する | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/008-launcher-ux-refinement/
├── spec.md                                   # 機能仕様書
├── plan.md                                   # 本実装計画書
├── research.md                               # Phase 0 技術調査・設計判断レポート
├── data-model.md                             # Phase 1 データモデル・状態遷移設計
├── quickstart.md                             # Phase 1 ビルド・検証ガイド
├── contracts/                                # Phase 1 インターフェース・UI 契約
│   └── ui-and-selection-contracts.md
└── checklists/
    └── requirements.md                       # 仕様品質チェックリスト
```

### Source Code (repository root)

既存の `WintchCore` + `Wintch` パッケージ構造を変更せず、以下のファイルのみを更新・追加する。

```text
Sources/WintchCore/
├── Domain/
│   └── SwitcherSelection.swift               # [更新] initialIndex(count:preferSecondItem:) を追加し、ランチャー時は先頭(0)を返せるようにする
├── ViewModels/
│   └── SwitcherViewModel.swift               # [更新] present(targetMode:) で targetMode != .launcher を preferSecondItem へ渡す
└── Views/
    └── LauncherSearchField.swift             # [更新] NSColor.secondaryLabelColor を用いた placeholderAttributedString を生成・設定する

Tests/WintchCoreTests/
├── SwitcherSelectionTests.swift              # [更新] preferSecondItem: true / false 双方の初期選択テストを追加
├── SwitcherViewModelTests.swift              # [更新] ランチャー初期選択が 0 であること・移動/通常スイッチャー維持の検証へ更新
└── LauncherSearchFieldTests.swift            # [新規] プレースホルダー属性文字列（文言・secondaryLabelColor・15pt フォント）の単体テスト

specs/
├── 002-window-search-launcher/spec.md        # [更新] ランチャー初期選択位置に関する 008 改定注記の整合化
└── 004-launcher-switcher-nav/spec.md         # [更新] ランチャー初期選択位置に関する 008 改定注記の整合化
```

**Structure Decision**:
- `Domain/` 層（`SwitcherSelection`）に `ViewModels/` の `SwitcherMode` への逆依存を持ち込まないよう、`Bool` 引数 `preferSecondItem: Bool = true` を用いることで層の境界と既存呼び出し互換性を維持する。
- `LauncherSearchField` のプレースホルダー構築ロジックを静的ヘルパーとして公開することで、`NSPanel` を画面表示しない環境でも `swift test` 上でカラー・フォント属性の退行テストを確実に実行できるようにする。

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
