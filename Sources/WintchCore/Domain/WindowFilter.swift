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

        // 通常フィルタで 1 件も捕捉できなかったアプリに限り、表示中（isOnScreen == true）の実サイズ CGWindow を救済する
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

        // 既に AXUIElement で有効なウィンドウが捕捉されているアプリは、
        // 内部の非表示 CGWindow（Chrome の裏ウィンドウや Finder/設定の補助ウィンドウ）を補完しない
        let axCoveredPIDs = Set(validCandidates.filter { $0.hasAXInfo }.map(\.pid))
        let representativeFallbackIDs = selectRepresentativeCGFallbackIDs(
            from: validCandidates,
            excluding: axCoveredPIDs
        )
        var emittedFallbackPIDs = Set<Int32>()

        return validCandidates
            .filter { candidate in
                guard !candidate.hasAXInfo else { return true }
                guard !axCoveredPIDs.contains(candidate.pid) else { return false }
                guard representativeFallbackIDs[candidate.pid] == candidate.id else { return false }
                // 同一 ID が複数含まれる場合でも PID あたり代表 1 件に制限する
                return emittedFallbackPIDs.insert(candidate.pid).inserted
            }
            .map { candidate in
                WindowEntry(
                    id: candidate.id,
                    cgWindowID: candidate.cgWindowID,
                    pid: candidate.pid,
                    bundleIdentifier: candidate.bundleIdentifier,
                    applicationName: candidate.applicationName,
                    windowTitle: candidate.title ?? "",
                    isMinimized: candidate.isMinimized,
                    lastActivatedAt: candidate.lastActivatedAt,
                    zOrderIndex: candidate.zOrderIndex
                )
            }
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

    /// AX 未捕捉アプリ（別スペース・フルスクリーン・フローティング等）の CGWindow 補完候補から、
    /// PID ごとに代表となる 1 件の識別子を選出する（通常レイヤー優先、同レイヤーなら最大面積・Z オーダー最上位を優先）
    /// - Parameters:
    ///   - candidates: 事前フィルタを通過したウィンドウ候補の配列
    ///   - axCoveredPIDs: 既に AXUIElement で有効ウィンドウが捕捉されている PID の集合
    /// - Returns: PID ごとに選出された代表候補 ID のマップ
    private static func selectRepresentativeCGFallbackIDs(
        from candidates: [RawWindowCandidate],
        excluding axCoveredPIDs: Set<Int32>
    ) -> [Int32: String] {
        var bestByPID: [Int32: (id: String, layer: Int, area: Double, zOrder: Int)] = [:]

        for candidate in candidates where !candidate.hasAXInfo && !axCoveredPIDs.contains(candidate.pid) {
            let area = candidate.bounds.width * candidate.bounds.height
            let zOrder = candidate.zOrderIndex
            let layer = candidate.layer

            if let current = bestByPID[candidate.pid] {
                let isNormalOverFloating = (layer == 0 && current.layer != 0)
                let isSameLayerClass = ((layer == 0) == (current.layer == 0))
                let isLargerArea = isSameLayerClass && area > current.area
                let isSameAreaHigherZ = isSameLayerClass && area == current.area && zOrder < current.zOrder
                guard isNormalOverFloating || isLargerArea || isSameAreaHigherZ else { continue }
            }
            bestByPID[candidate.pid] = (id: candidate.id, layer: layer, area: area, zOrder: zOrder)
        }

        return bestByPID.mapValues(\.id)
    }
}
