# 実装計画 (Implementation Plan): 画面収録権限未許可時のスイッチャー内設定リンク削除

**Branch**: `017-remove-switcher-permission-link` | **Date**: 2026-11-17 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/017-remove-switcher-permission-link/spec.md)

**Input**: Feature specification from `/specs/017-remove-switcher-permission-link/spec.md`

## Summary

通常スイッチャー（ホールド式）を「キャプチャ表示型」に設定し、かつ画面収録権限が未許可の状態で起動した際、パネル上部の権限案内バナーに表示されていた「設定を開く」リンクボタンを削除する（GitHub Issue #23）。`Option + Tab` 等で修飾キーを保持している間は両手が塞がっておりリンクをクリックすることが不可能なため、クリック可能なリンクとそれに伴う `SwitcherViewModel` 上の設定遷移メソッドを廃止し、プレースホルダー表示である旨を伝える非インタラクティブな案内表示のみを残す。

調査結果（[research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/017-remove-switcher-permission-link/research.md)）に基づき、以下を実施する：

1. **`SwitcherCaptureGridView` の設定リンク削除とテキスト表示調整（`Sources/WintchCore/Views/SwitcherCaptureGridView.swift`）**:
   - `permissionBannerView` から `Button("設定を開く")`（`.buttonStyle(.link)`）および `Spacer(minLength: 4)` を削除する。
   - バナーの案内メッセージ定数 `permissionBannerMessage` を整理し、1 枚表示時の最小幅（`360pt`）から複数枚表示時までテキストが途切れないよう `.fixedSize(horizontal: false, vertical: true)` と左寄せレイアウトを適用する。
2. **`SwitcherViewModel` の不要な設定遷移 API の整理（`Sources/WintchCore/ViewModels/SwitcherViewModel.swift`）**:
   - スイッチャーパネル専用の `openScreenRecordingSettings()` および `onOpenScreenRecordingSettingsRequested` を削除する（`SettingsViewModel` 側の設定遷移機能は維持する）。
3. **テストの更新と回帰テスト追加（`Tests/WintchCoreTests/`）**:
   - `SwitcherViewModelTests.swift` の不要になった `openScreenRecordingSettings()` テスト箇所を整理し、未許可時のフォールバック動作検証を維持する。
   - `SwitcherCaptureGridViewTests.swift` を追加（または既存ビューテストへ追加）し、`isScreenRecordingGranted == false` の描画ツリーにクリック可能ボタン（`NSButton`）が生成されないこと、および許可済み・未許可時のレイアウト整合性を検証する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`, Strict Concurrency 準拠）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`SwiftUI`, `AppKit`, `Foundation`, `Observation`）。外部サードパーティ依存ゼロ。  
**Storage**: N/A（永続化設定の変更なし）  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`WintchCore` + `Wintch`）  
**Performance Goals**: スイッチャーパネルの即時表示（100ms 以内）に影響を与えない（UI 要素削減によりむしろ軽量化）。  
**Constraints**:
- Wintch 憲章 v2.0.0 の「最小権限およびオプトインの原則」および「安全なフォールバック」を維持する。
- リスト型・検索ランチャーにおける画面収録権限ゼロの挙動を変えない。
- 設定画面（`SettingsView`）上の画面収録権限案内・リクエスト・システム設定を開くボタンはそのまま維持する。
- コード内のコメントおよびドキュメントコメント（`///`）はすべて日本語で記述する。

**Scale/Scope**: `Views/SwitcherCaptureGridView.swift`、`ViewModels/SwitcherViewModel.swift` のピンポイント修正と、`Tests/WintchCoreTests/` でのテスト更新・追加。

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限およびオプトインの原則（Privacy by Design）** | リスト型・検索ランチャーでは画面収録権限を一切使わず、キャプチャ表示型のみのオプトイン設計を維持 | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | ホールド式スイッチャー上でクリック不可能なリンクと不要な ViewModel メソッドを削除し、UI とコードをさらにシンプル化 | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | UI 要素の削減のみであり描画負荷増加なし | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | Apple 標準フレームワーク（`SwiftUI` / `AppKit`）のみを使用 | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。権限未許可時は案内テキスト＋アイコンプレースホルダーで安全に切り替えを継続 | PASS |
| **6. 技術スタック・MVVM + Services** | SwiftUI ビューと `@Observable` ViewModel の責務境界を維持し、OS API 漏洩なし | PASS |
| **7. 可読性・テスト可能性・ライセンス** | ビュー構造および ViewModel のテストを維持・追加。全コメント日本語 | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/017-remove-switcher-permission-link/
├── spec.md                                             # 機能仕様書
├── plan.md                                             # 本実装計画書
├── research.md                                         # Phase 0 技術調査・設計判断レポート
├── data-model.md                                       # Phase 1 UI状態・インターフェース変更モデル
├── quickstart.md                                       # Phase 1 テスト・動作確認ガイド
├── contracts/
│   └── switcher-permission-banner-contract.md          # Phase 1 バナーUI契約
└── checklists/
    └── requirements.md                                 # 仕様品質チェックリスト
```

### Source Code (repository root)

```text
Sources/WintchCore/
├── Views/
│   └── SwitcherCaptureGridView.swift                   # [更新] permissionBannerView から設定リンクボタン削除・テキスト配置調整
└── ViewModels/
    └── SwitcherViewModel.swift                         # [更新] openScreenRecordingSettings() / onOpenScreenRecordingSettingsRequested 削除

Tests/WintchCoreTests/
├── SwitcherViewModelTests.swift                        # [更新] 削除対象メソッドのテスト箇所整理
└── SwitcherCaptureGridViewTests.swift                  # [新規] 未許可バナーにクリックリンクが存在しないこと等の UI テスト
```

**Structure Decision**: 既存の MVVM + Services 構成（`Sources/WintchCore/` および `Tests/WintchCoreTests/`）を維持し、対象 View・ViewModel および対応ユニットテストのみを変更する。

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
