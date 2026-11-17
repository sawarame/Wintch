# 検証・動作確認ガイド (Quickstart): 画面収録権限未許可時のスイッチャー内設定リンク削除

**Feature**: `017-remove-switcher-permission-link` | **Date**: 2026-11-17

## 1. ユニットテストの実行

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

### 期待結果
- `SwitcherCaptureGridViewTests`（新規または追加テスト）がパスし、以下を確認できること：
  - `isScreenRecordingGranted == false` の状態で `SwitcherCaptureGridView` をホストした際、ビュー階層に「設定を開く」ボタン（クリック可能な `NSButton` / リンク）が存在しないこと。
  - `isScreenRecordingGranted == false` 時の `fittingSize` が正のサイズで算出され、バナーテキストが圧縮されないこと。
- `SwitcherViewModelTests` がパスし、権限未許可時もプレースホルダー表示のままウィンドウ切り替え・キャンセル・ランチャー非介入が動作すること。
- `SettingsViewModelTests` を含む全ユニットテストがエラー・スキップなしでパスすること。

## 2. アプリビルドと手動動作確認（任意・実機環境向け）

```bash
./scripts/build-app.sh
open .build/Wintch.app
```

1. メニューバーの Wintch アイコンから「設定…」を開き、通常スイッチャーの表示形式を「キャプチャ表示型」に変更する（画面収録権限は未許可の状態とする）。
2. 設定画面内には「権限をリクエスト」「システム設定を開く」「再確認」の各ボタンが引き続き表示・操作可能であることを確認する。
3. `Option + Tab` を押したままにしてキャプチャ表示型スイッチャーを開く。
4. パネル上部に「画面収録権限が未許可のためプレースホルダーを表示しています」という案内のみが表示され、「設定を開く」リンクが表示されていないことを確認する。
5. `Tab` / `Shift + Tab` / 矢印キーでウィンドウを選択し、`Option` を離してウィンドウが切り替わること（または `Esc` でキャンセルできること）を確認する。
