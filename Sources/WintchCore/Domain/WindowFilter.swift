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

    /// 複数スペースに跨って同一矩形になり得るフルスクリーン相当サイズの下限（スクリーン情報未指定時のフォールバック）
    private static let displaySpanningMinWidth: Double = 1280.0
    private static let displaySpanningMinHeight: Double = 700.0

    /// スクリーン矩形比較時にディスプレイ占有級（フルスクリーン／画面最大化）とみなす最小幅・高さ比率と下限（ポイント）
    private static let screenSpanningWidthRatio: Double = 0.95
    private static let screenSpanningHeightRatio: Double = 0.85
    private static let screenSpanningMinWidthWithScreens: Double = 800.0
    private static let screenSpanningMinHeightWithScreens: Double = 600.0

    /// 同一ウィンドウの二重生成 CGWindow やタブとみなす矩形の許容誤差（ポイント）
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
            // AX 未捕捉かつ画面外の非通常レイヤー（フローティング補助窓等）は全ウィンドウ閉鎖後の残骸となり得るため補完しない
            guard candidate.layer == 0 else {
                return false
            }
            return isSubstantialWindowBounds(candidate.bounds)
        }
    }

    /// 生のウィンドウ候補配列からノイズを除外し、WindowEntry の配列へ変換する
    /// - Parameters:
    ///   - candidates: 収集されたウィンドウ候補の配列
    ///   - screenBounds: 接続中ディスプレイの矩形一覧（CGWindow 座標系。省略時は固定閾値でフルスクリーン級を判定）
    /// - Returns: フィルタリング後のウィンドウ項目配列
    public static func filterAndMap(
        _ candidates: [RawWindowCandidate],
        screenBounds: [WindowBounds] = []
    ) -> [WindowEntry] {
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

        // 1. 非AX候補の補助ウィンドウ除外（内部オーバーレイ・補助フローティング・単一ウィンドウアプリの重複 CGWindow）
        var prefiltered: [RawWindowCandidate] = []
        prefiltered.reserveCapacity(validCandidates.count)
        var emittedCandidateIDs = Set<String>()

        for candidate in validCandidates {
            if candidate.hasAXInfo {
                guard emittedCandidateIDs.insert(candidate.id).inserted else { continue }
                prefiltered.append(candidate)
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

            // アプリ別プロファイルに基づき、画面外・AX 未捕捉 CGWindow 補完の採用ポリシーを統一適用する
            let profile = AppWindowProfileRegistry.profile(for: candidate.bundleIdentifier)
            switch profile.offscreenCGPolicy {
            case .allow:
                break
            case .singleRepresentativeOnly:
                // 単一メインウィンドウ構成アプリでは、既に AX 捕捉済みであれば CGWindow 補完を出さない
                if axCoveredPIDs.contains(candidate.pid) {
                    continue
                }
            case .requireAXOrMenuTitle:
                // メニュー補完等でもタイトルが確定しなかった画面外 CGWindow 補完は内部補助窓として除外する
                let trimmedTitle = (candidate.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.isOnScreen != true, trimmedTitle.isEmpty {
                    continue
                }
            }

            guard emittedCandidateIDs.insert(candidate.id).inserted else { continue }
            prefiltered.append(candidate)
        }

        // 2. 単一ウィンドウ構成アプリが AX 未捕捉（!hasAXInfo のみ）の場合、PID ごとに最良の代表 1 件へ絞る
        let singleWindowBestCGIndexByPID = selectBestSingleWindowCGIndices(in: prefiltered)

        // 3. 同一 PID・非ディスプレイ占有級の同一矩形候補（Finder の複数タブや二重生成 CGWindow）を統合する
        var keptIndices: [Int] = []
        keptIndices.reserveCapacity(prefiltered.count)

        for (index, candidate) in prefiltered.enumerated() {
            // 単一ウィンドウ構成アプリの !hasAXInfo 候補は代表 1 件のみ許可する
            if !candidate.hasAXInfo,
               AppWindowProfileRegistry.profile(for: candidate.bundleIdentifier).offscreenCGPolicy == .singleRepresentativeOnly,
               singleWindowBestCGIndexByPID[candidate.pid] != index {
                continue
            }

            // ディスプレイ占有級（フルスクリーン等）は別スペースの複数ウィンドウとして個別保持する
            if isDisplaySpanningBounds(candidate.bounds, screenBounds: screenBounds) {
                keptIndices.append(index)
                continue
            }

            // 同じスペースに同時表示中の独立ウィンドウや未照合の別 AX ウィンドウ同士は重複統合しない
            if let existingPos = keptIndices.firstIndex(where: { keptIdx in
                let existing = prefiltered[keptIdx]
                guard existing.pid == candidate.pid,
                      !isDisplaySpanningBounds(existing.bounds, screenBounds: screenBounds),
                      areBoundsNearlyEqual(existing.bounds, candidate.bounds) else {
                    return false
                }
                // 両方とも AX 捕捉済みかつ最小化状態が異なる場合は別ウィンドウとして統合しない
                if existing.hasAXInfo && candidate.hasAXInfo && existing.isMinimized != candidate.isMinimized {
                    return false
                }
                // 両方とも AX 捕捉済みで、かつどちらも非表示（isOnScreen == false）でない場合は独立ウィンドウとして保持する
                if existing.hasAXInfo && candidate.hasAXInfo
                    && existing.isOnScreen != false && candidate.isOnScreen != false {
                    return false
                }
                return true
            }) {
                let existingIdx = keptIndices[existingPos]
                let existing = prefiltered[existingIdx]
                if isHigherPriorityRepresentative(candidate, than: existing) {
                    keptIndices[existingPos] = index
                }
                continue
            }

            keptIndices.append(index)
        }

        return keptIndices.sorted().map { makeEntry(from: prefiltered[$0]) }
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

        // アプリ横断・アプリ固有の未表示バックキングウィンドウ（500x500 等）を除外する
        if AppWindowProfileRegistry.isHiddenBackingWindow(candidate) {
            return false
        }

        // フローティングレイヤー（layer == 3）は 64x64 等のフルスクリーン補助窓を除外するため通常サイズを要求する
        if candidate.layer != 0 {
            return isSubstantialWindowBounds(candidate.bounds)
        }

        return true
    }

    /// 単一ウィンドウ構成アプリの AX 未捕捉 CGWindow 候補から PID ごとに最良の代表 1 件を選出する
    /// - Parameter candidates: 事前フィルタ済み候補配列
    /// - Returns: PID ごとに選出された代表候補インデックスの辞書
    private static func selectBestSingleWindowCGIndices(in candidates: [RawWindowCandidate]) -> [Int32: Int] {
        var bestByPID: [Int32: Int] = [:]
        for (index, candidate) in candidates.enumerated() {
            guard !candidate.hasAXInfo,
                  AppWindowProfileRegistry.profile(for: candidate.bundleIdentifier).offscreenCGPolicy == .singleRepresentativeOnly else {
                continue
            }
            guard let currentBestIdx = bestByPID[candidate.pid] else {
                bestByPID[candidate.pid] = index
                continue
            }
            let current = candidates[currentBestIdx]
            if isBetterSingleWindowCGFallback(candidate, than: current) {
                bestByPID[candidate.pid] = index
            }
        }
        return bestByPID
    }

    /// 単一ウィンドウアプリの CGWindow 補完候補同士を比較し、より本物のメインウィンドウらしい方を判定する
    /// - Parameters:
    ///   - lhs: 比較元の候補
    ///   - rhs: 比較先の候補
    /// - Returns: lhs を代表として優先すべき場合は true
    private static func isBetterSingleWindowCGFallback(
        _ lhs: RawWindowCandidate,
        than rhs: RawWindowCandidate
    ) -> Bool {
        let lhsOnScreen = lhs.isOnScreen == true
        let rhsOnScreen = rhs.isOnScreen == true
        if lhsOnScreen != rhsOnScreen {
            return lhsOnScreen
        }
        let lhsArea = lhs.bounds.width * lhs.bounds.height
        let rhsArea = rhs.bounds.width * rhs.bounds.height
        if lhsArea != rhsArea {
            return lhsArea > rhsArea
        }
        return lhs.zOrderIndex < rhs.zOrderIndex
    }

    /// 重複統合時に残すべき代表候補としての優先順位を比較する
    /// - Parameters:
    ///   - lhs: 新規の比較元候補
    ///   - rhs: 既存の代表候補
    /// - Returns: lhs を代表として採用すべき場合は true
    private static func isHigherPriorityRepresentative(
        _ lhs: RawWindowCandidate,
        than rhs: RawWindowCandidate
    ) -> Bool {
        let lhsOnScreen = lhs.isOnScreen == true
        let rhsOnScreen = rhs.isOnScreen == true
        if lhsOnScreen != rhsOnScreen {
            return lhsOnScreen
        }
        if lhs.hasAXInfo != rhs.hasAXInfo {
            return lhs.hasAXInfo
        }
        switch (lhs.lastActivatedAt, rhs.lastActivatedAt) {
        case let (.some(lDate), .some(rDate)) where lDate != rDate:
            return lDate > rDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }
        return lhs.zOrderIndex < rhs.zOrderIndex
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

    /// 複数操作スペースで同一矩形になり得るディスプレイ占有級（フルスクリーン／画面最大化相当）のサイズかを判定する
    /// - Parameters:
    ///   - bounds: 判定対象のウィンドウ矩形
    ///   - screenBounds: 接続中ディスプレイの矩形一覧（省略時は固定閾値を使用）
    /// - Returns: ディスプレイ占有級のサイズであれば true
    static func isDisplaySpanningBounds(
        _ bounds: WindowBounds,
        screenBounds: [WindowBounds] = []
    ) -> Bool {
        guard !screenBounds.isEmpty else {
            return bounds.width >= displaySpanningMinWidth && bounds.height >= displaySpanningMinHeight
        }
        guard bounds.width >= screenSpanningMinWidthWithScreens,
              bounds.height >= screenSpanningMinHeightWithScreens else {
            return false
        }
        let targetScreen = screenBounds.max { lhs, rhs in
            let lhsArea = intersectionArea(bounds, lhs)
            let rhsArea = intersectionArea(bounds, rhs)
            if lhsArea != rhsArea {
                return lhsArea < rhsArea
            }
            return (lhs.width * lhs.height) < (rhs.width * rhs.height)
        }
        guard let screen = targetScreen, screen.width > 0, screen.height > 0 else {
            return false
        }
        return bounds.width >= screen.width * screenSpanningWidthRatio
            && bounds.height >= screen.height * screenSpanningHeightRatio
    }

    /// 2つの矩形が重なる部分の面積を計算する
    /// - Parameters:
    ///   - lhs: 比較元の矩形
    ///   - rhs: 比較先の矩形
    /// - Returns: 交差面積（重ならない場合は 0.0）
    private static func intersectionArea(_ lhs: WindowBounds, _ rhs: WindowBounds) -> Double {
        let minX = max(lhs.x, rhs.x)
        let minY = max(lhs.y, rhs.y)
        let maxX = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let maxY = min(lhs.y + lhs.height, rhs.y + rhs.height)
        let width = max(0.0, maxX - minX)
        let height = max(0.0, maxY - minY)
        return width * height
    }

    /// 2つのウィンドウ矩形がほぼ同一位置・同一サイズかを判定する
    /// - Parameters:
    ///   - lhs: 比較元のウィンドウ矩形
    ///   - rhs: 比較先のウィンドウ矩形
    /// - Returns: 各座標・辺が許容誤差以内なら true
    static func areBoundsNearlyEqual(_ lhs: WindowBounds, _ rhs: WindowBounds) -> Bool {
        abs(lhs.x - rhs.x) <= duplicateBoundsTolerance
            && abs(lhs.y - rhs.y) <= duplicateBoundsTolerance
            && abs(lhs.width - rhs.width) <= duplicateBoundsTolerance
            && abs(lhs.height - rhs.height) <= duplicateBoundsTolerance
    }
}
