# Phase 1 データモデル設計: Chrome等のタブ全閉によるウィンドウ閉鎖後に空の表示が残る問題の修正

**Feature**: `019-fix-chrome-empty-ghost` | **Date**: 2026-11-18

## 1. ドメインモデルおよびレジストリ拡張

### 1.1 `AppWindowProfileRegistry` (`Sources/WintchCore/Domain/AppWindowProfile.swift`)

既存の `AppWindowProfile` / `OffscreenCGFallbackPolicy` 構造体をそのまま活用し、`profilesByBundleIdentifier` に Google Chrome のプロファイル定義を追加する。

| キー (`bundleIdentifier`) | `offscreenCGPolicy` | `hiddenBackingSignatures` | 役割・制約 |
|---|---|---|---|
| `"com.google.Chrome"` | `.requireAXOrMenuTitle` | `[]` | ウィンドウ全閉後やバックグラウンド動作中に画面外（`isOnScreen != true`）に残存する無名の空き殻・補助 `CGWindow`（`!hasAXInfo` かつタイトル未確定）を除外し、AX または「ウィンドウ」メニューで実在が確認されたウィンドウのみを通過させる。 |

### 1.2 `WindowMenuCandidatePairing` (`Sources/WintchCore/Domain/WindowMenuPairing.swift`)

#### 追加・拡張する純粋関数

- **`needsMenuEnrichment(_ candidate: RawWindowCandidate) -> Bool`**
  - **入力**: `candidate: RawWindowCandidate`
  - **出力**: `Bool`
  - **判定規則**:
    - `WindowFilter.isValid(candidate)` が `true` であること。
    - `!candidate.hasAXInfo`（AX 未捕捉の `cg-*` 候補）、または `isMenuTrackedAXWindow(candidate)` かつ `candidate.title`（トリム後）が空であること。
- **`applyMenuTitles(to candidates: [RawWindowCandidate], menuItems: [WindowMenuItemSnapshot]) -> [RawWindowCandidate]`**
  - **拡張規則**:
    - `menuItems` が空（`menuItems.isEmpty`）の場合であっても、`axCandidates` 内の標準ウィンドウ（`isMenuTrackedAXWindow`）で `title` が空かつ `cgWindowName` が非空の候補に対しては、`cgWindowName` によるタイトル補完を適用してから返す。

---

## 2. サービス層内部モデルおよび純粋判定ヘルパー

### 2.1 `WindowService` (`Sources/WintchCore/Services/WindowService.swift`)

#### 追加する純粋判定メソッド

- **`shouldRetainCachedAXWindow(isPresentInLatestAXScan: Bool, knownCGWindowID: UInt32?, axRoleCheckResult: AXError, survivingCGWindowIDs: Set<UInt32>, hasSubstantialCGWindow: Bool) -> Bool`**
  - **目的**: `cleanupClosedWindows` において、キャッシュ済み `CachedAXWindow` を維持すべきか破棄すべきかを決定する。
  - **検証・遷移ルール**:
    1. `!isPresentInLatestAXScan` かつ `let knownID = knownCGWindowID` のとき、`!survivingCGWindowIDs.contains(knownID)` であれば `false`（WindowServer 上で対応ウィンドウが消滅済みのため破棄）。
    2. `axRoleCheckResult == .success` の場合は `true`（生存または別スペース在籍として保持）。
    3. `axRoleCheckResult == .cannotComplete` の場合：
       - `let knownID = knownCGWindowID` があれば `survivingCGWindowIDs.contains(knownID)`。
       - `knownCGWindowID == nil` であれば `isPresentInLatestAXScan && hasSubstantialCGWindow`（最新 AX スキャンに不在かつ `cgWindowID` 未確定の要素を裏方 `CGWindow` だけで延命しない）。
    4. 上記以外の `AXError`（`.invalidUIElement` 等）は `false`（破棄）。

- **`isWindowInCurrentSpace(isPresentInLatestAXScan: Bool, isOnScreen: Bool?, isMinimized: Bool) -> Bool`**
  - **目的**: `activateWindow` において、対象ウィンドウが現在の操作スペース上に存在するか（または別スペースへのメニュー遷移＋段階的フォローアップが必要か）を判定する。
  - **判定ルール**:
    1. `isPresentInLatestAXScan == false` なら `false`。
    2. `isOnScreen == false && !isMinimized`（非最小化かつ画面外＝別操作スペース上の `kAXFocusedWindow` / `kAXMainWindow` 補完ウィンドウ）なら `false`。
    3. それ以外は `true`。
