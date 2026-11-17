# UI・ウィンドウ契約 (Contracts): アクセシビリティ権限誘導ダイアログ

**Feature**: `016-fix-permission-guide-text` | **Date**: 2026-11-17

## 1. `PermissionGuideView` 表示契約

- **入力**:
  - `viewModel: PermissionGuideViewModel`
  - `appIdentity: AppIdentity`（既定値 `.current`）
- **保証事項**:
  1. ダイアログ基準幅は `PermissionGuideView.preferredWidth`（`460pt`）を維持する。
  2. 見出し（「アクセシビリティ権限の許可が必要です」）、サブタイトル（「ショートカット検知とウィンドウ切り替えの操作にのみ使用します」）、ステップ 1〜3 の `Label`、および補足説明（「※ リスト型および検索ランチャーでは「画面収録」権限を使用しません（キャプチャ表示型を選択した場合のみ任意で使用します）。」）はすべて `.fixedSize(horizontal: false, vertical: true)` を持ち、垂直圧縮による途中省略（`...`）を発生させない。
  3. 画面収録権限の要求・確認・誘導処理は一切実行しない（Wintch 憲章 v2.0.0 第 1 原則遵守）。

## 2. `AppCoordinator.ensurePermissionWindow()` ウィンドウ生成契約

- **トリガー**: `openPermissionGuide()` または `updatePermissionState(.denied)` による `presentPermissionGuideWindow()` 呼び出し。
- **保証事項**:
  1. 生成された `NSWindow` のコンテンツサイズ（`window.contentView?.frame.size` / `window.contentLayoutRect.size`）は、`NSHostingView.fittingSize` 以上かつ幅 `PermissionGuideView.preferredWidth` 以上・高さ `PermissionGuideView.minimumHeight` 以上である。
  2. 同一の `permissionWindow` インスタンスは再利用され、`isReleasedWhenClosed == false` が維持される。
  3. 引き続き `windowFrontPresenter.presentFrontmost(window)` を通じて最前面・アクティブディスプレイ中央へ表示される。
