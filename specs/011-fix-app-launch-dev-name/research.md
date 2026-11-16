# 調査・設計判断レポート (Research): ランチャーからのアプリ起動安定化およびローカル開発版の識別名分離

**Feature**: `011-fix-app-launch-dev-name` | **Date**: 2026-11-16

## 1. ランチャーからのアプリ起動直後のクラッシュ原因調査

### 観測された現象と実機クラッシュログ
- Homebrew 配布版（`/Applications/Wintch.app`、v0.2.2 build 49、`.github/workflows/release.yml` の `macos-15` ランナー上で Xcode 16 系 / macOS 15.5 SDK によりビルド）にて、検索ランチャーから未起動アプリを起動した直後に Wintch が終了する事象が発生。
- `~/Library/Logs/DiagnosticReports/Wintch-2026-11-16-185348.ips` を確認したところ、`faultingThread`（キュー: `com.apple.launchservices.open-queue`）にて `EXC_BREAKPOINT`（`SIGTRAP`）が発生していた。
- スタックトレースの抜粋：
  - `_dispatch_assert_queue_fail`
  - `_swift_task_checkIsolatedSwift`
  - `swift_task_isCurrentExecutorWithFlagsImpl`
  - `closure #1 in InstalledAppService.launchApplication(_:)`
  - `_NSWorkspaceHandleLSOpenResult` / `_LSFireCompletionHandler`

### バイナリ逆アセンブル比較（配布版 vs ローカルビルド版）
- **配布版（`Runtime Version=15.5.0`）**:
  `InstalledAppService.swift` 95 行目の空クロージャ `{ _, _ in }` が `closure #1 (__C.NSRunningApplication?, Swift.Error?) -> ()`（非 `@Sendable` の `@MainActor` 分離クロージャ）として生成され、冒頭に `_swift_task_isCurrentExecutor` および失敗時の `_swift_task_reportUnexpectedExecutor` 呼び出しが埋め込まれていた。
- **ローカルビルド版（Swift 6.4.2 / macOS 27.2 SDK）**:
  同一ソースコードから `closure #1 @Sendable (__C.NSRunningApplication?, Swift.Error?) -> ()` として生成され、MainActor チェックを持たないためクラッシュが顕在化していなかった。

### 設計判断 1: `InstalledAppService.launchApplication(_:)` の安全な実装
- **Decision**: `NSWorkspace.shared.openApplication(at:configuration:completionHandler:)` の呼び出しにおいて、不要な空クロージャ `{ _, _ in }` を削除し `completionHandler: nil` を指定する。さらに、将来完了ハンドラを利用する場合でもアクター分離違反が再発しないよう、非同期完了コールバックを伴う呼び出しを隔離する設計とし、非メインキュー実行に対する単体テストで検証可能にする。
- **Rationale**:
  - `NSWorkspace.h` の宣言上、`completionHandler` は `_Nullable` であり、`nil` を渡すことでそもそも LaunchServices からバックグラウンドキュー経由の Swift クロージャ呼び出しが発生しなくなる。
  - Swift / SDK のバージョンに依存せず、`macos-15` SDK 環境を含む全ビルド環境で 100% クラッシュを防げる。
- **Alternatives considered**:
  - `{ @Sendable _, _ in }` のように `@Sendable` を明示する方法：動作はするが、そもそも何も処理しない空クロージャを生成・保持する意味がなく、`completionHandler: nil` の方がシンプルで誤用余地もない。
  - `try await NSWorkspace.shared.openApplication(at:configuration:)` へ書き換えて `Task` で包む方法：`InstalledAppServicing.launchApplication(_:)` の同期メソッド契約を維持しつつ即座に起動指示を出す用途には不要な Task オーバーヘッドが増えるため不採用。

### 設計判断 2: 他サービスのコールバック安全性確認
- `Sources/WintchCore/Services/` 内の全システムコールバックを監査した結果：
  - `WindowService.swift` / `IconProviderService.swift` の `NSWorkspace.shared.notificationCenter.addObserver` はすべて `queue: .main` 指定済み。
  - `WindowService.swift` の `AXObserverCreate` および `HotKeyMonitorService.swift` の `CGEvent.tapCreate` は C 関数ポインタ型コールバック（キャプチャなし）＋ `nonisolated` 経由で `Task { @MainActor in }` / `DispatchQueue.main.async` へ明示転送している。
  - `WindowCaptureService.swift` の `SCShareableContent.getExcludingDesktopWindows` は `private nonisolated static func` 内で呼び出している。
  - 以上より、同様の潜在リスクがあるのは `InstalledAppService.launchApplication(_:)` のみであることを確認した。

---

## 2. ローカル開発用ビルドの識別名（`Wintch_dev`）および識別子分離の設計

