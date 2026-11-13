# Wintch

**Wintch**（Window + Switch）は、macOS 14.0 (Sonoma) 以降向けに設計された、シンプルで軽量な**ウィンドウ単位スイッチャー**アプリです。

macOS 標準の `Command + Tab` がアプリケーション単位の切り替えであるのに対し、Wintch は同じアプリの複数ウィンドウも含めて、操作スペース（仮想デスクトップ）を横断しながら素早く目的のウィンドウへ切り替えることができます。

---

## 主な特徴

* **最小権限・画面収録不要（Privacy by Design）**
  `ScreenCaptureKit` などの画面収録権限は一切使用せず、アクセシビリティ API（`AXUIElement`）とウィンドウメタデータ（`CGWindowListCopyWindowInfo`）のみで動作します。サムネイル画像は取得せず、「アプリアイコン」「アプリケーション名」「ウィンドウタイトル」の縦型リストを表示します。
* **メニューバー常駐・シンプル体験**
  Dock にアイコンを表示しない常駐アプリ（`LSUIElement`）として動作し、メニューバーから設定画面や終了操作にアクセスできます。
* **操作スペース横断と MRU 並び替え**
  現在の操作スペースだけでなく他のスペース上のウィンドウも候補に表示し、直近でアクティブだった順（MRU）で並べます（起動時は 1 つ前に使っていた 2 番目の項目を選択）。
* **軽快なキーボード操作とカスタマイズ**
  * デフォルトショートカット：`Option + Tab`
  * 修飾キーを押し続けたままトリガーキー（`Shift` 併用で逆順）や上下矢印キーで選択を移動し、修飾キーを離した瞬間に確定（`Esc` でキャンセル）
  * 設定画面から修飾キー（`Option` / `Control` / `Command`）とトリガーキー（`Tab` / `Space` / `` ` `` / `\`）の組み合わせ、および「ログイン時に自動起動」を切り替え可能
* **外部依存なし・Apple 標準フレームワークのみ**
  Swift 6.0 / SwiftUI（フローティングパネル制御のみ `NSPanel`）および `@Observable` マクロを採用した MVVM + Services アーキテクチャで構成し、非公開 API（`CGS*` 等）も使用していません。

---

## 動作環境・要件

* **OS**: macOS 14.0 (Sonoma) 以降
* **開発ツール**: Swift 6.0 以降（Xcode または Apple Command Line Tools）
* **必須権限**: macOS「アクセシビリティ」権限
  * 初回起動時または未許可時は誘導ダイアログが表示され、「システム設定 ＞ プライバシーとセキュリティ ＞ アクセシビリティ」から許可できます。

---

## プロジェクト構成

```text
.
├── Package.swift                   # Swift Package 定義（外部依存なし）
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
│       ├── Domain/                 # 純粋なビジネスロジック（フィルタ・ソート・選択計算等）
│       ├── Services/               # OS API 隔離層（AX / CGWindow / CGEventTap 等）
│       ├── ViewModels/             # @Observable ViewModel 群
│       └── Views/                  # SwiftUI ビュー & SwitcherPanel (NSPanel)
├── Tests/
│   └── WintchCoreTests/            # Swift Testing ユニットテスト（7 スイート・21 テスト）
└── scripts/
    └── build-app.sh                # .app バンドル組み立て・アイコン生成・署名スクリプト
```

設計仕様やプロジェクト憲章は [constitution.md](.specify/memory/constitution.md) および [specs/001-window-switcher-mvp/](specs/001-window-switcher-mvp/) にまとめています。

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
> SwiftPM の増分ビルドキャッシュにより `TestingMacros` 関連のビルドエラーが出た場合は、キャッシュをクリーンしてから再実行してください。
>
> ```bash
> swift package clean && swift test
> ```

### 3. `.app` バンドルのビルドと起動

`swift build` でバイナリを生成し、`AppIcon.svg` からの `.icns` 生成・リソース同梱・アドホック署名をまとめて行うスクリプトを用意しています。

```bash
# Debug ビルド (.build/Wintch.app を生成)
./scripts/build-app.sh

# Release ビルドを行う場合
./scripts/build-app.sh release

# アプリを起動
open .build/Wintch.app
```

（`swift run` 単体では `.app` バンドルや `Info.plist` が構成されないため、動作確認は `./scripts/build-app.sh` 経由で `.build/Wintch.app` を起動することを推奨します）

### 4. 再ビルド時のアクセシビリティ権限に関する注意

`./scripts/build-app.sh` ではローカル開発用にアドホック署名（`codesign --force --deep --sign -`）を使用しています。macOS の仕様上、アドホック署名アプリは**ビルドごとの署名ハッシュ（`cdhash`）で権限が識別**されるため、コードを変更して再ビルドすると「システム設定」一覧上は ON に見えても内部的に権限が外れることがあります。

再ビルド後に権限確認画面が表示された場合は、以下の手順で再登録してください。

1. 起動中の Wintch を終了する
2. **「システム設定」＞「プライバシーとセキュリティ」＞「アクセシビリティ」** を開く
3. 一覧から **「Wintch」を選択し、「`−`」ボタンで一度削除**する（単なる OFF/ON ではなく削除が必要）
4. 「`＋`」ボタンから `.build/Wintch.app` を追加し直して起動する

---

## ライセンス

[MIT License](LICENSE)
