# 検証・ビルドガイド (Phase 1 Quickstart): メモ等の非表示内部補助ウィンドウ除外

**Feature**: `009-filter-hidden-ghost-windows` | **Date**: 2026-11-15

## 1. 前提条件

- macOS 14.0 (Sonoma) 以降
- Swift 6.0 ツールチェイン / Xcode
- Wintch にアクセシビリティ権限が付与されていること（手動アプリ検証時）

## 2. 自動テストによる検証

実装後、以下のコマンドでユニットテストスイート全体を実行し、新規テストおよび既存リグレッションテストがすべて合格することを確認する。

```bash
swift test
```

> Command Line Tools が選択されていて `TestingMacros` ビルドエラーが出る場合は以下を使用：
> ```bash
> DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
> ```

### 主な検証観点（[window-filtering-contracts.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/009-filter-hidden-ghost-windows/contracts/window-filtering-contracts.md) および [data-model.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/009-filter-hidden-ghost-windows/data-model.md) 参照）
- `AppWindowProfileRegistry` のルックアップ・既定フォールバック・`HiddenBackingWindowSignature` の安全性ガード（`hasAXInfo == true` / `isOnScreen == true` / タイトルありの実ウィンドウは誤除外しない）
- メモアプリ（`com.apple.Notes`）で 1 ウィンドウ開いている場合（AX 捕捉済み＋`475x600`＋`500x500` 混在）に 1 件のみ通過すること
- メモアプリで全ウィンドウを閉じた場合（`475x600`＋`500x500` のみ）に 0 件になること
- メモアプリで複数実ウィンドウを開いている場合（複数 `hasAXInfo == true` 候補、またはメニュータイトル補完済み `cg-*`）に全実ウィンドウが保持されること
- Gemini 等の他アプリで `x ≈ 0, 500x500` の未表示バックキングウィンドウのみが残存している場合に 0 件になること
- 既存の `com.apple.systempreferences`、Finder、Chrome、VS Code、WezTerm テストがすべて引き続き合格すること

## 3. `.app` バンドルビルドおよび手動動作確認

```bash
./scripts/build-app.sh
open .build/Wintch.app
```

1. Mac 標準「メモ」アプリでウィンドウを 1 枚だけ開く。
2. 通常スイッチャー（デフォルト `Option + Tab`）および検索ランチャー（デフォルト `Option + Space`）をそれぞれ開き、メモアプリの項目が 1 件のみ表示され、`メモ (タイトルなし)` が表示されないことを確認する（リスト型・キャプチャ表示型双方、およびメモを別操作スペースへ移動した状態でも確認）。
3. ランチャーまたはスイッチャー上でメモアプリの 1 枚を選択して閉じる操作（デフォルト `Option + W` 等）を実行し、1 枚のみと判定されてメモアプリが通常終了することを確認する。
4. メモアプリでメモをダブルクリック等して 2 枚以上の独立ウィンドウを開き、スイッチャーおよびランチャーで実ウィンドウ数と同じ件数が表示されることを確認する。
5. Gemini 等、ウィンドウを閉じた状態で常駐起動しているアプリで「(タイトルなし)」エントリが表示されないことを確認する。
