# 検証ガイド (Quickstart): ランチャーアプリ起動安定化と開発版識別名分離

**Feature**: `011-fix-app-launch-dev-name` | **Date**: 2026-11-16

## 1. ユニットテストの実行

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

**期待結果**:
- `AppIdentityTests`（新規）を含む全ユニットテストがエラー・スキップなしで合格すること。
- `InstalledAppServiceTests` で非メインキュー安全化および起動設定検証が合格すること。

---

## 2. ローカル開発ビルド（`Wintch_dev`）の組み立てと検証

```bash
./scripts/build-app.sh
```

**検証コマンド**:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' .build/Wintch_dev.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleName' .build/Wintch_dev.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' .build/Wintch_dev.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' .build/Wintch_dev.app/Contents/Info.plist
ls -la .build/Wintch_dev.app/Contents/MacOS/Wintch_dev
```

**期待結果**:
- `.build/Wintch_dev.app` が生成されること。
- `CFBundleDisplayName` / `CFBundleName` / `CFBundleExecutable` が `Wintch_dev`、`CFBundleIdentifier` が `dev.wintch.Wintch.dev` であること。

**実機起動確認**:
1. `open .build/Wintch_dev.app` で開発版を起動する（配布版 `/Applications/Wintch.app` と共存した状態で検証可能）。
2. システム設定のアクセシビリティ一覧、メニューバー項目（`Wintch_devについて` / `Wintch_dev を終了`）、設定ウィンドウ（`Wintch_dev 設定`）、「Wintch_devについて」画面、アクティビティモニタのプロセス名がいずれも `Wintch_dev` として表示されることを確認する。
3. 検索ランチャー（デフォルト `Option + Space`）から未起動のアプリ（例: 計算機）を起動し、対象アプリが起動した直後も `Wintch_dev` が終了せずホットキーに応答し続けることを確認する。

---

## 3. リリースビルド（`Wintch`）の互換性・クラッシュ修正検証

```bash
./scripts/build-app.sh release
```

**検証コマンド**:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' .build/Wintch.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' .build/Wintch.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' .build/Wintch.app/Contents/Info.plist
nm -n .build/Wintch.app/Contents/MacOS/Wintch | grep -i "launchApplication" || true
```

**期待結果**:
- `.build/Wintch.app` が生成され、`CFBundleDisplayName` / `CFBundleExecutable` が `Wintch`、`CFBundleIdentifier` が `dev.wintch.Wintch` であること。
- `InstalledAppService.launchApplication` 内に完了ハンドラのクロージャシンボル（`closure #1 ... in InstalledAppService.launchApplication`）が生成されていないこと。
- リリースビルドの `.build/Wintch.app` を起動して検索ランチャーから未起動アプリを起動しても、`~/Library/Logs/DiagnosticReports/` にクラッシュログが出力されず常駐が継続すること。
