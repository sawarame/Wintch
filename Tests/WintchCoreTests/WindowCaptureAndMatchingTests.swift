import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit
import Testing
@testable import WintchCore

/// 同一矩形ウィンドウの CGWindow 照合、キャプチャ優先順位、およびタイムアウト保護を検証するテストスイート
@Suite("ウィンドウ照合・キャプチャ安定化テスト")
struct WindowCaptureAndMatchingTests {
    /// 同一サイズの複数ウィンドウが存在する環境で、現在スペース上のアクティブウィンドウが
    /// Z オーダー上位の別スペース CGWindow（isOnscreen == false）ではなく表示中（isOnscreen == true）を優先照合することを検証する
    @Test("同一矩形で別スペース窓がZオーダー上位にあっても現在表示中のCGWindowを優先照合する")
    func activeWindowMatchesOnscreenCGWindowOverOffscreenDuplicateBounds() {
        let fullscreenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let entries: [(zOrder: Int, info: WindowService.CGWindowMeta)] = [
            (
                zOrder: 0,
                info: WindowService.CGWindowMeta(
                    windowID: 4880,
                    pid: 1081,
                    layer: 0,
                    bounds: fullscreenRect,
                    alpha: 1.0,
                    isOnscreen: false
                )
            ),
            (
                zOrder: 1,
                info: WindowService.CGWindowMeta(
                    windowID: 55,
                    pid: 1081,
                    layer: 0,
                    bounds: fullscreenRect,
                    alpha: 1.0,
                    isOnscreen: true
                )
            )
        ]

        // 以前誤って別スペース側の 4880 と紐付いていた履歴があっても、現在表示中の 55 を正しく再照合する
        let matched = WindowService.selectBestCGWindowMatch(
            axBounds: fullscreenRect,
            isMinimized: false,
            preferOnscreen: true,
            preferredCGWindowID: 4880,
            in: entries,
            excluding: []
        )

        #expect(matched?.info.windowID == 55)
    }

    /// 既に正しい CGWindow ID が紐付いた複数同サイズ表示中ウィンドウでは ID が入れ替わらず維持されることを検証する
    @Test("同条件の複数ウィンドウでは前回照合済み CGWindow ID の連続性を維持する")
    func continuityPreservesPreferredCGWindowIDWhenVisibilityTies() {
        let rect = CGRect(x: 100, y: 100, width: 1000, height: 700)
        let entries: [(zOrder: Int, info: WindowService.CGWindowMeta)] = [
            (
                zOrder: 0,
                info: WindowService.CGWindowMeta(
                    windowID: 101,
                    pid: 2000,
                    layer: 0,
                    bounds: rect,
                    alpha: 1.0,
                    isOnscreen: true
                )
            ),
            (
                zOrder: 1,
                info: WindowService.CGWindowMeta(
                    windowID: 102,
                    pid: 2000,
                    layer: 0,
                    bounds: rect,
                    alpha: 1.0,
                    isOnscreen: true
                )
            )
        ]

        let matched = WindowService.selectBestCGWindowMatch(
            axBounds: rect,
            isMinimized: false,
            preferOnscreen: true,
            preferredCGWindowID: 102,
            in: entries,
            excluding: []
        )

        #expect(matched?.info.windowID == 102)
    }

