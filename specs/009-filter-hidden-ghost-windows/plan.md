# 実装計画 (Implementation Plan): メモ等の非表示内部補助ウィンドウによる重複・ゴースト表示の除外

**Branch**: `009-filter-hidden-ghost-windows` | **Date**: 2026-11-15 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/009-filter-hidden-ghost-windows/spec.md)

**Input**: Feature specification from `/specs/009-filter-hidden-ghost-windows/spec.md`

## Summary

Mac 標準「メモ」アプリ（`com.apple.Notes`）等で 1 枚しかウィンドウを開いていないにもかかわらずスイッチャーとランチャー双方に複数の「(タイトルなし)」が表示される不具合を修正する。

あわせて今後の他アプリ個別対応の増加に備え、個別アプリの特例判定が `WindowFilter.swift` 内に `if/else` として肥大化しないよう、**宣言的プロファイル／レジストリ構造（`AppWindowProfile` + `AppWindowProfileRegistry`）**を `Domain/` 層に新設する：
1. **アプリ横断の共通裏方ウィンドウ除外**: AppKit / SwiftUI 全般で発生する `x ≈ 0, 500x500`（`!hasAXInfo && isOnScreen != true`・タイトルなし）の未表示バックキングウィンドウを、`com.apple.systempreferences` 専用から全アプリ共通ルールへ昇格し、メモや Gemini 等のゴースト表示を同時に防止する。
2. **宣言的アプリプロファイルによる個別特性のカプセル化**: `AppWindowProfileRegistry` に Bundle ID ごとの定義テーブルを集約し、`com.apple.systempreferences` は `.singleRepresentativeOnly`、`com.apple.Notes` は `.requireAXOrMenuTitle` ＋ `475x600` 未表示補助ウィンドウシグネチャとして明快・独立に記述する。
3. **統一されたフィルタリング適用**: `WindowFilter` は `AppWindowProfileRegistry` を参照する単一の汎用コードパスのみを持ち、特定 Bundle ID の直接分岐をコード上から排除する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`Foundation` / `AppKit` / `ApplicationServices` / `CoreGraphics`）。外部サードパーティ依存ゼロ。  
**Storage**: N/A（永続化データやユーザー設定の追加なし）  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`LSUIElement = YES`、`WintchCore` + `Wintch` 構成）  
**Performance Goals**: プロファイル参照は静的辞書による O(1) ルックアップ、幾何シグネチャ照合は O(シグネチャ数) の定数時間であり、ゼロレイテンシ起動（100ms 以内）に一切の遅延を与えない。  
**Constraints**: 画面収録権限不使用、非公開 API（`CGS*` 等）不使用、日本語ドキュメントコメント（`///`）および日本語インラインコメント必須、`@Observable` 維持、既存アプリ（Chrome / VS Code / Finder / WezTerm / システム設定等）の別スペース・フルスクリーン複数ウィンドウ捕捉に退行を起こさないこと。  
**Scale/Scope**: `Domain/AppWindowProfile.swift` の新規追加、`Domain/WindowFilter.swift` のリファクタリング、および対応ユニットテスト（`AppWindowProfileTests.swift` / `WindowFilterTests.swift`）の追加・更新に閉じた純粋ドメイン層中心の変更。

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限およびオプトインの原則（Privacy by Design）** | 画面収録権限は一切使用せず、既存の AX・CGWindow メタデータ・メニュー情報のみで完結する | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | ユーザー向け設定項目や UI 変更を一切増やさず、内部判定の正確性と構造化のみを行う | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | 静的レジストリの O(1) 参照と定数時間の矩形比較のみで、追加 IPC や非同期遅延はゼロ（むしろ不要なゴーストに対するメニュー問い合わせを削減） | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | `Foundation` の標準型のみを使用し、外部依存は追加しない | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。実ウィンドウが 0 件の場合やタイトル未設定の実ウィンドウに対しても安全にフォールバックする | PASS |
| **6. 技術スタック・MVVM + Services** | すべての判定ロジックを OS 非依存の `Domain/` 層へ閉じ込め、`Services/` や `ViewModels/` / `Views/` へアプリ個別特例を漏洩させない | PASS |
| **7. 可読性・テスト可能性・ライセンス** | 過度な抽象化や独自ジェネリクスを使わず、値型構造体＋辞書テーブルで明快に構造化し、日本語ドキュメントコメント・純粋ユニットテストを完備する | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/009-filter-hidden-ghost-windows/
├── spec.md                                   # 機能仕様書
├── plan.md                                   # 本実装計画書
├── research.md                               # Phase 0 実測調査・設計判断レポート
├── data-model.md                             # Phase 1 プロファイル＆シグネチャデータモデル
├── quickstart.md                             # Phase 1 ビルド・検証ガイド
├── contracts/
│   └── window-filtering-contracts.md         # Phase 1 ドメイン・サービス契約
└── checklists/
    └── requirements.md                       # 仕様品質チェックリスト
```

### Source Code (repository root)

既存の `WintchCore` + `Wintch` パッケージ構造を変更せず、以下のファイルを追加・更新する。

```text
Sources/WintchCore/
└── Domain/
    ├── AppWindowProfile.swift                # [新規] OffscreenCGFallbackPolicy, HiddenBackingWindowSignature, AppWindowProfile, AppWindowProfileRegistry
    └── WindowFilter.swift                    # [更新] 個別 Bundle ID ハードコードを削除し、AppWindowProfileRegistry ベースの統一フィルタへ整理

Tests/WintchCoreTests/
├── AppWindowProfileTests.swift               # [新規] レジストリ参照・既定プロファイル・幾何シグネチャ判定（誤除外防止含む）の単体テスト
└── WindowFilterTests.swift                   # [更新] メモ（1枚/0枚/複数枚/別スペース）・Gemini（500x500のみ）・一般アプリ500x500の検証テスト追加
```

**Structure Decision**:
- 既存の `WindowFilter.swift` からアプリ固有知識（Bundle ID 定数や個別サイズ判定）を `AppWindowProfile.swift` へ分離することで、今後アプリ個別対応が増えても `AppWindowProfileRegistry.profilesByBundleIdentifier` へデータ定義を追加するだけで完結し、`WindowFilter.swift` のロジック本体は常に小さく読みやすい状態を保てる。
- `WindowService.swift` および `SwitcherViewModel.swift` はすでに `WindowFilter.isValid` / `WindowFilter.filterAndMap` を通じてスイッチャー・ランチャー共通のウィンドウ一覧を構築しているため、サービス層・ViewModel 層・View 層の変更を不要とし、影響範囲を最小限かつ純粋ドメイン層に閉じ込める。

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
