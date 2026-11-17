# 検証ガイド (Quickstart): セキュア入力フォーカス中のショートカット起動と安定復帰

**Feature**: `013-fix-secure-input-hotkey` | **Date**: 2026-11-17

## 1. 前提条件

- macOS 14.0 (Sonoma) 以降
- Xcode（Swift 6.0 ツールチェイン）
- テスト用ブラウザ（Google Chrome または Microsoft Edge）
- Wintch に「アクセシビリティ」権限が付与されていること

## 2. 自動テスト（ユニットテスト）の実行

プロジェクトルートで Swift Testing 全スイートを実行する（Command Line Tools 参照エラーが出る場合は `DEVELOPER_DIR` を指定）：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

### 確認観点
- [hotkey-secure-input-contracts.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/013-fix-secure-input-hotkey/contracts/hotkey-secure-input-contracts.md) および [data-model.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/013-fix-secure-input-hotkey/data-model.md) に基づく新規テスト（重複排除・Carbon ホットキー登録計画・セキュア入力解放ガード・一時アクティブ化連携・キャンセル時復元）を含む全テストが 100% 合格すること。

## 3. `.app` バンドルのビルドと起動

```bash
./scripts/build-app.sh
open .build/Wintch.app
```

> アドホック署名の再ビルドにより macOS が別署名とみなした場合は、「システム設定 ＞ プライバシーとセキュリティ ＞ アクセシビリティ」から一度削除して再登録する。

## 4. 実機 E2E 検証シナリオ（Issue #15 再現・解消確認）

### シナリオ A: パスワード欄フォーカス中の通常スイッチャー（US1）
1. Chrome または Edge でログインページ（`<input type="password">` がある画面）を開き、パスワード欄をクリックしてフォーカスする。
2. 必要なら別ターミナルで以下を実行し、OS がセキュア入力状態であることを確認する：
   ```bash
   ioreg -l -d 1 -w 0 -k IOConsoleUsers | grep -o '"kCGSSessionSecureInputPID"=[0-9]*'
   ```
3. パスワード欄にフォーカスしたまま `Option + Tab` を押す。
   - **期待結果**: スイッチャーパネルが即座に表示され、2 番目の候補が選択される（2 つ飛ばない）。
4. `Option` を押したまま `Tab` / `Shift + Tab` / 上下左右矢印キーを押し、さらに `Esc` を押す。
   - **期待結果**: 候補移動が正常に効き、`Esc` でパネルが閉じて元のブラウザへフォーカスが戻る（ブラウザ側に矢印や Esc が漏れない）。
5. 再度パスワード欄にフォーカスした状態で `Option + Tab` を押し、`Option` をすぐ（または数回送ってから）離す。
   - **期待結果**: 素早く離した場合でも取りこぼさず、選択したウィンドウへ切り替わる。

### シナリオ B: パスワード欄フォーカス中の検索ランチャー（US2）
1. パスワード欄にフォーカスした状態で `Option + Space` を押す。
   - **期待結果**: 検索ランチャーが表示され、検索入力・候補移動・切り替え、および `Esc` / 再押下での元アプリ復帰が正常に行われる。

### シナリオ C: フォーカス解除・往復後の安定性（US3）
1. パスワード欄フォーカス → 通常のテキスト欄やアドレスバーへフォーカス移動 → 別タブ切替を数回繰り返す。
2. 各タイミングで `Option + Tab` および `Option + Space` を押す。
   - **期待結果**: 一時的な反応不能状態に陥らず、常に即座にスイッチャー／ランチャーが起動する（権限誘導画面も誤表示されない）。

### シナリオ D: 通常時の非アクティブ動作・設定変更整合（US4）
1. パスワード欄以外のアプリ（Finder、エディタ等）で `Option + Tab` を押す。
   - **期待結果**: 従来通り裏アプリのフォーカスを奪わずにスイッチャーが動作し、二重移動しない。
2. Wintch の設定画面を開き、ショートカット記録中に現在のショートカット（`Option + Tab` 等）を押す、および別ショートカットへ変更する。
   - **期待結果**: 記録中にスイッチャーが誤起動せず、変更直後から通常時・パスワード欄上の双方で新しいショートカットが機能する。
