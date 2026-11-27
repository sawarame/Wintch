import Foundation

/// バックグラウンドでのサムネイル一括取得・イベント駆動更新・定期更新に関する
/// 対象ウィンドウ選定、鮮度（クールダウン）判定、契機マージを行う純粋ドメインポリシー
public enum WindowCaptureRefreshPolicy {
    /// バックグラウンド再取得における既定の最小再取得間隔（クールダウン秒数）
    public static let defaultRefreshCooldown: TimeInterval = 5.0

    /// 定期バックグラウンド更新の既定間隔
    public static let defaultPeriodicRefreshInterval: Duration = .seconds(15)

    /// 指定された事前取得契機が、デバウンス待ちなしの起動時・切替時全ウィンドウ一括取得対象かを判定する
    /// - Parameter reason: 判定対象の事前取得契機種別
    /// - Returns: 即時全ウィンドウ一括取得対象（`initialScanCompleted` / `displayStyleEnabled`）なら true
    public static func isImmediateBulkPrefetch(reason: WindowCapturePrefetchReason) -> Bool {
        switch reason {
        case .initialScanCompleted, .displayStyleEnabled:
            return true
        case .activeSpaceChanged,
             .windowCreated,
             .applicationLaunched,
             .windowDeminiaturized,
             .applicationActivated,
             .windowFocusChanged,
             .windowTitleChanged:
            return false
        }
    }

    /// 保留中の事前取得契機と新しく到着した契機を統合し、優先度の高い契機（全ウィンドウ一括取得）を失わないようにする
    /// - Parameters:
    ///   - existing: 既に保留されている契機種別（存在しない場合は nil）
    ///   - incoming: 新しく到着した契機種別
    /// - Returns: 統合後の契機種別
    public static func mergePendingPrefetchReason(
        existing: WindowCapturePrefetchReason?,
        incoming: WindowCapturePrefetchReason
    ) -> WindowCapturePrefetchReason {
        guard let existing else { return incoming }
        if isImmediateBulkPrefetch(reason: incoming) {
            return incoming
        }
        if isImmediateBulkPrefetch(reason: existing) {
            return existing
        }
        return incoming
    }

    /// 既キャッシュウィンドウがバックグラウンド再取得の対象（クールダウン経過済み）かを判定する
    /// - Parameters:
    ///   - lastCapturedAt: 最後にサムネイルを取得・格納した時刻（未記録時は nil）
    ///   - now: 判定基準となる現在時刻
    ///   - cooldown: 最小再取得間隔（秒）
    /// - Returns: クールダウン以上経過している（または最終取得時刻が未記録）なら true、未経過または時刻逆転時は false
    public static func isCooldownElapsed(
        lastCapturedAt: Date?,
        now: Date,
        cooldown: TimeInterval
    ) -> Bool {
        guard let lastCapturedAt else { return true }
        let safeCooldown = max(cooldown, 0)
        return now.timeIntervalSince(lastCapturedAt) >= safeCooldown
    }

