# 実装計画 (Implementation Plan): ランチャーおよびリスト型スイッチャーの選択候補スクロール追従修正

**Branch**: `018-fix-launcher-scroll` | **Date**: 2026-11-17 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/018-fix-launcher-scroll/spec.md`

## Summary

検索ランチャーおよび通常スイッチャー（リスト型）で多数のウィンドウやアプリ起動候補が表示され縦スクロールバーが出現しているにもかかわらず、方向キー等で候補を移動してもリストが自動スクロールしない不具合を修正する（GitHub Issue #25）。

調査結果（[research.md](research.md)）に基づき、根本原因であった `SwitcherListView` 内の `ForEach` 要素識別子（`\.element.id`）と行ビュー側の `.id(rowScrollID(...))`（`"window-<id>"` / `"app-<id>"`）の不一致を解消する。具体的には、以下の設計を実施する：

1. **リスト表示行の統一識別モデル導入（`Sources/WintchCore/Domain/SwitcherListRow.swift`）**:
   - ウィンドウ候補行・アプリ起動セクション見出し行・アプリ起動候補行を単一の `Identifiable` モデル（`SwitcherListRow`）として構築し、行の `id`（`"window-<id>"` / `"app-launch-section-header"` / `"app-<id>"`）と選択インデックスに対応するスクロール先 ID 解決（`scrollTargetID(for:)`）を一元化する。
2. **`SwitcherListView` の単一 `ForEach` 化とスクロール追従タイミング補強（`Sources/WintchCore/Views/SwitcherListView.swift`）**:
   - `LazyVStack` 内を単一の `ForEach(rows)` に統一し、`ForEach` の `id` と `.id(row.id)` / `proxy.scrollTo(targetID, anchor: .center)` が常に同一識別子を参照するよう修正する（`ForEach` 識別子と別 ID の競合を構造的に排除）。
   - `selectedIndex` 変化時に加え、`searchQuery` 変化時（手動スクロール後に同インデックス `0` のまま再検索された場合）、`mode` 変化時、および `onAppear` 時にも現在の選択候補が可視領域へ追従・リセットされるよう補強する。
3. **スクロール追従および行構築ロジックの自動テスト追加（`Tests/WintchCoreTests/`）**:
   - `Domain/SwitcherListRow` の構築・識別子一意性・インデックス対応・境界値のユニットテストを追加する。
   - `SwitcherListView` を実際に `NSHostingView` 上でレイアウトし、`NSScrollView.contentView.bounds.origin.y` の実測により、ランチャー上下移動・セクション跨ぎ移動・循環移動・検索リセット・再表示・通常リスト型スイッチャーのスクロール追従を検証するテストスイート（`SwitcherListViewTests.swift`）を追加する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`, Strict Concurrency 準拠）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`SwiftUI`, `AppKit`, `Foundation`, `Observation`）。外部サードパーティ依存ゼロ。  
**Storage**: N/A（永続化設定の変更なし）  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`WintchCore` + `Wintch`）  
**Performance Goals**: キー操作・検索更新から選択ハイライトおよびスクロール追従完了まで体感遅延なし（100ms 以内、既存アニメーション `0.08s` 維持）。`SwitcherListRow` の構築は表示候補数に対する単純配列変換 O(N) で無視できる軽量処理とする。  
**Constraints**:
- Wintch 憲章 v2.0.0 の全原則（最小権限・シンプルさ・ゼロレイテンシ・外部依存ゼロ・非公開 API 禁止）を遵守する。
- `SwitcherListView` 以外の通常スイッチャー（キャプチャ表示型）や `LauncherSearchField` の IME 変換優先挙動を壊さない。
- コード内のコメントおよびドキュメントコメント（`///`）はすべて日本語で記述する。

**Scale/Scope**: `Domain/` への軽量な行モデル追加（1ファイル）、`Views/SwitcherListView.swift` の修正、および `Tests/WintchCoreTests/` へのユニットテスト／ビュー検証テスト追加。

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限およびオプトインの原則（Privacy by Design）** | 画面収録権限には一切関与せず、リスト型・ランチャーのアクセシビリティ＋メタデータ完結設計を維持 | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | 既存 UI・操作体系を変更せず、リスト行識別契約の一元化によるバグ修正のみに限定 | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | `LazyVStack` による遅延描画を維持し、識別子不整合の解消のみで応答性を損なわない | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | Apple 標準フレームワーク（`SwiftUI` / `AppKit` / `Foundation`）のみ使用 | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。空状態・境界外インデックスに対して安全に nil ガードでフォールバック | PASS |
| **6. 技術スタック・MVVM + Services** | 純粋なリスト行マッピングを `Domain/` に切り出し、`Views/` には低レイヤー OS API を持ち込まない | PASS |
| **7. 可読性・テスト可能性・ライセンス** | 複雑なジェネリクスやマクロを使わない明快な enum 設計。`Domain` テストと `NSHostingView` 実スクロール検証の双方を整備。全コメント日本語 | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/018-fix-launcher-scroll/
├── spec.md                                      # 機能仕様書
├── plan.md                                      # 本実装計画書
├── research.md                                  # Phase 0 原因調査・検証レポート
├── data-model.md                                # Phase 1 リスト行・スクロール識別モデル
├── quickstart.md                                # Phase 1 テスト・動作確認ガイド
├── contracts/
│   └── launcher-scroll-contract.md              # Phase 1 スクロール追従 UI 契約
└── checklists/
    └── requirements.md                          # 仕様品質チェックリスト
```

### Source Code (repository root)

```text
Sources/WintchCore/
├── Domain/
│   └── SwitcherListRow.swift                    # [新規] ウィンドウ行・見出し行・アプリ起動行の統一 Identifiable モデルと ID 解決ヘルパー
└── Views/
    └── SwitcherListView.swift                   # [更新] 単一 ForEach(rows) 化および検索・表示切替時のスクロール追従補強

Tests/WintchCoreTests/
├── SwitcherListRowTests.swift                   # [新規] 統一リスト行構築・識別子一意性・インデックス解決テスト
└── SwitcherListViewTests.swift                  # [新規] NSHostingView + NSScrollView による実スクロール追従回帰テスト
```

**Structure Decision**: 既存の MVVM + Services 構成（`Sources/WintchCore/` および `Tests/WintchCoreTests/`）に従い、行リスト構築およびスクロール先 ID 解決という純粋ロジックを `Domain/SwitcherListRow.swift` に配置し、`Views/SwitcherListView.swift` はそのモデルを描画および `ScrollViewReader` 追従にのみ用いる構造とする。

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
