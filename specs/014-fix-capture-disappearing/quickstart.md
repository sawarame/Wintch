# 検証手順書 (Quickstart): キャプチャ消失防止とキャッシュ整合性

**Feature**: `014-fix-capture-disappearing`  
**Date**: 2026-11-17

## 1. 自動テスト（Swift Testing）

```bash
# Command Line Tools 環境で TestingMacros エラーが出る場合は Xcode Developer ディレクトリを指定
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

またはテストフィルタを指定して関連スイートを重点確認:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "WindowCaptureAndMatchingTests|SwitcherViewModelTests"
```

### 確認観点
1. `WindowCaptureService.pruneCache(keeping:)` が閉じ済みウィンドウのキャッシュのみを削除し、生存ウィンドウのキャッシュ・LRU 順を維持すること。
2. `WindowCaptureService` のデフォルト上限が 100 件であり、カスタム上限環境でも古いエントリから正しく追い出されること。
3. `SwitcherViewModel` で大量の開閉が発生した後も、生存ウィンドウのキャッシュが維持され、`sorted.reversed()` 参照により MRU 上位ウィンドウが追い出されないこと。
4. リスト型およびランチャーモードでは `pruneCache` を含めキャプチャサービスが一切呼ばれないこと。
5. `WindowService.selectBestCGWindowMatch` が包含フォールバック時やタイトル不一致時にも `preferredCGWindowID` 連続性と非空 `cgWindowName` を優先すること。

## 2. アプリビルドと手動動作確認

```bash
./scripts/build-app.sh
open .build/Wintch.app
```

1. 設定画面で通常スイッチャーの表示形式を「キャプチャ表示型」に設定し、画面収録権限を許可する。
2. 複数アプリのウィンドウを開き、`Option + Tab` で全ウィンドウのサムネイルが表示されることを確認する。
3. スイッチャーを使わずに通常操作（`Cmd+W` や閉じるボタン）で複数の別ウィンドウ・ダイアログを多数開閉する。
4. 再度 `Option + Tab` を開き、最初から開いていたウィンドウのキャプチャが消えてアイコンに戻ることなく維持されていることを確認する。
5. 設定を「リスト型」へ戻すと即座にキャッシュがクリアされ、リスト型および `Option + Space` ランチャーで従来通り動作することを確認する。