    /// 起動直後（`initialScanCompleted`）およびキャプチャ表示型有効化時（`displayStyleEnabled`）の
    /// 全ウィンドウ一括取得対象 ID を優先順・重複除外済みで抽出する
    ///
    /// 優先順位（各群内は MRU 順を維持）:
    /// 1. 現在スペース表示中（`isOnScreen == true` かつ非最小化）の未キャッシュウィンドウ
    /// 2. 現在スペース表示中（`isOnScreen == true` かつ非最小化）のクールダウン経過済み既キャッシュウィンドウ
    /// 3. 別スペース／フルスクリーン等のオフスクリーン非最小化ウィンドウ（`isOnScreen != true` かつ非最小化）の未キャッシュウィンドウ
    /// 4. 最小化ウィンドウ（`isMinimized == true`）の未キャッシュウィンドウ
    ///
    /// - Parameters:
    ///   - entries: 全操作スペースの有効ウィンドウ項目一覧（MRU 順）
    ///   - isCached: 指定 CGWindow ID がキャッシュ済みかを判定する副作用なしクロージャ
    ///   - lastCapturedAt: 指定 CGWindow ID の最終取得時刻を返す副作用なしクロージャ
    ///   - now: 鮮度判定の基準時刻
    ///   - cooldown: 既キャッシュ再取得の最小間隔（秒）
    /// - Returns: 一括取得対象となる CGWindow ID 配列（重複除外済み）
    public static func startupBulkPrefetchWindowIDs(
        from entries: [WindowEntry],
        isCached: (UInt32) -> Bool,
        lastCapturedAt: (UInt32) -> Date?,
        now: Date,
        cooldown: TimeInterval = defaultRefreshCooldown
    ) -> [UInt32] {
        var seen: Set<UInt32> = []
        var uncachedOnScreen: [UInt32] = []
        var staleCachedOnScreen: [UInt32] = []
        var uncachedOffScreen: [UInt32] = []
        var uncachedMinimized: [UInt32] = []

        for entry in entries {
            guard let windowID = entry.cgWindowID,
                  seen.insert(windowID).inserted else {
                continue
            }

            let cached = isCached(windowID)
            if entry.isMinimized {
                if !cached {
                    uncachedMinimized.append(windowID)
                }
            } else if entry.isOnScreen == true {
                if !cached {
                    uncachedOnScreen.append(windowID)
                } else if isCooldownElapsed(
                    lastCapturedAt: lastCapturedAt(windowID),
                    now: now,
                    cooldown: cooldown
                ) {
                    staleCachedOnScreen.append(windowID)
                }
            } else {
                // 別スペース・フルスクリーン等のオフスクリーン非最小化ウィンドウは未キャッシュのみ試行する
                if !cached {
                    uncachedOffScreen.append(windowID)
                }
            }
        }

        return uncachedOnScreen + staleCachedOnScreen + uncachedOffScreen + uncachedMinimized
    }

    /// 通常イベント契機（アプリ切替・フォーカス変更・タイトル変更・スペース切替・新規作成・起動・最小化解除）で
    /// 更新対象となる現在スペース表示中ウィンドウの CGWindow ID を優先順・重複除外済みで抽出する
    ///
    /// 優先順位（各群内は MRU 順を維持）:
    /// 1. 現在スペース表示中（`isOnScreen == true` かつ非最小化）の未キャッシュウィンドウ
    /// 2. 現在スペース表示中（`isOnScreen == true` かつ非最小化）のクールダウン経過済み既キャッシュウィンドウ
    ///
    /// - Parameters:
    ///   - entries: 全操作スペースの有効ウィンドウ項目一覧（MRU 順）
    ///   - isCached: 指定 CGWindow ID がキャッシュ済みかを判定する副作用なしクロージャ
    ///   - lastCapturedAt: 指定 CGWindow ID の最終取得時刻を返す副作用なしクロージャ
    ///   - now: 鮮度判定の基準時刻
    ///   - cooldown: 既キャッシュ再取得の最小間隔（秒）
    /// - Returns: イベント駆動更新対象となる CGWindow ID 配列（重複除外済み）
    public static func eventPrefetchWindowIDs(
        from entries: [WindowEntry],
        isCached: (UInt32) -> Bool,
        lastCapturedAt: (UInt32) -> Date?,
        now: Date,
        cooldown: TimeInterval = defaultRefreshCooldown
    ) -> [UInt32] {
        var seen: Set<UInt32> = []
        var uncachedOnScreen: [UInt32] = []
        var staleCachedOnScreen: [UInt32] = []

        for entry in entries {
            guard let windowID = entry.cgWindowID,
                  entry.isOnScreen == true,
                  !entry.isMinimized,
                  seen.insert(windowID).inserted else {
                continue
            }

            if !isCached(windowID) {
                uncachedOnScreen.append(windowID)
            } else if isCooldownElapsed(
                lastCapturedAt: lastCapturedAt(windowID),
                now: now,
                cooldown: cooldown
            ) {
                staleCachedOnScreen.append(windowID)
            }
        }

        return uncachedOnScreen + staleCachedOnScreen
    }

