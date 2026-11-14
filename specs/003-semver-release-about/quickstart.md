# 検証ガイド (Quickstart): セマンティックバージョニング導入・自動タグリリース・「Wintchについて」メニュー

**Feature**: `003-semver-release-about`  
**Date**: 2026-11-14  
**References**: [data-model.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/003-semver-release-about/data-model.md) / [release-pipeline-contracts.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/003-semver-release-about/contracts/release-pipeline-contracts.md) / [ui-contracts.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/003-semver-release-about/contracts/ui-contracts.md)

---

## 1. ユニットテストの実行

`AppVersionInfo` を含む全ユニットテストスイートを実行し、エラーゼロでパスすることを確認する。

```bash
swift test
```

**期待結果**: `AppVersionInfoTests`（正常値・空白トリミング・未設定時フォールバック）を含む全テストがパスすること。

---

## 2. ローカルでの `.app` バンドルビルドとバージョン・Universal 検証

### 2.1 通常ビルド・Universal Release ビルドの実行
```bash
# Release Universal Binary ビルド
./scripts/build-app.sh release --universal
```

### 2.2 `Info.plist` と実行バイナリの検証
```bash
# バンドル内 Info.plist に VERSION とコミット数が反映されていることを確認
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" ./.build/Wintch.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" ./.build/Wintch.app/Contents/Info.plist

# Universal Binary (arm64 + x86_64) であることを確認
lipo -info ./.build/Wintch.app/Contents/MacOS/Wintch

# アドホック署名が有効であることを確認
codesign --verify --deep --strict ./.build/Wintch.app
```

**期待結果**:
- `CFBundleShortVersionString` が `VERSION` ファイルの値（初期値 `0.1.0`）と一致すること
- `CFBundleVersion` が現在のコミット数（整数文字列）になっていること
- `lipo -info` に `arm64` と `x86_64` の両方が含まれること
- `codesign --verify` が成功すること

---

## 3. ZIP アーカイブ生成と展開構造の確認

```bash
APP_VERSION="$(tr -d '[:space:]' < VERSION)"
ditto -c -k --keepParent ./.build/Wintch.app "./.build/Wintch-v${APP_VERSION}.zip"
unzip -l "./.build/Wintch-v${APP_VERSION}.zip" | head -n 15
```

**期待結果**:
- `.build/Wintch-v0.1.0.zip` が生成されること
- ZIP 内パスが `Wintch.app/Contents/...` となっており、親ディレクトリ `Wintch.app` を保持した構造であること

---

## 4. 「Wintchについて」メニューおよびウィンドウの動作確認

1. ビルドしたアプリを起動する:
   ```bash
   open ./.build/Wintch.app
   ```
2. メニューバーの Wintch アイコンをクリックし、「Wintchについて」項目が表示されていることを確認する。
3. 「Wintchについて」をクリックし、以下を確認する:
   - アプリアイコン（`AppIcon`）が表示されること
   - アプリ名「Wintch」と `バージョン 0.1.0 (<ビルド番号>)` が表示されること
   - 著作権表記が表示されること
   - ウィンドウを閉じて再度「Wintchについて」をクリックしても重複ウィンドウが作られず、アプリも終了しないこと

---

## 5. GitHub Actions ワークフロー検証（YAML 構文・自動リリース確認）

1. `.github/workflows/release.yml` の構文・ロジックを確認する（SemVer バリデーション、`VERSION` 一致検証、プレリリース判定）。
2. `main` ブランチへ `VERSION` の更新をマージ／プッシュした際:
   - テスト成功後にタグ `v<VERSION>` が自動作成されること
   - 同タグの GitHub Release が自動公開され、`Wintch-v<VERSION>.zip` がアセットとして添付されること
