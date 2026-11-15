import AppKit
import CoreGraphics
import Foundation
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
}
