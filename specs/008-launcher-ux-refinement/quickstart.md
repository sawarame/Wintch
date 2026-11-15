# Phase 1 検証・クイックスタートガイド: ランチャー初期フォーカス変更と検索プレースホルダー視認性改善

**Feature**: `008-launcher-ux-refinement` | **Date**: 2026-11-15

## 1. 事前準備

- リポジトリルート（`/Users/sawarame_yasushi/dev/Wintch`）でブランチ `008-launcher-ux-refinement` がチェックアウトされていること。
- macOS 14.0 以降および Xcode / Swift 6.0 ツールチェインが利用可能であること。

## 2. 自動テストによる検証

ユニットテストを実行し、新規・更新テストを含む全テストが合格することを確認する。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

### 主な確認対象テスト
- `SwitcherSelectionTests`:
  - `preferSecondItem: true`（通常スイッチャー）で `count == 0 -> nil`, `count == 1 -> 0`, `count >= 2 -> 1`
  - `preferSecondItem: false`（ランチャー）で `count == 0 -> nil`, `count == 1 -> 0`, `count >= 2 -> 0`
- `SwitcherViewModelTests`:
  - 検索ランチャー起動時に 2件以上のウィンドウがある場合でも `selectedIndex == 0` となること
  - ランチャー起動直後の「次へ」（`↓` / 通常順方向ショートカット）で `selectedIndex == 1`、「前へ」（`↑` / 通常逆方向ショートカット）で末尾へ移動すること
  - 通常スイッチャー（リスト型およびキャプチャ表示型）起動時は従来通り `selectedIndex == 1` となること
- `LauncherSearchFieldTests`:
  - `LauncherSearchField` の `placeholderAttributedString` が `"ウィンドウまたはアプリを検索..."` を持ち、`.foregroundColor` に `NSColor.secondaryLabelColor`、`.font` に 15pt レギュラーフォントが設定されていること

## 3. 実機アプリビルドと手動検証

`.app` バンドルをビルドして起動し、実画面で視覚確認と操作確認を行う。

```bash
./scripts/build-app.sh
open .build/Wintch.app
```

> **注意**: アドホック署名での再ビルド後、必要に応じて「システム設定 ＞ プライバシーとセキュリティ ＞ アクセシビリティ」から Wintch を再登録する。

### 手動確認シナリオ

1. **ランチャー起動時の初期フォーカス確認**
   - 2つ以上のウィンドウを開いた状態で `Option + Space` を押す。
   - 期待結果: リストの **1番目（最上部）** の行が青いハイライトで初期選択されていること。そのまま `↓` または `Option + Tab` を押すと 2番目へ移動すること。
2. **通常スイッチャーの従来動作維持確認**
   - 2つ以上のウィンドウを開いた状態で `Option + Tab` を押す（リスト型・キャプチャ表示型の双方で確認）。
   - 期待結果: 従来通り **2番目** のウィンドウが初期選択されていること。
3. **プレースホルダー文字の視認性確認**
   - 白いウィンドウの上（ライトモード）および暗い背景の上（ダークモード）で `Option + Space` を押す。
   - 期待結果: 検索欄の `"ウィンドウまたはアプリを検索..."` が虫眼鏡アイコンや行タイトル補助文字と同等に読みやすく表示され、文字や日本語 IME の未確定文字を入力した瞬間に消えて入力文字（`labelColor`）と明確に区別できること。
