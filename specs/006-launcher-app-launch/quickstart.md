# クイックスタート検証ガイド (Quickstart): 検索ランチャーでの検索入力時におけるアプリ起動候補の併用表示

**Feature Branch**: `006-launcher-app-launch` | **Date**: 2026-11-15

## 1. 前提条件

- macOS 14.0 (Sonoma) 以降
- Xcode（Swift 6.0 / Swift Testing マクロ解決のため）
- Wintch に対する macOS「アクセシビリティ」権限許可

## 2. ユニットテストの実行

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

### 確認観点
- `AppSearchEngineTests`: 空クエリ空返却、日本語名／英語別名ファジー検索とハイライト範囲、スコア順／表示名昇順ソート、**上のウィンドウ候補に含まれるアプリの重複除外（`bundleIdentifier` 一致およびアプリ名フォールバック一致）**。
- `InstalledAppServiceTests`: 一時ディレクトリ構成における `.app` 走査・サブディレクトリ・シンボリックリンク解決・重複排除・`LSBackgroundOnly` / 自アプリ / 不完全バンドル除外。
- `SwitcherViewModelTests`: 検索入力時の混在表示（上ウィンドウ・下アプリ）、上下／通常スイッチャーショートカットのシームレス循環移動、ウィンドウ・アプリ双方の確定動作、アプリ候補上での `Option + Q` 無視、クローズ後の双方再評価、非同期リフレッシュ反映。

## 3. `.app` バンドルでの手動動作確認

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh
open .build/Wintch.app
```

1. 検索ランチャー（デフォルト `Option + Space`）を起動し、未入力状態では既存ウィンドウ一覧のみが表示されることを確認する。
2. 開いているアプリと未起動アプリの双方に一致するキーワード（例：Safari が開いていて Slack が未起動の状態で `"s"`、または `"cal"` など）を入力する。
3. 上部に一致ウィンドウ、その下に「アプリを起動」セクションとして一致アプリ（Safari 等の既出ウィンドウのアプリは除外）が表示されることを確認する。
4. `↓` キーや `Option + Tab` でウィンドウ候補の末尾からアプリ起動候補へシームレスに移動できること、また選択行へ自動スクロール追従することを確認する。
5. アプリ起動候補を選択した状態で `Option + Q` を押しても何も終了せずパネルが維持されること、および `Enter` またはクリックで対象アプリが起動しパネルが閉じることを確認する。
6. 検索欄の文字を全消去すると再びウィンドウ一覧のみの表示に戻ることを確認する。
