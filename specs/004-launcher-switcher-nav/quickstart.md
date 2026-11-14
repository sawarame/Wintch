# 検証ガイド (Quickstart): 検索ランチャー表示中の通常スイッチャーショートカットによる候補移動

**Feature**: `004-launcher-switcher-nav`  
**Date**: 2026-11-14

---

## 1. 前提条件

- macOS 14.0 (Sonoma) 以降
- Swift 6 ツールチェーン（`swift --version` で確認）
- 実機動作確認を行う場合は Wintch に対するアクセシビリティ権限の付与（「システム設定 > プライバシーとセキュリティ > アクセシビリティ」）

---

## 2. 自動テストによる検証

実装後、リポジトリルートで以下のコマンドを実行し、既存の全テストと新規追加テストがすべてパスすることを確認する。

```bash
swift test
```

### 確認対象の主要テスト観点
- `HotKeyMonitorDecisionTests`:
  - `.launcher` モード時に通常スイッチャー順方向（例：`Option + Tab`）で `.triggerPressed(isShiftPressed: false)` かつ `shouldConsume == true` を返すこと
  - `.launcher` モード時に通常スイッチャー逆方向（例：`Option + Shift + Tab`）で `.triggerPressed(isShiftPressed: true)` かつ `shouldConsume == true` を返すこと
  - `.launcher` モード時にランチャーショートカット再押下で `.launcherTriggerPressed` かつ `shouldConsume == true` を返し、`Esc` / `↑` / `↓` / 文字キーは `shouldConsume == false` で通過させること
  - `.normal` モード時にランチャーショートカットが `event == nil` かつ `shouldConsume == true` で無視・消費されること
  - カスタマイズ済みの通常ショートカット設定（例：`Control + Space` 等）にも追従すること
- `SwitcherViewModelTests`:
  - `.launcher` モード中に `.triggerPressed(isShiftPressed: false)` で「次へ」、`.triggerPressed(isShiftPressed: true)` で「前へ」へ循環移動すること
  - 移動後に `.modifierReleased` が届いてもパネルが閉じず `.launcher` が維持されること
  - `updateSearchQuery(...)` による絞り込み中に `.triggerPressed` を行っても `searchQuery` と `displayedResults` が維持されたまま選択のみ移動すること
  - 検索結果 0 件または 1 件の状態で `.triggerPressed` を行っても安全に動作すること
  - `.normal` モード中は引き続き `.launcherTriggerPressed` が無視されること

---

## 3. macOS 実機での手動検証シナリオ

ビルドおよびアプリバンドルの起動（例：`swift run Wintch` または `./scripts/build-app.sh`）後、3つ以上のウィンドウを開いた状態で以下を確認する。

1. **基本の「次へ」「前へ」移動と修飾キー解放**:
   - `Option + Space` で検索ランチャーを起動する（2番目のウィンドウが初期選択）。
   - `Option + Tab` を 1 回以上押し、選択カーソルが次の項目へ移動し、末尾から先頭へ循環することを確認する。
   - `Option + Shift + Tab` を押し、選択カーソルが前の項目へ戻り、先頭から末尾へ循環することを確認する。
   - `Option` キーを離してもランチャーが閉じず、検索入力欄にタブや余分な文字が入っていないことを確認する。
   - `Enter` を押すと、その時点で選択されていたウィンドウへ切り替わることを確認する。

2. **検索絞り込み中および 0 件時・IME 入力中の操作**:
   - `Option + Space` で起動し、複数候補が一致するキーワードを入力する。
   - `Option + Tab` / `Option + Shift + Tab` で絞り込み結果内を移動し、検索文字が消えないことを確認する。
   - 一致しない文字列を入力して「一致するウィンドウがありません」を表示した状態で `Option + Tab` を押してもクラッシュ・終了しないことを確認する。
   - 日本語 IME で未確定文字列を入力している状態で `Option + Tab` を押しても未確定文字列が壊れず候補移動できること、また `Esc` でランチャーを閉じた後は `Option + Space` 等の通常操作が継続できることを確認する。

3. **カスタマイズショートカット連動と通常モード側の排他維持**:
   - メニューバーから設定画面を開き、通常スイッチャーのショートカットを別の組み合わせ（例：`Control + ` `）へ変更する。
   - 検索ランチャーを開いた状態で `Control + ` ` および `Control + Shift + ` ` が「次へ」「前へ」として動作することを確認する。
   - 通常スイッチャー（`Control + ` ` を保持中）を開いた状態でランチャーショートカット（`Option + Space`）を押し、ランチャーへ切り替わらず通常スイッチャーが維持されることを確認する。
