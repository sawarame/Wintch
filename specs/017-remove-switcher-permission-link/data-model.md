# データ・UI状態モデル (Data Model): 画面収録権限未許可時のスイッチャー内設定リンク削除

**Feature**: `017-remove-switcher-permission-link` | **Date**: 2026-11-17

## 1. 状態・インタラクションの変化

本変更では永続化データやドメインモデル（`WindowEntry`, `SwitcherDisplayStyle`, `ScreenRecordingPermissionStatus`）の構造変更はない。`SwitcherViewModel` のインタラクション表面と `SwitcherCaptureGridView` の UI 構成のみを更新する。

### SwitcherViewModel 公開インターフェースの変更

| メンバー | 変更前 | 変更後 | 備考 |
|---|---|---|---|
| `isScreenRecordingGranted: Bool` | 維持 | 維持 | `false` のときバナー（テキストのみ）を表示しプレースホルダー描画 |
| `onOpenScreenRecordingSettingsRequested: (() -> Void)?` | 存在 | **削除** | スイッチャーパネルからの設定遷移廃止に伴い削除 |
| `openScreenRecordingSettings()` | 存在 | **削除** | スイッチャーパネルからの設定遷移廃止に伴い削除 |

### SwitcherCaptureGridView 権限バナー構成の変更

| 構成要素 | 変更前 | 変更後 | 備考 |
|---|---|---|---|
| 警告アイコン | `exclamationmark.triangle.fill`（orange, 12pt） | 維持 | 変更なし |
| 案内テキスト | `"画面収録権限が未許可のためプレースホルダーを表示しています"`（1行制限・末尾省略あり） | 同文言維持（`.fixedSize(horizontal: false, vertical: true)`・左寄せ） | 見切れ・途中省略を防止 |
| スペーサー | `Spacer(minLength: 4)` | **削除**（`frame(maxWidth: .infinity, alignment: .leading)` へ統合） | 右端リンク削除に伴う整理 |
| 設定リンクボタン | `Button("設定を開く")`（`.buttonStyle(.link)`） | **削除** | Issue #23 の直接要件 |
| パネル最小幅（未許可時） | `minWidthWithBanner = 360` | `360` 維持 | バナー 1〜2 行収容とカード 1 枚時の視認性バランスを維持 |
