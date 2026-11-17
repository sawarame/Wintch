# データ・状態モデル設計: メニューバーから開く設定画面等の最前面表示修正

**Feature**: `015-fix-settings-frontmost` | **Date**: 2026-11-17

本機能は永続化データや新設定項目を追加せず、ウィンドウ配置計算用の値型と前面表示ライフサイクルを扱う。

## 1. 値型: `WindowPlacement`（`Domain/WindowPlacement.swift`）

ウィンドウを指定されたディスプレイ領域中央へ配置するための純粋計算ロジックを提供する。

### 入力・パラメータ

- `windowSize: CGSize` — 配置対象ウィンドウのサイズ（幅・高さ）
- `cursorLocation: CGPoint` — 現在のマウスカーソル座標（グローバル座標系）
- `screens: [ScreenFrameSnapshot]`（または `bounds` / `visibleFrame` ペアの軽量構造体）— 利用可能なディスプレイ一覧
  - `frame: CGRect`: ディスプレイ全体矩形（カーソル所在判定に使用）
  - `visibleFrame: CGRect`: メニューバー・Dock を除いた有効表示領域（中央配置の基準矩形に使用）

### 出力・不変条件

- `centeredOrigin(windowSize:in:) -> CGPoint`:
  - `origin.x = visibleFrame.midX - (windowSize.width / 2.0)`
  - `origin.y = visibleFrame.midY - (windowSize.height / 2.0)`
  - ただし最小座標を `visibleFrame.minX` / `visibleFrame.minY` 付近に収めるため、ウィンドウが `visibleFrame` より大きい場合は `visibleFrame.minX` / `visibleFrame.minY` を下限としてクランプし、タイトルバーが画面外へはみ出さないようにする（上端は `visibleFrame.maxY - windowSize.height` へ収める）。
- `targetScreen(cursorLocation:screens:fallbackVisibleFrame:) -> CGRect?`:
  - `screens` から `frame.contains(cursorLocation)` を満たす最初のディスプレイの `visibleFrame` を優先選択する。
  - 一致しない場合は `fallbackVisibleFrame`（実機では `NSScreen.main?.visibleFrame`）、それも `nil` なら `screens.first?.visibleFrame` を返す。

---

## 2. ウィンドウ前面表示ライフサイクル状態遷移

```text
[非表示 / 背後 / 別スペース / 最小化]
   │
   ▼  メニューバー項目選択 / 権限未許可検知 (AppCoordinator)
[1. 事前整備]
   - collectionBehavior に .moveToActiveSpace を付与
   - isMiniaturized == true の場合は deminiaturize(nil)
   - WindowPlacement によりアクティブディスプレイ中央へ配置
   - level == .normal を維持
   │
   ▼
[2. 即時最前面化]
   - activateApplication()（ignoringOtherApps 強制アクティブ化）
   - window.orderFrontRegardless()
   - window.makeKeyAndOrderFront(nil)
   │
   ▼  MenuBarExtra メニュー追跡終了後の次ランループターン
[3. 遅延競合ガード再前面化]
   - window.isVisible == true を確認（ユーザーが既に閉じた場合は何もしない）
   - activateApplication()
   - window.orderFrontRegardless()
   - window.makeKeyAndOrderFront(nil)
   │
   ▼
[最前面・キーウィンドウとして表示完了]
   - 以降、他アプリやシステム設定のクリックで自然に背面へ移動可能
```
