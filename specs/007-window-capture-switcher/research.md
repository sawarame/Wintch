# 技術調査・意思決定記録 (Research): ウィンドウキャプチャ表示型スイッチャー

**Feature**: `007-window-capture-switcher`  
**Date**: 2026-11-15  
**Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/007-window-capture-switcher/spec.md)

## 1. macOS 14.0+ におけるウィンドウキャプチャ API と権限判定の方式

- **Decision**:
  - 画面収録権限の状態確認には `CGPreflightScreenCaptureAccess()`、ユーザー明示操作による権限リクエストには `CGRequestScreenCaptureAccess()`、システム設定誘導には `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)` を採用する。
  - 個別ウィンドウのサムネイル取得には `ScreenCaptureKit` の `SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)` および `SCScreenshotManager.captureImage(contentFilter:configuration:)` を採用する。
- **Rationale**:
  - `CGWindowListCreateImage` は macOS 14.0 で非推奨（macOS 15 SDK では利用不可）となっており、今後の OS バージョンとの互換性および Apple 推奨の公開 API 準拠の観点から `ScreenCaptureKit`（macOS 14.0+）一択となる。
  - `CGPreflightScreenCaptureAccess()` は OS の権限プロンプトを出さずに現在の許可状態のみを同期取得できるため、事前チェックと組み合わせることで「リスト型選択時は一切の権限確認・ダイアログ表示を行わない（FR-003）」を厳密に保証できる。
  - `SCScreenshotManager.captureImage` は `SCStreamConfiguration` 側で出力ピクセル解像度（例：カード枠の 2x Retina 相当、アスペクト比維持）を指定できるため、フル解像度画像を生成してから縮小するよりもメモリ消費・CPU負荷を大幅に抑えられる。
- **Alternatives Considered**:
  - `CGWindowListCreateImage`: macOS 14 以降非推奨であり、将来のビルドエラーや App Store 審査リスクがあるため不採用。
  - 常時 `SCStream` を立ち上げてバックグラウンドでフレーム受信し続ける方式: 常駐時の CPU・バッテリー・メモリ消費が増大し、憲章「起動と応答の高速性（ゼロレイテンシ）」と相反するため不採用。

## 2. オプトイン境界の厳格な分離（FR-003 準拠）

- **Decision**:
  - `SwitcherDisplayStyle` が `.list` の間、および `mode == .launcher` の間は、`ScreenRecordingPermissionServicing`（`CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`）および `WindowCaptureServicing`（`SCShareableContent` / `SCScreenshotManager`）を一切呼び出さない。
  - 設定画面（`SettingsView`）内の「画面収録権限」行および誘導メッセージは、`normalDisplayStyle == .capture` のときにのみ表示・評価する。
  - 設定が `.capture` から `.list` へ切り替えられた瞬間、メモリ内のキャプチャキャッシュを即時全消去する（`clearCache()`）。
- **Rationale**:
  - `SCShareableContent` へのアクセス自体が macOS 側で TCC の画面収録アクセス記録やプロンプトの契機となり得るため、呼び出し経路そのものをオプトイン条件で完全に遮断することでプライバシーとテスト容易性を両立できる。
- **Alternatives Considered**:
  - アプリ起動時にバックグラウンドで画面収録権限やサムネイルを事前取得・ウォームアップしておく方式: リスト型利用者に対しても不要な権限アクセスが発生し FR-003 および憲章原則1に違反するため不採用。

## 3. ゼロレイテンシ表示と非同期キャプチャ更新・セッション保護

- **Decision**:
  - 通常スイッチャーの起動時（`SwitcherViewModel.present(targetMode: .normal)`）、表示形式が `.capture` の場合でも**メインスレッドでキャプチャ完了を待機せず即座にパネルを表示**する。
  - 初期描画では、`WindowCaptureService` がメモリ上に保持している直前の一時キャッシュがあれば即時参照し、未キャッシュのウィンドウはアプリアイコン等のプレースホルダーを描画する。
  - パネル表示と同時に `presentationGeneration` をインクリメントして 1 つのバックグラウンド `Task` を起動し、`SCShareableContent` を 1 回だけ取得して各 `WindowEntry.cgWindowID` に対応する `SCWindow` を引き当て、`TaskGroup`（並列数上限付き、例：最大 4 並列）でサムネイルを非同期取得する。
  - 取得結果は 1 件または短時間バッチごとに `@MainActor` へ戻し、`mode == .normal && normalDisplayStyle == .capture && presentationGeneration == capturedGeneration` かつ対象ウィンドウがなお `displayedResults` に存在する場合のみ UI へ反映する。
