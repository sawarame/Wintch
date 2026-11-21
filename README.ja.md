# Wintch

[English](README.md) | **日本語**

**Wintch**（Window + Switch）は、macOS 14.0 (Sonoma) 以降向けに設計された、シンプルで軽量な**ウィンドウ単位スイッチャー＆ランチャー**アプリです。

macOS 標準の `Command + Tab` がアプリケーション単位の切り替えであるのに対し、Wintch は同じアプリの複数ウィンドウも含めて、操作スペース（仮想デスクトップ）を横断しながら素早く目的のウィンドウへ切り替えることができます。

---

## 主な特徴

* **最小権限およびオプトインの原則（Privacy by Design）**
  標準の「リスト型スイッチャー」「アイコン型スイッチャー」および「検索ランチャー」では画面収録権限を一切使用せず、アクセシビリティ API（`AXUIElement`）とウィンドウメタデータ（`CGWindowListCopyWindowInfo`）のみで動作します。設定またはメニューバーで「キャプチャ表示型」を明示的に選択した場合のみ、オプトインで `ScreenCaptureKit` による一時メモリ上のサムネイルプレビューを利用できます。
* **通常スイッチャー（デフォルト `Option + Tab`）**
  操作スペースを横断して通常ウィンドウを直近アクティブ順（MRU）で表示します。修飾キーを押し続けたままトリガーキー（`Shift` 併用で逆順）や矢印キーで選択を移動し、修飾キーを離した瞬間に切り替えます（`Esc` でキャンセル）。
* **検索ランチャー＆アプリ起動（デフォルト `Option + Space`）**
  トグル式の検索入力欄からアプリ名・ウィンドウタイトルをスペース区切り AND のファジー検索で絞り込み、ハイライト表示します。検索入力時には未表示のインストール済みアプリケーションを下部に起動候補として併せて表示し、ウィンドウが 0 件の状態でもアプリ起動ランチャーとして起動できます。
* **選択中ウィンドウ／アプリの終了操作（スイッチャー修飾キー + `Q`）**
  スイッチャー・ランチャー上から不要なウィンドウを閉じることができます（同じアプリの最後の 1 枚の場合はアプリ自体を通常終了します）。
* **メニューバー常駐・セキュア入力対応・カスタマイズ**
  Dock にアイコンを表示しない常駐アプリ（`LSUIElement`）として動作し、パスワード入力欄等のセキュア入力保護下でもショートカットが機能します。設定画面からショートカットのカスタマイズ（競合防止付き）、表示形式切り替え、ログイン時自動起動を設定できます。
* **外部依存なし・Apple 標準フレームワークのみ**
  Swift 6.0 / SwiftUI（フローティングパネル制御のみ `NSPanel`）および `@Observable` マクロを採用した MVVM + Services アーキテクチャで構成し、非公開 API（`CGS*` 等）も使用していません。

---

## 動作環境・要件

* **OS**: macOS 14.0 (Sonoma) 以降
* **開発ツール**: Swift 6.0 以降（Xcode または Apple Command Line Tools）
* **必須権限**: macOS「アクセシビリティ」権限
  * 初回起動時または未許可時は誘導ダイアログが表示され、「システム設定 ＞ プライバシーとセキュリティ ＞ アクセシビリティ」から許可できます。
* **任意権限**: macOS「画面収録」権限（通常スイッチャーで「キャプチャ表示型」を選択した場合のみ）

---

## インストール方法

### Homebrew でインストール（推奨）

```bash
brew install --cask sawarame/tap/wintch
```

アップデート・アンインストールする場合は以下のコマンドを実行します。

```bash
# 最新版へアップデート
brew upgrade --cask wintch

# アンインストール（設定ファイルも削除する場合は --zap を付与）
brew uninstall --cask wintch
```

### GitHub Releases から手動でインストール

