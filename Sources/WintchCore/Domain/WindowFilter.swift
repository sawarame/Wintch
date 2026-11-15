import Foundation

/// ウィンドウ候補からノイズを除外し、表示用の WindowEntry へ変換する純粋ロジック
public enum WindowFilter {
    /// 切り替え対象として許可するアクセシビリティロール
    private static let allowedRole = "AXWindow"

    /// 切り替え対象として許可する標準アクセシビリティサブロール
    private static let standardSubroles: Set<String> = ["AXStandardWindow", "AXDialog"]

    /// 実質的なウィンドウサイズを持つ場合のみ許可するフローティング用サブロール
    private static let floatingSubroles: Set<String> = ["AXFloatingWindow", "AXSystemFloatingWindow"]

    /// 切り替え対象として許可するウィンドウレイヤー（0: 通常ウィンドウ、3: フローティングウィンドウ）
    private static let allowedLayers: Set<Int> = [0, 3]

    /// ノイズウィンドウとして扱う最小辺サイズ（ポイント）
    private static let minimumDimension: Double = 50.0

    /// AX 情報なしの CGWindow 補完候補に要求する最小幅（ポイント）
    private static let cgFallbackMinimumWidth: Double = 200.0

    /// AX 情報なしの CGWindow 補完候補に要求する最小高さ（ポイント）
    private static let cgFallbackMinimumHeight: Double = 165.0

    /// フルスクリーン用ツールバー等の横長ストリップを判定するアスペクト比上限と高さ上限
    private static let maxToolbarAspectRatio: Double = 6.0
    private static let maxStripHeight: Double = 300.0

    /// 複数スペースに跨って同一矩形になり得るフルスクリーン相当サイズの下限（ポイント）
    private static let displaySpanningMinWidth: Double = 1280.0
    private static let displaySpanningMinHeight: Double = 700.0

    /// 同一ウィンドウの二重生成 CGWindow とみなす非フルスクリーン矩形の許容誤差（ポイント）
    private static let duplicateBoundsTolerance: Double = 2.0

    /// 候補がスイッチャーに表示すべき有効なウィンドウかどうかを判定する
    /// - Parameter candidate: 判定対象のウィンドウ候補
    /// - Returns: 表示対象とする場合は true
    public static func isValid(_ candidate: RawWindowCandidate) -> Bool {
        guard passesCommonGuards(candidate) else { return false }

        if candidate.hasAXInfo {
            // AX 情報がある場合、デスクトップのスクロール領域など非ウィンドウ要素を除外する
            if let role = candidate.axRole {
                guard role == allowedRole else { return false }
            }
            guard let subrole = candidate.axSubrole else { return false }
            if standardSubroles.contains(subrole) {
                return true
            }
            // フローティングウィンドウはツールバーや小パレット誤爆を防ぐため通常サイズ要件を課す
            if floatingSubroles.contains(subrole) {
                return isSubstantialWindowBounds(candidate.bounds)
            }
            return false
        } else {
            // 現在の操作スペース上で表示中にもかかわらず AX と照合できなかった CGWindow は原則除外する
            if candidate.isOnScreen == true {
                return false
            }
            return isSubstantialWindowBounds(candidate.bounds)
        }
    }

    /// 生のウィンドウ候補配列からノイズを除外し、WindowEntry の配列へ変換する
    /// - Parameter candidates: 収集されたウィンドウ候補の配列
    /// - Returns: フィルタリング後のウィンドウ項目配列
    public static func filterAndMap(_ candidates: [RawWindowCandidate]) -> [WindowEntry] {
        let baseValidCandidates = candidates.filter(isValid)
        let baseValidIDs = Set(baseValidCandidates.map(\.id))
        let coveredPIDs = Set(baseValidCandidates.map(\.pid))
        let axCoveredPIDs = Set(baseValidCandidates.filter(\.hasAXInfo).map(\.pid))

        // 通常フィルタで 1 件も捕捉できなかったアプリに限り、表示中（isOnScreen == true）の実サイズ CGWindow を救済対象へ含める
        let validCandidates = candidates.filter { candidate in
            if baseValidIDs.contains(candidate.id) {
                return true
            }
            return !coveredPIDs.contains(candidate.pid)
                && !candidate.hasAXInfo
                && candidate.isOnScreen == true
                && passesCommonGuards(candidate)
                && isSubstantialWindowBounds(candidate.bounds)
        }

        // PID ごとに通常レイヤー（layer == 0）の候補が存在するかを把握する
        let pidsWithPrimaryWindow = Set(
            validCandidates
                .filter { $0.hasAXInfo || $0.layer == 0 }
                .map(\.pid)
        )

        // Finder 等の非フルスクリーン二重生成 CGWindow を防ぐため、PID ごとの既出非フルスクリーン矩形を記録する
        var emittedNonFullscreenBoundsByPID: [Int32: [WindowBounds]] = [:]
        for candidate in validCandidates where candidate.hasAXInfo {
            if !isDisplaySpanningBounds(candidate.bounds) {
                emittedNonFullscreenBoundsByPID[candidate.pid, default: []].append(candidate.bounds)
            }
        }

        var emittedCandidateIDs = Set<String>()
        var result: [WindowEntry] = []
        result.reserveCapacity(validCandidates.count)

        for candidate in validCandidates {
            if candidate.hasAXInfo {
                guard emittedCandidateIDs.insert(candidate.id).inserted else { continue }
                result.append(makeEntry(from: candidate))
                continue
            }

            // 表示中の AX 未照合ウィンドウは、AX 捕捉済みアプリでは内部オーバーレイとみなして除外する
            if candidate.isOnScreen == true, axCoveredPIDs.contains(candidate.pid) {
                continue
            }

            // 通常ウィンドウや AX ウィンドウが既に存在するアプリのフローティング補助窓（layer != 0）は補完しない
            if candidate.layer != 0, pidsWithPrimaryWindow.contains(candidate.pid) {
                continue
            }

            // 同一非フルスクリーン座標で二重生成された CGWindow は重複統合する（別スペースのフルスクリーン等は保持）
            if !isDisplaySpanningBounds(candidate.bounds) {
                let existingBounds = emittedNonFullscreenBoundsByPID[candidate.pid] ?? []
                if existingBounds.contains(where: { areBoundsNearlyEqual($0, candidate.bounds) }) {
                    continue
                }
                emittedNonFullscreenBoundsByPID[candidate.pid, default: []].append(candidate.bounds)
            }

            guard emittedCandidateIDs.insert(candidate.id).inserted else { continue }
            result.append(makeEntry(from: candidate))
        }

        return result
    }