    /// 定期バックグラウンド更新（既定 15 秒間隔）で更新対象となる現在スペース表示中ウィンドウの
    /// CGWindow ID を優先順・重複除外済みで抽出する
    ///
    /// 優先順位:
    /// 1. 現在スペース表示中（`isOnScreen == true` かつ非最小化）の未キャッシュウィンドウ（MRU 順）
    /// 2. 現在スペース表示中（`isOnScreen == true` かつ非最小化）のクールダウン経過済み既キャッシュウィンドウ（最終取得時刻が古い順、同時刻時は MRU 順）
    ///
    /// - Parameters:
    ///   - entries: 全操作スペースの有効ウィンドウ項目一覧（MRU 順）
    ///   - isCached: 指定 CGWindow ID がキャッシュ済みかを判定する副作用なしクロージャ
    ///   - lastCapturedAt: 指定 CGWindow ID の最終取得時刻を返す副作用なしクロージャ
    ///   - now: 鮮度判定の基準時刻
    ///   - cooldown: 既キャッシュ再取得の最小間隔（秒）
    /// - Returns: 定期更新対象となる CGWindow ID 配列（重複除外済み）
    public static func periodicRefreshWindowIDs(
        from entries: [WindowEntry],
        isCached: (UInt32) -> Bool,
        lastCapturedAt: (UInt32) -> Date?,
        now: Date,
        cooldown: TimeInterval = defaultRefreshCooldown
    ) -> [UInt32] {
        var seen: Set<UInt32> = []
        var uncachedOnScreen: [UInt32] = []
        var staleCachedOnScreen: [(windowID: UInt32, capturedAt: Date?, mruIndex: Int)] = []

        for (index, entry) in entries.enumerated() {
            guard let windowID = entry.cgWindowID,
                  entry.isOnScreen == true,
                  !entry.isMinimized,
                  seen.insert(windowID).inserted else {
                continue
            }

            if !isCached(windowID) {
                uncachedOnScreen.append(windowID)
            } else {
                let capturedAt = lastCapturedAt(windowID)
                if isCooldownElapsed(
                    lastCapturedAt: capturedAt,
                    now: now,
                    cooldown: cooldown
                ) {
                    staleCachedOnScreen.append((windowID: windowID, capturedAt: capturedAt, mruIndex: index))
                }
            }
        }

        let orderedStaleIDs = staleCachedOnScreen
            .sorted { lhs, rhs in
                switch (lhs.capturedAt, rhs.capturedAt) {
                case (nil, nil):
                    return lhs.mruIndex < rhs.mruIndex
                case (nil, .some):
                    return true
                case (.some, nil):
                    return false
                case let (.some(lhsDate), .some(rhsDate)):
                    if lhsDate != rhsDate {
                        return lhsDate < rhsDate
                    }
                    return lhs.mruIndex < rhs.mruIndex
                }
            }
            .map(\.windowID)

        return uncachedOnScreen + orderedStaleIDs
    }

    /// キャッシュ整理（`pruneCache`）時に保持すべき生存 CGWindow ID 集合を安全に算出する
    ///
    /// 別スペースやフルスクリーン空間のウィンドウが一時的なフィルタ除外（タイトル未補完等）で
    /// 表示候補から一瞬漏れただけでキャッシュが誤消去されるのを防ぐため、
    /// OS 側の全生存 CGWindow ID 集合（取得可能な場合）およびフィルタ前生候補との和集合を保持対象とする。
    /// OS 側の一時的な取得失敗で空集合が返った場合は、全キャッシュ誤消去を防ぐため `nil` を返して整理を抑止する。
    ///
    /// - Parameters:
    ///   - survivingCGWindowIDs: OS（`CGWindowListCopyWindowInfo`）から取得した全生存 CGWindow ID 集合（未対応実装時は nil）
    ///   - rawCandidates: フィルタ前の生ウィンドウ候補一覧
    ///   - filteredEntries: フィルタ後の表示対象ウィンドウ一覧
    /// - Returns: 保持すべき CGWindow ID 集合（整理を見送るべき場合は nil）
    public static func cacheRetentionWindowIDs(
        survivingCGWindowIDs: Set<UInt32>?,
        rawCandidates: [RawWindowCandidate],
        filteredEntries: [WindowEntry]
    ) -> Set<UInt32>? {
        var retained = Set(rawCandidates.compactMap(\.cgWindowID))
        retained.formUnion(filteredEntries.compactMap(\.cgWindowID))

        if let survivingCGWindowIDs {
            // OS 側の生存一覧が空かつ候補も空の場合は、一時的な WindowServer 応答異常での全破棄を避ける
            if survivingCGWindowIDs.isEmpty && retained.isEmpty {
                return nil
            }
            retained.formUnion(survivingCGWindowIDs)
        }
        return retained
    }
}