1. [Releases](https://github.com/sawarame/Wintch/releases) ページから最新の `Wintch-vX.Y.Z.dmg`（または `Wintch-vX.Y.Z.zip`）をダウンロードします。
2. `Wintch-vX.Y.Z.dmg` を開いて `Wintch.app` を `Applications` フォルダへドラッグ＆ドロップし、起動します（`.zip` を選択した場合は展開した `Wintch.app` を `/Applications` へ移動します）。

*(配布版（`.app`・`.dmg`）は Developer ID 署名および Apple 公証済みのため、通常の起動で Gatekeeper 警告は表示されません。初回起動時に案内に従って「アクセシビリティ」権限を許可してください。)*

---

## プロジェクト構成

```text
.
├── Package.swift                   # Swift Package 定義（外部依存なし）
├── VERSION                         # アプリバージョン定義（セマンティックバージョニング）
├── AGENTS.md                       # AI エージェント・開発者向けプロジェクトガイド
├── README.md                       # プロジェクト概要・インストール・ローカル開発手順（英語）
├── README.ja.md                    # プロジェクト概要・インストール・ローカル開発手順（日本語）
├── .context/                       # 基礎ドキュメント・仕様書正本・憲章
│   ├── constitution.md             # プロジェクト憲章（設計原則・制約）
│   ├── spec.md                     # 全機能の仕様書正本
│   ├── tech_stack.md               # 技術スタック・ディレクトリ構成
│   ├── development.md              # 開発・ビルド・リリースワークフロー
│   └── swift.md                    # Swift 6.0 コーディング規約
├── .github/
│   └── workflows/
│       └── release.yml             # テスト・署名・公証・ZIP/DMG リリース・Homebrew Tap 更新自動化
├── Resources/
│   ├── Info.plist                  # バンドル情報（LSUIElement / CFBundleIconFile 等）
│   └── Icons/
│       ├── AppIcon.svg             # アプリアイコン原画（1024x1024）
│       └── MenuBarIcon.svg         # メニューバー用テンプレートアイコン（18x18）
├── Sources/
│   ├── Wintch/
│   │   └── WintchApp.swift         # アプリエントリポイント・MenuBarExtra
│   └── WintchCore/
│       ├── App/                    # AppCoordinator（画面・サービス統括）
│       ├── Domain/                 # 純粋なビジネスロジック（フィルタ・ソート・検索・選択・プロファイル等）
│       ├── Services/               # OS API 隔離層（AX / CGWindow / CGEventTap / Carbon / ScreenCaptureKit 等）
│       │   └── Protocols/          # テスト用モック差し替えプロトコル群
│       ├── ViewModels/             # @Observable ViewModel 群
│       └── Views/                  # SwiftUI ビュー & SwitcherPanel (NSPanel)
├── Tests/
│   └── WintchCoreTests/            # Swift Testing ユニットテスト
└── scripts/
    ├── build-app.sh                # .app バンドル組み立て・バージョン反映・アイコン生成・署名スクリプト
    └── build-dmg.sh                # .app バンドルと /Applications リンクを格納した DMG 生成・署名スクリプト
```

設計仕様やプロジェクト憲章は [constitution.md](.context/constitution.md) および [spec.md](.context/spec.md) にまとめています。

---

## ローカルでの開発方法

### 1. リポジトリの取得

```bash
git clone <repository-url>
cd Wintch
```

### 2. テストの実行

ドメインロジックや ViewModel のユニットテストは Swift Testing で記述されています。

```bash
swift test
```

> [!NOTE]
> `TestingMacros` 関連のビルドエラーが出た場合は、Xcode の Developer ディレクトリ指定またはキャッシュクリーンを行ってから再実行してください。
>
> ```bash
> DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
> # または
> swift package clean && swift test
> ```

### 3. `.app` バンドルのビルドと起動

`swift build` でバイナリを生成し、`AppIcon.svg` からの `.icns` 生成・リソース同梱・署名をまとめて行うスクリプトを用意しています。ローカル開発用（Debug）ビルドは配布版との競合を防ぐため `Wintch_dev.app` として生成されます。

```bash
# Debug ビルド (.build/Wintch_dev.app を生成)
./scripts/build-app.sh

# ローカル開発版を起動
open .build/Wintch_dev.app

# Release ビルド (.build/Wintch.app を生成)
./scripts/build-app.sh release

# Apple Silicon + Intel 対応の Universal Binary でビルドする場合
./scripts/build-app.sh release --universal

# ビルド済み .app バンドルから DMG ディスクイメージを生成する場合
./scripts/build-dmg.sh
```

（`swift run` 単体では `.app` バンドルや `Info.plist` が構成されないため、動作確認は `./scripts/build-app.sh` 経由で `.build/Wintch_dev.app` を起動することを推奨します）

### 4. バージョニングと自動リリース（GitHub Actions）

アプリバージョンはリポジトリルートの [`VERSION`](VERSION) ファイルでセマンティックバージョニング（例: `0.1.0`、`0.2.0-beta.1`）により一元管理しています。

* `./scripts/build-app.sh` 実行時に `VERSION` の値と Git コミット数がバンドル内の `Info.plist`（`CFBundleShortVersionString` / `CFBundleVersion`）へ自動反映されます。
* `main` ブランチで `VERSION` を更新してプッシュすると、[`.github/workflows/release.yml`](.github/workflows/release.yml) が自動でテストを実行した上で `v<VERSION>` タグを作成し、Universal Binary 版の `.app` に Developer ID 署名・Apple 公証・Staple を行った `Wintch-v<VERSION>.zip` と、同じく署名・公証・Staple を行った `Wintch-v<VERSION>.dmg`（`Wintch.app` と `/Applications` シンボリックリンクを同梱）を GitHub Release へ公開し、安定版では Homebrew Tap（`sawarame/homebrew-tap`）も自動更新します（手動での `v*` タグプッシュ・GitHub Release 公開・`workflow_dispatch` にも対応）。

### 5. 再ビルド時のアクセシビリティ権限に関する注意

`./scripts/build-app.sh` ではローカル開発用にアドホック署名（`codesign --force --deep --sign -`）を使用しています。macOS の仕様上、アドホック署名アプリは**ビルドごとの署名ハッシュ（`cdhash`）で権限が識別**されるため、コードを変更して再ビルドすると「システム設定」一覧上は ON に見えても内部的に権限が外れることがあります。

再ビルド後に権限確認画面が表示された場合は、以下の手順で再登録してください。

1. 起動中の `Wintch_dev`（または `Wintch`）を終了する
2. **「システム設定」＞「プライバシーとセキュリティ」＞「アクセシビリティ」** を開く
3. 一覧から **「Wintch_dev」を選択し、「`−`」ボタンで一度削除**する（単なる OFF/ON ではなく削除が必要）
4. 「`＋`」ボタンから `.build/Wintch_dev.app` を追加し直して起動する

---

## ライセンス

[MIT License](LICENSE)
