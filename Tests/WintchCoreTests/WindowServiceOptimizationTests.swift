import CoreGraphics
import Foundation
import Testing
@testable import WintchCore

/// WindowService の遅延対策（キャッシュファースト収集・CGWindow ベース整理・Stale-While-Revalidate・不要 IPC 削減）を検証するテストスイート
@Suite("WindowService 遅延対策・キャッシュ最適化テスト")
struct WindowServiceOptimizationTests {
    /// 監視稼働中かつ初回スキャン完了後の定常状態では同期フルスキャンへフォールバックしないことを検証する
    @Test("shouldPerformSyncScanOnFetch は監視稼働中の定常状態で同期スキャンを回避する")
    func shouldPerformSyncScanOnFetchSkipsSyncScanDuringSteadyObservation() {
        #expect(
            WindowService.shouldPerformSyncScanOnFetch(
                isObserving: false,
                hasCompletedInitialBackgroundScan: false
            ) == true
        )
        #expect(
            WindowService.shouldPerformSyncScanOnFetch(
                isObserving: false,
                hasCompletedInitialBackgroundScan: true
            ) == true
        )
        #expect(
            WindowService.shouldPerformSyncScanOnFetch(
                isObserving: true,
                hasCompletedInitialBackgroundScan: false
            ) == true
        )
        #expect(
            WindowService.shouldPerformSyncScanOnFetch(
                isObserving: true,
                hasCompletedInitialBackgroundScan: true
            ) == false
        )
    }

    /// CGWindow 生存情報のみを用いたキャッシュ整理判定が、同期 AX IPC なしで閉鎖済み破棄と遷移中保護を両立することを検証する
    @Test("cgCacheRetentionDecision は CGWindow 生存情報のみで閉鎖破棄・最小化保持・再照合を正しく判定する")
    func cgCacheRetentionDecisionHandlesEvictionAndRevalidationWithoutSyncAX() {
        // 1. cgWindowID 未確定の候補はここでは破棄しない（後段の照合・shouldEmitCachedAXWindow へ委ねる）
        #expect(
            WindowService.cgCacheRetentionDecision(
                isPresentInLatestAXScan: false,
                isMinimized: false,
                knownCGWindowID: nil,
                survivingCGWindowIDs: [],
                hasSubstantialCGWindow: false
            ) == .retain
        )

        // 2. 対応 CGWindowID が生存している場合は現在スペース・別スペース問わず保持する
        #expect(
            WindowService.cgCacheRetentionDecision(
                isPresentInLatestAXScan: false,
                isMinimized: false,
                knownCGWindowID: 100,
                survivingCGWindowIDs: [100, 200],
                hasSubstantialCGWindow: true
            ) == .retain
        )

        // 3. 最新 AX スキャンに不在かつ対応 CGWindowID も消滅している場合は閉鎖済みとして即破棄する
        #expect(
            WindowService.cgCacheRetentionDecision(
                isPresentInLatestAXScan: false,
                isMinimized: false,
                knownCGWindowID: 100,
                survivingCGWindowIDs: [200],
                hasSubstantialCGWindow: true
            ) == .evict
        )

        // 4. 最新 AX スキャン在籍・非最小化で対応 CGWindowID が消え、他に実サイズ CGWindow も無ければ閉鎖済みとして破棄する
        #expect(
            WindowService.cgCacheRetentionDecision(
                isPresentInLatestAXScan: true,
                isMinimized: false,
                knownCGWindowID: 100,
                survivingCGWindowIDs: [],
                hasSubstantialCGWindow: false
            ) == .evict
        )

        // 5. 最新 AX スキャン在籍・非最小化だが別の実サイズ CGWindow が存在する場合は ID 付け替わりを想定し再照合する
        #expect(
            WindowService.cgCacheRetentionDecision(
                isPresentInLatestAXScan: true,
                isMinimized: false,
                knownCGWindowID: 100,
                survivingCGWindowIDs: [200],
                hasSubstantialCGWindow: true
            ) == .clearCGWindowIDAndRevalidate
        )

        // 6. 最小化ウィンドウは CGWindow の一時不在でも誤破棄せず保持する
        #expect(
            WindowService.cgCacheRetentionDecision(
                isPresentInLatestAXScan: true,
                isMinimized: true,
                knownCGWindowID: 100,
                survivingCGWindowIDs: [],
                hasSubstantialCGWindow: false
            ) == .retain
        )
    }

    /// メニュー補完キャッシュが監視中は Stale-While-Revalidate でメインスレッドの同期再取得を回避することを検証する
    @Test("menuCacheLookupAction は監視中の期限切れキャッシュを同期再取得せず裏更新へ回す")
    func menuCacheLookupActionUsesStaleWhileRevalidateWhenObserving() {
        #expect(
            WindowService.menuCacheLookupAction(
                hasCachedState: false,
                isFresh: false,
                allowStaleWhileRevalidate: true
            ) == .fetchSynchronously
        )
        #expect(
            WindowService.menuCacheLookupAction(
                hasCachedState: true,
                isFresh: true,
                allowStaleWhileRevalidate: true
            ) == .useFresh
        )
        #expect(
            WindowService.menuCacheLookupAction(
                hasCachedState: true,
                isFresh: false,
                allowStaleWhileRevalidate: true
            ) == .useStaleAndRefreshInBackground
        )
        #expect(
            WindowService.menuCacheLookupAction(
                hasCachedState: true,
                isFresh: false,
                allowStaleWhileRevalidate: false
            ) == .fetchSynchronously
        )
    }

    /// 非ウィンドウ要素（AXScrollArea / AXUnknown 等）を AX スナップショット収集段階で除外しキャッシュ蓄積を防ぐことを検証する
    @Test("shouldCacheAXWindowAttributes は許可されたロール・サブロールのみキャッシュ対象とする")
    func shouldCacheAXWindowAttributesFiltersNonWindowNoiseElements() {
        #expect(WindowService.shouldCacheAXWindowAttributes(role: "AXWindow", subrole: "AXStandardWindow") == true)
        #expect(WindowService.shouldCacheAXWindowAttributes(role: "AXWindow", subrole: "AXDialog") == true)
        #expect(WindowService.shouldCacheAXWindowAttributes(role: "AXWindow", subrole: "AXFloatingWindow") == true)
        #expect(WindowService.shouldCacheAXWindowAttributes(role: "AXWindow", subrole: "AXSystemFloatingWindow") == true)
        #expect(WindowService.shouldCacheAXWindowAttributes(role: "AXWindow", subrole: nil) == true)
        #expect(WindowService.shouldCacheAXWindowAttributes(role: nil, subrole: "AXStandardWindow") == true)

        #expect(WindowService.shouldCacheAXWindowAttributes(role: "AXScrollArea", subrole: nil) == false)
        #expect(WindowService.shouldCacheAXWindowAttributes(role: "AXWindow", subrole: "AXUnknown") == false)
        #expect(WindowService.shouldCacheAXWindowAttributes(role: "AXWindow", subrole: "AXSheet") == false)
    }

    /// バックグラウンド全スキャン時のメニュー先読み対象 PID 抽出が、現在スペースのみの通常アプリを除外し
    /// 別スペース実サイズ窓を持つアプリや既知補完対象のみに絞ることを検証する
    @Test("pidsRequiringMenuPreload はオフスクリーン実サイズ窓または既知対象 PID のみにメニュー取得を限定する")
    func pidsRequiringMenuPreloadLimitsMenuScansToRelevantPIDs() {
        let cgWindows = [
            // PID 10: 現在スペース上のみ -> メニュー走査不要
            WindowService.CGWindowMeta(
                windowID: 1,
                pid: 10,
                layer: 0,
                bounds: CGRect(x: 0, y: 0, width: 1200, height: 800),
                alpha: 1.0,
                isOnscreen: true
            ),
            // PID 20: 別スペースの実サイズ通常ウィンドウ -> メニュー先読み対象
            WindowService.CGWindowMeta(
                windowID: 2,
                pid: 20,
                layer: 0,
                bounds: CGRect(x: 0, y: 0, width: 1400, height: 900),
                alpha: 1.0,
                isOnscreen: false
            ),
            // PID 30: オフスクリーン極小窓または layer != 0 のみ -> メニュー走査不要
            WindowService.CGWindowMeta(
                windowID: 3,
                pid: 30,
                layer: 0,
                bounds: CGRect(x: 0, y: 0, width: 64, height: 64),
                alpha: 1.0,
                isOnscreen: false
            ),
            WindowService.CGWindowMeta(
                windowID: 4,
                pid: 30,
                layer: 3,
                bounds: CGRect(x: 0, y: 0, width: 400, height: 600),
                alpha: 1.0,
                isOnscreen: false
            )
        ]

        let targetPIDs = WindowService.pidsRequiringMenuPreload(
            from: cgWindows,
            knownTargetPIDs: [40]
        )
        #expect(targetPIDs == [20, 40])
    }
}
