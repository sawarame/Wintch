# インターフェース契約: ウィンドウ前面表示サービスとコーディネーター

**Feature**: `015-fix-settings-frontmost` | **Date**: 2026-11-17

## 1. `WindowFrontPresenting` プロトコル（`Services/Protocols/WindowFrontPresenting.swift`）

```swift
@MainActor
public protocol WindowFrontPresenting: AnyObject {
    /// 指定ウィンドウを現在スペース上のアクティブディスプレイ中央へ移動し、最前面・キーウィンドウとして表示する
    /// - Parameter window: 表示対象の NSWindow
    func presentFrontmost(_ window: NSWindow)
}
```

### 契約事項

1. **実行スレッド**: 必ず `@MainActor` 上で呼び出される。
2. **スペースおよび最小化対応**:
   - `window.collectionBehavior` に `.moveToActiveSpace` を含める（既存の他のフラグを破壊しないよう `insert(.moveToActiveSpace)` を使用）。
   - `window.isMiniaturized` が `true` の場合は `window.deminiaturize(nil)` で復帰させる。
   - `window.level` は通常ウィンドウレベル（`.normal`）のまま維持する（他アプリやシステム設定の邪魔をしない）。
3. **配置**:
   - マウスカーソルがあるディスプレイ（見つからない場合は `NSScreen.main`、さらにフォールバックとして `NSScreen.screens.first`）の `visibleFrame` 中央へウィンドウを配置する。取得不能時は `window.center()` にフォールバックする。
4. **即時表示とメニュー閉鎖後フォローアップ**:
   - 即時にアプリを強制アクティブ化し、`window.orderFrontRegardless()` と `window.makeKeyAndOrderFront(nil)` を実行する。
   - さらに次ランループターンへフォローアップ処理をスケジュールし、実行時点で `window.isVisible` が `true` の場合のみ再度アクティブ化・`orderFrontRegardless()`・`makeKeyAndOrderFront(nil)` を実行する。

## 2. `AppCoordinator` の利用契約（`App/AppCoordinator.swift`）

- `openSettings()`:
  1. `settingsViewModel.refreshStatus()` を呼ぶ。
  2. `ensureSettingsWindow()` でウィンドウを取得（初回のみ生成・`isReleasedWhenClosed = false`）。
  3. `windowFrontPresenter.presentFrontmost(window)` を呼ぶ。
- `openAbout()`:
  1. `ensureAboutWindow()` でウィンドウを取得。
  2. `windowFrontPresenter.presentFrontmost(window)` を呼ぶ。
- `openPermissionGuide()` / `presentPermissionGuideWindow()`:
  1. `permissionGuideViewModel.refreshStatus()` 後、`permissionStatus == .denied` の場合のみ `ensurePermissionWindow()` でウィンドウを取得。
  2. `windowFrontPresenter.presentFrontmost(window)` を呼ぶ。
