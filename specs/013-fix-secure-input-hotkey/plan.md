# 実装計画 (Implementation Plan): セキュア入力フォーカス中のショートカット起動と安定復帰

**Branch**: `013-fix-secure-input-hotkey` | **Date**: 2026-11-17 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/013-fix-secure-input-hotkey/spec.md)

**Input**: Feature specification from `/specs/013-fix-secure-input-hotkey/spec.md`

## Summary

ブラウザ（Chrome / Microsoft Edge 等）のパスワード入力フォームにフォーカスした際、`Option + Tab` 等のショートカットが効かなくなり、フォーカスを外しても稀にしばらく使えなくなる不具合（GitHub Issue #15）を修正する。

調査（[research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/013-fix-secure-input-hotkey/research.md)）により、原因は macOS の **Secure Event Input**（`EnableSecureEventInput()`）が他プロセスの `CGEventTap` へのキーボードイベント配信を遮断すること（およびブラウザ側の解除遅延や `CGEventTap` クールダウン期間）にあると特定した。これに対し、以下の多層設計で解決する：

1. **起動経路のハイブリッド化（`Services/HotKeyMonitorService.swift`）**: 従来の `CGEventTap` に加え、Secure Event Input 中でも通知を受信できる Apple 標準の公開 Carbon API（`RegisterEventHotKey`）を代替起動経路として併用し、設定変更・記録サスペンド（`UnregisterEventHotKey`）とも連動させる。OS 予約キー（`Command + Tab` 等）登録失敗時もクラッシュせず安全に処理する。
2. **二重発火防止・純粋判定の分離（`Domain/HotKeyFallbackSupport.swift`）**: `CGEventTap` と Carbon の間で同一キー操作の二重移動を防ぐ `HotKeyTriggerDeduplicator`、Carbon ホットキー登録計画 `CarbonHotKeyRegistrationPlan`、および Secure Input 誤検知を防ぐ修飾キー解放判定ヘルパーを `Domain/` へ切り出し単体テスト可能にする。
3. **セキュア入力時の一時アクティブ化とキャンセル復元（`HotKeyMonitorService` / `SwitcherViewModel` / `AppCoordinator` / `SwitcherPanel`）**: Carbon 経由または `IsSecureEventInputEnabled() == true` 下での通常スイッチャー起動時は `SwitcherPanel` 表示時に `NSApplication.shared.activate()` を実行してブラウザの Secure Input を解除し、ローカル `NSEvent` モニタと `!IsSecureEventInputEnabled()` ガード付き短周期ウォッチドッグにより `Esc`・矢印・`Q`・高速な修飾キー解放をすべて確実に処理する。キャンセル時は直前アプリへフォーカスを戻し、通常時は従来通り非アクティブ表示を維持する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`, Strict Concurrency 準拠）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`Foundation`, `AppKit`, `ApplicationServices`, `CoreGraphics`, `Carbon` / `HIToolbox`）。外部サードパーティ依存ゼロ。  
**Storage**: N/A（新規の永続化データ・設定項目追加なし。既存のショートカット設定値をそのまま利用）  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`WintchCore` + `Wintch` 構成）  
**Performance Goals**: 常駐時の追加ポーリングなし（CPU 追加負荷ゼロ）。フォールバック起動時のパネル表示も体感遅延ゼロ（0.2 秒以内）。ウォッチドッグおよびローカルモニタはフォールバック通常セッション中のみ限定稼働し、終了時に即時破棄する。  
**Constraints**:
- リスト型スイッチャーおよび検索ランチャーで画面収録権限を一切要求・使用しない。
- 非公開 API（`CGS*` 等）を一切使用しない（`Carbon.HIToolbox` の `RegisterEventHotKey` / `IsSecureEventInputEnabled` は公開 SDK API）。
- `CGEventTap`・`Carbon`・`IsSecureEventInputEnabled`・`NSEvent` モニタ等の低レイヤー OS API はすべて `Services/`（および最小限の `AppKit` パネル制御 `Views/SwitcherPanel.swift`）に隔離し、`ViewModels/` へ漏洩させない。
- コード内コメントおよびドキュメントコメント（`///`）はすべて日本語で記述する。
- 既存の `HotKeyMonitorDecisionTests`・`AppCoordinatorTests`・`SwitcherViewModelTests` の既存契約・挙動を壊さないこと。