    /// キャプチャ優先順位計算が「未キャッシュ表示中 → キャッシュ済み表示中 → 未キャッシュ別スペース → 未キャッシュ最小化」になり、
    /// 既にキャッシュ済みの別スペース・最小化ウィンドウを無駄に再取得しないことを検証する
    @Test("キャプチャ対象IDは未キャッシュかつ画面表示中のウィンドウを最優先に並べる")
    @MainActor
    func prioritizedCaptureWindowIDsOrdersOnScreenUncachedFirst() {
        let entries = [
            WindowEntry(id: "off-cached", cgWindowID: 10, pid: 1, applicationName: "App", windowTitle: "OffCached", isMinimized: false, isOnScreen: false),
            WindowEntry(id: "min-uncached", cgWindowID: 11, pid: 1, applicationName: "App", windowTitle: "MinUncached", isMinimized: true, isOnScreen: false),
            WindowEntry(id: "on-cached", cgWindowID: 12, pid: 1, applicationName: "App", windowTitle: "OnCached", isMinimized: false, isOnScreen: true),
            WindowEntry(id: "off-uncached", cgWindowID: 13, pid: 1, applicationName: "App", windowTitle: "OffUncached", isMinimized: false, isOnScreen: false),
            WindowEntry(id: "on-uncached", cgWindowID: 14, pid: 1, applicationName: "App", windowTitle: "OnUncached", isMinimized: false, isOnScreen: true)
        ]
        let dummyImage = NSImage(size: NSSize(width: 10, height: 10))
        let cached: [UInt32: NSImage] = [
            10: dummyImage,
            12: dummyImage
        ]

        let ordered = SwitcherViewModel.prioritizedCaptureWindowIDs(
            from: entries,
            cachedThumbnails: cached
        )

        #expect(ordered == [14, 12, 13, 11])
    }

    /// runWithTimeout が応答しない非同期処理を待機し続けずタイムアウトで nil を返して解放し、
    /// 期限内完了時は即座に結果を返すことを検証する
    @Test("runWithTimeout はハングした処理をタイムアウトで中断し通常完了時は即座に値を返す")
    func runWithTimeoutProtectsAgainstHungCapture() async {
        let quick = await WindowCaptureService.runWithTimeout(seconds: 0.5) {
            return 42
        }
        #expect(quick == 42)

        let timedOut: Int? = await WindowCaptureService.runWithTimeout(seconds: 0.05) {
            try? await Task.sleep(for: .seconds(5))
            return 99
        }
        #expect(timedOut == nil)
    }

    /// タブ切り替えによるキャッシュ置換判定が、非フルスクリーンの同矩形入れ替えを検出しつつ
    /// スペース移動時のフルスクリーン別ウィンドウを誤削除しないことを検証する
    @Test("isReplacedTabBounds は通常窓のタブ置換を検出しスペース移動時のフルスクリーン誤削除を防ぐ")
    func replacedTabBoundsDetectsTabSwitchWithoutEvictingOtherSpaceFullscreen() {
        let screens = [WindowBounds(x: 0, y: 0, width: 1920, height: 1080)]
        let finderRect = CGRect(x: 472, y: 294, width: 1150, height: 688)
        let fullscreenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let otherRect = CGRect(x: 100, y: 120, width: 1150, height: 688)

        // 非フルスクリーンの同矩形・同最小化状態はタブ切り替えとみなす
        #expect(
            WindowService.isReplacedTabBounds(
                oldBounds: finderRect,
                oldIsMinimized: false,
                newBounds: finderRect,
                newIsMinimized: false,
                allowDisplaySpanningReplacement: false,
                screenBounds: screens
            )
        )

