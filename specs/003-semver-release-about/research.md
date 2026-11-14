# 技術調査レポート (Research): セマンティックバージョニング導入・自動タグリリース・「Wintchについて」メニュー

**Feature**: `003-semver-release-about`  
**Date**: 2026-11-14  
**Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/003-semver-release-about/spec.md)

---

## 1. バージョンファイルと `Info.plist` 同期方式

### Decision
リポジトリルートにプレーンテキストの `VERSION` ファイル（初期値 `0.1.0`）を配置し、`scripts/build-app.sh` がビルド時に読み取って `.build/Wintch.app/Contents/Info.plist` へ `/usr/libexec/PlistBuddy` で動的に注入する。`Resources/Info.plist` 自体はビルド時に書き換えない。

### Rationale
- **単一の信頼できる情報源（SSOT）**: バージョン更新時の変更対象が `VERSION` の 1 ファイルに限定され、GitHub Actions の `paths: ['VERSION']` トリガーと完全に一致する。
- **ビルド時のクリーン性**: `Resources/Info.plist` をビルドスクリプトで直接書き換えると、`git status` が汚れたりローカル開発中の作業ツリーと競合したりする。バンドル先の `Contents/Info.plist` に対して `PlistBuddy` で注入する方式であれば、リポジトリファイルを汚さずに常に正確な値がアプリに埋め込まれる。
- **ビルド番号（`CFBundleVersion`）**: `git rev-list --count HEAD` により単調増加する整数値を設定し、Git 履歴が利用できない環境では `1` へフォールバックする。macOS の `CFBundleVersion` 仕様（ピリオド区切りの整数列）にも確実に適合する。

### Alternatives Considered
- **`Resources/Info.plist` の直接更新**: Git 差分が 2 ファイルに分散し、CI での `VERSION` 変更検知と `Info.plist` 不整合のリスクがあるため不採用。
- **`version.json` による管理**: ビルドスクリプトや CI での `jq`/Python パース依存が増えるため、シンプルなプレーンテキスト `VERSION` を採用。

---

## 2. セマンティックバージョニング検証規則

### Decision
SemVer 2.0.0 互換（`MAJOR.MINOR.PATCH` および任意の `-prerelease`、先頭ゼロ不可の数値バージョン部）の正規表現で検証する:
```text
^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$
```
ハイフン（`-`）を含む場合はプレリリース版と判定し、GitHub Release 作成時に `--prerelease` フラグを付与する。

### Rationale
- `0.1.0`、`1.2.3`、`0.2.0-beta.1`、`1.0.0-rc.1` 等を正確に許容し、`v0.1.0`（ファイル内での `v` 接頭辞誤記）や `01.0.0`、空白混入などを確実に弾ける。
- `VERSION` ファイルは前後空白・末尾改行をトリミングして評価するため、エディタの自動末尾改行（`\n`）による失敗を防げる。

### Alternatives Considered
- **`MAJOR.MINOR.PATCH` のみ許可**: プレリリース（`beta` / `rc`）運用ができなくなるため不採用。

---

## 3. Universal Binary ビルド・ZIP パッケージ化

### Decision
`scripts/build-app.sh` に `--universal` オプション（例: `./scripts/build-app.sh release --universal`）を追加し、指定時は `swift build -c release --arch arm64 --arch x86_64` で Universal Binary を構築する。また `--show-bin-path` も同一の `--arch` 引数を渡して出力パス（例: `.build/out/Products/Release`）を取得することをローカル環境で確認済み。

ZIP 化は以下を実行する:
```bash
ditto -c -k --keepParent ./.build/Wintch.app "./.build/Wintch-v${VERSION}.zip"
```

### Rationale
- 既存の `scripts/build-app.sh` の出力先は `.build/Wintch.app` であり、`ditto -c -k --keepParent` を使うことで展開後のルートディレクトリ直下に `Wintch.app/` が再現され、macOS のリソースフォーク・シンボリックリンク・署名属性も損なわれない。
- リリース時のみ `--universal` を有効にすることで、ローカルでの通常開発ビルド（`./scripts/build-app.sh`）の高速さを犠牲にせず、配布物では Apple Silicon / Intel 両対応を実現できる。
- コード署名は既存のアドホック署名（`codesign --force --deep --sign -`）を維持する。

### Alternatives Considered
- **常に Universal Binary ビルド**: ローカルのインクリメンタル開発ビルド時間が約 2 倍になるため、フラグによる切り替え方式を採用。
- **`zip` コマンド使用**: macOS アプリバンドルの拡張属性や実行権限の保持において `ditto -c -k --keepParent` が Apple 標準推奨であるため `ditto` を採用。

---

## 4. GitHub Actions 自動タグ作成・リリース公開設計

