# 開発ワークフロー (Development Workflow)

## 1. 開発環境の要件

- **OS**: macOS 14.0 (Sonoma) 以降
- **ツールチェーン**: Swift 6.0 以降（Xcode または Command Line Tools）
  - ※ `swift test` 実行時に `TestingMacros` 関連のビルドエラーが発生する場合は、環境変数 `DEVELOPER_DIR` で Xcode を明示指定する。

---

## 2. ユニットテストの実行

ドメインロジック、ViewModel、サービス協調処理のテストは Swift Testing で `Tests/WintchCoreTests/` に配置されています。

```bash
swift test
```

`TestingMacros` 関連エラーが出る場合や増分キャッシュ不整合時は以下を実行します。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
# またはキャッシュクリーン後
swift package clean && swift test
```

---

## 3. アプリバンドルのビルドと起動

`swift run` 単体では `.app` バンドル構造や `Info.plist`・`.icns` アイコンが構成されないため、動作確認は `scripts/build-app.sh` を使用します。

```bash
# ローカル開発用ビルド (.build/Wintch_dev.app を生成)
./scripts/build-app.sh

# ローカル開発版を起動
open .build/Wintch_dev.app

# リリースビルド (.build/Wintch.app を生成)
./scripts/build-app.sh release

# Apple Silicon + Intel 対応 Universal Binary でリリースビルド
./scripts/build-app.sh release --universal

# ビルド済み Release バンドルから DMG を生成 (.build/Wintch-v<VERSION>.dmg を生成)
./scripts/build-dmg.sh
```

### 配布版と開発版の識別分離
- **Debug ビルド（既定）**: バンドル名 `.build/Wintch_dev.app`、表示名 `Wintch_dev`、Bundle ID `dev.wintch.Wintch.dev` として組み立てられます。これにより、同一 Mac 上にインストール済みの配布版 `Wintch` と権限登録や `UserDefaults` 設定が競合しません。
- **Release ビルド（`release` 引数）**: バンドル名 `.build/Wintch.app`、表示名 `Wintch`、Bundle ID `dev.wintch.Wintch` として組み立てられます。

---

## 4. ローカル再ビルド時のアクセシビリティ権限・画面収録権限の注意

`./scripts/build-app.sh` で `WINTCH_SIGN_IDENTITY` を指定しない場合、ローカル開発用にアドホック署名（`codesign --force --deep --sign -`）が適用されます。macOS の TCC 仕様上、アドホック署名されたアプリはビルドごとの署名ハッシュ（`cdhash`）で権限が識別されるため、コードを変更して再ビルドすると「システム設定」一覧上は ON に見えても内部的に権限が無効化される場合があります。

再ビルド後に権限誘導画面や未許可状態が表示された場合は、以下の手順で再登録してください。

1. 起動中の `Wintch_dev`（または `Wintch`）を終了する。
2. **「システム設定」＞「プライバシーとセキュリティ」＞「アクセシビリティ」**（キャプチャ表示型検証時は「画面収録」も）を開く。
3. 一覧から対象アプリを選択し、**「`−`」ボタンで一度削除**する（OFF/ON 切り替えではなく削除が必要）。
4. 「`＋`」ボタンから `.build/Wintch_dev.app` を追加し直して起動する。

---

## 5. デバッグと動作確認のポイント

- アプリ起動後、メニューバーアイコンから「Wintch_devについて」「設定を開く...」の表示および各種設定変更を確認する。
- 通常スイッチャー（デフォルト `Option + Tab`）と検索ランチャー（デフォルト `Option + Space`）について、通常ウィンドウ・別操作スペース・最小化ウィンドウ・ウィンドウ 0 件・セキュア入力（パスワード欄）の各条件を確認する。
- 検索ランチャーでは日本語 IME 変換中の `Enter` / `Esc` / `↑` / `↓` が IME 操作を妨げないことも確認する。
- システムログは `Console.app` または `log stream --predicate 'process == "Wintch_dev"'` 等で確認できる（`os.Logger` を使用）。

---

## 6. バージョニングとリリース（GitHub Actions）

アプリバージョンはリポジトリルートの [`VERSION`](../VERSION) ファイルでセマンティックバージョニング（`MAJOR.MINOR.PATCH` または `MAJOR.MINOR.PATCH-<prerelease>`）により一元管理しています。

1. 機能追加や修正の反映後、[`VERSION`](../VERSION) を更新して `main` ブランチへプッシュする（または手動で `v<VERSION>` タグを作成・プッシュする）。
2. [`.github/workflows/release.yml`](../.github/workflows/release.yml) が自動で以下を実行する。
   - `VERSION` の SemVer 形式検証・タグ重複／整合性チェック
   - `macos-15` ランナー上での `swift test` 実行
   - `v<VERSION>` タグの自動作成（`main` push 時）
   - Universal Binary ビルド、Developer ID 署名（Hardened Runtime）、Apple 公証（`notarytool`）・Staple
   - `ditto` による `Wintch-v<VERSION>.zip` 生成、`scripts/build-dmg.sh` による `Wintch-v<VERSION>.dmg`（`Wintch.app` + `/Applications` シンボリックリンク）生成・署名・Apple 公証・Staple、および ZIP／DMG 双方を添付した GitHub Release 公開（プレリリース識別子付きの場合は Prerelease 扱い）
   - 安定版リリース時のみ `Wintch-v<VERSION>.zip` の SHA256 を用いた `sawarame/homebrew-tap` の Homebrew Cask 自動更新 PR／コミット作成
