# 実装計画 (Implementation Plan): ウィンドウ検索ランチャーモード

**Branch**: `002-window-search-launcher` | **Date**: 2026-11-13 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/002-window-search-launcher/spec.md)

**Input**: Feature specification from `/specs/002-window-search-launcher/spec.md`

## Summary

既存の通常ウィンドウ単位スイッチャー（`Option + Tab` / 逆順 `Option + Shift + Tab`）を維持したまま、トグル起動型の検索ランチャーモード（デフォルト `Option + Space`）を追加する。Domain 層にスペース区切り AND ファジー検索・ハイライト範囲算出（`WindowSearchEngine`）およびランチャーショートカット・双方向競合検証ロジック（`LauncherShortcutPreference` / `ShortcutConflictValidator`）を純粋 Swift で実装し、`HotKeyMonitorService` は通常／ランチャー／ショートカット記録サスペンドの各モードを同期制御する。UI 層では `SwitcherListView` 上部へ検索バーを統合し、AppKit `NSTextField` ラッパーによる日本語 IME 優先入力、`SwitcherPanel` の上端固定・下方向伸縮リサイズ、一致箇所の太字ハイライト、および `SettingsView` へのショートカットレコーダー組み込みを行う。

## Technical Context

**Language/Version**: Swift 6（`Apple Swift version 6.4.2` / `swift-tools-version: 6.0` を確認済み）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`SwiftUI`, `AppKit`, `ApplicationServices`, `CoreGraphics`, `Observation`, `Foundation`）。外部サードパーティ依存ゼロ。  
**Storage**: `UserDefaults`（既存の通常ショートカットキー `dev.wintch.shortcutPreference` に加え、ランチャーショートカットキー `dev.wintch.launcherShortcutPreference` を追加保存）  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`LSUIElement = YES`、`WintchCore` + `Wintch` 2ターゲット構成）  
**Performance Goals**: ランチャー起動から入力受付開始まで 100ms 未満、50ウィンドウ以上での1文字入力あたりの検索・ソート・再描画 100ms 未満、パネル上端座標のズレ 0pt  
**Constraints**: 画面収録権限（ScreenCaptureKit 等）不使用、非公開 API（`CGS*` 等）不使用、macOS 14.0+ 互換 API のみ使用（macOS 15 限定 API 不使用）、日本語ドキュメントコメント・インラインコメント必須  
**Scale/Scope**: 既存の 4 画面構成（メニューバー、スイッチャーパネル、設定画面、権限誘導画面）を維持したまま、検索ランチャー機能および設定画面ショートカットレコーダーを拡張

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限の原則（Privacy by Design）** | 検索対象は既存の `WindowEntry`（アプリ名・ウィンドウタイトル）のみで、画面収録権限やサムネイル取得は一切追加しない | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | 既存の縦型リスト上部に検索バーを統合し、設定画面もランチャーショートカットレコーダー1項目の追加に留める | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | 純粋線形ファジー検索・インメモリ評価により 100ms 以内で絞り込みとハイライトを描画し、非表示時の負荷を増やさない | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | ファジー検索・キー変換・レコーダー・ハイライト描画をすべて Swift 標準 / Apple 標準フレームワークのみで実装 | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。権限未許可時は既存の権限誘導画面へフォールバックし、記録サスペンドや 0 件時もクラッシュしない | PASS |
| **6. 技術スタック・MVVM + Services** | `@Observable` を維持。`CGEventTap` 拡張は `HotKeyMonitorService` に隔離し、`NSTextField` / `NSPanel` 制御は `Views/` 内に閉じ込める | PASS |
| **7. 可読性・テスト可能性・ライセンス** | ファジー検索・ハイライト範囲・競合検証・状態遷移をすべて `Domain/` と `ViewModels/` に分離して `swift test` 可能にし、日本語コメント規約を遵守 | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/002-window-search-launcher/
├── plan.md                        # 本実装計画書
├── research.md                    # Phase 0 技術調査レポート（IME・上端固定・ファジー検索・競合防止）
├── data-model.md                  # Phase 1 データモデル・状態遷移設計
├── quickstart.md                  # Phase 1 ビルド・実機検証ガイド
├── contracts/                     # Phase 1 サービス・UIコントラクト
│   ├── service-contracts.md
│   └── ui-contracts.md
└── checklists/
    └── requirements.md            # 仕様品質チェックリスト
