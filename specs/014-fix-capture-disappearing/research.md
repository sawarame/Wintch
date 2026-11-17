# Phase 0 リサーチ: キャプチャ表示型スイッチャーにおけるサムネイル消失の防止とキャッシュ整合性改善

**Feature**: `014-fix-capture-disappearing`  
**Date**: 2026-11-17  
**Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/014-fix-capture-disappearing/spec.md)  
**Related Issue**: [#16](https://github.com/sawarame/Wintch/issues/16)

## 1. コード精査および再現情報から特定した原因

Issue #16（「使っていると、スイッチャーにキャプチャされていたはずの画像が消えてアイコンになってしまうことがある。再度そのウィンドウを開くと無事キャプチャされる。」「しばらく使って多数のウィンドウを開閉した後に発生している感覚」）について、関連コード（`WindowCaptureService.swift`、`SwitcherViewModel.swift`、`WindowService.swift`、`SwitcherCaptureGridView.swift`）を精査し、以下の複合原因を特定した。

### 原因 A: 閉じ済みウィンドウによるキャッシュ枠の占有（破棄漏れ）
- **現状**: `WindowCaptureService.invalidateThumbnail(for:)` が呼ばれているのは `SwitcherViewModel.closeSelectedWindow()`（スイッチャー上の `Opt+Q` 操作）のみであり、通常のウィンドウ閉じ操作（`Cmd+W`、閉じるボタン、`Cmd+Q`、一時ダイアログのクローズ等）で消滅したウィンドウのキャッシュが一切解放されない。
- **影響**: 長時間の常駐利用で多数のウィンドウを開閉すると、既に閉じられたウィンドウの古いサムネイルが `maxCacheCount = 50` の枠を圧迫し、メモリを浪費すると同時に現在開いているウィンドウが押し出される原因となる。

### 原因 B: `SwitcherViewModel.present()` における LRU アクセス順の逆転
- **現状**: `SwitcherViewModel.present(targetMode: .normal)` は、MRU 順（インデックス `0` が最直近アクティブ、末尾が最古）の `sorted` を先頭から順に走査して `windowCaptureService.cachedThumbnail(for: windowID)` を呼び出している。
- **メカニズム**: `cachedThumbnail(for:)` は内部で `touchCacheOrder(for:)` を呼び出し、対象 ID を `cacheOrder` の末尾（最新位置）へ移動する。そのため `sorted[0]` から順に参照すると、最終的に **`sorted[0]`（最直近アクティブウィンドウ）が `cacheOrder` の先頭（次期追い出し対象）** に配置される。
- **影響**: キャッシュ上限を超えた状態で新規キャプチャ（`storeInCache`）が実行されると、MRU 上位（直近使っていたウィンドウ）から先に破棄され、一時的に別ウィンドウの裏や非表示・遅延状態にあるとアイコン表示へ劣化し、再度そのウィンドウを開くまで未取得状態が続く。

### 原因 C: `maxCacheCount = 50` の容量不足
- **現状**: `WindowCaptureService.maxCacheCount` が `50` 固定となっている。
- **影響**: 複数アプリ・ブラウザウィンドウ・ツールウィンドウを併用する開発作業等では 50 枚前後に達しやすく、死んだキャッシュの整理に加えて上限を 100 件へ引き上げても 1 枚あたり約 0.45 MB（432×270 RGBA 相当、100 枚で約 45 MB 以下）で収まるため、十分な余裕を持たせられる（Issue #16 で案 A として合意済み）。

### 原因 D: `WindowService.selectBestCGWindowMatch` における `cgWindowID` 連続性の脆弱性
- **現状**:
  1. `selectBestCGWindowMatch` の近接マッチ（`matchPriorityTuple`）では `continuityPriority`（前回の `preferredCGWindowID` 一致）が存在するものの、無名空き殻 CGWindow（`kCGWindowName == ""`）を劣後させる判定がないため、タイトル変更や一時読み取り欠損時に同位置の無名補助 CGWindow が選ばれるリスクがある。
  2. `containmentMatch`（`boundsDistance > 40.0` 時の包含判定フォールバック）には `preferredCGWindowID` の考慮と `nonEmptyName` の考慮が全く入っていないため、リサイズ・ツールバー開閉・フルスクリーン遷移等で包含判定に落ちた際、より大きい面積を持つ別 CGWindow や無名空き殻窓へ ID がすり替わってしまう。
- **影響**: 既存の `CachedAXWindow.cgWindowID` が別 ID に書き換わる（または欠落する）と、`WindowCaptureService` 側に元の ID でキャッシュが残っていても参照できずアイコン表示になる。再度そのウィンドウを開くと再照合・再キャプチャされて復帰する。

### 原因 E: 無効画像サイズに対する防衛的チェックの欠如
- **現状**: `WindowCaptureService.captureSingleWindow` は `SCScreenshotManager.captureImage` が返した `CGImage` の幅・高さを確認せず `.captured` としている。万一 `0x0` 等の空イメージが返った場合でもキャッシュを上書きしないようガードを入れておく必要がある。

---

## 2. 設計判断（Decisions & Alternatives）

### 判断 1: 生存ウィンドウ同期整理（`pruneCache`）の導入と上限 100 件化
- **Decision**:
  - `WindowCaptureServicing` に `pruneCache(keeping activeCGWindowIDs: Set<UInt32>)` を追加する。
  - `SwitcherViewModel.present(targetMode: .normal)` において `shouldUseCapture && isScreenRecordingGranted` が真のときのみ、キャッシュ取得前に `windowCaptureService.pruneCache(keeping: Set(sorted.compactMap(\.cgWindowID)))` を実行し、既に閉じられたウィンドウのキャッシュを即座に破棄する。
  - `WindowCaptureService` のデフォルト上限を `100`（`defaultMaxCacheCount = 100`）へ引き上げるとともに、テスト容易性のためイニシャライザで `maxCacheCount: Int = defaultMaxCacheCount` を注入可能にする。
- **Rationale**:
  - スイッチャーを起動するたびに死んだウィンドウのキャッシュが除去されるため、通常の開閉を繰り返しても有効なウィンドウが追い出されない。
  - 憲章原則 1（最小権限・オプトイン原則）に基づき、`.list` モード・`.launcher` モード・画面収録権限未許可時は `pruneCache` を含め `WindowCaptureService` を一切呼び出さない。
- **Alternatives considered**:
  - `NSWorkspace` / `AXUIElementDestroyedNotification` から常時 `WindowCaptureService` へ削除通知を飛ばす案 → `WindowService` と `WindowCaptureService` の結合度が上がり、`.list` 利用時にも連動処理が走る恐れがあるため、`SwitcherViewModel.present()` での明示的・オプトイン限定同期を採用。

### 判断 2: `SwitcherViewModel.present()` での逆順キャッシュ読み込みによる LRU 正順化
- **Decision**:
  - `SwitcherViewModel.present()` の初期サムネイル読み込みループを `for entry in sorted.reversed()` とし、MRU 最古（末尾）から最直近（先頭 `sorted[0]`）の順に `cachedThumbnail(for:)` を呼び出す。
- **Rationale**:
  - `cachedThumbnail(for:)` の `touchCacheOrder` の性質（呼ばれるたびに末尾＝最新保持位置へ移動）をそのまま活かし、プロトコルを複雑化することなく `cacheOrder` を MRU 正順（先頭＝最古、末尾＝最直近）に整列できる。
  - 上限 100 件を超える環境で新規キャプチャが発生しても、追い出されるのは MRU 最下位の古いウィンドウのみとなる。
- **Alternatives considered**:
  - LRU 順を更新しない `peekThumbnail(for:)` メソッドを別途増やす案 → 初期読み込み後に新しいウィンドウが追加された際、直近ウィンドウの鮮度が更新されない欠点があるため、`sorted.reversed()` による正順更新を採用。

### 判断 3: `WindowService.selectBestCGWindowMatch` の連続性・無名空き殻劣後強化
- **Decision**:
  - `matchPriorityTuple` に `nonEmptyNamePriority`（非空 `cgWindowName` なら `0`、空/`nil` なら `1`）を追加し、`(layerPriority, visibilityPriority, titleMatchPriority, continuityPriority, nonEmptyNamePriority, dist, entry.zOrder)` の順で比較する。
  - `containmentMatch` の比較にも `onscreenRank` → `titleRank` → `continuityRank`（`preferredCGWindowID` 一致）→ `nonEmptyNameRank` → `intersectionArea` の優先順を導入する。
- **Rationale**:
  - `continuityPriority` を `nonEmptyNamePriority` より上位に置くことで、既に正当な `cgWindowID` を持っているウィンドウがタイトル一時空化等でも ID を失わないようにしつつ、未確定時や乗り換え候補間では無名空き殻窓を確実に回避できる。
  - 画面収録権限がない環境では全 CGWindow の `name` が `nil` になるため `nonEmptyNamePriority` は引き分けとなり、既存挙動に一切悪影響を与えない。

### 判断 4: 無効サイズ画像のガード（FR-005）
- **Decision**:
  - `WindowCaptureService.captureSingleWindow` で取得した `CGImage` に対し `guard image.width > 0, image.height > 0 else { return .failed }` を検証し、万一の空画像で既存の有効キャッシュを上書きしない。
- **Rationale**:
  - 正常なキャッシュが異常結果で上書きされるリスクを排除する。
