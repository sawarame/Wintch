import AppKit
import SwiftUI
import Testing
@testable import WintchCore

/// SwitcherCaptureGridView の画面収録権限未許可バナーおよびレイアウト契約を検証するテストスイート
@Suite("SwitcherCaptureGridView テスト")
struct SwitcherCaptureGridViewTests {
    /// テスト用の SwitcherViewModel を生成するヘルパー
    /// - Parameter status: 画面収録権限のスタブ状態
    /// - Returns: キャプチャ表示型に設定された SwitcherViewModel
    @MainActor
    private func makeCaptureViewModel(status: ScreenRecordingPermissionStatus) -> SwitcherViewModel {
        let windowService = MockWindowService()
        windowService.stubbedCandidates = [
            RawWindowCandidate(
                id: "w1",
                cgWindowID: 101,
                pid: 10,
                applicationName: "TestApp",
                title: "Window 1",
                lastActivatedAt: Date()
            )
        ]

        let screenRecordingService = MockScreenRecordingPermissionService()
        screenRecordingService.stubbedStatus = status

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            iconProvider: MockIconProvider(),
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: MockWindowCaptureService(),
            normalDisplayStyle: .capture
        )
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        return viewModel
    }

    /// NSView ツリーを再帰走査してすべてのサブビューを収集するヘルパー
    /// - Parameter root: 走査の起点となるビュー
    /// - Returns: 起点ビュー自身および全子孫ビューの配列
    @MainActor
    private func collectAllSubviews(in root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap { collectAllSubviews(in: $0) }
    }

    /// SwiftUI のビュー値グラフを Mirror で再帰走査し、文字列値と型名を収集するヘルパー
    /// - Parameters:
    ///   - value: 走査対象の SwiftUI ビューまたは値
    ///   - depth: 無限再帰を防ぐための探索深度上限
    ///   - visitedTypeNames: 収集された型名一覧
    ///   - strings: 収集された文字列リテラル一覧
    private func inspectSwiftUIValue(
        _ value: Any,
        depth: Int = 0,
        visitedTypeNames: inout [String],
        strings: inout [String]
    ) {
        guard depth < 20 else { return }
        let typeName = String(describing: type(of: value))
        visitedTypeNames.append(typeName)

        if let str = value as? String {
            strings.append(str)
            return
        }
        if value is Text {
            strings.append(String(describing: value))
        }

        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            // SwitcherViewModel 等の参照オブジェクト内部までは辿らず SwiftUI 値グラフのみを検査する
            if child.value is SwitcherViewModel { continue }
            inspectSwiftUIValue(
                child.value,
                depth: depth + 1,
                visitedTypeNames: &visitedTypeNames,
                strings: &strings
            )
        }
    }

    /// 画面収録権限が未許可のとき、案内バナーにクリック可能な設定ボタン／リンクが存在せず案内文のみ表示されることを検証する
    @Test("権限未許可時のキャプチャグリッドにクリック可能な設定リンクが存在せずバナー案内のみ表示される")
    @MainActor
    func deniedBannerContainsNoSettingsLinkButton() {
        let deniedViewModel = makeCaptureViewModel(status: .denied)
        #expect(deniedViewModel.isScreenRecordingGranted == false)

        let deniedView = SwitcherCaptureGridView(viewModel: deniedViewModel)
        var typeNames: [String] = []
        var strings: [String] = []
        inspectSwiftUIValue(deniedView.permissionBannerView, visitedTypeNames: &typeNames, strings: &strings)

        // バナーの SwiftUI ビュー階層に Button 型および「設定を開く」文言が存在せず、案内メッセージが含まれること
        #expect(!typeNames.contains { $0.contains("Button<") || $0 == "Button" })
        #expect(!strings.contains { $0.contains("設定を開く") })
        #expect(strings.contains { $0.contains(SwitcherCaptureGridView.permissionBannerMessage) })

        // バナー単体を最小パネル幅 360pt でホストしても NSButton が生成されず正の高さでレイアウトされること
        let bannerHostingView = NSHostingView(
            rootView: deniedView.permissionBannerView
                .frame(width: SwitcherCaptureGridView.minWidthWithBanner)
        )
        bannerHostingView.layoutSubtreeIfNeeded()
        let bannerSize = bannerHostingView.fittingSize
        #expect(bannerSize.width == SwitcherCaptureGridView.minWidthWithBanner)
        #expect(bannerSize.height >= 30)
        #expect(collectAllSubviews(in: bannerHostingView).compactMap { $0 as? NSButton }.isEmpty)

        let deniedHostingView = NSHostingView(rootView: deniedView)
        deniedHostingView.layoutSubtreeIfNeeded()
        let deniedSize = deniedHostingView.fittingSize

        // 最小バナー幅 360pt が維持されていること
        #expect(deniedSize.width == SwitcherCaptureGridView.minWidthWithBanner)

        // NSButton を含むクリック可能なボタンコントロールが生成されていないこと
        let subviews = collectAllSubviews(in: deniedHostingView)
        let buttons = subviews.compactMap { $0 as? NSButton }
        #expect(buttons.isEmpty)

        // 許可済み時はバナーがないため、幅・高さともに未許可時よりコンパクトになること
        let grantedViewModel = makeCaptureViewModel(status: .granted)
        #expect(grantedViewModel.isScreenRecordingGranted == true)

        let grantedHostingView = NSHostingView(
            rootView: SwitcherCaptureGridView(viewModel: grantedViewModel)
        )
        grantedHostingView.layoutSubtreeIfNeeded()
        let grantedSize = grantedHostingView.fittingSize

        #expect(grantedSize.width == SwitcherGridLayout.cardWidth + SwitcherGridLayout.gridPadding * 2)
        #expect(deniedSize.height > grantedSize.height)
    }
}
