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

    /// アイコン型グリッドビューが「1 ウィンドウ = 1 アイコン」でアプリ名・ウィンドウタイトルを表示し、
    /// 画面収録権限未許可バナーを含まず列数に応じた幅でレイアウトされること、および SwitcherContentView がモード・表示形式に応じて正しく分岐することを検証する
    @Test("SwitcherIconGridView のタイル表示・複数列レイアウトと SwitcherContentView の分岐を検証する")
    @MainActor
    func iconGridViewRendersTilesWithoutPermissionBannerAndContentViewBranches() {
        let windowService = MockWindowService()
        let now = Date()
        windowService.stubbedCandidates = [
            RawWindowCandidate(
                id: "w1",
                cgWindowID: 101,
                pid: 10,
                applicationName: "Safari",
                title: "Apple Documentation",
                lastActivatedAt: now
            ),
            RawWindowCandidate(
                id: "w2",
                cgWindowID: 102,
                pid: 10,
                applicationName: "Safari",
                title: "GitHub Repository",
                lastActivatedAt: now.addingTimeInterval(-10)
            ),
            RawWindowCandidate(
                id: "w3",
                cgWindowID: 103,
                pid: 20,
                applicationName: "Visual Studio Code",
                title: "Wintch",
                lastActivatedAt: now.addingTimeInterval(-20)
            )
        ]

        let screenRecordingService = MockScreenRecordingPermissionService()
        screenRecordingService.stubbedStatus = .denied
        let captureService = MockWindowCaptureService()

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            iconProvider: MockIconProvider(),
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: captureService,
            normalDisplayStyle: .icon
        )
        viewModel.updateAvailableScreenSize(CGSize(width: 1440, height: 900))
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))

        // アイコン型起動時に画面収録権限チェックやキャプチャ処理が一切呼ばれていないこと
        #expect(screenRecordingService.currentStatusCallCount == 0)
        #expect(captureService.capturedRequestWindowIDs.isEmpty)
        #expect(viewModel.gridColumnCount == 3)

        let iconGridView = SwitcherIconGridView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: iconGridView)
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize

        let expectedWidth = 3 * SwitcherGridLayout.iconTileWidth
            + 2 * SwitcherGridLayout.cardSpacing
            + SwitcherGridLayout.gridPadding * 2
        #expect(fittingSize.width == expectedWidth)
        #expect(fittingSize.height >= SwitcherGridLayout.iconTileHeight + SwitcherGridLayout.gridPadding * 2)

        // SwitcherContentView が通常モード・アイコン型のときはアイコングリッド幅でレイアウトされ、
        // ランチャーモード時はアイコン型設定中でもリスト型（幅 520pt）で描画されること
        let normalContentHosting = NSHostingView(rootView: SwitcherContentView(viewModel: viewModel))
        normalContentHosting.layoutSubtreeIfNeeded()
        #expect(normalContentHosting.fittingSize.width == expectedWidth)

        viewModel.cancel()
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.mode == .launcher)
        let launcherContentHosting = NSHostingView(rootView: SwitcherContentView(viewModel: viewModel))
        launcherContentHosting.layoutSubtreeIfNeeded()
        #expect(launcherContentHosting.fittingSize.width == 520)
    }
}
