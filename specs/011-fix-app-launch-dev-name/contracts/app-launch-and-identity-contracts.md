# インターフェース契約 (Contracts): ランチャーアプリ起動安定化と開発版識別名

**Feature**: `011-fix-app-launch-dev-name` | **Date**: 2026-11-16

## 1. `InstalledAppService` 契約

### `launchApplication(_ app: LaunchableApp)`

- **事前条件**: `app.bundleURL` が有効な `.app` バンドル URL を保持していること。
- **事後条件**:
  - `NSWorkspace.OpenConfiguration` の `activates` を `true` に設定して起動要求を発行する。
  - 完了コールバックとして `@MainActor` 分離されたクロージャを LaunchServices へ渡さない（`completionHandler: nil` を指定する）。
  - LaunchServices のバックグラウンドディスパッチキュー上で処理が完了しても、`EXC_BREAKPOINT` / `SIGTRAP` を発生させず、Wintch プロセスの常駐とホットキー監視を継続する。
- **互換性**: `InstalledAppServicing` プロトコル（`func launchApplication(_ app: LaunchableApp)`）の公開シグネチャは変更しない。テスト用に任意注入のオープンハンドラを引数に追加する場合は既定値 `nil` を与え、既存呼び出し側のソース互換性を 100% 維持する。

---

## 2. `AppIdentity` 契約

### `AppIdentity`（`Sources/WintchCore/Domain/AppIdentity.swift`）

- **不変性・並行性**: `Equatable` かつ `Sendable` な不変構造体とする。
- **既定コンストラクタ互換**:
  - `AppIdentity.current` は `Bundle.main.infoDictionary` を基に現在の実行形態を返す。
  - `AboutView.init(...)`、`PermissionGuideView.init(...)`、`AppCoordinator.init(...)` は既存引数に対する既定値として `.current` を設定し、既存テスト・呼び出しコードの破壊的変更を行わない。

---

## 3. UI 表示契約

| 表示箇所 | ファイル | 表示契約 |
|---|---|---|
| メニューバー「〜について」項目 | `Sources/Wintch/WintchApp.swift` | `appIdentity.aboutMenuTitle`（`Wintch_devについて` / `Wintchについて`） |
| メニューバー「〜を終了」項目 | `Sources/Wintch/WintchApp.swift` | `appIdentity.quitMenuTitle`（`Wintch_dev を終了` / `Wintch を終了`） |
| 設定ウィンドウタイトル | `Sources/WintchCore/App/AppCoordinator.swift` | `appIdentity.settingsWindowTitle`（`Wintch_dev 設定` / `Wintch 設定`） |
| 「〜について」ウィンドウタイトル | `Sources/WintchCore/App/AppCoordinator.swift` | `appIdentity.aboutMenuTitle`（`Wintch_devについて` / `Wintchについて`） |
| 権限確認ウィンドウタイトル | `Sources/WintchCore/App/AppCoordinator.swift` | `appIdentity.permissionGuideWindowTitle`（`Wintch_dev - 権限の確認` / `Wintch - 権限の確認`） |
| 「〜について」見出し | `Sources/WintchCore/Views/AboutView.swift` | `appIdentity.displayName`（`Wintch_dev` / `Wintch`） |
| 権限手順ステップ 2 文言 | `Sources/WintchCore/Views/PermissionGuideView.swift` | `appIdentity.accessibilitySwitchInstruction`（`2. 一覧の「Wintch_dev」のスイッチをオンにします` / `2. 一覧の「Wintch」のスイッチをオンにします`） |

---

## 4. `scripts/build-app.sh` CLI・成果物契約

| コマンド | 出力バンドルパス | `CFBundleDisplayName` / `CFBundleName` | `CFBundleExecutable` | `CFBundleIdentifier` |
|---|---|---|---|---|
| `./scripts/build-app.sh`（または `debug`） | `.build/Wintch_dev.app` | `Wintch_dev` | `Wintch_dev` | `dev.wintch.Wintch.dev` |
| `./scripts/build-app.sh release` | `.build/Wintch.app` | `Wintch` | `Wintch` | `dev.wintch.Wintch` |
| `./scripts/build-app.sh release --universal` | `.build/Wintch.app` | `Wintch` | `Wintch` | `dev.wintch.Wintch` |

- リポジトリ内の正本ファイル `Resources/Info.plist` はリリース用の値（`Wintch` / `dev.wintch.Wintch`）のまま変更せず、ビルド成果物内の `Contents/Info.plist` のみを更新する。
- `.github/workflows/release.yml` が参照する `./scripts/build-app.sh release --universal` および `./.build/Wintch.app` のパス・メタデータ（`CFBundleShortVersionString` 等）を完全に維持する。
