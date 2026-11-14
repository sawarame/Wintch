# リリースパイプライン契約 (Release Pipeline Contracts): セマンティックバージョニング導入・自動タグリリース

**Feature**: `003-semver-release-about`  
**Date**: 2026-11-14  
**Purpose**: バージョンファイル、ローカル/CI ビルドスクリプト、配布用 ZIP アーカイブ、および GitHub Actions リリースワークフローの外部入出力仕様を定義する。

---

## 1. ビルドスクリプト契約 (`scripts/build-app.sh`)

### 1.1 コマンドラインインターフェース
```bash
./scripts/build-app.sh [debug|release] [--universal]
```
- **第1引数（任意）**: ビルド構成（`debug` または `release`、デフォルト: `debug`）。
- **`--universal`（任意）**: 指定時は `arm64` と `x86_64` の Universal Binary としてビルドする。未指定時は実行ホストのネイティブアーキテクチャでビルドする。環境変数 `WINTCH_UNIVERSAL=true` でも同等に有効化できる。

### 1.2 バージョン読み込み・`Info.plist` 反映契約
- リポジトリルートの `VERSION` ファイルを読み込み、前後空白・改行を除去した文字列を `APP_VERSION` とする。
- `VERSION` が存在しない、または SemVer 形式に一致しない場合は標準エラーへメッセージを出力して終了コード `1` で終了する。
- `BUILD_NUMBER` は `git rev-list --count HEAD` の出力値とし、取得できない場合（Git 外の環境やコミット 0 件）は `1` とする。
- 組み立てられた `.build/Wintch.app/Contents/Info.plist` に対して以下を反映する（`Resources/Info.plist` 自体は変更しない）:
  - `CFBundleShortVersionString` = `${APP_VERSION}`
  - `CFBundleVersion` = `${BUILD_NUMBER}`

### 1.3 出力成果物契約
- `.build/Wintch.app` に有効な macOS アプリケーションバンドルを生成し、アドホック署名（`codesign --force --deep --sign -`）を適用する。

---

## 2. 配布用 ZIP アーカイブ契約

### 2.1 生成コマンド・ファイル名
```bash
ditto -c -k --keepParent ./.build/Wintch.app "./.build/Wintch-v${APP_VERSION}.zip"
```
- **ファイル名**: `Wintch-v<APP_VERSION>.zip`（例: `Wintch-v0.1.0.zip`, `Wintch-v0.2.0-beta.1.zip`）
- **アーカイブ内部構造**: 展開したカレントディレクトリ直下に `Wintch.app/Contents/...` が配置されること（`--keepParent` によりトップレベルにアプリバンドルディレクトリを保持）。

---

## 3. GitHub Actions ワークフロー契約 (`.github/workflows/release.yml`)

### 3.1 実行環境・権限
- **Runner**: `macos-15`（Swift 6.0+・macOS SDK・`qlmanage` / `iconutil` / `sips` / `codesign` / `ditto` / `PlistBuddy` / `gh` 利用可能）
- **Permissions**: `contents: write`
- **Checkout**: `actions/checkout@v4`（`fetch-depth: 0`）

### 3.2 トリガーと振る舞い
1. **`push`（`branches: [main]`, `paths: ['VERSION']`）**:
   - `VERSION` を検証し、既存タグ `v<VERSION>` が存在すれば失敗終了する。
   - `swift test` を実行する。
   - `github-actions[bot]` としてタグ `v<VERSION>` を作成し `origin` へ push する。
   - 引き続き同一ワークフロー内の後続ジョブで `./scripts/build-app.sh release --universal`、`ditto` ZIP 生成、および `gh release create` を実行する。
2. **`push`（`tags: ['v*']`）** および **`release`（`types: [published]`）**:
   - タグ名から `v` を除いたバージョンが SemVer 適合かつ当該コミットの `VERSION` と一致することを検証する（不一致時は失敗終了）。
   - `swift test` を実行する。
   - `./scripts/build-app.sh release --universal` および `ditto` ZIP 生成を実行する。
   - 該当タグの GitHub Release が未作成なら作成（`--generate-notes`、プレリリース時は `--prerelease`）し、作成済みなら `gh release upload ... --clobber` で ZIP を添付・上書きする。
3. **`workflow_dispatch`**:
   - 現在の `VERSION` に基づきテスト・必要に応じたタグ作成・ビルド・リリース添付を行う。

### 3.3 同時実行制御
- バージョンタグ単位の `concurrency` グループを使用し、同一バージョンのタグ push とリリース公開イベントが同時発火しても競合しないよう直列実行する。
