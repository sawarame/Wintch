# UI画面・振る舞い契約 (UI Contracts): ウィンドウ検索ランチャーモード

**Feature**: `002-window-search-launcher`  
**Date**: 2026-11-13  
**Purpose**: ランチャー検索UI、IME対応入力フィールド、上端固定リサイズ、文字ハイライト、および設定画面ショートカットレコーダーの UI 振る舞いを定義する。

---

## 1. フローティングパネルと検索統合ビュー (`SwitcherPanel` + `SwitcherListView`)

### 1.1 パネルのフォーカスとウィンドウ特性（モード別）
- **通常モード (`mode == .normal`)**:
  - 従来通り `.nonactivatingPanel` として `orderFrontRegardless()` + `makeKey()` で表示し、他アプリのアクティブ状態を奪わない。
- **ランチャーモード (`mode == .launcher`)**:
  - 日本語 IME（ライブ変換・変換候補ウィンドウ・入力ソース切替）を確実に動作させるため、表示直前に直前のアクティブアプリ（`NSWorkspace.shared.frontmostApplication`）を保持した上で `NSApplication.shared.activate()` を呼び出し、`SwitcherPanel` をキーウィンドウ化する。
  - 検索入力フィールド（`LauncherSearchField`）に自動的にファーストレスポンダを割り当てる。
  - `Esc` またはランチャーショートカット再押下によるキャンセル時は、パネルを非表示にした後に保持していた直前アプリを再度 `activate()` して元の作業ウィンドウへフォーカスを戻す（他アプリをクリックして `resignKey()` で閉じた場合は、クリック先アプリが既に前面のため復元しない）。
  - ウィンドウ選択確定時は、直前アプリ復元ではなく選択されたターゲットウィンドウの `activateWindow(_:)` を実行する。

### 1.2 パネル上端固定の下方向リサイズ
- ランチャー初回表示時は、初期ウィンドウ一覧＋検索ヘッダを含むパネルサイズを基準に画面中央へ配置し、その上端 Y 座標（`frame.maxY`）を `anchoredTopY` として記憶する。
- 検索入力によってリスト行数が変化した際は、`anchoredTopY` を固定したまま `newOriginY = anchoredTopY - newHeight` でパネル高さを更新し、検索入力ボックスが画面上で上下に一切移動しないようにする（FR-013 / SC-003）。
- リスト表示領域の最大高さ（420pt）を超えた場合は縦スクロール可能とし、上端・下端とも画面外へはみ出さないように制御する。

### 1.3 検索入力ヘッダと IME 優先制御 (`LauncherSearchField`)
- `SwitcherListView` の最上部に検索ヘッダを配置する（`mode == .launcher` 時のみ表示し、通常モード時は従来通りリストのみ）。
  - 虫眼鏡アイコン + `NSTextField` ラッパー（プレースホルダ：「ウィンドウを検索...」）+ 入力時のみクリアボタン等（またはシンプルなテキスト欄のみ）。
  - 下部に区切り線（`Divider`）を挟んでウィンドウリスト領域へ接続する。
- `NSTextFieldDelegate` の `control(_:textView:doCommandBy:)` により、IME 未確定文字列がない（`!textView.hasMarkedText()`）場合のみ以下を実行する：
  - `insertNewline:` (`Enter`) → `viewModel.confirmSelection()`（0件時は何もしない）
  - `cancelOperation:` (`Esc`) → `viewModel.cancel()`
  - `moveUp:` (`↑` / `Ctrl + P`) → `viewModel.moveSelection(.up)`
  - `moveDown:` (`↓` / `Ctrl + N`) → `viewModel.moveSelection(.down)`
- IME 変換中（`textView.hasMarkedText() == true` または変換候補ウィンドウ操作中）は `doCommandBy` にこれらのセレクタが渡されないため、IME 側の候補移動・確定・キャンセルが 100% 優先される（FR-012 / SC-005）。

### 1.4 リスト表示・ハイライト・0件状態
- **行レイアウト**:
  - 既存の縦型リスト（アプリアイコン 24x24pt + アプリケーション名 + ウィンドウタイトル）を維持する。
  - 検索文字列により一致した文字範囲（`matchedAppNameRanges` / `matchedTitleRanges`）は、`AttributedString` を用いて太字（`.semibold` / `.bold`）およびハイライトカラー（非選択時はアクセントカラー、選択時は白・高コントラスト強調）で描画する（FR-010）。
- **0件状態**:
  - `displayedResults.isEmpty` かつ検索入力中の場合は、リスト領域に「一致するウィンドウがありません」という案内ビューを表示する（FR-014）。

---

## 2. 設定画面の拡張 (`SettingsView` + `ShortcutRecorderView`)

### 2.1 セクション構成
既存の「起動ショートカット」セクションを拡張（または「通常スイッチャー」と「検索ランチャー」の役割が明確に分かる構成に整理）し、設定項目を増やしすぎずシンプルさを維持する。

1. **通常スイッチャー（ホールド式）**:
   - 修飾キー Picker（`Option` / `Control` / `Command`）
   - トリガーキー Picker（`Tab` / `Space` / `` ` `` / `\`）
   - 操作方法プレビュー（次へ / 前へ `⇧` 併用）
   - 重複エラー表示：ランチャー設定と重複する組み合わせを選択しようとした場合、変更をブロックしてエラーメッセージを表示し、Picker を直前の有効な値のまま維持する（FR-017）。
   - `Command + Tab` 警告（既存通り）。
2. **検索ランチャー（トグル式）**:
   - **ショートカットレコーダー (`ShortcutRecorderView`)**:
     - 通常状態：現在のショートカット（例：`⌥ + Space`）をボタン/カプセル枠内に表示。
     - クリックで記録待機状態へ遷移（「キーを入力...（Esc でキャンセル）」表示、`HotKeyMonitor.isSuspendedForRecording = true`）。
     - 記録待機中に `Esc` が押されたら変更せず待機解除。
     - 修飾キー（`⌘` / `⌥` / `⌃` のいずれか1つ以上）がない入力、または `⇧` のみの組み合わせはエラー表示して拒否。
     - 通常スイッチャー（順方向または `⇧` 併用逆方向）と重複する組み合わせはエラー表示してブロック。
     - 有効かつ非重複の組み合わせが入力されたら保存・監視反映し、エラー表示をクリアして待機解除。
     - リセット補助（任意・最小限：「デフォルトに戻す」またはシンプルな待機解除制御）。
3. **一般 / システム権限**: 既存通り維持。
