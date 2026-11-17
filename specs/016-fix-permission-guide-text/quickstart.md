# 検証ガイド (Quickstart): アクセシビリティ権限誘導ダイアログの説明文全文表示修正

**Feature**: `016-fix-permission-guide-text` | **Date**: 2026-11-17

## 1. 自動テストによる検証

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

### 期待結果
- 既存の全ユニットテストおよび新規追加のレイアウト・サイズ検証テストがエラー 0 件で通過すること。
- `PermissionGuideView` の `NSHostingView.fittingSize` が幅 `460pt`・必要高さ（`280pt` 超）を返し、`AppCoordinator.openPermissionGuide()` が生成するウィンドウのコンテンツ高さが `fittingSize.height` 以上であることを確認できること。

## 2. `.app` バンドルビルド確認

```bash
./scripts/build-app.sh
```

### 期待結果
- Debug ビルド（`.build/Wintch.app`）がコンパイルエラーおよび警告なしで完了すること。

## 3. 手動確認シナリオ（任意・実機 UI 目視）

1. アクセシビリティ権限が未許可の状態（または権限リセット後）で `.build/Wintch.app` を起動する。
2. 自動表示される権限誘導ダイアログ（またはメニューバーの「アクセシビリティ権限が必要です...」から開くダイアログ）を確認する。
3. **確認項目**:
   - 下部注記「※ リスト型および検索ランチャーでは「画面収録」権限を使用しません（キャプチャ表示型を選択した場合のみ任意で使用します）。」が省略記号（`...`）なしで全文表示されていること。
   - 手順 1〜3、見出し、「再確認」「システム設定を開く」ボタンがいずれも見切れ・重なりなく収まっていること。