```

### Source Code (repository root)

既存の `WintchCore`（ライブラリ）＋ `Wintch`（実行ターゲット）構成を維持し、以下のファイルを追加・拡張する。

```text
Sources/WintchCore/
├── App/
│   └── AppCoordinator.swift                  # [更新] ランチャー起動設定ロード、前後アプリ記録・復元連携、パネルモード/リサイズ連携
├── Domain/
│   ├── ShortcutPreference.swift              # [更新] ShortcutModifiers との変換・比較連携
│   ├── LauncherShortcutPreference.swift      # [新規] ランチャーショートカットモデル・表示表記・デフォルト値
│   ├── ShortcutConflictValidator.swift       # [新規] 修飾キー必須検証・通常↔ランチャー双方向競合検証
│   ├── WindowSearchResult.swift              # [新規] スコアとハイライト範囲付き検索結果モデル
│   └── WindowSearchEngine.swift              # [新規] スペース区切り AND ファジー検索・スコアリング・範囲抽出
├── Services/
│   ├── Protocols/
│   │   ├── HotKeyMonitoring.swift            # [更新] HotKeyMonitorMode, launcherTriggerPressed, isSuspendedForRecording 追加
│   │   └── PreferencesStoring.swift          # [更新] loadLauncherShortcut / saveLauncherShortcut 追加
│   ├── HotKeyMonitorService.swift            # [更新] モード別イベント消費/通過、ランチャーキー監視、記録時サスペンド
│   └── PreferencesStore.swift                # [更新] ランチャーショートカット永続化キー追加
├── ViewModels/
│   ├── SwitcherViewModel.swift               # [更新] SwitcherMode (.inactive/.normal/.launcher)、検索状態・移動・トグル制御
│   └── SettingsViewModel.swift               # [更新] ランチャーショートカット状態、記録サスペンド制御、双方向競合エラー管理
└── Views/
    ├── SwitcherPanel.swift                   # [更新] ランチャー時フォーカス制御、上端固定下方向リサイズ制御
    ├── SwitcherListView.swift                # [更新] 検索バー統合、AttributedString 太字ハイライト、0件空状態表示
    ├── LauncherSearchField.swift             # [新規] NSTextField ラッパー（IME 優先・Enter/Esc/↑↓/Ctrl+N/P 処理）
    ├── SettingsView.swift                    # [更新] ランチャーショートカットレコーダー統合・双方のエラー表示
    └── ShortcutRecorderView.swift            # [新規] 実キー入力によるショートカット記録 UI コンポーネント

Tests/WintchCoreTests/
├── Mocks/
│   └── MockServices.swift                    # [更新] HotKeyMonitoring / PreferencesStoring 拡張メソッド対応
├── LauncherShortcutPreferenceTests.swift     # [新規] モデル・Codable・表示表記テスト
├── ShortcutConflictValidatorTests.swift      # [新規] 修飾キー必須・順/逆双方向競合検証テスト
├── WindowSearchEngineTests.swift             # [新規] スペース区切り AND・ファジー・スコア順・MRUタイブレーク・ハイライト範囲テスト
├── SwitcherViewModelTests.swift              # [更新] ランチャー起動・トグル・検索更新・モード排他・0件Enter無視テスト
└── SettingsViewModelTests.swift              # [更新] レコーダー適用・重複ブロック・サスペンド状態テスト
```

**Structure Decision**:
- 既存の `Domain/`・`Services/`・`ViewModels/`・`Views/` レイヤー分割をそのまま拡張し、新しい純粋ロジック（`WindowSearchEngine`, `ShortcutConflictValidator`）は AppKit / SwiftUI に一切依存させないことで Swift Testing による高速な単体テストを担保する。
- 低レイヤーの `CGEventTap` 変更は `HotKeyMonitorService` に閉じ込め、IME と競合しないようランチャー表示中はキーイベントをキーウィンドウの `NSTextField` へ通過させる責務境界を明確にする。

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