**Scale/Scope**: `Domain/` に 1 ファイル新規追加、`Services/`（`HotKeyMonitorService`, `HotKeyMonitoring`）、`ViewModels/SwitcherViewModel`、`App/AppCoordinator`、`Views/SwitcherPanel` のピンポイント更新、および対応ユニットテストの追加。

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限およびオプトインの原則（Privacy by Design）** | 画面収録権限を一切要求・使用しない。追加する Carbon ホットキー・ローカルモニタも既存機能の範囲内であり追加権限を要求しない | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | UI や設定項目を増やさず、既存の通常スイッチャー・検索ランチャー・ショートカット設定をそのまま動作させる | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | 常駐時の追加バックグラウンドポーリングは行わず、Carbon イベント駆動のみで応答する。監視補助もフォールバック通常セッション中のみ限定稼働する | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | Apple 標準 SDK に含まれる `Carbon`（`HIToolbox`）のみを追加利用し、外部ライブラリ依存ゼロを維持する | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。OS 予約キー（`Command + Tab` 等）で `RegisterEventHotKey` が失敗してもクラッシュせず安全に継続し、実際の権限剥奪時は既存通り権限誘導へフォールバックする | PASS |
| **6. 技術スタック・MVVM + Services** | 重複排除・Carbon 登録計画・解放ガード判定は `Domain/` へ分離し、OS API は `Services/HotKeyMonitorService.swift` に隔離する。状態管理は既存の `@Observable` / `@MainActor` を踏襲する | PASS |
| **7. 可読性・テスト可能性・ライセンス** | 純粋関数・値型でユニットテスト可能な構造とし、すべての型・メソッド・インラインコメントを日本語で記述する | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/013-fix-secure-input-hotkey/
├── spec.md                                      # 機能仕様書
├── plan.md                                      # 本実装計画書
├── research.md                                  # Phase 0 技術調査・設計判断レポート
├── data-model.md                                # Phase 1 状態モデル・値型設計
├── quickstart.md                                # Phase 1 ビルド・自動テスト・実機検証ガイド
├── contracts/
│   └── hotkey-secure-input-contracts.md         # Phase 1 サービス・UI 契約仕様
└── checklists/
    └── requirements.md                          # 仕様品質チェックリスト
```

### Source Code (repository root)

既存の `WintchCore` + `Wintch` 構造を維持し、以下のファイルを追加・更新する。

```text
Sources/WintchCore/
├── Domain/
│   └── HotKeyFallbackSupport.swift              # [新規] TriggerDeduplicator, CarbonHotKeyRegistrationPlan, 修飾キー解放安全判定
├── Services/
│   ├── Protocols/
│   │   └── HotKeyMonitoring.swift               # [更新] requiresAppActivationOnPresentation プロパティ追加
│   └── HotKeyMonitorService.swift               # [更新] Carbon RegisterEventHotKey 併用、重複排除、ローカル NSEvent モニタ、解放ウォッチドッグ
├── ViewModels/
│   └── SwitcherViewModel.swift                  # [更新] shouldActivateAppForCurrentSession の保持とリセット
├── App/
│   └── AppCoordinator.swift                     # [更新] SwitcherPanel.show への activateApp 伝播
└── Views/
    └── SwitcherPanel.swift                      # [更新] show(mode:activateApp:) による通常モード一時アクティブ化・復元対応

Tests/WintchCoreTests/
├── Mocks/
│   └── MockServices.swift                       # [更新] MockHotKeyMonitor への requiresAppActivationOnPresentation 対応
├── HotKeyFallbackSupportTests.swift             # [新規] 重複排除・Carbon登録計画・SecureInput解放ガードの単体テスト
├── HotKeyMonitorDecisionTests.swift             # [更新] 必要に応じた境界ケース検証追加
└── SwitcherViewModelTests.swift                 # [更新] 一時アクティブ化フラグ連携・リセットの検証追加
```

**Structure Decision**:
- OS 依存の薄い境界（`Carbon` の `RegisterEventHotKey` / `IsSecureEventInputEnabled` と `CGEventTap` / `NSEvent` ローカルモニタ）は `HotKeyMonitorService.swift` のみに閉じ込め、すべての分岐判断・重複排除・登録変換は `Domain/HotKeyFallbackSupport.swift` の純粋ロジックへ逃がすことで、Swift Testing による高速かつ決定論的な検証を担保する。
- `HotKeyEvent` 列挙型の既存ケース（`.triggerPressed(isShiftPressed:)`）を変えず `HotKeyMonitoring.requiresAppActivationOnPresentation` を追加する構成により、既存テスト群への波及を最小限に抑える。

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