    /// RawWindowCandidate から UI 表示用の WindowEntry を生成する
    /// - Parameter candidate: フィルタを通過したウィンドウ候補
    /// - Returns: 生成された WindowEntry
    private static func makeEntry(from candidate: RawWindowCandidate) -> WindowEntry {
        WindowEntry(
            id: candidate.id,
            cgWindowID: candidate.cgWindowID,
            pid: candidate.pid,
            bundleIdentifier: candidate.bundleIdentifier,
            applicationName: candidate.applicationName,
            windowTitle: candidate.title ?? "",
            isMinimized: candidate.isMinimized,
            isOnScreen: candidate.isOnScreen,
            lastActivatedAt: candidate.lastActivatedAt,
            zOrderIndex: candidate.zOrderIndex
        )
    }

    /// 候補が自アプリ・非通常アプリ・禁止レイヤー・不可視・極小サイズに該当しないか判定する
    /// - Parameter candidate: 判定対象のウィンドウ候補
    /// - Returns: 基本条件を満たす場合は true
    private static func passesCommonGuards(_ candidate: RawWindowCandidate) -> Bool {
        // Wintch 自身のウィンドウは除外する
        guard !candidate.isSelf else { return false }

        // 通常アプリ（Dock 表示対象の一般アプリ）以外は除外する
        guard candidate.isRegularApplication else { return false }

        // 通常・フローティング以外のシステム UI（メニューバー、Dock、通知センター等）は除外する
        guard allowedLayers.contains(candidate.layer) else { return false }

        // 完全に透明な補助ウィンドウは除外する
        guard candidate.alpha > 0.0 else { return false }

        // 極小サイズの隠しトラッキングウィンドウ等を除外する
        guard candidate.bounds.width >= minimumDimension,
              candidate.bounds.height >= minimumDimension else {
            return false
        }

        // フローティングレイヤー（layer == 3）は 64x64 等のフルスクリーン補助窓を除外するため通常サイズを要求する
        if candidate.layer != 0 {
            return isSubstantialWindowBounds(candidate.bounds)
        }

        return true
    }

    /// Finder の 64x64 やフルスクリーン上端バー等の補助ウィンドウではなく、実質的なウィンドウサイズかを判定する
    /// - Parameter bounds: 判定対象のウィンドウ矩形
    /// - Returns: 通常ウィンドウ相当のサイズ要件を満たす場合は true
    private static func isSubstantialWindowBounds(_ bounds: WindowBounds) -> Bool {
        guard bounds.width >= cgFallbackMinimumWidth,
              bounds.height >= cgFallbackMinimumHeight else {
            return false
        }
        if bounds.height < maxStripHeight,
           (bounds.width / bounds.height) > maxToolbarAspectRatio {
            return false
        }
        return true
    }

    /// 複数操作スペースで同一矩形になり得るディスプレイ占有級（フルスクリーン等）のサイズかを判定する
    /// - Parameter bounds: 判定対象のウィンドウ矩形
    /// - Returns: ディスプレイ占有級のサイズであれば true
    private static func isDisplaySpanningBounds(_ bounds: WindowBounds) -> Bool {
        bounds.width >= displaySpanningMinWidth && bounds.height >= displaySpanningMinHeight
    }

    /// 2つのウィンドウ矩形がほぼ同一位置・同一サイズかを判定する
    /// - Parameters:
    ///   - lhs: 比較元のウィンドウ矩形
    ///   - rhs: 比較先のウィンドウ矩形
    /// - Returns: 各座標・辺が許容誤差以内なら true
    private static func areBoundsNearlyEqual(_ lhs: WindowBounds, _ rhs: WindowBounds) -> Bool {
        abs(lhs.x - rhs.x) <= duplicateBoundsTolerance
            && abs(lhs.y - rhs.y) <= duplicateBoundsTolerance
            && abs(lhs.width - rhs.width) <= duplicateBoundsTolerance
            && abs(lhs.height - rhs.height) <= duplicateBoundsTolerance
    }
}
