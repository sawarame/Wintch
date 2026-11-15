# 実装計画 (Implementation Plan): スイッチャーおよび検索ランチャーからの選択中ウィンドウ／アプリ終了

**Branch**: `005-close-selected-window` | **Date**: 2026-11-15 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/005-close-selected-window/spec.md)

**Input**: Feature specification from `/specs/005-close-selected-window/spec.md`

## Summary

通常スイッチャーおよび検索ランチャーの双方で「通常スイッチャー必須修飾キー + `Q`」（デフォルト `Option + Q`）が押された際、選択中ウィンドウが所属するアプリケーションの有効ウィンドウ総数（`allEntries` 基準）に応じて動作を分岐する：
- **複数ウィンドウがある場合**: 選択中のウィンドウ 1 枚のみを閉じる（未訪問の別スペースにある `cg-*` ウィンドウの場合は一時的に対象スペースへ切り替えて `AXUIElement` を解決した上でクローズし、パネルフォーカスを回復する）。
- **1 ウィンドウのみの場合**: `NSRunningApplication.terminate()` によりアプリケーション自体を通常終了し、終了確認後に一覧から除外することで裏ウィンドウの再出現を防ぐ。

いずれの場合もパネルを開いたまま連続整理でき、全ウィンドウが 0 件になった場合のみパネルを自動終了する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`SwiftUI`, `AppKit`, `ApplicationServices`, `CoreGraphics`, `Observation`, `Foundation`, `os`）。外部サードパーティ依存ゼロ。  
**Storage**: 新規ストレージキーなし。既存の `UserDefaults`（`dev.wintch.shortcutPreference`）のみ参照。  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`LSUIElement = YES`、`WintchCore` + `Wintch` 構成）  
**Performance Goals**: 同一スペースの単一ウィンドウクローズは 200ms 以内、通常アプリ終了および別スペース取得を含む終了処理は 500ms〜600ms の早期脱出ポーリングで即応する。  
**Constraints**: 画面収録権限不使用、非公開 API（`CGS*` 等）不使用、日本語ドキュメントコメント・インラインコメント必須、`@Observable` 使用、強制終了（`forceTerminate`）禁止、検索中の誤アプリ終了防止、一時スペース移動時の `resignedActive` 誤キャンセル防止。  
**Scale/Scope**: `WindowServicing` / `WindowService`、`SwitcherViewModel`、`SwitcherPanel`、`AppCoordinator`、`HotKeyMonitoring` / `HotKeyMonitorService`、`SwitcherSelection`、および対応テストに限定した変更。

## Constitution Check

*GATE: 仕様改定後の再検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限の原則（Privacy by Design）** | 画面収録権限不使用。既存のアクセシビリティ権限と `NSRunningApplication` 標準 API のみで完結する | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | 設定項目を増やさず、既存の `修飾キー + Q` の単一操作でウィンドウ数に応じた自然な終了・整理を実現する | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | キー判定は O(1)、クローズ・終了ポーリングは早期脱出方式で不要な待機を行わない | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | Apple 標準フレームワークのみ使用 | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API（`CGS*`）不使用。未訪問別スペースのウィンドウは標準 `NSRunningApplication.activate()` によるスペース切り替えで安全に解決し、強制終了も用いない | PASS |
| **6. 技術スタック・MVVM + Services** | `AXUIElement`・`CGEventTap`・`NSRunningApplication.terminate` はすべて `Services/` に隔離する | PASS |
| **7. 可読性・テスト可能性・ライセンス** | 複数/単一判定・分岐呼び出し・`resignedActive` 抑制・フォーカス回復通知をすべて `MockWindowService` 経由で `swift test` 検証可能とし、日本語コメント規約を遵守する | PASS |

## Project Structure

### Source Code (repository root)

```text
Sources/WintchCore/
├── App/
│   └── AppCoordinator.swift                # [更新] onPanelFocusRestoreNeeded を SwitcherPanel.restoreFocusIfNeeded へ接続
├── Domain/
│   └── SwitcherSelection.swift             # [更新済] 1件除外後のインデックス補正 indexAfterRemoval 追加
├── Services/
│   ├── Protocols/
│   │   ├── HotKeyMonitoring.swift          # [更新済] HotKeyEvent.closeSelectedWindowPressed 追加
│   │   └── WindowServicing.swift           # [更新] terminateApplication(pid:) async -> Bool 追加
│   ├── HotKeyMonitorService.swift          # [更新済] .normal / .launcher での修飾キー + Q 判定・消費
│   └── WindowService.swift                 # [更新] closeWindow の別スペース自動移動フォールバック + terminateApplication(pid:) 実装
├── ViewModels/
│   └── SwitcherViewModel.swift             # [更新] 同一アプリ件数による分岐、処理中 resignedActive 抑止、フォーカス回復通知
└── Views/
    └── SwitcherPanel.swift                 # [更新] 高さ追従拡張 + restoreFocusIfNeeded(mode:) 追加

Tests/WintchCoreTests/
├── Mocks/
│   └── MockServices.swift                  # [更新] MockWindowService に terminateApplication スタブ・履歴追加
├── HotKeyMonitorDecisionTests.swift        # [更新済] 修飾キー + Q 判定・単体 Q 通過・Command+Q 消費テスト
├── SwitcherSelectionTests.swift            # [更新済] indexAfterRemoval 境界値テスト
└── SwitcherViewModelTests.swift            # [更新] 単一ウィンドウ終了・複数時クローズ・絞り込み時誤終了防止・処理中 resignedActive 抑止テスト追加
```

## Complexity Tracking

> 憲章違反は存在しないため、該当なし。