### 現状の課題
- `scripts/build-app.sh` は `debug` / `release` いずれの構成でも `APP_NAME="Wintch"`、出力先 `.build/Wintch.app`、`Resources/Info.plist` そのままの `CFBundleIdentifier = dev.wintch.Wintch` / `CFBundleDisplayName = Wintch` でバンドルを生成している。
- そのため、ローカルで `./scripts/build-app.sh` によりビルド・起動した際、Homebrew でインストールした `/Applications/Wintch.app` と名前・Bundle ID・実行プロセス名・UserDefaults ドメインが完全に重複し、以下の問題が起きる：
  1. メニューバー項目・「Wintchについて」・設定画面タイトル・アクティビティモニタ・システム設定のアクセシビリティ一覧上で両者の区別がつかない。
  2. Bundle ID が同一（`dev.wintch.Wintch`）かつ署名が異なる（アドホック署名 vs Developer ID 署名）ため、macOS の TCC（アクセシビリティ権限）が競合し、切り替えのたびに権限登録の削除・再追加が必要になりやすい。

### 設計判断 3: ビルドスクリプトによる開発／リリース切り替え方式
- **Decision**: `scripts/build-app.sh` において、ビルド構成に応じてバンドル構成を自動切り替えし、コピー後のバンドル内 `Contents/Info.plist` を `PlistBuddy` で上書きする（リポジトリの `Resources/Info.plist` はリリース用の正本として無変更に保つ）。
  - `debug` 構成（ローカル開発時のデフォルト `./scripts/build-app.sh`）:
    - バンドル名・実行ファイル名・表示名: `Wintch_dev`（出力先 `.build/Wintch_dev.app`）
    - バンドル識別子 (`CFBundleIdentifier`): `dev.wintch.Wintch.dev`
  - `release` 構成（`./scripts/build-app.sh release` / CI `.github/workflows/release.yml`）:
    - バンドル名・実行ファイル名・表示名: `Wintch`（出力先 `.build/Wintch.app`）
    - バンドル識別子 (`CFBundleIdentifier`): `dev.wintch.Wintch`
- **Rationale**:
  - `.github/workflows/release.yml` は `./scripts/build-app.sh release --universal` と `./.build/Wintch.app` を直接参照しているため、リリース構成を従来通り維持することで配布自動化フローへの破壊的変更をゼロにできる。
  - `CFBundleExecutable` および `Contents/MacOS/` 配下のバイナリファイル名も `Wintch_dev` に揃えることで、macOS のアクティビティモニタや `ps`、クラッシュログ上のプロセス名も `Wintch_dev` として明瞭に区別できる。
  - `CFBundleIdentifier` を `dev.wintch.Wintch.dev` に分離することで、macOS の TCC 権限（アクセシビリティ／画面収録）と `UserDefaults.standard` の保存先（`dev.wintch.Wintch.dev.plist`）が配布版と完全に分離される。
  - `InstalledAppService` は `Bundle.main.bundleIdentifier` を自己除外 ID として使用しているため、`Wintch_dev` 起動時は開発版自身のみが検索候補から除外され、破綻しない。
- **Alternatives considered**:
  - 表示名（`CFBundleDisplayName` / `CFBundleName`）のみ `Wintch_dev` にし、`CFBundleIdentifier` は `dev.wintch.Wintch` のままにする案：
    一覧上の見た目だけでは権限（TCC）の `cdhash` 衝突や設定の混線を防げないため不採用。
  - `Package.swift` に別ターゲット `WintchDev` を追加する案：
    ターゲット重複により構成が複雑化し、憲章原則 2（シンプルさ）に反するため不採用。`build-app.sh` 側で生成物名とバンドル内 `Info.plist` を調整する方が最小変更で済む。

### 設計判断 4: アプリ内 UI 名称の単一真実源（`AppIdentity` ドメインモデル）
- **Decision**: `Sources/WintchCore/Domain/AppIdentity.swift` を新設し、`Info.plist` 辞書（およびデフォルトのコンパイル構成）からアプリ表示名・識別子・開発版判定を解決する純粋モデルと UI 文言ヘルパーを提供する。
  - `CFBundleDisplayName` → `CFBundleName` の順で空白除去済み文字列を参照し、取得できない場合（`swift run` 等の未バンドル起動やテスト時）は `#if DEBUG` なら `"Wintch_dev"`、それ以外は `"Wintch"` をフォールバックとする。
  - `WintchApp.swift`、`AppCoordinator.swift`、`AboutView.swift`、`PermissionGuideView.swift` のハードコードされた `"Wintch"` 文言（メニュー項目・ウィンドウタイトル・案内文・About 見出し）をすべて `AppIdentity` 由来へ統一する。
- **Rationale**:
  - 既存の `AppVersionInfo` はバージョン・ビルド番号・著作権表記の単一責務を持っており、既存契約・テスト（`AppVersionInfoTests`）を変更せずに拡張できる。
  - `Domain/` に純粋値型として配置することで、OS ウィンドウを起動せずに Swift Testing で全パターン（開発バンドル、配布バンドル、空白入り、欠損時フォールバック、各 UI 文言生成）をテストできる。
- **Alternatives considered**:
  - `AboutView` や `WintchApp` ごとに `Bundle.main.object(forInfoDictionaryKey:)` を直接呼び出す案：
    4 箇所に同様のフォールバック分岐が重複するため、コード品質規約（ロジック重複の禁止）に照らし共通ヘルパー `AppIdentity` へ抽出する。
