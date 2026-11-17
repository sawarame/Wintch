# 技術調査レポート: メニューバーから開く設定画面等の最前面表示修正

**Feature**: `015-fix-settings-frontmost` | **Date**: 2026-11-17 | **Related Issue**: [#18](https://github.com/sawarame/Wintch/issues/18)

## 1. 原因調査

### 現在の実装と発生メカニズム

`WintchApp.swift` および `Resources/Info.plist` により、Wintch は `LSUIElement = true`・`NSApplication.ActivationPolicy.accessory`（Dock アイコン非表示のメニューバー常駐アプリ）として動作し、メニューバー UI には SwiftUI の `MenuBarExtra`（メニュー形式）を使用している。

`AppCoordinator.swift` の `openSettings()`（ならびに `openAbout()`・`presentPermissionGuideWindow()`）は現在、以下の 3 行でウィンドウを表示している。

```swift
NSApplication.shared.activate()
window.center()
window.makeKeyAndOrderFront(nil)
```

この実装では、他アプリケーションが前面でアクティブな状態からメニューバーアイコンをクリックして「設定を開く...」を選択した際、以下の複合要因により設定画面が他ウィンドウの背後に隠れてしまう。

1. **macOS 14 以降の協調的アクティブ化（Cooperative Activation）による拒否**
   - `NSApplication.shared.activate()` は協調的アクティブ化 API であり、他の通常アプリケーションがアクティブでかつ明示的に `yieldActivation` を行っていない場合、`.accessory` ポリシーのアプリからのアクティブ化要求が WindowServer により拒否／無視されることがある。
2. **`makeKeyAndOrderFront(nil)` の制限**
   - `makeKeyAndOrderFront(nil)` は「自アプリ内での最前面化」を行うメソッドであり、自アプリがアクティブでない状態では他アプリケーションのウィンドウより背後に配置される。対して `SwitcherPanel` 側では `orderFrontRegardless()` を併用していたが、設定画面等の標準 `NSWindow` には `orderFrontRegardless()` が呼ばれていなかった。
3. **`MenuBarExtra` メニュー閉鎖とのタイミング競合**
   - `MenuBarExtra` の `Button` アクションはメニュー追跡の終了直前に同期実行される。そのため、ボタンアクション内で同期的にアクティブ化・前面化を試みても、直後にメニュー閉鎖処理が走って直前のアクティブアプリへフォーカスが戻る（あるいはアクティブ化が相殺される）競合が起きやすい。
4. **仮想デスクトップ（操作スペース）およびマルチディスプレイ配置の考慮不足**
   - `ensureSettingsWindow()` 等で生成される `NSWindow` に `.moveToActiveSpace` が付与されておらず、開いたまま別スペースへ移動して再度開いた際に現在スペースへ移動しない。また `window.center()` は初回座標 `(0, 0)` 基準の画面へ寄るため、別ディスプレイ上でメニューバーを開いた際にカーソルのあるディスプレイ中央に出ない場合がある。

---

## 2. 設計判断と根拠

### 判断 1: アクティベーションポリシーと前面表示アプローチ

- **決定（Decision）**:
  `.accessory` アクティベーションポリシー（Dock アイコン非表示）を維持したまま、`WindowFrontPresenter` にて以下を組み合わせて実行する：
  1. `window.collectionBehavior` に `.moveToActiveSpace` を確保し、`isMiniaturized` なら `deminiaturize(nil)` を実行する。
  2. マウスカーソル位置のディスプレイ（フォールバックは `NSScreen.main` / `NSScreen.screens.first`）の `visibleFrame` 中央へ配置する（`WindowPlacement` 純粋計算ヘルパーで算出）。
  3. 同期的に `activateIgnoringOtherApps`（`NSApplication.shared.activate(ignoringOtherApps: true)`）＋ `window.orderFrontRegardless()` ＋ `window.makeKeyAndOrderFront(nil)` を実行する。
  4. `MenuBarExtra` メニュー閉鎖完了後のフォーカス戻りを確実に抑止するため、次のメインランループターン（非同期キュー投入）で `window.isVisible` が維持されている場合に限り再度アクティブ化・`orderFrontRegardless()`・`makeKeyAndOrderFront(nil)` を実行する。
  5. ウィンドウレベルは通常の `.normal` に保ち、常時最前面（`.floating` 等）には固定しない。

- **根拠（Rationale）**:
  - `AGENTS.md` に定義された「Dock アイコンを持たない常駐アプリ（`LSUIElement`）」というアプリ特性を損なわず、Dock の一時出現・点滅を防ぐことができる。
  - macOS 14〜27 SDK（`-target arm64-apple-macosx14.0`）環境において `NSApplication.shared.activate(ignoringOtherApps: true)` は警告なしでコンパイル可能であり、`orderFrontRegardless()` とメニュー閉鎖後の次ランループ再適用を組み合わせることで、アプリ非アクティブ時でも確実に WindowServer 上の最前面かつキーウィンドウ状態へ到達できる。
  - ウィンドウレベルを `.normal` に保つことで、設定画面内の「アクセシビリティ設定を開く」等からシステム設定を開いた際もシステム設定ウィンドウを覆い隠さない。

- **検討した代替案（Alternatives Considered）**:
  - **代替案 A（一時的 `.regular` 切り替え）**: 設定画面表示中のみ `NSApplication.shared.setActivationPolicy(.regular)` にして閉鎖時に `.accessory` に戻す案。Dock アイコンが表示／消滅を繰り返すため常駐ユーティリティとしての非侵襲性に反し、見送った。
  - **代替案 B（常時 `.floating` レベル化）**: 設定画面の `level` を `.floating` に固定する案。システム設定を開いた際や他アプリへ切り替えた際も設定画面が画面上に残り続けるため不適切として却下した。
  - **代替案 C（遅延なしの `NSApplication.shared.activate()` 単体）**: 現行コードがまさにこれであり、Issue #18 の不具合原因そのものであるため不可。

### 判断 2: 適用対象ウィンドウの統一

- **決定（Decision）**:
  `openSettings()`、`openAbout()`、`presentPermissionGuideWindow()` のすべてを同一の `WindowFrontPresenting` プロトコル経由で前面表示する。
- **根拠（Rationale）**:
  3 画面とも同じ `NSApplication.shared.activate()` + `window.makeKeyAndOrderFront(nil)` の重複実装を持っており、メニューバー起動（およびバックグラウンドからの誘導起動）で同一の不具合を抱えていたため、ロジック重複を排除し一貫した表示保証を行う。

### 判断 3: テスト可能性の確保（MVVM + Services 分離）

- **決定（Decision）**:
  - `Services/Protocols/WindowFrontPresenting.swift` と `Services/WindowFrontPresenter.swift` に AppKit のアクティブ化・ウィンドウ最前面操作を隔離し、`AppCoordinator` へ DI（デフォルト引数付き）で注入可能にする。
  - ウィンドウの中央配置座標計算は純粋関数 `Domain/WindowPlacement.swift` へ切り出し、マルチディスプレイやゼロサイズ境界の単体テストを OS 非依存で高速実行できるようにする。
  - `WindowFrontPresenter` 自体は、アプリアクティブ化や非同期ディスパッチを内部コールバックで差し替え可能にしつつ実 `NSWindow` を使った決定論的単体テストも書ける構造にする。

---

## 3. 憲章（Constitution）への適合確認

- 画面収録権限：一切使用しない（第 1 原則準拠）。
- 外部依存：追加なし（Apple 標準 `AppKit` / `Foundation` のみ、第 4 原則準拠）。
- 非公開 API：`CGS*` 等を一切使用しない（第 5 原則準拠）。
- 過度な抽象化の回避：1 プロトコル + 1 具象クラス + 1 純粋配置計算ヘルパーという最小構成（第 2・6 原則準拠）。
