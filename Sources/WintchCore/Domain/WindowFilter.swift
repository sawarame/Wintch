import Foundation

/// ウィンドウ候補からノイズを除外し、表示用の WindowEntry へ変換する純粋ロジック
public enum WindowFilter {
    /// 切り替え対象として許可するアクセシビリティロール
    private static let allowedRole = "AXWindow"

    /// 切り替え対象として許可するアクセシビリティサブロール
    private static let allowedSubroles: Set<String> = ["AXStandardWindow", "AXDialog"]

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
        // Wintch 自身のウィンドウは除外する
        guard !candidate.isSelf else { return false }

        // 通常アプリ（Dock 表示対象の一般アプリ）以外は除外する
        guard candidate.isRegularApplication else { return false }

        // レイヤー 0 以外のシステム UI（メニューバー、Dock、通知センター等）は除外する
        guard candidate.layer == 0 else { return false }

        // 完全に透明な補助ウィンドウは除外する
        guard candidate.alpha > 0.0 else { return false }

        // 極小サイズの隠しトラッキングウィンドウ等を除外する
        guard candidate.bounds.width >= minimumDimension,
              candidate.bounds.height >= minimumDimension else {
            return false
        }

        if candidate.hasAXInfo {
            // AX 情報がある場合、デスクトップのスクロール領域など非ウィンドウ要素を除外する
            if let role = candidate.axRole {
                guard role == allowedRole else { return false }
            }
            guard let subrole = candidate.axSubrole,
                  allowedSubroles.contains(subrole) else {
                return false
            }
        } else {
            // 現在の操作スペース上で表示中にもかかわらず AX と照合できなかった CGWindow は内部補助ウィンドウのため除外する
            if candidate.isOnScreen == true {
                return false
            }
            // Finder の 64x64 や Chrome/Electron のフルスクリーン上端バー等の内部ウィンドウを除外する
            guard candidate.bounds.width >= cgFallbackMinimumWidth,
                  candidate.bounds.height >= cgFallbackMinimumHeight else {
                return false
            }
            if candidate.bounds.height < maxStripHeight,
               (candidate.bounds.width / candidate.bounds.height) > maxToolbarAspectRatio {
                return false
            }
        }

        return true
    }

    /// CGWindow 補完候補同士を同一ウィンドウとして重複統合する矩形差の許容しきい値（ポイント）
    private static let duplicateBoundsTolerance: Double = 40.0

    /// 生のウィンドウ候補配列からノイズを除外し、WindowEntry の配列へ変換する
    /// - Parameter candidates: 収集されたウィンドウ候補の配列
    /// - Returns: フィルタリング後のウィンドウ項目配列
    public static func filterAndMap(_ candidates: [RawWindowCandidate]) -> [WindowEntry] {
        let validCandidates = candidates.filter(isValid)

        // 既に AXUIElement で有効なウィンドウが捕捉されているアプリは、
        // 内部の非表示 CGWindow（Chrome の裏ウィンドウや Finder/設定の補助ウィンドウ）を補完しない
        let axCoveredPIDs = Set(validCandidates.filter { $0.hasAXInfo }.map(\.pid))
        var emittedCGFallbackBoundsByPID: [Int32: [WindowBounds]] = [:]

        return validCandidates
            .filter { candidate in
                guard !candidate.hasAXInfo else { return true }
                guard !axCoveredPIDs.contains(candidate.pid) else { return false }

                // 同一アプリ・同一座標に複数存在する CGWindow（Finder の二重サーフェス等）を 1 つに統合する
                let existingBounds = emittedCGFallbackBoundsByPID[candidate.pid] ?? []
                let isDuplicateBounds = existingBounds.contains { existing in
                    boundsDistance(existing, candidate.bounds) <= duplicateBoundsTolerance
                }
                guard !isDuplicateBounds else { return false }

                emittedCGFallbackBoundsByPID[candidate.pid, default: []].append(candidate.bounds)
                return true
            }
            .map { candidate in
                WindowEntry(
                    id: candidate.id,
                    cgWindowID: candidate.cgWindowID,
                    pid: candidate.pid,
                    applicationName: candidate.applicationName,
                    windowTitle: candidate.title ?? "",
                    isMinimized: candidate.isMinimized,
                    lastActivatedAt: candidate.lastActivatedAt,
                    zOrderIndex: candidate.zOrderIndex
                )
            }
    }

    /// 2つのウィンドウ矩形間のマンハッタン距離を計算する
    /// - Parameters:
    ///   - a: 比較元の矩形
    ///   - b: 比較先の矩形
    /// - Returns: 座標とサイズの差分合計値
    private static func boundsDistance(_ a: WindowBounds, _ b: WindowBounds) -> Double {
        abs(a.x - b.x) + abs(a.y - b.y) + abs(a.width - b.width) + abs(a.height - b.height)
    }
}
