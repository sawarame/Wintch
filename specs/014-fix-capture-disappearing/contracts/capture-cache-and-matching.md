# 契約定義: キャプチャキャッシュ同期・LRU 正順維持・CGWindow 照合安定化

**Feature**: `014-fix-capture-disappearing`  
**Date**: 2026-11-17

## 1. `WindowCaptureServicing` プロトコル契約

`Sources/WintchCore/Services/Protocols/WindowCaptureServicing.swift`

追加メソッド:
```swift
/// 現在開いている有効ウィンドウ ID 集合に含まれない閉じ済みウィンドウのキャッシュを破棄する
/// - Parameter activeCGWindowIDs: 現在生存しているウィンドウの CoreGraphics ウィンドウ ID 集合
func pruneCache(keeping activeCGWindowIDs: Set<UInt32>)
```

- **事前条件**: キャプチャ表示型（`normalDisplayStyle == .capture`）かつ画面収録権限が許可されている通常スイッチャー起動文脈でのみ呼び出す（`.list` 時・`.launcher` 時・権限未許可時は呼び出し禁止）。
- **事後条件**: `activeCGWindowIDs` に含まれないエントリはすべて破棄され、`activeCGWindowIDs` に含まれる既存キャッシュおよびそれらの相対 LRU 順序は保持される。

## 2. `WindowCaptureService` 契約

`Sources/WintchCore/Services/WindowCaptureService.swift`

- `public static let defaultMaxCacheCount = 100`
- `public init(screenRecordingPermissionService: (any ScreenRecordingPermissionServicing)? = nil, maxCacheCount: Int = defaultMaxCacheCount)`
  - `maxCacheCount` は `max(maxCacheCount, 1)` に正規化する。
- `captureSingleWindow`:
  - `image.width > 0 && image.height > 0` の場合のみ `.captured` を返し、サイズ 0 の無効画像は `.failed` として既存キャッシュを上書きしない。

## 3. `SwitcherViewModel` 契約

`Sources/WintchCore/ViewModels/SwitcherViewModel.swift`

- `present(targetMode: .normal)` における `shouldUseCapture && granted` 分岐内:
  1. `let activeWindowIDs = Set(sorted.compactMap(\.cgWindowID))`
  2. `windowCaptureService.pruneCache(keeping: activeWindowIDs)` を実行
  3. `for entry in sorted.reversed()` で `cachedThumbnail(for:)` を参照して `initialThumbnails` を構築（`sorted[0]` が `cacheOrder` の最新位置＝末尾に残る）
- `shouldUseCapture == false` または `granted == false` の場合、`pruneCache` も `cachedThumbnail` も `captureThumbnails` も一切呼ばない。

## 4. `WindowService` 契約

`Sources/WintchCore/Services/WindowService.swift`

- `selectBestCGWindowMatch(...)`:
  - 近接マッチ (`matchPriorityTuple`) において `continuityPriority` の直後に `nonEmptyNamePriority` を適用し、タイトル一時不一致時に無名空き殻 CGWindow より非空タイトル付き CGWindow を優先する。
  - 包含マッチ (`containmentMatch`) において `onscreenRank` → `titleRank` → `continuityRank` → `nonEmptyNameRank` → `intersectionArea` の順で比較し、既存 `preferredCGWindowID` の連続性と無名空き殻窓の劣後を保証する。
