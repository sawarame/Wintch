# クイックスタート・検証ガイド: スイッチャーおよび検索ランチャーからの選択中ウィンドウ／アプリ終了

**Feature**: `005-close-selected-window`  
**Date**: 2026-11-15  
**Plan**: [plan.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/005-close-selected-window/plan.md)

## 1. ビルドと自動ユニットテスト

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

### 確認対象の主要テスト観点

- `HotKeyMonitorDecisionTests`: `.normal` / `.launcher` での修飾キー + `Q` 消費、単体 `Q` / `Shift + Q` 通過、`Command + Q` 消費
- `SwitcherSelectionTests`: `indexAfterRemoval(current:remainingCount:)` 境界値
- `SwitcherViewModelTests`:
  - 同一アプリ複数ウィンドウ時 → `closeWindow` のみ呼ばれ `terminateApplication` は呼ばれないこと
  - 同一アプリ残り 1 ウィンドウ時 → `terminateApplication` が呼ばれ `closeWindow` は呼ばれないこと
  - 検索ランチャーで 1 件だけ絞り込まれているが裏に同一アプリの別ウィンドウがある場合 → `closeWindow` が呼ばれアプリは終了しないこと
  - 複数ウィンドウの 1 枚目を閉じたあと残り 1 枚に連続で操作すると 2 回目でアプリ終了になること
  - クローズ／終了失敗時（`false`）の一覧維持、最後の 1 件終了時の自動クローズ、処理中 `resignedActive` 抑止、および `onPanelFocusRestoreNeeded` 発火

---

## 2. 手動 E2E 検証シナリオ

```bash
./scripts/build-app.sh
```

1. **単一ウィンドウアプリの終了と再出現防止**:
   - WezTerm や Gemini（1 ウィンドウのみ開いた状態）を選択して `Option + Q` を押すとアプリ自体が終了し、再度スイッチャーを開いても候補に復活しないこと。
2. **複数ウィンドウアプリの段階的クローズ〜終了**:
   - Google Chrome 等でウィンドウを 2 枚開き、1 回目の `Option + Q` では選択した 1 枚のみが閉じ、残り 1 枚になった状態で 2 回目の `Option + Q` を押すとアプリごと終了すること。
3. **未訪問別スペースにある複数ウィンドウアプリのクローズ**:
   - Wintch 起動後にまだ一度も開いていない別スペースに複数ウィンドウアプリがある状態で `Option + Q` を押すと、自動でそのスペースへ切り替わって対象ウィンドウが閉じ、パネルも開いたまま操作を継続できること。
4. **検索ランチャーでの文字 `q` 入力と未保存確認**:
   - 単体 `Q` で `"q"` 検索でき、未保存変更があるアプリでは確認ダイアログが尊重されること。
