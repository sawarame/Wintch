# UI 契約: スイッチャー内画面収録権限案内バナー (`SwitcherCaptureGridView`)

**Feature**: `017-remove-switcher-permission-link` | **Date**: 2026-11-17

## 1. 表示条件

- **表示対象**: `SwitcherViewModel.mode == .normal && SwitcherViewModel.normalDisplayStyle == .capture && !SwitcherViewModel.isScreenRecordingGranted`
- **非表示対象**:
  - `normalDisplayStyle == .list`（画面収録権限自体を参照しない）
  - `mode == .launcher`（検索ランチャーでは画面収録権限を参照しない）
  - `isScreenRecordingGranted == true`（権限許可済み）

## 2. バナー内容の契約

1. **非インタラクティブ性（クリックリンク禁止）**:
   - バナー内に `Button` やリンク（`.buttonStyle(.link)`）、クリックによりシステム設定や設定ウィンドウを開くアクションを一切含めない。
   - ユーザーは修飾キーを離さずにパネル上の案内を視認でき、誤操作や操作不能 UI との遭遇を防止する。
2. **案内メッセージ**:
   - 警告アイコン（`exclamationmark.triangle.fill`）と定数メッセージ `SwitcherCaptureGridView.permissionBannerMessage`（`"画面収録権限が未許可のためプレースホルダーを表示しています"`）を表示する。
   - テキストは途中で `...` 省略されないよう垂直方向に圧縮せず左寄せで表示する。
3. **カード操作との独立性**:
   - バナー表示中もグリッド内のウィンドウカードは通常通りキーボード（トリガーキー・矢印キー・`Esc`・終了ショートカット）およびカードクリックで選択・切り替えできる。

## 3. ViewModel 契約

- `SwitcherViewModel` はスイッチャーパネル経由でシステム設定を開く API（`openScreenRecordingSettings()`, `onOpenScreenRecordingSettingsRequested`）を公開しない。
- システム設定への遷移導線は `SettingsView` / `SettingsViewModel` が引き続き単独で担う。
