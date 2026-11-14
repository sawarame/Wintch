# UI画面・振る舞い契約 (UI Contracts): 「Wintchについて」メニューおよびウィンドウ

**Feature**: `003-semver-release-about`  
**Date**: 2026-11-14  
**Purpose**: メニューバー項目「Wintchについて」、`AppCoordinator` のウィンドウ管理、および `AboutView` の表示仕様を定義する。

---

## 1. メニューバー常駐メニュー (`WintchApp`)

`MenuBarExtra` 内のメニュー構成を以下の通り拡張する:

1. （アクセシビリティ権限未許可時のみ）`アクセシビリティ権限が必要です...` + `Divider`
2. `Wintchについて` → `appDelegate.coordinator.openAbout()` を呼び出す
3. `設定を開く...` (ショートカット `⌘,`)
4. `Divider`
5. `Wintch を終了` (ショートカット `⌘Q`)

---

## 2. ウィンドウ制御契約 (`AppCoordinator.openAbout()`)

既存の `openSettings()` / `openPermissionGuide()` と同一のウィンドウライフサイクル契約に従う:
- `aboutWindow: NSWindow?` を遅延生成し、`isReleasedWhenClosed = false` を設定することで、閉じた後もインスタンスを再利用し重複ウィンドウを生成しない。
- `NSApplication.shared.activate()` を呼び出し、`window.center()` かつ `window.makeKeyAndOrderFront(nil)` で画面中央・最前面に表示する（`LSUIElement = YES` 環境でも確実に前面表示される）。
- ウィンドウタイトルは `"Wintchについて"` とし、スタイルマスクは `[.titled, .closable]` とする。
- ウィンドウを閉じてもアプリケーション本体（メニューバー常駐・ホットキー監視）は終了しない。

---

## 3. 「Wintchについて」画面契約 (`AboutView`)

### 3.1 表示要素
1. **アプリアイコン**:
   - `NSApplication.shared.applicationIconImage`（`Wintch.app` 実行時は `AppIcon.icns` が自動適用される）を 80x80pt 程度で表示する。
   - アイコン画像が取得できない、またはバンドル外実行時は安全なフォールバック表示を行う。
2. **アプリ名**:
   - `"Wintch"`（太字・タイトルサイズ）
3. **バージョン情報 (`AppVersionInfo.current`)**:
   - `"バージョン \(versionInfo.shortVersion) (\(versionInfo.buildNumber))"` を明瞭に表示する（テキスト選択可能 `.textSelection(.enabled)` にしてサポート時のコピーを容易にする）。
4. **アプリ説明・著作権表記**:
   - 簡潔なアプリ説明（例: `"macOS 向けウィンドウ単位スイッチャー"`）および `versionInfo.copyright`（例: `"Copyright © 2026 Wintch Contributors. MIT License."`）を表示する。

### 3.2 サイズとレスポンシブ性
- コンパクトで余白の整った固定サイズ（例: 幅 320pt × 高さ 240pt 前後）とし、過剰な設定ボタンやリンク類を置かず、憲章原則 2（シンプルさの徹底）に沿った構成とする。
- `@Observable` 以外のレガシー状態管理は使用せず、低レイヤー OS API にも直接依存しない。
