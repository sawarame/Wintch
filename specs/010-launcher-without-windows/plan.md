# 実装計画 (Implementation Plan): ウィンドウ 0 件時の検索ランチャー起動対応

**Branch**: `010-launcher-without-windows` | **Date**: 2026-11-16 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/010-launcher-without-windows/spec.md)

**Input**: Feature specification from `/specs/010-launcher-without-windows/spec.md`

## Summary

操作可能な通常ウィンドウが 0 件の状態でも検索ランチャーを起動できるようにし、アプリ起動ランチャーとして常時利用可能にする：

1. **ウィンドウ 0 件時の検索ランチャー起動許可**: `SwitcherViewModel.present(targetMode:)` において、通常スイッチャー（`.normal`）は従来通り 0 件時非表示を維持しつつ、検索ランチャー（`.launcher`）は有効ウィンドウが 0 件でもパネルを開いて検索入力欄にフォーカスを当てられるようにする。
2. **空状態の明快なドメインモデル化 (`LauncherEmptyState`)**: ウィンドウ 0 件・未入力時の案内メッセージ（「開いているウィンドウがありません（アプリ名を入力して起動）」）と、検索入力後の一致 0 件メッセージ（ウィンドウ 0 件時は「一致するアプリがありません」、ウィンドウ 1 件以上時は「一致するウィンドウやアプリがありません」）、およびアプリ起動セクション見出しを純粋ドメイン型 `LauncherEmptyState` + `SwitcherViewModel` の導出プロパティとして整理し、`SwitcherListView` へ渡す。
3. **最後のウィンドウ終了時のランチャー継続維持**: `SwitcherViewModel.closeSelectedWindow()` で `allEntries` が 0 件になった際、`.normal` モードのみ従来通りパネルを自動終了し、`.launcher` モードではパネルを閉じずに維持して検索結果・空状態を再評価する。
4. **関連仕様書の整合化**: `002-window-search-launcher`・`005-close-selected-window`・`006-launcher-app-launch`・`008-launcher-ux-refinement` の該当記述を本仕様に合わせて整合更新する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`Foundation` / `AppKit` / `SwiftUI`）。外部サードパーティ依存ゼロ。  
**Storage**: N/A（永続化データやユーザー設定の追加なし）  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`LSUIElement = YES`、`WintchCore` + `Wintch` 構成）  
**Performance Goals**: ウィンドウ 0 件時も 100ms 以内に検索ランチャーパネルを表示し入力を受け付ける。未入力時はアプリ検索を走らせず、入力時のみメモリキャッシュ済みアプリ一覧に対して 100ms 以内に検索・再描画を完了する。  
**Constraints**: 画面収録権限不使用、非公開 API（`CGS*` 等）不使用、日本語ドキュメントコメント（`///`）および日本語インラインコメント必須、`@Observable` / `@MainActor` 維持、通常スイッチャーの 0 件時非起動・最後 1 枚クローズ時自動終了の既存挙動を維持すること。  
**Scale/Scope**: `Domain/LauncherEmptyState.swift` の新規追加、`ViewModels/SwitcherViewModel.swift` および `Views/SwitcherListView.swift` の最小限の更新、対応ユニットテスト（`LauncherEmptyStateTests.swift` / `SwitcherViewModelTests.swift`）および既存仕様書（4 件）の整合更新。

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限およびオプトインの原則（Privacy by Design）** | 検索ランチャー機能のみの変更であり、画面収録権限は一切要求・使用せず、既存のアクセシビリティ権限チェックのみで完結する | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | 新しい設定項目や複雑な UI 要素は増やさず、既存の検索ランチャーがウィンドウ 0 件でも開く自然な拡張にとどめる | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | ウィンドウ 0 件時はウィンドウソート対象が空で、未入力時はアプリ検索も行わないため、従来以上の即時起動を維持できる | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | `Foundation` / `SwiftUI` / `AppKit` のみを使用し、外部パッケージは一切追加しない | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。権限未許可時は従来通り `onPermissionDenied?()` 経由で権限誘導画面へ安全にフォールバックし、候補 0 件時の確定・移動・終了操作もすべて安全に無視する | PASS |
| **6. 技術スタック・MVVM + Services** | 空状態判定の純粋ロジックを `Domain/LauncherEmptyState.swift` へ分離し、状態管理は `@Observable` / `@MainActor` な `SwitcherViewModel`、`Views/` は描画のみに徹する | PASS |
| **7. 可読性・テスト可能性・ライセンス** | 過度な抽象化や独自ジェネリクスを避けた明快な enum・純粋関数設計とし、日本語ドキュメントコメント・インラインコメント・ユニットテストを完備する | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/010-launcher-without-windows/
├── spec.md                                      # 機能仕様書
├── plan.md                                      # 本実装計画書
├── research.md                                  # Phase 0 調査・設計判断レポート
├── data-model.md                                # Phase 1 空状態・状態遷移データモデル
├── quickstart.md                                # Phase 1 ビルド・検証ガイド
├── contracts/
│   └── launcher-zero-windows-contracts.md       # Phase 1 ドメイン・ViewModel・View 契約
└── checklists/
    └── requirements.md                          # 仕様品質チェックリスト
```

### Source Code (repository root)

既存の `WintchCore` + `Wintch` パッケージ構造を変更せず、以下のファイルを追加・更新する。

```text
Sources/WintchCore/
├── Domain/
│   └── LauncherEmptyState.swift                 # [新規] 空状態種別（noOpenWindows / noMatchingApps / noMatchingCandidates）と純粋判定ロジック
├── ViewModels/
│   └── SwitcherViewModel.swift                  # [更新] 0件時の .launcher 起動許可、最後1枚クローズ時の .launcher 維持、hasOpenWindows / emptyState / launchSectionHeaderTitle 追加
└── Views/
    └── SwitcherListView.swift                   # [更新] emptyState に応じた案内文言表示と launchSectionHeaderTitle の適用

Tests/WintchCoreTests/
├── LauncherEmptyStateTests.swift                # [新規] 空状態判定ロジック（未入力/入力済・0件/1件以上・メッセージ）の単体テスト
└── SwitcherViewModelTests.swift                 # [更新] 0件起動・アプリ検索起動・キャンセル・検索クリア・最後1枚クローズ時維持・通常スイッチャー非起動の検証追加・更新

specs/
├── 002-window-search-launcher/spec.md           # [更新] 0件時起動に関する参照注記の整合化
├── 005-close-selected-window/spec.md            # [更新] ランチャーで最後のウィンドウ終了後もパネルを維持する旨の整合化
├── 006-launcher-app-launch/spec.md              # [更新] ウィンドウ0件時のランチャー起動前提の整合化
└── 008-launcher-ux-refinement/spec.md           # [更新] 0件時空パネル非表示記述の整合化
```

**Structure Decision**:
- `SwitcherSelection.initialIndex(count:preferSecondItem:)` の既存契約（`count == 0` で `nil`）は維持し、起動可否判断を `SwitcherViewModel.present(targetMode:)` に閉じることで、通常スイッチャー・選択計算の既存テストを一切破壊せずに目的を達成する。
- 空状態メッセージの分岐を `Domain/LauncherEmptyState.swift` に切り出すことで、View にビジネス条件分岐を置かず、SwiftUI を起動しない純粋ユニットテストで確実にカバーできる。

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
