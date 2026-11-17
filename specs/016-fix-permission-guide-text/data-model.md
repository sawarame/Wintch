# データ・レイアウトモデル設計 (Data Model): アクセシビリティ権限誘導ダイアログの説明文全文表示修正

**Feature**: `016-fix-permission-guide-text` | **Date**: 2026-11-17

## 1. ビュー寸法・レイアウト制約モデル（`PermissionGuideView`）

本修正では新規の永続化データモデルは追加せず、`PermissionGuideView` が自身の基準サイズ制約を公開定数として保持し、`AppCoordinator` が `NSHostingView.fittingSize` と組み合わせてウィンドウサイズを決定する。

| 項目 | 型 / 値 | 役割 | 制約 / ルール |
|---|---|---|---|
| `PermissionGuideView.preferredWidth` | `CGFloat = 460` | 権限誘導ダイアログの基準横幅 | `.frame(width: Self.preferredWidth)` により横幅を固定しつつ、縦方向は内容に応じて伸縮させる |
| `PermissionGuideView.minimumHeight` | `CGFloat = 280` | 権限誘導ウィンドウの最小高さ下限 | 実際のウィンドウコンテンツ高さは `max(fittingSize.height, minimumHeight)` とし、`fittingSize.height` を下回らない |
| `PermissionGuideView` 内テキスト群 | `Text` / `Label` | 見出し・説明・手順 1〜3・補足説明 | `.fixedSize(horizontal: false, vertical: true)` を適用し、横幅内で折り返し・縦方向の圧縮省略（`...`）を禁止する |

## 2. ウィンドウ生成時のサイズ算出フロー

1. `PermissionGuideView(viewModel: permissionGuideViewModel, appIdentity: appIdentity)` を `NSHostingView` に格納する。
2. `hostingView.layoutSubtreeIfNeeded()` 実行後、`hostingView.fittingSize` を取得する。
3. `contentSize = NSSize(width: max(fittingSize.width, PermissionGuideView.preferredWidth), height: max(fittingSize.height, PermissionGuideView.minimumHeight))` を算出する。
4. `NSWindow(contentRect: NSRect(origin: .zero, size: contentSize), styleMask: [.titled, .closable], ...)` を生成し、`window.contentView = hostingView` 設定後に `window.setContentSize(contentSize)` でコンテンツ領域を確定する。
5. `WindowFrontPresenter.presentFrontmost(window)` が確定済み `window.frame.size` を用いてアクティブディスプレイ中央へ配置・最前面表示する。
