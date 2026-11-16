# Phase 0 リサーチ: 複数ウィンドウを持つブラウザ（Chrome 等）の正確な切り替えと一覧・キャプチャ整合性の確保

**Branch**: `012-fix-chrome-window-switch` | **Date**: 2026-11-17 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/012-fix-chrome-window-switch/spec.md)

## 1. 実機・コード調査から特定した根本原因

GitHub Issue #13（Chrome で複数ウィンドウを開いているとき、スイッチャー／ランチャーに表示されるが、キャプチャが取れない状態になっており、選択しても別の Chrome ウィンドウに移動してしまう）について、現行実装および実機で稼働中の Google Chrome（PID `1871`）の `CGWindowListCopyWindowInfo` / `AXUIElement` / `AXMenuBar` の状態を精査し、以下の連鎖的な原因を特定した。

### 原因 A: Chrome の非表示内部補助 CGWindow によるタイトル奪取とキャプチャ不能化

- **実測事実**: 稼働中の Google Chrome に対して `CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements])` を確認したところ、Chrome は 1 つのウィンドウに対しても複数の `CGWindow`（ツールバー／タブバー分離パーツやアドレスバー予測変換用の補助ウィンドウ等）を `layer=0, alpha=1.0, isOnscreen=false` として保持している。実機では本体ウィンドウ `wid=111`（`bounds=(0, 88, 1920, 992)`, index `54`）よりも手前の Z オーダーに、予測変換系と思われる `wid=125`（`bounds=(99, 26, 1344, 178)`, index `31`）が存在していた。
- **コード上の問題**: [WindowFilter.swift](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/Domain/WindowFilter.swift#L333-L343) の横長ストリップ除外は `height < 300 && width / height > 6.0` が閾値であるため、予測候補が増えて高さが 225pt 以上（既存テスト [WindowMenuPairingTests.swift](file:///Users/sawarame_yasushi/dev/Wintch/Tests/WintchCoreTests/WindowMenuPairingTests.swift#L200-L209) でも想定されている `1344x378` 等）になると `WindowFilter.isValid` を通過する。さらに [WindowMenuCandidatePairing.applyMenuTitles](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/Domain/WindowMenuPairing.swift#L173-L192) の `cgCandidatePriority` は `(isOnScreen, layer, zOrderIndex)` のみで並び替えるため、Z オーダー上位の補助 CGWindow に「ウィンドウ」メニューのタイトルが割り当てられ、本物の CGWindow がペア数超過で除外される。
- **症状への影響**: 補助 CGWindow は描画実体のない非表示ポップアップであるため [WindowCaptureService](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/Services/WindowCaptureService.swift#L208-L236) でサムネイル取得に失敗し、プレースホルダー表示（キャプチャが取れない状態）となる。

### 原因 B: 同位置・同サイズの別スペース通常ウィンドウのキャッシュ誤削除

- **コード上の問題**: [WindowService.applyAXWindowSnapshots](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/Services/WindowService.swift#L750-L787) および [isReplacedTabBounds](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/Services/WindowService.swift#L1306-L1338) は、ディスプレイ占有級（画面幅 95% 以上かつ高さ 85% 以上）に満たない通常ウィンドウについて、前回捕捉したウィンドウが今回の `kAXWindowsAttribute` スキャンから消え、かつ同一矩形の別ウィンドウが現在スペースにある場合、`allowDisplaySpanningReplacement == false` の全体再スキャン時であっても「旧タブが置換された」とみなしてキャッシュ（`CachedAXWindow`）から削除する。
- **症状への影響**: 異なる操作スペースに同じ位置・同じサイズの Chrome ウィンドウ（フルスクリーン未満の最大化など）を開いていると、スペース移動やスイッチャー起動時の `scanAllRegularApps()` で別スペース側の `AXUIElement` と `cgWindowID` が破棄され、`cg-*` 補完候補へ降格して原因 A・C の影響を受けやすくなる。

### 原因 C: 別スペース／`cg-*` ウィンドウに対する `activateWindow` のメニュー遷移失敗と前面化競合

上記原因 A・B 等で「キャプチャが取れない状態」にあるウィンドウの多くは `targetAX == nil`（`cg-*` 候補）または `isPresentInLatestAXScan == false`（別スペース不在）である。この状態で [WindowService.activateWindow](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/Services/WindowService.swift#L375-L425) が呼ばれると、以下の 3 点が重なり別の Chrome ウィンドウへ遷移する。

1. **メニューキャッシュの TTL 無視とエラー未検証**: [resolveWindowMenuItemElement](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/Services/WindowService.swift#L1504-L1514) が `cachedWindowMenuByPID[pid]` の経過時間（`fetchedAt`）を確認せずに古い `AXUIElement` 参照を返し、`AXUIElementPerformAction(menuItemElement, kAXPressAction)` の戻り値 `AXError` も検査しないため、メニュー再構築後の無効参照で失敗したまま次の処理へ進んでしまう。
2. **メニュー押下直後の無待機 `app?.activate(options: [])` との競合**: メニュー項目の `kAXPressAction` を実行した同一同期処理内で即座に `app?.activate(options: [])` を呼び出しているため、Chrome 側がメニュー経由の対象ウィンドウ前面化／スペース遷移を完了する前に OS が現在スペース上（または直近アクティブ）の別ウィンドウをアクティブ化してしまう。さらに 80ms 後のフォローアップスキャンは macOS のスペース切り替えアニメーション（約 300〜500ms）完了前に終わることがある。
3. **タイトル照合ロジックの制約と重複タイトル選択**: [WindowMenuCandidatePairing.matchesEllipsisPattern](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/Domain/WindowMenuPairing.swift#L306-L320) が `components(separatedBy: separator)` で `parts.count == 2`（省略記号がちょうど 1 個のみ）を要求しているため、ページタイトル自体に `…` や `...` が含まれるとメニュー上の省略タイトルと一致しない。また同一タイトルのウィンドウが複数ある場合に `first(where:)` が現在スペース側（チェックマーク付き）を誤選択する可能性がある。

## 2. 設計判断（Decisions & Alternatives）

### 判断 1: `cg-*` 候補ペアリングにおける「実ウィンドウらしさ」優先度の導入

- **Decision**: `WindowMenuCandidatePairing.cgCandidatePriority` において、`onScreenPriority`・`layerPriority` に続き、横長扁平な補助ウィンドウらしき矩形（例: `height < 420 && width / height > 3.0`、かつ `WindowFilter` 上の純粋ストリップ除外だけでなくペアリング順位上の明確な劣後扱い）を通常のブラウザ／アプリウィンドウ矩形より劣後に並べ替える。また、すでに他ウィンドウの標準領域に完全に内包されるオフスクリーン小片等も不必要に優先されないよう設計する。
- **Rationale**: Chrome の予測変換ウィンドウはディスプレイ幅やウィンドウ幅に応じて幅・高さが変動するため（例: `1344x178` 〜 `1344x378`）、固定ピクセルのハードコード除外だけでは不十分。横長扁平なオフスクリーン候補を「完全除外」ではなく「ペアリング順位で実ウィンドウより劣後」にすることで、ユーザーが本当に細長いウィンドウを 1 枚だけ開いている場合でも誤除外せず、本物のブラウザウィンドウが存在するときにタイトルを奪われる事故を確実に防げる。
- **Alternatives considered**:
  - `com.google.Chrome` 専用の `1344x378` 固定シグネチャを追加する案 → 解像度・ウィンドウ幅が変わると無効化されるため不採用。
  - `WindowFilter` の `maxToolbarAspectRatio` を一律 `3.0` に厳格化する案 → 細長いターミナル等を誤除外するリスクがあるため、ペアリング順位での劣後化を主軸とし安全性を優先。

### 判断 2: `isReplacedTabBounds` による別スペース同矩形ウィンドウの誤削除防止

- **Decision**: [WindowService.applyAXWindowSnapshots](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/Services/WindowService.swift#L750-L787) での旧タブ除去判定において、スペース移動直後や全体スキャン時（`allowDisplaySpanningReplacement == false`）に通常ウィンドウの同矩形キャッシュを無条件削除する挙動を改め、(1) 同一スペース内のウィンドウ更新イベント由来であること（`allowDisplaySpanningReplacement == true`）、かつ (2) 削除対象候補が現在もシステム上に独立して生存している別の CGWindow（新ウィンドウに割り当てられたものとは異なる有効 CGWindowID、または再照合可能な別 CGWindow）を持たない場合にのみ旧タブとして置換除去する。
- **Rationale**: 別スペースに同位置・同サイズの Chrome ウィンドウがある場合、両者は別々の `cgWindowID` として CGWindow 一覧上に生存している一方、同一ウィンドウ内のタブ切り替えでは旧タブ固有の独立 CGWindow が別個に残存することはない。生存確認を組み合わせることで、同一スペース内タブ切り替えの重複整理を維持したまま、別スペース同矩形ウィンドウの誤削除をゼロにできる。
- **Alternatives considered**:
  - 通常ウィンドウでも一切置換削除しない案 → Finder 等のタブ切り替えで旧タブのゴーストが残る退行を起こすため不採用。

### 判断 3: `resolveWindowMenuItemElement` の鮮度管理・未チェック優先照合・`AXError` 時リトライ

- **Decision**:
  1. `WindowMenuCandidatePairing` にメニュー項目選択用の純粋関数（`selectMatchingMenuItemIndex`）を追加し、`needsMenuNavigation == true`（別スペース等）の場合は **未チェック項目（`!isChecked`）を優先** してタイトル照合し、見つからない場合に全項目へフォールバックする。
  2. `titlesMatch` の `matchesEllipsisPattern` を複数セグメント対応（`…` / `...` が 2 個以上含まれる場合も先頭・中間・末尾の順序一致かつ非ワイルドカード文字数 4 文字以上で一致判定）へ拡張する。
  3. `resolveWindowMenuItemElement` は `windowMenuCacheTTL`（2.0 秒）を超過した古いキャッシュを使用せず最新メニューを取得し、`AXUIElementPerformAction(..., kAXPressAction)` が `.success` 以外を返した場合はキャッシュを破棄して最新メニューを再取得し 1 回だけリトライする。
- **Rationale**: 同名タイトル（例:「新しいタブ」）が現在スペースと別スペースにある場合でも未チェック項目を優先すれば別スペース側を的確に押せる。また TTL チェックと失敗時リトライにより古い `AXUIElement` による無言失敗を防げる。
- **Alternatives considered**:
  - 毎回 `fetchRawWindowCandidates()` ごとにメニューを強制同期取得する案 → 一覧表示のゼロレイテンシ性を損なうため、確定操作時（`activateWindow`）のみ鮮度を担保する方針を採用。

### 判断 4: `activateWindow` における非競合の前面化シーケンスと段階的フォローアップ

- **Decision**:
  - **同一スペースかつキャッシュあり（`targetAX != nil && isPresentInCurrentSpace`）の場合**: `raiseAXWindow` と `app?.activate(options: [])` を従来通り即時実行して体感遅延ゼロを維持する。
  - **別スペース遷移が必要（`needsMenuNavigation == true`）な場合**:
    1. 前回の未完了フォーカス確定タスク（`pendingActivationFollowUpTask`）があればキャンセルする（連続操作時の競合防止）。
    2. メニュー項目による `AXPress`（失敗時はリフレッシュ後リトライ）が成功した場合は、**即時に `app?.activate(options: [])` を並列実行せず**、メニューアクションによるスペース移動を阻害しない。メニュー項目が解決できなかったか押下に失敗した場合のみフォールバックとして `app?.activate(options: [])` を即時実行する。
    3. 非同期フォローアップタスクで段階的（例: `60ms`, `140ms`, `280ms`, `450ms` 相当のポーリング間隔）にバックグラウンド AX スナップショットを取得し、対象ウィンドウが現在スペースに現れた（または最大待機時間に達した）時点で、対象アプリが未アクティブであれば `app?.activate(options: [])` を実行し、最後に `raiseAXWindow` と MRU 時刻更新を行う。
- **Rationale**: `kAXPressAction` で Chrome にウィンドウ／スペース切り替えを指示した直後に `app?.activate(options: [])` を同期呼び出しする競合を排除することで、OS が現在スペースの別ウィンドウへフォーカスを奪う現象を防ぐ。同時に、メニュー押下のみでアプリ自体がアクティブにならなかったケースでも、スペース遷移後に `app?.activate()` と `raiseAXWindow` で確実にフォーカスを確定できる。
- **Alternatives considered**:
  - 固定で 500ms スリープした後に `app?.activate()` を 1 回呼ぶ案 → スペース移動不要／高速完了時に体感遅延が生じるため、早期検知可能な段階的ポーリングを採用。
