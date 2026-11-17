# Phase 0 リサーチ: Chrome等のタブ全閉によるウィンドウ閉鎖後に空の表示が残る問題の修正

**Feature**: `019-fix-chrome-empty-ghost` | **Date**: 2026-11-18 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/.worktrees/Wintch-issue-27/specs/019-fix-chrome-empty-ghost/spec.md) | **Related Issue**: [#27](https://github.com/sawarame/Wintch/issues/27)

## 1. 実機計測・スクリーンショット解析から特定した根本原因

GitHub Issue #27（「chromeのタブをすべて閉じてウィンドウを閉じると（アプリは終了してない）、スイッチャーに空の表示が残ったままになり、選択しても何も起こらない状態になってしまう」）について、添付スクリーンショットのピクセル解析・実機稼働中の Google Chrome プロセス（`com.google.Chrome`）の `CGWindowListCopyWindowInfo` / `AXUIElement` / `AXMenuBar` ダンプ・および現行ソースコードの精査から、以下の複合原因を特定した。

### 原因 A: ウィンドウ全閉後（メニュー項目 0 件時）に画面外の無名空き殻 `CGWindow`（`cg-*`）が素通りする問題

- **実測事実**:
  - Issue #27 の添付スクリーンショットにおける `Google Chrome (タイトルなし)` カードのサムネイル領域（`170x95 = 16,150` ピクセル）を解析したところ、全 16,150 ピクセルが 100.00% 純白（`RGB(255, 255, 255)`）であり、タブバーやツールバーを一切持たない Chrome 内部のオフスクリーン空き殻 `CGWindow`（例: フルスクリーン遷移等に伴って生成される `1920x1042`, `layer=0`, `alpha=1.0`, `isOnscreen=false`, `kCGWindowName=""` や、オムニボックス予測変換用の `1344x378`, `isOnscreen=false`, `kCGWindowName=""`）であった。
  - Chrome で実ウィンドウが 1 枚以上開いている間は、Chrome の「ウィンドウ」メニューに `makeKeyAndOrderFront:` 項目が 1 件以上存在するため、`WindowService.enrichCandidatesWithWindowMenu` から `WindowMenuCandidatePairing.applyMenuTitles` が呼ばれ、メニュー項目数を超える裏方の無名 `cg-*` 候補はすべて余剰ゴーストとして除外されていた。
  - しかし、**Chrome のタブをすべて閉じて開いている実ウィンドウが 0 枚になると、Chrome の「ウィンドウ」メニュー内の `makeKeyAndOrderFront:` 項目も 0 件（`menuState.items.isEmpty == true`）になる**。
- **コード上の問題**:
  1. `WindowService.enrichCandidatesWithWindowMenu` が `!menuState.items.isEmpty` のときしか `applyMenuTitles` を呼ばず、`menuState.items` が空になると `group` をそのまま返していた。
  2. `AppWindowProfileRegistry.profilesByBundleIdentifier` に `"com.google.Chrome"` が登録されておらず、`defaultProfile`（`offscreenCGPolicy: .allow`）となっていたため、`WindowFilter.filterAndMap` でもタイトル未確定（`title == nil`）の画面外 `cg-*` 候補が除外されずに通過し、`Google Chrome (タイトルなし)` として表示されていた。

### 原因 B: 閉鎖済みウィンドウの `CachedAXWindow` が消滅済み `cgWindowID` チェック欠如により残留・空き殻 `CGWindow` へ乗り換える問題

- **コード上の問題**:
  - `WindowService.cleanupClosedWindows` は、今回の AX スキャン（`kAXWindowsAttribute` + `kAXFocusedWindowAttribute` + `kAXMainWindowAttribute`）に存在しないキャッシュ要素（`!cached.isPresentInLatestAXScan`）であっても、`AXUIElementCopyAttributeValue(cached.axElement, kAXRoleAttribute)` が `.success` を返す場合（Chromium 等で破棄直後の要素参照が一時的に応答する場合）や、`.cannotComplete` かつ `cgWindowID == nil` で裏方 `CGWindow` により `hasSubstantialCGWindow == true` となる場合に、キャッシュから除去せず残していた。
  - さらに、本来のウィンドウが閉じられて対応する `cached.cgWindowID` が WindowServer（`CGWindowListCopyWindowInfo`）上から既に消滅しているにもかかわらず、`cleanupClosedWindows` を生き残った `CachedAXWindow` が直後の `findMatchingCGWindow` で同サイズの無名空き殻 `CGWindow`（`kCGWindowName == ""`）と再マッチして `cgWindowID` を書き換え、ゾンビ項目として延命していた。

### 原因 C: ウィンドウ破棄時の「ウィンドウ」メニューキャッシュ（TTL 2.0 秒）未無効化

- **コード上の問題**:
  - `WindowService.handleAXNotification` で `kAXUIElementDestroyedNotification` を受信した際、`cachedWindowsByPID[pid]` から要素を削除するだけで `cachedWindowMenuByPID.removeValue(forKey: pid)` を実行しておらず、また `applyAXWindowSnapshots` でウィンドウ数が減少・0 件化した際にもメニューキャッシュを破棄していなかった。
  - そのため、最後のタブを閉じてから 2.0 秒（`windowMenuCacheTTL`）以内にスイッチャーを起動すると、閉じる前の古いメニュー項目（例: `"新しいタブ"`）がキャッシュから返され、裏方の空き殻 `CGWindow` に古いタイトルが割り当てられて一時的に残存する経路があった。

### 原因 D: 別スペースで「新しいタブ」等を開いている実 `AXWindow` の空タイトル未補完および別スペース遷移判定の不整合

- **実測事実**:
  - 別スペースのフルスクリーン等で Chrome の「新しいタブ」（`chrome://newtab/`）がアクティブになっている際、`kAXFocusedWindowAttribute` から取得した実 `AXWindow` の `kAXTitleAttribute` が `""`（空文字列）を返す一方、`CGWindow` の `kCGWindowName` および「ウィンドウ」メニューの `makeKeyAndOrderFront:` 項目には `"新しいタブ"` が保持されていることを確認した。
- **コード上の問題**:
  1. `WindowService.enrichCandidatesWithWindowMenu` の `targetPIDs` 抽出が `!candidate.hasAXInfo && WindowFilter.isValid(candidate)` のみに限定されていたため、未マッチの有効 `cg-*` 候補が存在しない（実ウィンドウが `hasAXInfo == true` として捕捉済みである）場合に `applyMenuTitles` が呼ばれず、`title == ""` のまま `(タイトルなし)` となっていた。
  2. また `WindowMenuCandidatePairing.applyMenuTitles` も `menuItems.isEmpty` のときに早期リターンしていたため、「ウィンドウ」メニュー項目を持たないアプリ（Chrome PWA 等）で `title` が空かつ `cgWindowName` が非空の `AXWindow` に対するタイトル補完が行われていなかった。
  3. さらに `WindowService.activateWindow` では、`kAXFocusedWindowAttribute` 経由で別スペースから捕捉されたウィンドウ（`isPresentInLatestAXScan == true` だが `entry.isOnScreen == false` かつ `!entry.isMinimized`）を `isPresentInCurrentSpace = true` と判定していたため、別スペースにあるにもかかわらずメニュー遷移および段階的フォローアップ（`usesSteppedSpaceFollowUp`）がスキップされるケースがあった。

---

## 2. 設計判断（Decisions & Alternatives）

### 判断 1: `AppWindowProfileRegistry` への `"com.google.Chrome"`（`.requireAXOrMenuTitle`）登録

- **Decision**: `AppWindowProfileRegistry.profilesByBundleIdentifier` に `"com.google.Chrome"` を追加し、`offscreenCGPolicy: .requireAXOrMenuTitle` を設定する。
- **Rationale**:
  - Chrome の実在する別スペースウィンドウは、`kAXFocusedWindowAttribute` / `kAXMainWindowAttribute` または訪問済みキャッシュにより `hasAXInfo == true` となるか、未訪問の 2 枚目以降であっても Chrome の「ウィンドウ」メニュー（`makeKeyAndOrderFront:`）から必ずタイトルが補完される。
  - 一方、タブ・ウィンドウをすべて閉じた後やメニュー項目数を超過して画面外に残る無名の空き殻 `CGWindow`（`!hasAXInfo`, `isOnScreen != true`, `title == nil`）は `.requireAXOrMenuTitle` によって `WindowFilter.filterAndMap` で 100% 除外される。
- **Alternatives considered**:
  - 空き殻 `CGWindow` のサイズ（`1920x1042` や `1344x378`）を `HiddenBackingWindowSignature` で固定登録する案 → ディスプレイ解像度やスケーリング設定によってサイズが変化するため不十分。`.requireAXOrMenuTitle` であれば画面解像度に依存せずすべての無名オフスクリーン裏方窓を除外できる。

### 判断 2: `cleanupClosedWindows` における消滅済み `cgWindowID` 判定の厳格化（純粋関数 `shouldRetainCachedAXWindow`）

- **Decision**:
  - `WindowService.shouldRetainCachedAXWindow` を純粋静的メソッドとして定義する。
  - 今回の AX スキャンに存在しないキャッシュ要素（`!isPresentInLatestAXScan`）について、前回確定済みの `knownCGWindowID` が現在の `CGWindowListCopyWindowInfo`（`survivingCGWindowIDs`）に存在しない場合は、WindowServer 上で既に破棄されたウィンドウであるため、AX 属性読み取りの成否に関わらず即座にキャッシュから除去する。
  - また、`axRoleCheckResult == .cannotComplete` かつ `knownCGWindowID == nil` の場合も、`isPresentInLatestAXScan` が `false` であれば裏方 `CGWindow` の存在だけで延命させず除去する。
- **Rationale**:
  - macOS の `CGWindowID` はウィンドウ生成からクローズまで不変であり、`CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements])` は全スペースの生存ウィンドウを網羅する。したがって `!isPresentInLatestAXScan` かつ既知の `CGWindowID` が消滅していれば 100% クローズ済みと断定でき、閉じたウィンドウが裏方の空き殻 `CGWindow` に乗り換えてゾンビ化する経路を根絶できる。
- **Alternatives considered**:
  - `!isPresentInLatestAXScan` のキャッシュを無条件で全削除する案 → 別スペースに 2 枚以上のウィンドウがある場合に 2 枚目以降の AX 参照が失われるため不採用。

### 判断 3: ウィンドウ破棄イベントおよびウィンドウ減少時のメニューキャッシュ即時無効化

- **Decision**:
  - `handleAXNotification` で `kAXUIElementDestroyedNotification` を受信した際、`cachedWindowMenuByPID.removeValue(forKey: pid)` を呼び出してメニューキャッシュを即時破棄し、デバウンス付きバックグラウンド更新をスケジュールする。
  - `applyAXWindowSnapshots` において、スナップショットが空になった場合や既存キャッシュに今回スキャン不在要素が発生した場合にも `cachedWindowMenuByPID.removeValue(forKey: pid)` を行う。
- **Rationale**:
  - ウィンドウを閉じた直後（2.0 秒の TTL 以内）にスイッチャーを起動した場合でも、確実に最新の「ウィンドウ」メニュー（0 件）が再取得され、閉じる前の古いタイトルが裏方 `CGWindow` に付与されるのを防げる。

### 判断 4: 空タイトルの標準 AX 候補に対するメニュー／`cgWindowName` 補完の適用と別スペース在籍判定の適正化

- **Decision**:
  1. `WindowMenuCandidatePairing.needsMenuEnrichment(_ candidate: RawWindowCandidate) -> Bool` を追加し、有効な `!candidate.hasAXInfo` 候補だけでなく、`isMenuTrackedAXWindow(candidate)` かつ `title` が空の AX 候補も `enrichCandidatesWithWindowMenu` の対象 PID に含める。
  2. `WindowMenuCandidatePairing.applyMenuTitles` において、`menuItems` が空の場合でも、タイトルが空の標準 AX 候補に対して非空の `cgWindowName` があれば補完を適用する。
  3. `WindowService.isWindowInCurrentSpace(isPresentInLatestAXScan:isOnScreen:isMinimized:)` を導入し、`isOnScreen == false && !isMinimized`（別スペースの非最小化ウィンドウ）の場合は `isPresentInLatestAXScan == true`（`kAXFocusedWindowAttribute` 由来）であっても現在スペース不在（`false`）と判定してメニュー遷移＋段階的フォローアップを実行する。
- **Rationale**:
  - 別スペースのフルスクリーン Chrome で「新しいタブ」を開いている際や Chrome PWA 等で `kAXTitleAttribute` が空文字列を返す場合でも、`(タイトルなし)` にならず正しいタイトルが表示され、選択時の別スペース遷移も確実に成功する。
