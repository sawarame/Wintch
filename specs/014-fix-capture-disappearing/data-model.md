# データモデル・状態遷移設計 (Data Model): キャプチャキャッシュと識別連続性

**Feature**: `014-fix-capture-disappearing`  
**Date**: 2026-11-17  
**Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/014-fix-capture-disappearing/spec.md)

## 1. エンティティと不変条件

### 1.1 WindowCaptureThumbnailCache（`WindowCaptureService` 内部状態）

| 属性 | 型 | 説明 | 不変条件 |
|---|---|---|---|
| `maxCacheCount` | `Int` | 保持上限件数（既定値 `100`） | `>= 1`、`thumbnailCache.count <= maxCacheCount` |
| `thumbnailCache` | `[UInt32: NSImage]` | `cgWindowID` キーの縮小サムネイルマップ | キー集合は `Set(cacheOrder)` と完全一致 |
| `cacheOrder` | `[UInt32]` | LRU 順序配列（`first` が最古、`last` が最新） | 重複なし、件数 `<= maxCacheCount` |
| `invalidatedWindowIDsDuringCapture` | `Set<UInt32>` | キャプチャ中に明示無効化・整理された ID 集合 | 完了コールバック時に含まれていれば反映・格納しない |

#### 状態遷移

1. **スイッチャー表示前整理（`pruneCache(keeping: activeIDs)`）**:
   - `activeIDs` に含まれない全キーを `thumbnailCache` と `cacheOrder` から削除し、進行中キャプチャの誤混入を防ぐため `invalidatedWindowIDsDuringCapture` へ追加する。
   - `activeIDs` に含まれるエントリの相対順序は維持される。
2. **初期プレビュー読み込み（`SwitcherViewModel.present()`）**:
   - `sorted`（MRU 先頭=最新, 末尾=最古）の **逆順（`sorted.reversed()`）** で `cachedThumbnail(for:)` を呼び出す。
   - 各呼び出しで `touchCacheOrder(for:)` が実行され、`sorted[last]` → ... → `sorted[0]` の順に末尾へ送られるため、`cacheOrder` は `[最古 ..., 最直近]` の正順に整列される。
3. **非同期キャプチャ完了格納（`storeInCache(_:for:)`）**:
   - `cgImage.width > 0 && cgImage.height > 0` を満たす画像のみ受け付ける。
   - `cacheOrder` の末尾へ格納し、`cacheOrder.count > maxCacheCount` の間のみ `cacheOrder.removeFirst()`（最古＝MRU 最下位）を破棄する。
   - 失敗・タイムアウト時は何もしない（既存キャッシュを保持する）。

### 1.2 WindowIdentityContinuity（`WindowService.selectBestCGWindowMatch`）

`CachedAXWindow` と `CGWindowMeta` の対応付けにおける優先順位モデル（値が小さいほど優先 / Rank が大きいほど優先）。

#### 近接一致（`boundsDistance <= 40.0` かつ `dist <= minDist + 4.0`）

比較タプル（昇順優先）:
1. `layerPriority`: `layer == 0` (`0`) < その他 (`1`)
2. `visibilityPriority`: 表示状態一致 (`0`) < 不一致 (`1`)
3. `titleMatchPriority`: `doesCGWindowNameMatchTitle` 一致 (`0`) < 不一致 (`1`)
4. `continuityPriority`: `windowID == preferredCGWindowID` (`0`) < 不一致 (`1`)
5. `nonEmptyNamePriority`: 非空 `cgWindowName` (`0`) < 空または `nil` (`1`)
6. `dist`: マンハッタン距離（小さいほど優先）
7. `zOrder`: システム Z オーダー（小さいほど優先）

#### 包含フォールバック一致（`containmentMatch`）

`intersectionArea / cgArea >= 0.85` かつ `intersectionArea / axArea >= 0.5` を満たす候補から以下を降順（大きい方が優先）で比較:
1. `onscreenRank`: `preferOnscreen && isOnscreen` (`1` > `0`)
2. `titleRank`: `doesCGWindowNameMatchTitle` 一致 (`1` > `0`)
3. `continuityRank`: `windowID == preferredCGWindowID` (`1` > `0`)
4. `nonEmptyNameRank`: 非空 `cgWindowName` (`1` > `0`)
5. `intersectionArea`: 交差面積が大きい候補を優先
