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

        // プロファイル名サフィックス付き AX タイトルでも対応する CGWindow 名と正しく一致照合すること
        let matchedWithProfileSuffix = WindowService.selectBestCGWindowMatch(
            axBounds: rect,
            axTitle: "tipsを表示する · Issue #17 · sawarame/Nickmark - Google Chrome - Yasushi",
            applicationName: "Google Chrome",
            isMinimized: false,
            preferOnscreen: false,
            preferredCGWindowID: nil,
            in: entries,
            excluding: []
        )
        #expect(matchedWithProfileSuffix?.info.windowID == 111)
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

    /// shouldRetainCachedAXWindow が閉鎖済みで対応 CGWindowID を失った非現在スキャン要素を確実に破棄し、
    /// 別スペースに生存しているウィンドウや現在スキャン捕捉済みウィンドウを保持することを検証する
    @Test("shouldRetainCachedAXWindow は対応CGWindowIDが消滅した閉鎖済みキャッシュを破棄し別スペース生存窓を保持する")
    func shouldRetainCachedAXWindowEvictsClosedWindowWhoseCGWindowDisappeared() {
        // 1. 今回の AX スキャンに不在で、かつ前回確定していた knownCGWindowID(58) が消滅している場合は、
        //    たとえ AXRole 読み取りが一時的に .success を返しても閉鎖済みとして破棄し、空き殻 (377) への乗り換えを防ぐ
        #expect(
            WindowService.shouldRetainCachedAXWindow(
                isPresentInLatestAXScan: false,
                knownCGWindowID: 58,
                axRoleCheckResult: .success,
                survivingCGWindowIDs: [377, 76],
                hasSubstantialCGWindow: true
            ) == false
        )

        // 2. 別スペースに存在し、対応する knownCGWindowID(58) が現在も生存している場合は保持する
        #expect(
            WindowService.shouldRetainCachedAXWindow(
                isPresentInLatestAXScan: false,
                knownCGWindowID: 58,
                axRoleCheckResult: .success,
                survivingCGWindowIDs: [58, 377],
                hasSubstantialCGWindow: true
            ) == true
        )
        #expect(
            WindowService.shouldRetainCachedAXWindow(
                isPresentInLatestAXScan: false,
                knownCGWindowID: 58,
                axRoleCheckResult: .cannotComplete,
                survivingCGWindowIDs: [58],
                hasSubstantialCGWindow: true
            ) == true
        )

        // 3. 最新スキャン不在かつ knownCGWindowID 未確定で .cannotComplete となった要素は、裏方 CGWindow だけでは延命しない
        #expect(
            WindowService.shouldRetainCachedAXWindow(
                isPresentInLatestAXScan: false,
                knownCGWindowID: nil,
                axRoleCheckResult: .cannotComplete,
                survivingCGWindowIDs: [377],
                hasSubstantialCGWindow: true
            ) == false
        )

        // 4. 最新スキャンで捕捉されている要素は .cannotComplete でも実質 CGWindow があれば保持し、.invalidUIElement は破棄する
        #expect(
            WindowService.shouldRetainCachedAXWindow(
                isPresentInLatestAXScan: true,
                knownCGWindowID: nil,
                axRoleCheckResult: .cannotComplete,
                survivingCGWindowIDs: [58],
                hasSubstantialCGWindow: true
            ) == true
        )
        #expect(
            WindowService.shouldRetainCachedAXWindow(
                isPresentInLatestAXScan: true,
                knownCGWindowID: 58,
                axRoleCheckResult: .invalidUIElement,
                survivingCGWindowIDs: [58],
                hasSubstantialCGWindow: true
            ) == false
        )
    }

    /// isWindowInCurrentSpace が kAXFocusedWindow 等で別スペースから AX 捕捉された非最小化オフスクリーンウィンドウを
    /// 現在スペース不在（false）と正しく判定し、現在スペース表示中や最小化ウィンドウを true と判定することを検証する
    @Test("isWindowInCurrentSpace は別スペースのフォーカス補完AX窓を現在スペース不在と判定する")
    func isWindowInCurrentSpaceDistinguishesOffspaceFocusedAXWindow() {
        // 1. 現在スペース上に表示中の AX ウィンドウ -> true
        #expect(
            WindowService.isWindowInCurrentSpace(
                isPresentInLatestAXScan: true,
                isOnScreen: true,
                isMinimized: false
            ) == true
        )

        // 2. kAXFocusedWindowAttribute 等で捕捉されたが isOnScreen == false かつ非最小化（別スペース在籍） -> false
        #expect(
            WindowService.isWindowInCurrentSpace(
                isPresentInLatestAXScan: true,
                isOnScreen: false,
                isMinimized: false
            ) == false
        )

        // 3. 最小化中の AX ウィンドウ（isOnScreen == false でも最小化解除で現在スペース復帰可能） -> true
        #expect(
            WindowService.isWindowInCurrentSpace(
                isPresentInLatestAXScan: true,
                isOnScreen: false,
                isMinimized: true
            ) == true
        )

        // 4. 最新 AX スキャンで未捕捉 -> false
        #expect(
            WindowService.isWindowInCurrentSpace(
                isPresentInLatestAXScan: false,
                isOnScreen: true,
                isMinimized: false
            ) == false
        )
    }

    /// shouldEmitCachedAXWindow が、最新 AX スキャンに不在かつ WindowServer 上の対応 CGWindow も消滅した閉鎖済みキャッシュを除外し、
    /// 現在スペース捕捉済みまたは別スペースに生存 CGWindow が存在するキャッシュのみを保持することを検証する
    @Test("shouldEmitCachedAXWindow はAX不在かつ生存CGWindow無しの閉鎖済みキャッシュを出力しない")
    func shouldEmitCachedAXWindowExcludesNonExistentClosedWindow() {
        // 1. 最新 AX スキャンに不在かつ照合できた生存 CGWindow も無い場合は閉鎖済みとして除外する
        #expect(
            WindowService.shouldEmitCachedAXWindow(
                isPresentInLatestAXScan: false,
                resolvedCGWindowID: nil
            ) == false
        )

        // 2. 別スペース等に生存中の対応 CGWindow が確認できた場合は保持・出力する
        #expect(
            WindowService.shouldEmitCachedAXWindow(
                isPresentInLatestAXScan: false,
                resolvedCGWindowID: 511
            ) == true
        )

        // 3. 最新 AX スキャンで現在スペース上に捕捉されている場合は保持・出力する
        #expect(
            WindowService.shouldEmitCachedAXWindow(
                isPresentInLatestAXScan: true,
                resolvedCGWindowID: nil
            ) == true
        )
    }

    /// selectBestCGWindowMatch が通常ウィンドウ（非フローティング）に対して、
    /// Figma の 400x600（layer=3, isOnscreen=false）のようなオフスクリーン非通常レイヤー補助窓を
    /// 近接照合および包含フォールバックのいずれでも誤照合しないことを検証する
    @Test("selectBestCGWindowMatch は通常ウィンドウに対してオフスクリーンlayer=3補助窓を誤照合しない")
    func selectBestCGWindowMatchDoesNotMatchOffscreenFloatingBackingWindowForStandardWindow() {
        let figmaBacking400 = (
            zOrder: 0,
            info: WindowService.CGWindowMeta(
                windowID: 432,
                pid: 14934,
                layer: 3,
                bounds: CGRect(x: 760, y: 208, width: 400, height: 600),
                alpha: 1.0,
                isOnscreen: false,
                name: "Figma"
            )
        )
        let figmaTopStrip = (
            zOrder: 1,
            info: WindowService.CGWindowMeta(
                windowID: 427,
                pid: 14934,
                layer: 0,
                bounds: CGRect(x: 0, y: 0, width: 1920, height: 30),
                alpha: 1.0,
                isOnscreen: false,
                name: ""
            )
        )

        // 1. 近接距離内（同矩形 400x600）にあっても非フローティング通常ウィンドウなら照合しない
        let proximityBlocked = WindowService.selectBestCGWindowMatch(
            axBounds: CGRect(x: 760, y: 208, width: 400, height: 600),
            axTitle: "Design File — Figma",
            isMinimized: false,
            preferOnscreen: false,
            preferredCGWindowID: nil,
            allowOffscreenNonZeroLayer: false,
            in: [figmaBacking400, figmaTopStrip],
            excluding: []
        )
        #expect(proximityBlocked == nil)

        // 2. 包含関係（800x600 の通常ウィンドウ内に 400x600 補助窓が収まるケース）でも誤照合しない
        let containmentBlocked = WindowService.selectBestCGWindowMatch(
            axBounds: CGRect(x: 560, y: 208, width: 800, height: 600),
            axTitle: "Design File — Figma",
            isMinimized: false,
            preferOnscreen: false,
            preferredCGWindowID: nil,
            allowOffscreenNonZeroLayer: false,
            in: [figmaBacking400, figmaTopStrip],
            excluding: []
        )
        #expect(containmentBlocked == nil)

        // 3. フローティングサブロール（allowOffscreenNonZeroLayer: true）であれば近接照合できる
        let floatingAllowed = WindowService.selectBestCGWindowMatch(
            axBounds: CGRect(x: 760, y: 208, width: 400, height: 600),
            axTitle: "Palette",
            isMinimized: false,
            preferOnscreen: false,
            preferredCGWindowID: nil,
            allowOffscreenNonZeroLayer: true,
            in: [figmaBacking400],
            excluding: []
        )
        #expect(floatingAllowed?.info.windowID == 432)
    }

    /// shouldRetainOffscreenCachedAXWindow が、orderOut 等で CGWindow を残すアプリの閉鎖済みオフスクリーンキャッシュを破棄し、
    /// メニュー確認済みの別スペース窓・最小化窓・アプリ非表示中・現在スペース表示中・対象外アプリを保持することを検証する
    @Test("shouldRetainOffscreenCachedAXWindow は未確認のorderOut閉鎖キャッシュを破棄し生存ウィンドウを保持する")
    func shouldRetainOffscreenCachedAXWindowEvictsClosedOrderOutAndKeepsLegitimateWindows() {
        let matchingMenu = [
            WindowMenuItemSnapshot(
                title: "Gemini",
                identifier: "makeKeyAndOrderFront:",
                mark: nil,
                index: 12
            )
        ]

        // 1. 閉鎖済み（AX 不在・非最小化・アプリ非表示なし・CG 非表示・ウィンドウメニュー不一致） -> 破棄
        #expect(
            WindowService.shouldRetainOffscreenCachedAXWindow(
                requiresLiveVerificationWhenOffscreen: true,
                isPresentInLatestAXScan: false,
                isMinimized: false,
                isAppHidden: false,
                isCGOnScreen: false,
                title: "Gemini",
                menuItems: []
            ) == false
        )

        // 2. 別スペースで実際に開いている（ウィンドウメニューに同一タイトルが存在） -> 保持
        #expect(
            WindowService.shouldRetainOffscreenCachedAXWindow(
                requiresLiveVerificationWhenOffscreen: true,
                isPresentInLatestAXScan: false,
                isMinimized: false,
                isAppHidden: false,
                isCGOnScreen: false,
                title: "Gemini",
                menuItems: matchingMenu
            ) == true
        )

        // 3. 最小化・アプリ非表示（Cmd+H）・画面表示中・最新 AX 捕捉済み・対象外アプリ -> 保持
        #expect(
            WindowService.shouldRetainOffscreenCachedAXWindow(
                requiresLiveVerificationWhenOffscreen: true,
                isPresentInLatestAXScan: false,
                isMinimized: true,
                isAppHidden: false,
                isCGOnScreen: false,
                title: "Gemini",
                menuItems: []
            ) == true
        )
        #expect(
            WindowService.shouldRetainOffscreenCachedAXWindow(
                requiresLiveVerificationWhenOffscreen: true,
                isPresentInLatestAXScan: false,
                isMinimized: false,
                isAppHidden: true,
                isCGOnScreen: false,
                title: "Gemini",
                menuItems: []
            ) == true
        )
        #expect(
            WindowService.shouldRetainOffscreenCachedAXWindow(
                requiresLiveVerificationWhenOffscreen: true,
                isPresentInLatestAXScan: false,
                isMinimized: false,
                isAppHidden: false,
                isCGOnScreen: true,
                title: "Gemini",
                menuItems: []
            ) == true
        )
        #expect(
            WindowService.shouldRetainOffscreenCachedAXWindow(
                requiresLiveVerificationWhenOffscreen: true,
                isPresentInLatestAXScan: true,
                isMinimized: false,
                isAppHidden: false,
                isCGOnScreen: false,
                title: "Gemini",
                menuItems: []
            ) == true
        )
        #expect(
            WindowService.shouldRetainOffscreenCachedAXWindow(
                requiresLiveVerificationWhenOffscreen: false,
                isPresentInLatestAXScan: false,
                isMinimized: false,
                isAppHidden: false,
                isCGOnScreen: false,
                title: "メモ",
                menuItems: []
            ) == true
        )
    }

    /// evaluateAXWindowLivenessFromList が、kAXWindowsAttribute 成功時の空配列をクローズ済み（false）と判定し、
    /// 取得失敗時のみ要素ロール確認へのフォールバック（nil）を指示することを検証する
    @Test("evaluateAXWindowLivenessFromList はkAXWindows成功時の不在を閉鎖済みと判定する")
    func evaluateAXWindowLivenessFromListTreatsSuccessfulEmptyListAsClosed() {
        #expect(
            WindowService.evaluateAXWindowLivenessFromList(
                windowsAttributeSucceeded: true,
                containsTarget: true
            ) == true
        )
        #expect(
            WindowService.evaluateAXWindowLivenessFromList(
                windowsAttributeSucceeded: true,
                containsTarget: false
            ) == false
        )
        #expect(
            WindowService.evaluateAXWindowLivenessFromList(
                windowsAttributeSucceeded: false,
                containsTarget: true
            ) == true
        )
        #expect(
            WindowService.evaluateAXWindowLivenessFromList(
                windowsAttributeSucceeded: false,
                containsTarget: false
            ) == nil
        )
    }

    /// hasCachedThumbnail がキャッシュの有無を正しく返しつつ、LRU のアクセス順序を変更しないことを検証する
    @Test("WindowCaptureService.hasCachedThumbnail は LRU 順序を変更せずにキャッシュ存在を判定する")
    @MainActor
    func hasCachedThumbnailDoesNotMutateLRUOrder() {
        let service = WindowCaptureService(maxCacheCount: 3)
        let img1 = NSImage(size: NSSize(width: 10, height: 10))
        let img2 = NSImage(size: NSSize(width: 10, height: 10))
        let img3 = NSImage(size: NSSize(width: 10, height: 10))

        service.storeInCache(img1, for: 10)
        service.storeInCache(img2, for: 20)
        service.storeInCache(img3, for: 30)
        #expect(service.cacheOrder == [10, 20, 30])

        #expect(service.hasCachedThumbnail(for: 10) == true)
        #expect(service.hasCachedThumbnail(for: 99) == false)
        // 存在確認のみでは最古エントリ (10) が末尾へ移動しないこと
        #expect(service.cacheOrder == [10, 20, 30])
    }

    /// uncachedOnScreenPrefetchWindowIDs が現在スペース表示中かつ未キャッシュの通常ウィンドウのみを
    /// MRU 順・重複除外済みで抽出し、別スペース・最小化・既キャッシュ・表示状態不明を除外することを検証する
    @Test("uncachedOnScreenPrefetchWindowIDs は現在表示中かつ未キャッシュのウィンドウ ID のみを抽出する")
    @MainActor
    func uncachedOnScreenPrefetchWindowIDsSelectsOnlyVisibleUncachedWindows() {
        let entries = [
            WindowEntry(id: "cached-on", cgWindowID: 10, pid: 1, applicationName: "App", windowTitle: "CachedOn", isMinimized: false, isOnScreen: true),
            WindowEntry(id: "uncached-on-1", cgWindowID: 11, pid: 1, applicationName: "App", windowTitle: "UncachedOn1", isMinimized: false, isOnScreen: true),
            WindowEntry(id: "offscreen", cgWindowID: 12, pid: 1, applicationName: "App", windowTitle: "Offscreen", isMinimized: false, isOnScreen: false),
            WindowEntry(id: "unknown-visibility", cgWindowID: 13, pid: 1, applicationName: "App", windowTitle: "Unknown", isMinimized: false, isOnScreen: nil),
            WindowEntry(id: "minimized", cgWindowID: 14, pid: 1, applicationName: "App", windowTitle: "Minimized", isMinimized: true, isOnScreen: true),
            WindowEntry(id: "no-cgid", cgWindowID: nil, pid: 1, applicationName: "App", windowTitle: "NoCG", isMinimized: false, isOnScreen: true),
            WindowEntry(id: "duplicate-id", cgWindowID: 11, pid: 1, applicationName: "App", windowTitle: "Dup", isMinimized: false, isOnScreen: true),
            WindowEntry(id: "uncached-on-2", cgWindowID: 15, pid: 2, applicationName: "App2", windowTitle: "UncachedOn2", isMinimized: false, isOnScreen: true)
        ]
        let cachedIDs: Set<UInt32> = [10]

        let targetIDs = SwitcherViewModel.uncachedOnScreenPrefetchWindowIDs(
            from: entries,
            isCached: { cachedIDs.contains($0) }
        )

        #expect(targetIDs == [11, 15])
    }

    /// AXObserver 通知種別からの事前キャプチャ／更新契機判定が、
    /// ウィンドウ作成・最小化解除・フォーカス/メインウィンドウ変更・タイトル変更を正しくマッピングすることを検証する
    @Test("WindowService.capturePrefetchReason はウィンドウ作成・最小化解除・フォーカス・タイトル変更を契機へ変換する")
    func capturePrefetchReasonForAXNotificationMapsExpectedEvents() {
        #expect(WindowService.capturePrefetchReason(forAXNotification: kAXWindowCreatedNotification) == .windowCreated)
        #expect(WindowService.capturePrefetchReason(forAXNotification: kAXWindowDeminiaturizedNotification) == .windowDeminiaturized)
        #expect(WindowService.capturePrefetchReason(forAXNotification: kAXFocusedWindowChangedNotification) == .windowFocusChanged)
        #expect(WindowService.capturePrefetchReason(forAXNotification: kAXMainWindowChangedNotification) == .windowFocusChanged)
        #expect(WindowService.capturePrefetchReason(forAXNotification: kAXTitleChangedNotification) == .windowTitleChanged)
        #expect(WindowService.capturePrefetchReason(forAXNotification: kAXWindowMiniaturizedNotification) == nil)
    }

    /// WindowCaptureService が各サムネイルの最終取得時刻を LRU 順序を変更せずに参照でき、
    /// 無効化・整理・全破棄・LRU 追い出し時に画像と時刻の整合性を維持することを検証する
    @Test("WindowCaptureService は最終取得時刻を LRU 不変で管理し無効化・整理・追い出し・全破棄で整合を保つ")
    @MainActor
    func captureServiceTracksLastCapturedAtWithoutMutatingLRUAndCleansUpConsistently() {
        let clock = MutableTestClock(initial: Date(timeIntervalSince1970: 1_700_000_000))
        let service = WindowCaptureService(maxCacheCount: 2, nowProvider: { clock.now })
        let img1 = NSImage(size: NSSize(width: 10, height: 10))
        let img2 = NSImage(size: NSSize(width: 10, height: 10))
        let img3 = NSImage(size: NSSize(width: 10, height: 10))

        let t0 = clock.now
        service.storeInCache(img1, for: 10)
        clock.advance(by: 3)
        let t1 = clock.now
        service.storeInCache(img2, for: 20)
        #expect(service.cacheOrder == [10, 20])

        // lastCapturedAt は LRU 順序を変更せずに最終取得時刻を返す
        #expect(service.lastCapturedAt(for: 10) == t0)
        #expect(service.lastCapturedAt(for: 20) == t1)
        #expect(service.lastCapturedAt(for: 99) == nil)
        #expect(service.cacheOrder == [10, 20])

        // LRU 追い出し（上限 2 件へ 3 件目格納）で最古の 10 の画像・時刻がともに削除される
        clock.advance(by: 4)
        let t2 = clock.now
        service.storeInCache(img3, for: 30)
        #expect(service.cacheOrder == [20, 30])
        #expect(service.lastCapturedAt(for: 10) == nil)
        #expect(service.hasCachedThumbnail(for: 10) == false)
        #expect(service.lastCapturedAt(for: 30) == t2)

        // 再格納すると最終取得時刻が最新時刻へ更新される
        clock.advance(by: 5)
        let t3 = clock.now
        service.storeInCache(img2, for: 20)
        #expect(service.lastCapturedAt(for: 20) == t3)

        // invalidateThumbnail で画像・時刻ともに削除される
        service.invalidateThumbnail(for: 20)
        #expect(service.lastCapturedAt(for: 20) == nil)
        #expect(service.hasCachedThumbnail(for: 20) == false)

        // pruneCache で除外されたウィンドウの時刻も削除される
        service.storeInCache(img1, for: 40)
        service.pruneCache(keeping: [40])
        #expect(service.lastCapturedAt(for: 30) == nil)
        #expect(service.lastCapturedAt(for: 40) != nil)

        // clearCache で全時刻・全画像が破棄される
        service.clearCache()
        #expect(service.lastCapturedAt(for: 40) == nil)
        #expect(service.hasCachedThumbnail(for: 40) == false)
    }

    /// WindowCaptureRefreshPolicy の起動時一括取得・イベント駆動更新・定期更新の対象選定順、
    /// クールダウン境界判定、および契機マージが仕様どおりに動作することを検証する
    @Test("WindowCaptureRefreshPolicy は起動時一括・イベント・定期更新の優先順とクールダウン境界を正しく判定する")
    func captureRefreshPolicyPrioritizesTargetsAndEvaluatesCooldownAndMerging() {
        let baseNow = Date(timeIntervalSince1970: 1_700_000_100)
        let entries = [
            // MRU 0: 現在スペース表示中・キャッシュ済み（クールダウン未経過: 4.9秒前）
            WindowEntry(id: "on-fresh", cgWindowID: 1, pid: 1, applicationName: "A", windowTitle: "OnFresh", isMinimized: false, isOnScreen: true),
            // MRU 1: 最小化・未キャッシュ
            WindowEntry(id: "min-uncached", cgWindowID: 2, pid: 1, applicationName: "A", windowTitle: "MinUncached", isMinimized: true, isOnScreen: false),
            // MRU 2: 現在スペース表示中・キャッシュ済み（クールダウン経過済み: 6秒前）
            WindowEntry(id: "on-stale-newer", cgWindowID: 3, pid: 1, applicationName: "A", windowTitle: "OnStaleNewer", isMinimized: false, isOnScreen: true),
            // MRU 3: 別スペース・未キャッシュ
            WindowEntry(id: "off-uncached", cgWindowID: 4, pid: 1, applicationName: "A", windowTitle: "OffUncached", isMinimized: false, isOnScreen: false),
            // MRU 4: 現在スペース表示中・未キャッシュ
            WindowEntry(id: "on-uncached", cgWindowID: 5, pid: 1, applicationName: "A", windowTitle: "OnUncached", isMinimized: false, isOnScreen: true),
            // MRU 5: 現在スペース表示中・キャッシュ済み（クールダウン経過済み: 20秒前・最古）
            WindowEntry(id: "on-stale-oldest", cgWindowID: 6, pid: 1, applicationName: "A", windowTitle: "OnStaleOldest", isMinimized: false, isOnScreen: true),
            // MRU 6: 別スペース・キャッシュ済み（クールダウン経過済みでも対象外）
            WindowEntry(id: "off-cached", cgWindowID: 7, pid: 1, applicationName: "A", windowTitle: "OffCached", isMinimized: false, isOnScreen: false),
            // MRU 7: 最小化・キャッシュ済み（対象外）
            WindowEntry(id: "min-cached", cgWindowID: 8, pid: 1, applicationName: "A", windowTitle: "MinCached", isMinimized: true, isOnScreen: false),
            // MRU 8: 重複 cgWindowID（除外される）
            WindowEntry(id: "dup", cgWindowID: 5, pid: 1, applicationName: "A", windowTitle: "Dup", isMinimized: false, isOnScreen: true),
            // MRU 9: 現在スペース表示中・キャッシュ済み（ちょうど 5.0 秒前 = 境界で経過扱い）
            WindowEntry(id: "on-boundary", cgWindowID: 9, pid: 1, applicationName: "A", windowTitle: "OnBoundary", isMinimized: false, isOnScreen: true),
            // MRU 10: オフスクリーン（isOnScreen == nil）・未キャッシュ
            WindowEntry(id: "unknown-off-uncached", cgWindowID: 10, pid: 1, applicationName: "A", windowTitle: "UnknownOff", isMinimized: false, isOnScreen: nil)
        ]

        let timestamps: [UInt32: Date] = [
            1: baseNow.addingTimeInterval(-4.9),
            3: baseNow.addingTimeInterval(-6.0),
            6: baseNow.addingTimeInterval(-20.0),
            7: baseNow.addingTimeInterval(-30.0),
            8: baseNow.addingTimeInterval(-30.0),
            9: baseNow.addingTimeInterval(-5.0)
        ]

        // 1. 起動時・切替時一括取得: 現在スペース未キャッシュ(5) -> 現在スペースクールダウン経過済み MRU順(3, 6, 9) -> 別スペース未キャッシュ(4, 10) -> 最小化未キャッシュ(2)
        let startupIDs = WindowCaptureRefreshPolicy.startupBulkPrefetchWindowIDs(
            from: entries,
            isCached: { timestamps[$0] != nil },
            lastCapturedAt: { timestamps[$0] },
            now: baseNow,
            cooldown: 5.0
        )
        #expect(startupIDs == [5, 3, 6, 9, 4, 10, 2])

        // 2. イベント駆動更新: 現在スペース未キャッシュ(5) -> 現在スペースクールダウン経過済み MRU順(3, 6, 9) のみ
        let eventIDs = WindowCaptureRefreshPolicy.eventPrefetchWindowIDs(
            from: entries,
            isCached: { timestamps[$0] != nil },
            lastCapturedAt: { timestamps[$0] },
            now: baseNow,
            cooldown: 5.0
        )
        #expect(eventIDs == [5, 3, 6, 9])

        // 3. 定期更新: 現在スペース未キャッシュ(5) -> 現在スペースクールダウン経過済み 古いキャッシュ順(6:20秒前, 3:6秒前, 9:5秒前)
        let periodicIDs = WindowCaptureRefreshPolicy.periodicRefreshWindowIDs(
            from: entries,
            isCached: { timestamps[$0] != nil },
            lastCapturedAt: { timestamps[$0] },
            now: baseNow,
            cooldown: 5.0
        )
        #expect(periodicIDs == [5, 6, 3, 9])

        // 4. 時刻逆転時はクールダウン未経過扱い
        #expect(
            WindowCaptureRefreshPolicy.isCooldownElapsed(
                lastCapturedAt: baseNow.addingTimeInterval(2.0),
                now: baseNow,
                cooldown: 5.0
            ) == false
        )

        // 5. 即時一括取得判定と契機マージ（一括取得契機は通常イベントで降格されない）
        #expect(WindowCaptureRefreshPolicy.isImmediateBulkPrefetch(reason: .initialScanCompleted) == true)
        #expect(WindowCaptureRefreshPolicy.isImmediateBulkPrefetch(reason: .displayStyleEnabled) == true)
        #expect(WindowCaptureRefreshPolicy.isImmediateBulkPrefetch(reason: .applicationActivated) == false)
        #expect(WindowCaptureRefreshPolicy.isImmediateBulkPrefetch(reason: .windowFocusChanged) == false)
        #expect(WindowCaptureRefreshPolicy.isImmediateBulkPrefetch(reason: .windowTitleChanged) == false)
        #expect(
            WindowCaptureRefreshPolicy.mergePendingPrefetchReason(
                existing: .initialScanCompleted,
                incoming: .windowTitleChanged
            ) == .initialScanCompleted
        )
        #expect(
            WindowCaptureRefreshPolicy.mergePendingPrefetchReason(
                existing: .windowFocusChanged,
                incoming: .displayStyleEnabled
            ) == .displayStyleEnabled
        )
    }

    /// cacheRetentionWindowIDs が OS 生存 CGWindow ID およびフィルタ前候補を保持対象に含め、
    /// 一時的なフィルタ欠落でのキャッシュ誤消去と OS 側空応答時の全破棄を防ぐことを検証する
    @Test("WindowCaptureRefreshPolicy.cacheRetentionWindowIDs は OS 生存 ID とフィルタ前候補を保護し空応答時は整理を抑止する")
    func cacheRetentionWindowIDsProtectsTransientlyFilteredAndOSSurvivingWindows() {
        let rawCandidates = [
            // タイトル空で Chrome プロファイル等により WindowFilter から一時除外される別スペース窓を想定
            RawWindowCandidate(
                id: "cg-301",
                cgWindowID: 301,
                pid: 10,
                bundleIdentifier: "com.google.Chrome",
                applicationName: "Google Chrome",
                title: nil,
                hasAXInfo: false,
                isOnScreen: false
            ),
            RawWindowCandidate(
                id: "w-101",
                cgWindowID: 101,
                pid: 20,
                applicationName: "Safari",
                title: "Docs",
                isOnScreen: true
            )
        ]
        let filteredEntries = [
            WindowEntry(id: "w-101", cgWindowID: 101, pid: 20, applicationName: "Safari", windowTitle: "Docs", isOnScreen: true)
        ]

        // 1. OS 生存 ID に 401（別スペースで一時的に rawCandidates にも出なかった生存窓）が含まれる場合、101 / 301 / 401 すべて保護される
        let withOSSurviving = WindowCaptureRefreshPolicy.cacheRetentionWindowIDs(
            survivingCGWindowIDs: [101, 401],
            rawCandidates: rawCandidates,
            filteredEntries: filteredEntries
        )
        #expect(withOSSurviving == [101, 301, 401])

        // 2. OS 生存 ID が nil（フォールバック）でも、フィルタ前の 301 は保護される
        let withoutOSSurviving = WindowCaptureRefreshPolicy.cacheRetentionWindowIDs(
            survivingCGWindowIDs: nil,
            rawCandidates: rawCandidates,
            filteredEntries: filteredEntries
        )
        #expect(withoutOSSurviving == [101, 301])

        // 3. OS 生存 ID が空かつ候補も空の場合は、一時異常による全キャッシュ誤破棄を防ぐため nil（整理スキップ）を返す
        let emptyOSResponse = WindowCaptureRefreshPolicy.cacheRetentionWindowIDs(
            survivingCGWindowIDs: [],
            rawCandidates: [],
            filteredEntries: []
        )
        #expect(emptyOSResponse == nil)
    }

    /// 指定した単色 RGBA ピクセルで埋められたテスト用 CGImage を生成する
    /// - Parameters:
    ///   - width: 画像幅（ピクセル）
    ///   - height: 画像高さ（ピクセル）
    ///   - r: 赤成分（0〜255）
    ///   - g: 緑成分（0〜255）
    ///   - b: 青成分（0〜255）
    ///   - a: アルファ成分（0〜255）
    /// - Returns: 生成された CGImage
    private func makeSolidTestCGImage(
        width: Int,
        height: Int,
        r: UInt8,
        g: UInt8,
        b: UInt8,
        a: UInt8
    ) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for idx in stride(from: 0, to: pixels.count, by: 4) {
            pixels[idx] = r
            pixels[idx + 1] = g
            pixels[idx + 2] = b
            pixels[idx + 3] = a
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    /// materializeAndValidateCapturedImage が全面透明（alpha == 0 および微細ノイズのみ）の CGImage を拒否し、
    /// 暗い単色ウィンドウを含む不透明・半透明の正常な CGImage を独立ビットマップへ複製して受理することを検証する
    @Test("materializeAndValidateCapturedImage は全面透明画像を拒否し正常画像を独立ビットマップ複製する")
    func materializeAndValidateCapturedImageRejectsTransparentAndMaterializesValidImages() {
        // 1. 全ピクセル完全透明（alpha == 0）は transparentImage として拒否する
        let fullyTransparent = makeSolidTestCGImage(width: 32, height: 24, r: 0, g: 0, b: 0, a: 0)
        if case let .invalid(reason) = WindowCaptureService.materializeAndValidateCapturedImage(fullyTransparent) {
            #expect(reason == WindowCaptureService.transparentImageFailureReason)
        } else {
            Issue.record("完全透明画像が有効と誤判定されました")
        }

        // 2. しきい値未満の微細アルファノイズ（alpha == 7）のみの画像も拒否する
        let subtleNoiseOnly = makeSolidTestCGImage(width: 16, height: 16, r: 7, g: 7, b: 7, a: 7)
        if case let .invalid(reason) = WindowCaptureService.materializeAndValidateCapturedImage(subtleNoiseOnly) {
            #expect(reason == WindowCaptureService.transparentImageFailureReason)
        } else {
            Issue.record("微細ノイズのみの透明画像が有効と誤判定されました")
        }

        // 3. しきい値ちょうど（alpha == 8）の半透明画像は有効として受理し独立ビットマップを返す
        let translucentValid = makeSolidTestCGImage(width: 16, height: 12, r: 8, g: 8, b: 8, a: 8)
        if case let .valid(detached) = WindowCaptureService.materializeAndValidateCapturedImage(translucentValid) {
            #expect(detached.width == 16)
            #expect(detached.height == 12)
            #expect(detached !== translucentValid)
        } else {
            Issue.record("しきい値以上の半透明画像が拒否されました")
        }

        // 4. 真っ黒な不透明ウィンドウ（RGB = (0, 0, 0), alpha = 255）はダークテーマ誤判定を起こさず有効受理する
        let darkOpaqueWindow = makeSolidTestCGImage(width: 40, height: 30, r: 0, g: 0, b: 0, a: 255)
        if case let .valid(detached) = WindowCaptureService.materializeAndValidateCapturedImage(darkOpaqueWindow) {
            #expect(detached.width == 40)
            #expect(detached.height == 30)
            #expect(detached !== darkOpaqueWindow)
        } else {
            Issue.record("暗色の不透明ウィンドウ画像が誤拒否されました")
        }
    }

    /// 全面透明フレームの失敗結果が返却されても、既存の正常サムネイルキャッシュが上書き・消去されず維持され、
    /// 未キャッシュウィンドウには格納されないことを検証する
    @Test("WindowCaptureService は全面透明フレーム検知時に既存キャッシュを維持し未キャッシュには格納しない")
    @MainActor
    func applySingleCaptureResultProtectsExistingCacheOnTransparentFrameFailure() {
        let clock = MutableTestClock(initial: Date(timeIntervalSince1970: 1_700_000_500))
        let service = WindowCaptureService(nowProvider: { clock.now })

        // 既キャッシュ済みの正常サムネイルを用意する
        let existingImage = NSImage(size: NSSize(width: 80, height: 50))
        let initialCapturedAt = clock.now
        service.storeInCache(existingImage, for: 101)

        var succeeded = 0
        var failedOnScreen = 0
        var failedOffScreen = 0
        var notifiedWindowIDs: [UInt32] = []

        clock.advance(by: 10)

        // 1. 既キャッシュ済みウィンドウ (101) に対する透明フレーム失敗 -> 既存画像と取得時刻が維持され通知も飛ばない
        service.applySingleCaptureResult(
            .failed(windowID: 101, isOnScreen: false, reason: WindowCaptureService.transparentImageFailureReason),
            succeededCount: &succeeded,
            failedOnScreenCount: &failedOnScreen,
            failedOffScreenCount: &failedOffScreen
        ) { windowID, _ in
            notifiedWindowIDs.append(windowID)
        }
        #expect(service.cachedThumbnail(for: 101) === existingImage)
        #expect(service.lastCapturedAt(for: 101) == initialCapturedAt)
        #expect(failedOffScreen == 1)
        #expect(notifiedWindowIDs.isEmpty)

        // 2. 未キャッシュウィンドウ (202) に対する透明フレーム失敗 -> キャッシュに格納されない
        service.applySingleCaptureResult(
            .failed(windowID: 202, isOnScreen: true, reason: WindowCaptureService.transparentImageFailureReason),
            succeededCount: &succeeded,
            failedOnScreenCount: &failedOnScreen,
            failedOffScreenCount: &failedOffScreen
        ) { windowID, _ in
            notifiedWindowIDs.append(windowID)
        }
        #expect(service.hasCachedThumbnail(for: 202) == false)
        #expect(service.cachedThumbnail(for: 202) == nil)
        #expect(failedOnScreen == 1)
        #expect(notifiedWindowIDs.isEmpty)

        // 3. 有効な CGImage の取得成功 -> 新規格納・通知が行われる
        let validCGImage = makeSolidTestCGImage(width: 40, height: 25, r: 100, g: 150, b: 200, a: 255)
        service.applySingleCaptureResult(
            .captured(202, validCGImage),
            succeededCount: &succeeded,
            failedOnScreenCount: &failedOnScreen,
            failedOffScreenCount: &failedOffScreen
        ) { windowID, _ in
            notifiedWindowIDs.append(windowID)
        }
        #expect(service.hasCachedThumbnail(for: 202) == true)
        #expect(succeeded == 1)
        #expect(notifiedWindowIDs == [202])
    }

    /// selectShareableCaptureTargets が SCShareableContent 取得時点でオフスクリーン化していた既キャッシュウィンドウをスキップし、
    /// 画面表示中ウィンドウ優先・未キャッシュ別スペースウィンドウ後続の順を保つことを検証する
    @Test("selectShareableCaptureTargets はオフスクリーン化済み既キャッシュをスキップし表示中優先順を維持する")
    func selectShareableCaptureTargetsSkipsCachedOffScreenWindows() {
        let requested: [UInt32] = [10, 20, 30, 40, 50, 20, 60]
        let isOnScreenByID: [UInt32: Bool] = [
            // 10: 別スペース退避済み・既キャッシュ -> スキップ対象
            10: false,
            // 20: 別スペース・未キャッシュ -> 後続で試行
            20: false,
            // 30: 現在表示中・既キャッシュ -> 優先対象
            30: true,
            // 40: 現在表示中・未キャッシュ -> 優先対象
            40: true,
            // 50: 別スペース退避済み・既キャッシュ -> スキップ対象
            50: false
            // 60: SCShareableContent に存在しない -> missing
        ]
        let cachedIDs: Set<UInt32> = [10, 30, 50]

        let selection = WindowCaptureService.selectShareableCaptureTargets(
            requestedWindowIDs: requested,
            isOnScreenByID: isOnScreenByID,
            isCached: { cachedIDs.contains($0) }
        )

        #expect(selection.orderedWindowIDs == [30, 40, 20])
        #expect(selection.onScreenCount == 2)
        #expect(selection.offScreenCount == 1)
        #expect(selection.skippedCachedOffScreenCount == 2)
        #expect(selection.missingCount == 1)
    }

    /// selectBestCGWindowMatch が alpha <= 0.0 の完全透明な補助 CGWindow を近接照合・包含照合のいずれでも除外することを検証する
    @Test("selectBestCGWindowMatch は alpha <= 0.0 の完全透明な CGWindow を照合候補から除外する")
    func selectBestCGWindowMatchExcludesZeroAlphaCGWindows() {
        let rect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let transparentExactOverlay: (zOrder: Int, info: WindowService.CGWindowMeta) = (
            zOrder: 0,
            info: WindowService.CGWindowMeta(
                windowID: 900,
                pid: 3000,
                layer: 0,
                bounds: rect,
                alpha: 0.0,
                isOnscreen: true,
                name: "Google Chrome"
            )
        )
        let visibleContentWindow: (zOrder: Int, info: WindowService.CGWindowMeta) = (
            zOrder: 1,
            info: WindowService.CGWindowMeta(
                windowID: 901,
                pid: 3000,
                layer: 0,
                bounds: CGRect(x: 0, y: 88, width: 1920, height: 992),
                alpha: 1.0,
                isOnscreen: true,
                name: "Google Chrome"
            )
        )

        // 1. 同一矩形・Z オーダー上位の alpha == 0.0 窓を除外し、包含する可視本体窓 (901) を照合すること
        let matched = WindowService.selectBestCGWindowMatch(
            axBounds: rect,
            axTitle: "Google Chrome",
            isMinimized: false,
            preferOnscreen: true,
            preferredCGWindowID: nil,
            in: [transparentExactOverlay, visibleContentWindow],
            excluding: []
        )
        #expect(matched?.info.windowID == 901)

        // 2. alpha <= 0.0 の候補しかない場合は照合しないこと
        let onlyTransparent = WindowService.selectBestCGWindowMatch(
            axBounds: rect,
            axTitle: "Google Chrome",
            isMinimized: false,
            preferOnscreen: true,
            preferredCGWindowID: 900,
            in: [transparentExactOverlay],
            excluding: []
        )
        #expect(onlyTransparent == nil)
    }
}
