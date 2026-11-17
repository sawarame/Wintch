# コントラクト定義: ウィンドウ閉鎖時のキャッシュ整理・画面外空き殻除外・タイトル補完

**Feature**: `019-fix-chrome-empty-ghost` | **Date**: 2026-11-18

## 1. ドメイン層コントラクト

### 1.1 `AppWindowProfileRegistry.profile(for: "com.google.Chrome")`

- **事前条件**: `bundleIdentifier == "com.google.Chrome"`
- **事後条件**:
  - `offscreenCGPolicy == .requireAXOrMenuTitle` を返す。
  - `WindowFilter.filterAndMap` において、`bundleIdentifier == "com.google.Chrome"` かつ `hasAXInfo == false` かつ `isOnScreen != true` であり、`title`（前後空白除去後）が空の `RawWindowCandidate` はすべて除外される。
  - メニュー補完等により非空の `title` が確定した別スペース候補、および `hasAXInfo == true` の実ウィンドウ候補は保持される。

### 1.2 `WindowMenuCandidatePairing.needsMenuEnrichment(_ candidate: RawWindowCandidate) -> Bool`

- **事後条件**:
  - `WindowFilter.isValid(candidate) == false` の場合は常に `false`。
  - `candidate.hasAXInfo == false`（有効な `cg-*` 候補）の場合は `true`。
  - `candidate.hasAXInfo == true` かつ非フローティング標準ウィンドウであり、`candidate.title`（トリム後）が空の場合は `true`。
  - すでに非空の `candidate.title` を持つ `hasAXInfo == true` 候補、またはフローティングウィンドウの場合は `false`。

### 1.3 `WindowMenuCandidatePairing.applyMenuTitles(to:menuItems:)`

- **事後条件**:
  - `menuItems` が空配列 `[]` の場合でも、`candidates` 内の標準 AX ウィンドウ（`hasAXInfo == true`）で `title` が空かつ `cgWindowName` が非空のものには `cgWindowName` が `title` として補完される。
  - `menuItems` が非空の場合は、従来通り未消費メニュー項目または `cgWindowName` から空タイトル AX 候補を補完し、残余のメニュー容量（`remainingMenuCapacity`）の範囲内で有効な `cg-*` 候補へタイトルを割り当て、余剰の `cg-*` 候補を除外する。

---

## 2. サービス層コントラクト (`WindowService`)

### 2.1 `WindowService.shouldRetainCachedAXWindow(...) -> Bool`

- **入力**:
  - `isPresentInLatestAXScan: Bool`
  - `knownCGWindowID: UInt32?`
  - `axRoleCheckResult: AXError`
  - `survivingCGWindowIDs: Set<UInt32>`
  - `hasSubstantialCGWindow: Bool`
- **事後条件**:
  - `!isPresentInLatestAXScan` かつ `knownCGWindowID != nil` かつ `!survivingCGWindowIDs.contains(knownCGWindowID!)` のとき、常に `false` を返す（`axRoleCheckResult == .success` であっても保持しない）。
  - `!isPresentInLatestAXScan` かつ `knownCGWindowID == nil` かつ `axRoleCheckResult == .cannotComplete` のとき、常に `false` を返す。

### 2.2 ウィンドウ破棄・減少時のメニューキャッシュ整合性

- **事後条件**:
  - `kAXUIElementDestroyedNotification` 受信時、および `applyAXWindowSnapshots` でスナップショットが空またはスキャン不在要素が生じた際、該当 `pid` の `cachedWindowMenuByPID[pid]` は即座に無効化される。

### 2.3 `WindowService.isWindowInCurrentSpace(...) -> Bool`

- **事後条件**:
  - `isPresentInLatestAXScan == true` であっても、`isOnScreen == false && !isMinimized`（別操作スペース上の非最小化ウィンドウ）であれば `false` を返し、`activateWindow` においてメニュー遷移と段階的スペースフォローアップを実行させる。
