# クイックスタート・検証ガイド: スイッチャーおよび検索ランチャーからの選択中ウィンドウ終了

**Feature**: `005-close-selected-window`  
**Date**: 2026-11-15  
**Plan**: [plan.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/005-close-selected-window/plan.md)

## 前提条件

- macOS 14.0 (Sonoma) 以降、Swift 6 ツールチェーン（Xcode 16 以降または Command Line Tools）
- 手動実機テスト時は Wintch に macOS の「アクセシビリティ」権限が付与されていること（画面収録権限は不要・オフのままで検証可能）

---

## 1. ビルドと自動ユニットテスト

```bash
# パッケージのビルド確認
swift build

# 全ユニットテスト実行
swift test
```

### 確認対象の主要テスト観点

- `HotKeyMonitorDecisionTests`:
  - `.normal` / `.launcher` 双方で「設定中の通常スイッチャー必須修飾キー + `Q`」および `Shift` 併用の判定が `.closeSelectedWindowPressed` かつ `shouldConsume: true` になること
  - `.launcher` における単体 `Q`・`Shift + Q` が非消費通過（`event: nil, shouldConsume: false`）であること
  - カスタム修飾キー（`Control`、`Command`、複数修飾キー）への追従、および既存ショートカット（ランチャー再押下・通常移動）が優先されること
- `SwitcherSelectionTests`:
  - `indexAfterRemoval(current:remainingCount:)` の先頭・中間・末尾・空境界値
- `SwitcherViewModelTests`:
  - 通常モードでの連続クローズ、末尾クローズ時のインデックス補正、最後の 1 件クローズ時のパネル自動終了、未クローズ時（`false` 返却）の維持
  - ランチャーモードでの検索語維持クローズ、絞り込み結果 0 件遷移時の 0 件案内維持、全ウィンドウ 0 件時のパネル自動終了、再入防止・処理中キャンセルの安全性

---

## 2. アプリバンドル作成と手動 E2E 検証

```bash
# .app バンドルをビルド（既存スクリプトを使用）
./scripts/build-app.sh
```

### 手動検証シナリオ

1. **通常スイッチャーでの連続ウィンドウクローズ（デフォルト `Option + Tab`）**
   - 同一アプリの複数ウィンドウ（例：Finder 2 枚、TextEdit 2 枚など）を開いた状態で `Option + Tab` を押してパネルを表示（`Option` は保持）。
   - `Option` を押したまま `Q` を押すと、選択中のウィンドウ **1 枚のみ**が閉じられ、他ウィンドウやアプリ自体は終了しないこと、パネルが開いたまま一覧が更新されること、さらに `Q` を続けて押して連続クローズできることを確認。
   - 残りのウィンドウを選択して `Option` を離すと対象ウィンドウへフォーカスが切り替わることを確認。

2. **検索ランチャーでのクローズと文字 `q` 入力の両立（デフォルト `Option + Space`）**
   - `Option + Space` で検索ランチャーを開き、`"q"` や `"quick"` など `q` を含む文字を入力して、ウィンドウが閉じられず普通に文字入力できることを確認。
   - キーワード入力済み（または未入力）の状態で `Option + Q` を押すと、選択中のウィンドウ 1 枚のみが閉じ、検索入力欄に `œ` 等の特殊文字が入らず、検索語とパネルが維持されることを確認。

3. **未保存確認ダイアログと最後の 1 件の安全性**
   - TextEdit 等で文字を入力した未保存ドキュメントウィンドウを選択し、`Option + Q` を押す。変更が強制破棄されず確認ダイアログが尊重されることを確認。
   - すべての通常ウィンドウが残り 1 枚の状態で `Option + Q` を押し、ウィンドウが閉じると同時にパネルが自動的に閉じることを確認。

4. **修飾キー設定変更（特に `Command` 設定時）**
   - 設定画面で通常スイッチャーのショートカットを `Command + Tab`（または `Control + Tab`）等に変更する。
   - パネル表示中に `Command + Q` を押しても Wintch 自身や他アプリ全体が強制終了せず、選択中ウィンドウ 1 枚のみが閉じられることを確認。
