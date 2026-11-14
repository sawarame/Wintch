# データモデル・状態遷移設計 (Data Model): セマンティックバージョニング導入・自動タグリリース・「Wintchについて」メニュー

**Feature**: `003-semver-release-about`  
**Date**: 2026-11-14  
**Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/003-semver-release-about/spec.md)

---

## 1. バージョン定義ファイル (`VERSION`)

リポジトリルートに配置する単一のバージョン定義ファイル。

| 項目 | 仕様 |
|---|---|
| ファイルパス | `VERSION`（リポジトリルート） |
| フォーマット | プレーンテキスト（UTF-8、1行、前後空白・末尾改行は読み取り時にトリミング） |
| 初期値 | `0.1.0` |
| バリデーション規則 | `^(0\|[1-9][0-9]*)\.(0\|[1-9][0-9]*)\.(0\|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$` |
| 導出値: タグ名 | `v<VERSION>`（例: `v0.1.0`, `v0.2.0-beta.1`） |
| 導出値: プレリリース判定 | `<VERSION>` に `-` を含む場合 `true` |
| 導出値: ZIP ファイル名 | `Wintch-v<VERSION>.zip` |

---

## 2. ドメインモデル (`Sources/WintchCore/Domain/AppVersionInfo.swift`)

アプリのバージョン情報および著作権表記を `Bundle` 辞書から安全に抽出・正規化する純粋 Swift 値型（`Equatable`, `Sendable`）。

| フィールド | 型 | フォールバック値 | 抽出元 (`Info.plist` キー) | 説明 |
|---|---|---|---|---|
| `shortVersion` | `String` | `"dev"` | `CFBundleShortVersionString` | ユーザー向けセマンティックバージョン（例: `"0.1.0"`） |
| `buildNumber` | `String` | `"1"` | `CFBundleVersion` | ビルド番号（コミット数文字列、例: `"12"`） |
| `copyright` | `String` | `"Copyright © 2026 Wintch Contributors. MIT License."` | `NSHumanReadableCopyright` | 著作権・ライセンス表記 |

### 算出プロパティ・メソッド
- `displayVersionText: String`
  - 例: `"バージョン 0.1.0 (12)"`（`shortVersion` と `buildNumber` の組み合わせ）
- `init(infoDictionary: [String: Any]?)`
  - 文字列の前後の空白をトリミングし、空文字や未設定・型不一致時はそれぞれ上記のフォールバック値を適用する。
- `static var current: AppVersionInfo`
  - `AppVersionInfo(infoDictionary: Bundle.main.infoDictionary)` を返す便利プロパティ。

---

## 3. リリース自動化パイプラインの状態遷移

### 3.1 `prepare`（検証・タグ確定ジョブ）

| トリガー種別 | 入力ソース | バリデーション条件 | 正常時出力 (`tag_name`, `version`, `is_prerelease`) | 異常時振る舞い |
|---|---|---|---|---|
| `push` (`main`, `paths: ['VERSION']`) | `VERSION` ファイル | SemVer 適合 ∧ タグ `v<VERSION>` が未存在 ∧ `swift test` パス | タグ `v<VERSION>` を作成＆push し、`release` ジョブへ連携 | 即時失敗（タグ作成・リリース実行なし） |
| `push` (`tags: ['v*']`) | タグ名 (`github.ref_name`) | `v` 除去後が SemVer 適合 ∧ `VERSION` ファイル値と一致 ∧ `swift test` パス | `tag_name = v<VERSION>` を出力し、`release` ジョブへ連携 | 即時失敗（リリース作成・ZIP 添付なし） |
| `release` (`published`) | リリースタグ (`github.event.release.tag_name`) | `v` 除去後が SemVer 適合 ∧ `VERSION` ファイル値と一致 ∧ `swift test` パス | `tag_name = v<VERSION>` を出力し、`release` ジョブへ連携 | 即時失敗（ZIP 添付・更新なし） |
| `workflow_dispatch` | `VERSION` ファイル | SemVer 適合 ∧ `swift test` パス | タグ `v<VERSION>` が未存在なら作成＆push し、`release` ジョブへ連携 | 即時失敗 |

### 3.2 `release`（ビルド・ZIP 生成・公開ジョブ）

| ステップ | 入力 | 出力 / 副作用 | エラー時 |
|---|---|---|---|
| Universal ビルド | `CONFIGURATION=release`, `--universal` | `.build/Wintch.app`（`arm64` + `x86_64`, `Info.plist` 同期済み, アドホック署名済み） | ジョブ失敗（公開なし） |
| ZIP 圧縮 | `.build/Wintch.app` | `.build/Wintch-v<VERSION>.zip`（ルート直下に `Wintch.app/` を保持） | ジョブ失敗 |
| GitHub Release 反映 | `tag_name`, ZIP, `is_prerelease` | 未存在なら `gh release create`（`--generate-notes`, 必要に応じ `--prerelease`）／既存なら `gh release upload --clobber` | ジョブ失敗 |
