# データモデル (Data Model): ランチャーアプリ起動安定化と開発版識別情報

**Feature**: `011-fix-app-launch-dev-name` | **Date**: 2026-11-16

## 1. `AppIdentity`（新規ドメインモデル：`Sources/WintchCore/Domain/AppIdentity.swift`）

実行中アプリケーションのバンドルメタデータおよびビルド構成から、アプリ表示名・バンドル識別子・UI 文言を一貫して導出する純粋値型モデル。

### 属性（Fields）

| フィールド名 | 型 | 説明 |
|---|---|---|
| `displayName` | `String` | UI および OS 連携文言に用いるアプリ表示名（開発版: `"Wintch_dev"`、配布版: `"Wintch"`） |
| `bundleIdentifier` | `String` | 実行中アプリのバンドル識別子（開発版: `"dev.wintch.Wintch.dev"`、配布版: `"dev.wintch.Wintch"`） |
| `isDevelopment` | `Bool` | 開発用ビルドとして動作しているかどうか |

### 導出プロパティ（Derived Properties）

| プロパティ名 | 導出ルール | 開発版出力例 | 配布版出力例 |
|---|---|---|---|
| `aboutMenuTitle` | `"\(displayName)について"` | `"Wintch_devについて"` | `"Wintchについて"` |
| `quitMenuTitle` | `"\(displayName) を終了"` | `"Wintch_dev を終了"` | `"Wintch を終了"` |
| `settingsWindowTitle` | `"\(displayName) 設定"` | `"Wintch_dev 設定"` | `"Wintch 設定"` |
| `permissionGuideWindowTitle` | `"\(displayName) - 権限の確認"` | `"Wintch_dev - 権限の確認"` | `"Wintch - 権限の確認"` |
| `accessibilitySwitchInstruction` | `"2. 一覧の「\(displayName)」のスイッチをオンにします"` | `"2. 一覧の「Wintch_dev」のスイッチをオンにします"` | `"2. 一覧の「Wintch」のスイッチをオンにします"` |

### 解決・正規化ルール（Validation & Resolution Rules）

1. **表示名の解決優先順位**:
   1. `infoDictionary["CFBundleDisplayName"]`（トリミング後に非空の文字列）
   2. `infoDictionary["CFBundleName"]`（トリミング後に非空の文字列）
   3. `fallbackDisplayName`（既定値は `#if DEBUG` 時 `"Wintch_dev"`、それ以外 `"Wintch"`）
2. **バンドル識別子の解決優先順位**:
   1. `infoDictionary["CFBundleIdentifier"]`（トリミング後に非空の文字列）
   2. `fallbackBundleIdentifier`（既定値は `#if DEBUG` 時 `"dev.wintch.Wintch.dev"`、それ以外 `"dev.wintch.Wintch"`）
3. **開発版判定**:
   - `displayName == "Wintch_dev"` または `bundleIdentifier == "dev.wintch.Wintch.dev"` または `bundleIdentifier.hasSuffix(".dev")` の場合に `true`。

---

## 2. バンドルビルドバリアント（`scripts/build-app.sh`）

`.app` バンドル組み立て時にビルド構成から決定されるバンドル構成の定義。

| 構成 (`CONFIGURATION`) | バンドル名 / 出力先 | `CFBundleDisplayName` / `CFBundleName` | `CFBundleExecutable` | `CFBundleIdentifier` |
|---|---|---|---|---|
| `debug`（既定・ローカル開発用） | `Wintch_dev` (`.build/Wintch_dev.app`) | `Wintch_dev` | `Wintch_dev` | `dev.wintch.Wintch.dev` |
| `release`（配布用 / CI） | `Wintch` (`.build/Wintch.app`) | `Wintch` | `Wintch` | `dev.wintch.Wintch` |

### 整合性・共存境界（Isolation Guarantees）

- **OS 権限（TCC）境界**: `CFBundleIdentifier` が `dev.wintch.Wintch.dev` と `dev.wintch.Wintch` に分離されるため、アクセシビリティ権限および画面収録権限の許可登録が配布版と干渉しない。
- **設定永続化境界**: `PreferencesStore` は `UserDefaults.standard`（バンドル識別子スコープ）を使用するため、設定保存先ドメインも開発版と配布版で自動分離される。
- **ランチャー自己除外境界**: `InstalledAppService` は `Bundle.main.bundleIdentifier` を `excludedBundleIdentifier` として使用するため、開発版起動中は開発版自身のみが起動候補から除外される。
- **ウィンドウ監視自己除外境界**: `WindowService` は `ProcessInfo.processInfo.processIdentifier` および `activationPolicy == .regular` で判定するため、両方がメニューバー常駐していても互いにウィンドウ候補へ混入しない。

---

## 3. アプリ起動要求の実行モデル（`InstalledAppService.launchApplication(_:)`）

| 項目 | 変更前 | 変更後 |
|---|---|---|
| 呼び出し方式 | `NSWorkspace.shared.openApplication(at:configuration:) { _, _ in }` | `NSWorkspace.shared.openApplication(at:configuration:completionHandler: nil)` |
| 完了クロージャのアクター分離 | `@MainActor` クラス内で非 `@Sendable` クロージャ生成（macOS 15.5 SDK で MainActor チェック挿入） | クロージャ生成なし（`nil` 指定） |
| `com.apple.launchservices.open-queue` 上での動作 | MainActor 検証失敗により `SIGTRAP` クラッシュ | 検証コード自体が存在せず安全に完了 |