        // 座標が異なる別ウィンドウは置換対象にしない
        #expect(
            !WindowService.isReplacedTabBounds(
                oldBounds: finderRect,
                oldIsMinimized: false,
                newBounds: otherRect,
                newIsMinimized: false,
                allowDisplaySpanningReplacement: true,
                screenBounds: screens
            )
        )

        // スペース移動中（allowDisplaySpanningReplacement == false）のフルスクリーン同矩形は別ウィンドウとして保持
        #expect(
            !WindowService.isReplacedTabBounds(
                oldBounds: fullscreenRect,
                oldIsMinimized: false,
                newBounds: fullscreenRect,
                newIsMinimized: false,
                allowDisplaySpanningReplacement: false,
                screenBounds: screens
            )
        )

        // 同一スペースでのタブ切り替え（allowDisplaySpanningReplacement == true）ならフルスクリーンでも置換対象
        #expect(
            WindowService.isReplacedTabBounds(
                oldBounds: fullscreenRect,
                oldIsMinimized: false,
                newBounds: fullscreenRect,
                newIsMinimized: false,
                allowDisplaySpanningReplacement: true,
                screenBounds: screens
            )
        )
    }

    /// ScreenCaptureKit の権限拒否・エンタイトルメント不足エラーのみを失効対象として識別し、
    /// 一時的なストリーム失敗や別ドメインエラーを誤判定しないことを検証する
    @Test("isPermissionDeniedError は権限拒否とエンタイトルメント不足のみを識別する")
    func permissionDeniedErrorDetectionMatchesOnlyPermissionFailures() {
        let userDeclined = NSError(
            domain: SCStreamError.errorDomain,
            code: SCStreamError.userDeclined.rawValue
        )
        let missingEntitlements = NSError(
            domain: SCStreamError.errorDomain,
            code: SCStreamError.missingEntitlements.rawValue
        )
        let failedToStart = NSError(
            domain: SCStreamError.errorDomain,
            code: SCStreamError.failedToStart.rawValue
        )
        let otherDomain = NSError(
            domain: NSCocoaErrorDomain,
            code: SCStreamError.userDeclined.rawValue
        )

        #expect(WindowCaptureService.isPermissionDeniedError(userDeclined) == true)
        #expect(WindowCaptureService.isPermissionDeniedError(missingEntitlements) == true)
        #expect(WindowCaptureService.isPermissionDeniedError(failedToStart) == false)
        #expect(WindowCaptureService.isPermissionDeniedError(otherDomain) == false)
    }

    /// 実行中に権限失効を検知した場合、サービスおよび共有権限サービスが未許可状態へ切り替わり、
    /// 次回以降の captureThumbnails 呼び出しが即座に抑止されることを検証する
    @Test("権限拒否検知時は共有権限サービスへ失効を記録し以降のステータス確認と再リクエストを抑止する")
    @MainActor
    func permissionDeniedMarksSessionRevokedAndSuppressesSubsequentRequests() async {
        let permissionService = ScreenRecordingPermissionService()
        let captureService = WindowCaptureService(screenRecordingPermissionService: permissionService)

        // 権限拒否を検知すると共有サービスもセッション内失効状態へ遷移する
        captureService.handlePermissionDenied()

        #expect(permissionService.currentStatus() == .denied)
        #expect(permissionService.requestPermission() == false)

        // 失効後は captureThumbnails を呼んでも OS API に進まず安全に即終了する
        var capturedCount = 0
        await captureService.captureThumbnails(
            for: [101, 102],
            maxPixelSize: CGSize(width: 200, height: 120)
        ) { _, _ in
            capturedCount += 1
        }
        #expect(capturedCount == 0)
    }

    /// 全体スキャン時や別スペースに独立 CGWindow が生存している場合、通常サイズの同矩形キャッシュを誤削除しないことを検証する
    @Test("shouldEvictCachedWindowAsReplacedTab は別スペース同矩形ウィンドウを保護し同一スペースの旧タブのみ削除する")
    func shouldEvictCachedWindowProtectsOffspaceSameBoundsWindow() {
        let screens = [WindowBounds(x: 0, y: 0, width: 1920, height: 1080)]
        let normalRect = CGRect(x: 100, y: 100, width: 1200, height: 800)

        // 1. 全体再スキャン・スペース移動時（allowDisplaySpanningReplacement == false）は削除しない
        #expect(
            !WindowService.shouldEvictCachedWindowAsReplacedTab(
                oldBounds: normalRect,
                oldIsMinimized: false,
                oldCGWindowID: nil,
                newBounds: normalRect,
                newIsMinimized: false,
                newCGWindowID: nil,
                survivingCGWindowIDs: [],
                allowDisplaySpanningReplacement: false,
                screenBounds: screens
            )
        )

        // 2. 同一スペースイベント由来でも、別スペースに独立 CGWindowID (201) が生存中なら誤削除しない
        #expect(
            !WindowService.shouldEvictCachedWindowAsReplacedTab(
                oldBounds: normalRect,
                oldIsMinimized: false,
                oldCGWindowID: 201,
                newBounds: normalRect,
                newIsMinimized: false,
                newCGWindowID: 202,
                survivingCGWindowIDs: [201, 202],
                allowDisplaySpanningReplacement: true,
                screenBounds: screens
            )
        )

        // 3. 同一スペース内のタブ置換（同 CGWindowID または消滅済み）は旧タブとして削除する
        #expect(
            WindowService.shouldEvictCachedWindowAsReplacedTab(
                oldBounds: normalRect,
                oldIsMinimized: false,
                oldCGWindowID: 201,
                newBounds: normalRect,
                newIsMinimized: false,
                newCGWindowID: 201,
                survivingCGWindowIDs: [201],
                allowDisplaySpanningReplacement: true,
                screenBounds: screens
            )
        )
        #expect(
            WindowService.shouldEvictCachedWindowAsReplacedTab(
                oldBounds: normalRect,
                oldIsMinimized: false,
                oldCGWindowID: nil,
                newBounds: normalRect,
                newIsMinimized: false,
                newCGWindowID: 202,
                survivingCGWindowIDs: [202],
                allowDisplaySpanningReplacement: true,
                screenBounds: screens
            )
        )
    }

    /// ウィンドウアクティブ化時の実行計画が、メニュー遷移成功時に同期 app.activate を抑止し競合を防ぐことを検証する
    @Test("makeActivationPlan はメニュー遷移成功時に同期前面化を並走させずフォローアップへ委ねる")
    func activationPlanPreventsSyncActivateRaceWhenMenuNavigationSucceeds() {
        // 同一スペース上で AX 捕捉済みなら即時前面化・即時 raiseAXWindow
        let sameSpacePlan = WindowService.makeActivationPlan(
            hasTargetAX: true,
            isPresentInCurrentSpace: true,
            menuNavigationSucceeded: false
        )
        #expect(sameSpacePlan.shouldActivateApplicationImmediately == true)
        #expect(sameSpacePlan.shouldRaiseTargetAXImmediately == true)
        #expect(sameSpacePlan.usesSteppedSpaceFollowUp == false)

        // 別スペース等でメニュー遷移に成功した場合、同期 app.activate() は行わず段階フォローアップへ委ねる
        let menuSuccessPlan = WindowService.makeActivationPlan(
            hasTargetAX: false,
            isPresentInCurrentSpace: false,
            menuNavigationSucceeded: true
        )
        #expect(menuSuccessPlan.shouldActivateApplicationImmediately == false)
        #expect(menuSuccessPlan.shouldRaiseTargetAXImmediately == false)
        #expect(menuSuccessPlan.usesSteppedSpaceFollowUp == true)

        // メニュー遷移が利用不能・失敗した場合のみフォールバックとして即時 app.activate() する
        let menuFailurePlan = WindowService.makeActivationPlan(
            hasTargetAX: true,
            isPresentInCurrentSpace: false,
            menuNavigationSucceeded: false
        )
        #expect(menuFailurePlan.shouldActivateApplicationImmediately == true)
        #expect(menuFailurePlan.shouldRaiseTargetAXImmediately == true)
        #expect(menuFailurePlan.usesSteppedSpaceFollowUp == true)
    }

    /// メニューキャッシュの鮮度判定が TTL（2.0秒）以内のみ有効とみなすことを検証する
    @Test("isMenuCacheFresh は TTL 以内のみ有効とし期限切れや逆転時刻を無効と判定する")
    func menuCacheFreshnessChecksTTLBoundaries() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(WindowService.isMenuCacheFresh(fetchedAt: baseDate, now: baseDate.addingTimeInterval(0.5), ttl: 2.0) == true)
        #expect(WindowService.isMenuCacheFresh(fetchedAt: baseDate, now: baseDate.addingTimeInterval(2.0), ttl: 2.0) == true)
        #expect(WindowService.isMenuCacheFresh(fetchedAt: baseDate, now: baseDate.addingTimeInterval(2.01), ttl: 2.0) == false)
        #expect(WindowService.isMenuCacheFresh(fetchedAt: baseDate, now: baseDate.addingTimeInterval(-0.5), ttl: 2.0) == false)
    }

    /// 同一矩形の複数オフスクリーン CGWindow が存在する場合、axTitle と一致する name を持つ CGWindow を優先照合することを検証する
    @Test("selectBestCGWindowMatch は同条件の複数CGWindow間でaxTitleと一致するnameを優先する")
    func selectBestCGWindowMatchPrefersMatchingCGWindowName() {
        let rect = CGRect(x: 0, y: 88, width: 1920, height: 992)
        let entries: [(zOrder: Int, info: WindowService.CGWindowMeta)] = [
            (
                zOrder: 0,
                info: WindowService.CGWindowMeta(
                    windowID: 377,
                    pid: 1871,
                    layer: 0,
                    bounds: rect,
                    alpha: 1.0,
                    isOnscreen: false,
                    name: ""
                )
            ),
            (
                zOrder: 1,
                info: WindowService.CGWindowMeta(
                    windowID: 409,
                    pid: 1871,
                    layer: 0,
                    bounds: rect,
                    alpha: 1.0,
                    isOnscreen: false,
                    name: "新しいタブ"
                )
            ),
            (
                zOrder: 2,
                info: WindowService.CGWindowMeta(
                    windowID: 111,
                    pid: 1871,
                    layer: 0,
                    bounds: rect,
                    alpha: 1.0,
                    isOnscreen: false,
                    name: "tipsを表示する · Issue #17 · sawarame/Nickmark"
                )
            )
        ]

        let matched = WindowService.selectBestCGWindowMatch(
            axBounds: rect,
            axTitle: "tipsを表示する · Issue #17 · sawarame/Nickmark",
            isMinimized: false,
            preferOnscreen: false,
            preferredCGWindowID: nil,
            in: entries,
            excluding: []
        )
        #expect(matched?.info.windowID == 111)
    }

    /// pruneCache が閉じ済みウィンドウのキャッシュのみ破棄して生存ウィンドウの LRU 順を維持し、
    /// デフォルト上限 100 件・カスタム上限での最古追い出しが正しく動作することを検証する
    @Test("WindowCaptureService は生存ウィンドウ以外を自動整理し上限 100 件の LRU 順を正しく維持する")
    @MainActor
    func captureCachePrunesStaleWindowsAndEnforcesLRUWithCapacity100() {
        #expect(WindowCaptureService.defaultMaxCacheCount == 100)

        let defaultService = WindowCaptureService()
        for id: UInt32 in 1...100 {
            defaultService.storeInCache(NSImage(size: NSSize(width: 20, height: 20)), for: id)
        }
        // 100 件までは追い出しが発生しない
        #expect(defaultService.cacheOrder.count == 100)
        #expect(defaultService.cachedThumbnail(for: 1) != nil)

        let smallService = WindowCaptureService(maxCacheCount: 3)
        let img1 = NSImage(size: NSSize(width: 10, height: 10))
        let img2 = NSImage(size: NSSize(width: 10, height: 10))
        let img3 = NSImage(size: NSSize(width: 10, height: 10))
        let img4 = NSImage(size: NSSize(width: 10, height: 10))

        smallService.storeInCache(img1, for: 10)
        smallService.storeInCache(img2, for: 20)
        smallService.storeInCache(img3, for: 30)
        #expect(smallService.cacheOrder == [10, 20, 30])

        // 20 を閉じ済みとして整理すると、10 と 30 およびその相対順のみが維持される
        smallService.pruneCache(keeping: [10, 30])
        #expect(smallService.cacheOrder == [10, 30])
        #expect(smallService.cachedThumbnail(for: 20) == nil)

        // 10 を参照すると末尾（最新）へ移動するため、新規追加で追い出されるのは最古の 30 になる
        #expect(smallService.cachedThumbnail(for: 10) === img1)
        #expect(smallService.cacheOrder == [30, 10])

        smallService.storeInCache(img2, for: 20)
        smallService.storeInCache(img4, for: 40)
        #expect(smallService.cacheOrder == [10, 20, 40])
        #expect(smallService.cachedThumbnail(for: 30) == nil)
        #expect(smallService.cachedThumbnail(for: 10) === img1)
    }

    /// タイトル変化やサイズ変化による包含フォールバック時にも、無名空き殻窓へ乗り換えず
    /// preferredCGWindowID の連続性と非空 cgWindowName を優先して維持することを検証する
    @Test("selectBestCGWindowMatch は包含フォールバックやタイトル不一致時も既存ID連続性と非空名を優先する")
    func selectBestCGWindowMatchPreservesContinuityAndPrefersNamedWindow() {
        let axRect = CGRect(x: 0, y: 88, width: 1920, height: 992)
        // 空き殻窓 (377) の方が面積が大きく Z オーダー上位にある状況で、本物の窓 (111) とリサイズ包含照合する
        let containmentEntries: [(zOrder: Int, info: WindowService.CGWindowMeta)] = [
            (
                zOrder: 0,
                info: WindowService.CGWindowMeta(
                    windowID: 377,
                    pid: 1871,
                    layer: 0,
                    bounds: CGRect(x: 0, y: 38, width: 1920, height: 1042),
                    alpha: 1.0,
                    isOnscreen: true,
                    name: ""
                )
            ),
            (
                zOrder: 1,
                info: WindowService.CGWindowMeta(
                    windowID: 111,
                    pid: 1871,
                    layer: 0,
                    bounds: CGRect(x: 0, y: 120, width: 1860, height: 940),
                    alpha: 1.0,
                    isOnscreen: true,
                    name: "新しいタブ"
                )
            )
        ]

        // 1. タイトルが変化して一時不一致になっても、preferredCGWindowID(111) と非空名を維持する
        let matchedByContinuity = WindowService.selectBestCGWindowMatch(
            axBounds: axRect,
            axTitle: "遷移中タイトル",
            isMinimized: false,
            preferOnscreen: true,
            preferredCGWindowID: 111,
            in: containmentEntries,
            excluding: []
        )
        #expect(matchedByContinuity?.info.windowID == 111)

        // 2. preferredCGWindowID が未設定の場合も、無名空き殻窓ではなく非空タイトル窓を優先する
        let matchedNamed = WindowService.selectBestCGWindowMatch(
            axBounds: axRect,
            axTitle: nil,
            isMinimized: false,
            preferOnscreen: true,
            preferredCGWindowID: nil,
            in: containmentEntries,
            excluding: []
        )
        #expect(matchedNamed?.info.windowID == 111)

        // 3. 近接マッチでタイトル未一致時も、無名空き殻窓ではなく非空タイトル窓を優先する
        let sameRectEntries: [(zOrder: Int, info: WindowService.CGWindowMeta)] = [
            (
                zOrder: 0,
                info: WindowService.CGWindowMeta(
                    windowID: 500,
                    pid: 1871,
                    layer: 0,
                    bounds: axRect,
                    alpha: 1.0,
                    isOnscreen: false,
                    name: ""
                )
            ),
            (
                zOrder: 1,
                info: WindowService.CGWindowMeta(
                    windowID: 501,
                    pid: 1871,
                    layer: 0,
                    bounds: axRect,
                    alpha: 1.0,
                    isOnscreen: false,
                    name: "Document"
                )
            )
        ]
        let matchedProximityNamed = WindowService.selectBestCGWindowMatch(
            axBounds: axRect,
            axTitle: nil,
            isMinimized: false,
            preferOnscreen: false,
            preferredCGWindowID: nil,
            in: sameRectEntries,
            excluding: []
        )
        #expect(matchedProximityNamed?.info.windowID == 501)
    }

    /// 幅または高さが 0 以下の無効なキャプチャ画像サイズを拒否することを検証する
    @Test("isValidCapturedImageSize は 1px 以上の画像サイズのみ許可する")
    func validCapturedImageSizeRejectsEmptyDimensions() {
        #expect(WindowCaptureService.isValidCapturedImageSize(CGSize(width: 0, height: 0)) == false)
        #expect(WindowCaptureService.isValidCapturedImageSize(CGSize(width: 0, height: 120)) == false)
        #expect(WindowCaptureService.isValidCapturedImageSize(CGSize(width: 200, height: 0)) == false)
        #expect(WindowCaptureService.isValidCapturedImageSize(CGSize(width: 1, height: 1)) == true)
        #expect(WindowCaptureService.isValidCapturedImageSize(CGSize(width: 432, height: 270)) == true)
    }
}