- **Rationale**:
  - 数十枚ウィンドウが開かれている状態でも 100ms 以内にパネルと操作応答が出揃い（SC-001）、かつアクティブな操作スペース上の通常ウィンドウを 500ms 以内に最新キャプチャへ更新できる（SC-002）。
  - 世代カウンタとセッションキャンセルにより、素早い `Option + Tab` 一瞬押しや閉じ操作時の競合（古いタスク結果の誤反映）を確実に防げる（FR-013）。
- **Alternatives Considered**:
  - 起動前に同期または `await` で全キャプチャ取得を待つ方式: ウィンドウ数が多いと 200〜600ms 以上の引っかかりが生じ、憲章のゼロレイテンシ原則に反するため不採用。

## 4. メモリキャッシュ上限管理と取得不能ウィンドウ（最小化・別スペース等）の扱い

- **Decision**:
  - `WindowCaptureService` 内のメモリキャッシュは `cgWindowID: UInt32` をキーとし、最大件数（例：50 件）の LRU（最近使用順）方式で管理する。ディスク書き出しやログへの画像出力は一切行わない（FR-012）。
  - ウィンドウクローズ時（`closeSelectedWindow`）およびアプリ終了時は対象 `cgWindowID` のキャッシュを明示的に削除する。
  - `SCShareableContent.windows` に見つからない、または `SCScreenshotManager.captureImage` がエラーを返したウィンドウ（最小化中、別操作スペースで WindowServer が非表示扱い、保護コンテンツ等）についてはエラーを握りつぶして全体処理を継続し、既存キャッシュがあれば維持、なければプレースホルダー（アプリアイコン表示）へフォールバックする（FR-009）。
- **Rationale**:
  - 最小化・別スペースのウィンドウでも直前に表示していたときのキャッシュが残っていれば視覚的に識別しやすく、初回から未表示の場合でもアプリアイコン＋アプリ名＋ウィンドウタイトルのカードで確実に切り替えできる。
- **Alternatives Considered**:
  - キャプチャ失敗時にリスト項目から除外する／カードを表示しない方式: 切り替え可能なウィンドウまで見えなくなり、操作の信頼性を損なうため不採用。

## 5. グリッドレイアウトと 4 方向キーボードナビゲーション・動的パネルサイズ

- **Decision**:
  - グリッドの列数計算と上下左右移動ロジックは純粋関数群 `SwitcherGridLayout` として `Domain/` に配置し、単体テストで 100% 検証可能にする。
  - 1 枚のカードサイズは固定幅・固定高さ（例：幅 210pt、プレビュー領域 16:10 比率 190×118pt 相当＋下部メタ情報行、カード間隔 10pt、外側余白 14pt）とし、現在マウスカーソルがあるアクティブディスプレイの `visibleFrame` 幅（例：85% 上限）から最大列数 `maxColumns`（最低 1 列〜最大 5〜6 列程度）を算出する。実件数 `itemCount` が `maxColumns` 未満のときは `columns = itemCount` としてパネル幅を不要に広げない。
  - `ArrowDirection`（`HotKeyMonitoring.swift`）に `.left` / `.right` を追加し、`HotKeyMonitorService.resolveKeyDown` の `mode == .normal` でのみ仮想キーコード `123`（左矢印）と `124`（右矢印）を横取り消費する（`mode == .launcher` では検索欄のカーソル移動を妨げないよう従来通り透過する）。
  - `SwitcherPanel` はコンテンツサイズ変化（初期表示、ウィンドウクローズ、`Mod + Q` 後の再レイアウト、権限バナー表示）に応じて上端中央を基準にサイズを更新できる。
- **Rationale**:
  - 固定カードサイズ＋`SCStreamConfiguration` での一定上限サイズ取得により、縦長・横長・5K ウィンドウなど極端なウィンドウが混在してもグリッドが綺麗に揃い、かつ画像リサイズ負荷を最小化できる。
  - `mode == .normal` 限定で左右矢印を横取りすることで、既存のランチャー検索欄の文字カーソル操作と一切干渉しない。
- **Alternatives Considered**:
  - ウィンドウごとの実アスペクト比でカード幅を可変にする方式: 行内の縦横高さが揃わず、上下矢印キーでの列移動が直感的でなくなるため不採用（カード枠を統一し、その中で画像のみ `.aspectRatio(contentMode: .fit)` で表示する）。