### Decision
単一ワークフロー `.github/workflows/release.yml` を採用し、`macos-15` ランナー上で `fetch-depth: 0` でチェックアウトし、以下の全トリガーを統合管理する:
1. `push`（`branches: [main]`, `paths: ['VERSION']`）: `VERSION` 更新を検知し、SemVer 検証・タグ未存在確認・`swift test` 実行後に `v<VERSION>` タグを push し、**同一ワークフロー内の後続ジョブで** Universal ビルド・ZIP 生成・GitHub Release 公開を行う。
2. `push`（`tags: ['v*']`）: 手動タグ push 時も `VERSION` 一致検証・`swift test`・Universal ビルド・ZIP 生成・GitHub Release 公開を実行する。
3. `release`（`types: [published]`）: GitHub UI 上でリリース公開した場合も同様に検証・ビルドし、`gh release upload ... --clobber` で ZIP を添付・更新する。
4. `workflow_dispatch`: 緊急時・再生成用の手動実行口。

また、バージョン単位の `concurrency` グループを設定し、`push: tags` と `release: published` が同時に発火した場合の競合を防ぐ。

### Rationale
- **GitHub Actions の仕様制約への対応**: デフォルトの `GITHUB_TOKEN` で `git push origin v...` を行っても、別の `on: push: tags:` ワークフローはセキュリティ仕様上自動起動しない。単一ワークフロー内でタグ作成ジョブ（`prepare`）からリリースビルドジョブ（`release`）へ直列接続することで、PAT や GitHub App Secret の追加設定なしで「`VERSION` 更新 → 自動タグ → 自動ビルド＆リリース添付」を完全に自動化できる。
- **冪等性とバージョン整合性**: `gh release view` による存在確認と `--clobber` 上書き、およびタグ名 `v<X>` と `VERSION` ファイル値の一致チェック（FR-009）により、不整合リリースや重複アップロードエラーを防止する。

### Alternatives Considered
- **タグ作成ワークフローとリリースワークフローを分離 + PAT 導入**: 個人用 PAT の管理・ローテーション負担が増えるため、リポジトリ標準の `GITHUB_TOKEN` のみで完結する統合ワークフローを採用。

---

## 5. 「Wintchについて」メニューおよび専用ウィンドウ設計

### Decision
1. **ドメインモデル (`AppVersionInfo`)**: `Sources/WintchCore/Domain/AppVersionInfo.swift` に純粋 Swift の値型を定義し、`Bundle.main.infoDictionary`（テスト時は任意の `[String: Any]` を注入）から `CFBundleShortVersionString`・`CFBundleVersion`・`NSHumanReadableCopyright` を読み取る。バンドル外（`swift run` 等）で値が欠損する場合の安全なフォールバック値（例: `shortVersion = "0.1.0 (dev)"` または `"不明"`、`buildNumber = "1"`、`copyright = "Copyright © 2026 Wintch Contributors. MIT License."`）を備える。
2. **UI ビュー (`AboutView`)**: `Sources/WintchCore/Views/AboutView.swift` に SwiftUI ビューを作成し、アプリアイコン（`NSApplication.shared.applicationIconImage` を利用し、バンドル外等でフォールバックアイコン表示も可能）・アプリ名（「Wintch」）・バージョン表記（`バージョン <shortVersion> (<buildNumber>)`）・アプリ概要および著作権表記を表示する。
3. **コーディネーター (`AppCoordinator`)**: 既存の `ensureSettingsWindow()` / `ensurePermissionWindow()` と同じパターンで `aboutWindow: NSWindow?` と `openAbout()` を実装し、`isReleasedWhenClosed = false` によりウィンドウの再利用と閉じ操作後のアプリ継続を保証する。
4. **メニュー配置 (`WintchApp.swift`)**: `MenuBarExtra` 内の「設定を開く...」の上（または直近）に「Wintchについて」ボタンと区切り線を配置する。

### Rationale
- 既存の `SettingsView` / `PermissionGuideView` とアーキテクチャ（`AppCoordinator` + `NSWindow` + `NSHostingView` + SwiftUI View + `Domain` 純粋モデル）を完全に統一でき、Swift Testing で `AppVersionInfo` のパース・フォールバック・表示文字列生成を 100% 単体テストできる。
- `LSUIElement = YES`（`.accessory` ポリシー）環境下でも `NSApplication.shared.activate()` + `window.center()` + `window.makeKeyAndOrderFront(nil)` により確実に最前面表示される。

### Alternatives Considered
- **`NSApplication.shared.orderFrontStandardAboutPanel`**: 最小コードだがデザイン調整やバンドル外実行時の表示制御・テストが難しいため、ユーザー選択に従いカスタム SwiftUI ウィンドウを採用。
