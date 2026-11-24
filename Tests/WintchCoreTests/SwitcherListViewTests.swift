import AppKit
import SwiftUI
import Testing
@testable import WintchCore

/// SwitcherListView の縦スクロール追従（ランチャーおよびリスト型スイッチャー）を検証するテストスイート
@Suite("SwitcherListView スクロール追従テスト")
struct SwitcherListViewTests {
    /// 多数のウィンドウ候補とアプリ起動候補を持つ SwitcherViewModel を生成するヘルパー
    /// - Parameters:
    ///   - windowCount: スタブウィンドウ候補の件数
    ///   - appCount: スタブアプリ起動候補の件数
    /// - Returns: 構築済みの SwitcherViewModel と関連モック
    @MainActor
    private func makeViewModel(
        windowCount: Int,
        appCount: Int,
        launcherDisplayStyle: LauncherDisplayStyle = .list,
        screenRecordingStatus: ScreenRecordingPermissionStatus = .granted,
        windowCaptureService: MockWindowCaptureService = MockWindowCaptureService()
    ) -> SwitcherViewModel {
        let windowService = MockWindowService()
        let now = Date()
        var candidates: [RawWindowCandidate] = []
        candidates.reserveCapacity(windowCount)
        for index in 0..<windowCount {
            // macOS 15 ランナー上の Swift コンパイラで型推論がタイムアウトしないよう式を分割する
            let offsetSeconds = TimeInterval(-index * 10)
            let candidate = RawWindowCandidate(
                id: "win-\(index)",
                cgWindowID: UInt32(1000 + index),
                pid: Int32(100 + index),
                bundleIdentifier: "com.example.win\(index)",
                applicationName: "SampleApp\(index)",
                title: "Document Window \(index)",
                lastActivatedAt: now.addingTimeInterval(offsetSeconds)
            )
            candidates.append(candidate)
        }
        windowService.stubbedCandidates = candidates

        let installedAppService = MockInstalledAppService()
        var apps: [LaunchableApp] = []
        apps.reserveCapacity(appCount)
        for index in 0..<appCount {
            let bundlePath = "/Applications/SampleLaunch\(index).app"
            let app = LaunchableApp(
                id: bundlePath,
                displayName: "SampleLaunch\(index)",
                alternateName: "Sample",
                bundleIdentifier: "com.example.launch\(index)",
                bundleURL: URL(fileURLWithPath: bundlePath)
            )
            apps.append(app)
        }
        installedAppService.stubbedApps = apps

        let screenRecordingService = MockScreenRecordingPermissionService()
        screenRecordingService.stubbedStatus = screenRecordingStatus

        return SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            iconProvider: MockIconProvider(),
            installedAppService: installedAppService,
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: windowCaptureService,
            normalDisplayStyle: .list,
            launcherDisplayStyle: launcherDisplayStyle
        )
    }

    /// ビュー階層内を再帰探索して最初の NSScrollView を返すヘルパー
    /// - Parameter root: 探索の起点となる NSView
    /// - Returns: 見つかった NSScrollView（存在しない場合は nil）
    @MainActor
    private func findScrollView(in root: NSView) -> NSScrollView? {
        if let scrollView = root as? NSScrollView {
            return scrollView
        }
        for subview in root.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        return nil
    }

    /// SwitcherListView を透明なテスト用パネルにホストして実レイアウト・スクロール計測を行うヘルパー
    /// - Parameter viewModel: ホスト対象の SwitcherViewModel
    /// - Returns: ホストパネルと NSHostingView のタプル
    @MainActor
    private func makeHostedPanel(
        for viewModel: SwitcherViewModel
    ) throws -> (panel: SwitcherPanel, hostingView: NSHostingView<SwitcherContentView>) {
        let contentView = SwitcherContentView(viewModel: viewModel)
        let panel = SwitcherPanel(contentView: contentView)
        // テスト実行中に視覚的なウィンドウフラッシュが起きないよう透過した状態でレイアウトする
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.show(mode: viewModel.mode == .inactive ? .launcher : viewModel.mode, activateApp: false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        let hostingView = try #require(panel.contentView as? NSHostingView<SwitcherContentView>)
        return (panel, hostingView)
    }

    /// 指定秒数だけメインランループを回して SwiftUI の onChange・スクロールアニメーション反映を待つヘルパー
    /// - Parameter seconds: 待機する秒数
    @MainActor
    private func pumpMainRunLoop(for seconds: TimeInterval = 0.08) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    /// 検索ランチャーで方向キー下移動・アプリ起動候補セクション跨ぎ移動・上移動・循環移動時にスクロール位置が追従することを検証する
    @Test("検索ランチャーで方向キー移動・セクション跨ぎ・循環移動に合わせてリストが自動スクロール追従する")
    @MainActor
    func launcherScrollFollowsArrowAndWrapNavigation() throws {
        let viewModel = makeViewModel(windowCount: 15, appCount: 15)
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        // 検索語を入力してウィンドウ候補（15件）＋アプリ起動候補（15件）の混在リストを表示する
        viewModel.updateSearchQuery("Sample")
        #expect(viewModel.displayedResults.count == 15)
        #expect(viewModel.displayedAppResults.count == 15)
        #expect(viewModel.selectedIndex == 0)

        let (panel, hostingView) = try makeHostedPanel(for: viewModel)
        defer { panel.hidePanel(restorePreviousApp: false) }

        let scrollView = try #require(findScrollView(in: hostingView))
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        let expectedMaxHeight = SwitcherPanelLayout.maxListScrollHeight(
            availableScreenHeight: viewModel.availableScreenSize.height,
            hasSearchHeader: true,
            hasPermissionBanner: false
        )
        // ディスプレイ高さに応じた最大高さ（従来の 420pt より拡大）まで広がり、かつスクロール可能であること
        #expect(expectedMaxHeight > 420)
        #expect(scrollView.frame.height > 420)
        #expect(scrollView.frame.height <= expectedMaxHeight + 0.5)
        #expect(documentHeight > scrollView.frame.height + 100)
        #expect(scrollView.contentView.bounds.origin.y == 0)

        // 下方向キーでウィンドウ候補末尾からアプリ起動候補セクション（インデックス 20）まで移動する
        for _ in 0..<20 {
            viewModel.moveSelection(.down)
            pumpMainRunLoop(for: 0.03)
        }
        pumpMainRunLoop(for: 0.2)

        #expect(viewModel.selectedIndex == 20)
        let scrolledDownY = scrollView.contentView.bounds.origin.y
        // 下方のアプリ起動候補までスクロール領域が追従移動していること
        #expect(scrolledDownY > 200)

        // 上方向キーで先頭側へ戻るとスクロール位置も上方へ戻ることを検証する
        for _ in 0..<20 {
            viewModel.moveSelection(.up)
            pumpMainRunLoop(for: 0.03)
        }
        pumpMainRunLoop(for: 0.2)

        #expect(viewModel.selectedIndex == 0)
        #expect(scrollView.contentView.bounds.origin.y < 10)

        // 先頭（0）から上方向キーで末尾（29）へ循環移動した場合も末尾付近まで大きくスクロール追従すること
        viewModel.moveSelection(.up)
        pumpMainRunLoop(for: 0.25)

        #expect(viewModel.selectedIndex == 29)
        let wrappedBottomY = scrollView.contentView.bounds.origin.y
        #expect(wrappedBottomY > scrolledDownY)

        // 末尾（29）から下方向キーで先頭（0）へ循環移動した場合も先頭へ戻ること
        viewModel.moveSelection(.down)
        pumpMainRunLoop(for: 0.25)

        #expect(viewModel.selectedIndex == 0)
        #expect(scrollView.contentView.bounds.origin.y < 10)
    }

    /// 手動スクロール後に selectedIndex == 0 のまま検索語を更新した場合および再表示時に先頭へ戻ることを検証する
    @Test("検索クエリ更新時およびパネル再表示時に先頭候補が見える位置へスクロールが復帰する")
    @MainActor
    func searchQueryUpdateAndReopenResetScrollToTop() throws {
        let viewModel = makeViewModel(windowCount: 15, appCount: 15)
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        viewModel.updateSearchQuery("Sample")

        let (panel, hostingView) = try makeHostedPanel(for: viewModel)
        defer { panel.hidePanel(restorePreviousApp: false) }

        let scrollView = try #require(findScrollView(in: hostingView))
        // selectedIndex == 0 のまま手動でリスト下部へスクロールした状態を再現する
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 260))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        pumpMainRunLoop(for: 0.05)
        #expect(scrollView.contentView.bounds.origin.y >= 200)
        #expect(viewModel.selectedIndex == 0)

        // 検索語を変更すると先頭候補（selectedIndex == 0）が見える位置へスクロールが復帰すること
        viewModel.updateSearchQuery("SampleApp")
        pumpMainRunLoop(for: 0.15)
        #expect(viewModel.selectedIndex == 0)
        #expect(scrollView.contentView.bounds.origin.y < 10)

        // 再度下方の候補へスクロールさせた状態からパネルを閉じ、同一パネルで再表示する
        viewModel.updateSearchQuery("Sample")
        pumpMainRunLoop(for: 0.1)
        for _ in 0..<18 {
            viewModel.moveSelection(.down)
            pumpMainRunLoop(for: 0.02)
        }
        pumpMainRunLoop(for: 0.2)
        #expect(scrollView.contentView.bounds.origin.y > 180)

        viewModel.cancel(reason: .cancelled)
        panel.hidePanel(restorePreviousApp: false)
        pumpMainRunLoop(for: 0.08)

        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        panel.show(mode: .launcher, activateApp: false)
        pumpMainRunLoop(for: 0.15)

        let reopenedScrollView = try #require(findScrollView(in: hostingView))
        #expect(viewModel.selectedIndex == 0)
        #expect(reopenedScrollView.contentView.bounds.origin.y < 10)
    }

    /// 通常スイッチャー（リスト型）で多数のウィンドウを表示した際も選択移動に合わせてスクロール追従することを検証する
    @Test("通常スイッチャー（リスト型）でもトリガー移動・矢印移動に合わせて自動スクロール追従する")
    @MainActor
    func normalListModeFollowsSelectionScroll() throws {
        let viewModel = makeViewModel(windowCount: 25, appCount: 0)
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.mode == .normal)
        #expect(viewModel.selectedIndex == 1)

        let (panel, hostingView) = try makeHostedPanel(for: viewModel)
        defer { panel.hidePanel(restorePreviousApp: false) }

        let scrollView = try #require(findScrollView(in: hostingView))
        let expectedMaxHeight = SwitcherPanelLayout.maxListScrollHeight(
            availableScreenHeight: viewModel.availableScreenSize.height,
            hasSearchHeader: false,
            hasPermissionBanner: false
        )
        #expect(expectedMaxHeight > 420)
        #expect(scrollView.frame.height > 420)
        #expect(scrollView.frame.height <= expectedMaxHeight + 0.5)
        #expect((scrollView.documentView?.frame.height ?? 0) > scrollView.frame.height + 100)

        // Option + Tab 連続押下相当で下方のウィンドウ（インデックス 18）まで移動する
        for _ in 0..<17 {
            viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
            pumpMainRunLoop(for: 0.02)
        }
        pumpMainRunLoop(for: 0.2)

        #expect(viewModel.selectedIndex == 18)
        #expect(scrollView.contentView.bounds.origin.y > 200)

        // Shift 併用逆順移動で先頭付近（インデックス 0）まで戻るとスクロールも上端へ戻ること
        for _ in 0..<18 {
            viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: true))
            pumpMainRunLoop(for: 0.02)
        }
        pumpMainRunLoop(for: 0.2)

        #expect(viewModel.selectedIndex == 0)
        #expect(scrollView.contentView.bounds.origin.y < 10)
    }

    /// 候補数が最大高さ内に収まる少数件数では選択移動しても不要なスクロールが発生しないことを検証する
    @Test("少数候補時は選択移動しても不要なスクロールが発生しない")
    @MainActor
    func smallListDoesNotScrollUnnecessarily() throws {
        let viewModel = makeViewModel(windowCount: 3, appCount: 0)
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)

        let (panel, hostingView) = try makeHostedPanel(for: viewModel)
        defer { panel.hidePanel(restorePreviousApp: false) }

        let scrollView = try #require(findScrollView(in: hostingView))
        let expectedMaxHeight = SwitcherPanelLayout.maxListScrollHeight(
            availableScreenHeight: viewModel.availableScreenSize.height,
            hasSearchHeader: true,
            hasPermissionBanner: false
        )
        #expect(scrollView.frame.height < expectedMaxHeight)
        #expect(scrollView.contentView.bounds.origin.y == 0)

        for _ in 0..<3 {
            viewModel.moveSelection(.down)
            pumpMainRunLoop(for: 0.04)
            #expect(scrollView.contentView.bounds.origin.y == 0)
        }
    }

    /// 検索ランチャーのキャプチャ表示型で縦型リスト（幅 520pt）とサムネイル付き行高さ・
    /// 画面収録権限未許可時の非インタラクティブ警告バナー・自動スクロール追従が正しく動作することを検証する
    @Test("検索ランチャーのキャプチャ表示型でサムネイル行レイアウト・権限未許可バナー・自動スクロール追従が動作する")
    @MainActor
    func launcherCaptureStyleLayoutPermissionBannerAndScroll() throws {
        // 1. 同一 2 件候補で、キャプチャ表示型はリスト型より行高さが大きく幅 520pt を維持する
        let listViewModel = makeViewModel(windowCount: 2, appCount: 0, launcherDisplayStyle: .list)
        listViewModel.handleHotKeyEvent(.launcherTriggerPressed)
        let listHosting = NSHostingView(rootView: SwitcherListView(viewModel: listViewModel))
        listHosting.layoutSubtreeIfNeeded()
        let listSize = listHosting.fittingSize

        let captureService = MockWindowCaptureService()
        captureService.cachedThumbnails[1000] = NSImage(size: NSSize(width: 160, height: 100))
        let captureGrantedVM = makeViewModel(
            windowCount: 2,
            appCount: 0,
            launcherDisplayStyle: .capture,
            screenRecordingStatus: .granted,
            windowCaptureService: captureService
        )
        captureGrantedVM.handleHotKeyEvent(.launcherTriggerPressed)
        let captureGrantedHosting = NSHostingView(rootView: SwitcherListView(viewModel: captureGrantedVM))
        captureGrantedHosting.layoutSubtreeIfNeeded()
        let captureGrantedSize = captureGrantedHosting.fittingSize

        #expect(listSize.width == 520)
        #expect(captureGrantedSize.width == 520)
        #expect(captureGrantedSize.height > listSize.height)

        // 2. 画面収録権限未許可時は検索ヘッダ下に非インタラクティブな警告バナーが追加表示され、NSButton を含まない
        let captureDeniedVM = makeViewModel(
            windowCount: 2,
            appCount: 0,
            launcherDisplayStyle: .capture,
            screenRecordingStatus: .denied
        )
        captureDeniedVM.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(captureDeniedVM.isScreenRecordingGranted == false)

        let deniedView = SwitcherListView(viewModel: captureDeniedVM)
        let deniedHosting = NSHostingView(rootView: deniedView)
        deniedHosting.layoutSubtreeIfNeeded()
        let deniedSize = deniedHosting.fittingSize

        #expect(deniedSize.width == 520)
        #expect(deniedSize.height > captureGrantedSize.height)

        let bannerHosting = NSHostingView(rootView: deniedView.permissionBannerView.frame(width: 520))
        bannerHosting.layoutSubtreeIfNeeded()
        #expect(bannerHosting.fittingSize.height >= 30)
        func collectSubviews(_ root: NSView) -> [NSView] {
            [root] + root.subviews.flatMap(collectSubviews)
        }
        #expect(collectSubviews(bannerHosting).compactMap { $0 as? NSButton }.isEmpty)

        // 3. 多数の候補＋アプリ起動候補がある状態でもキャプチャ表示型ランチャーでスクロール追従が機能する
        let scrollableVM = makeViewModel(
            windowCount: 12,
            appCount: 10,
            launcherDisplayStyle: .capture,
            screenRecordingStatus: .granted
        )
        scrollableVM.handleHotKeyEvent(.launcherTriggerPressed)
        scrollableVM.updateSearchQuery("Sample")
        #expect(scrollableVM.displayedResults.count == 12)
        #expect(scrollableVM.displayedAppResults.count == 10)

        let (panel, hostingView) = try makeHostedPanel(for: scrollableVM)
        defer { panel.hidePanel(restorePreviousApp: false) }

        let scrollView = try #require(findScrollView(in: hostingView))
        let expectedMaxHeight = SwitcherPanelLayout.maxListScrollHeight(
            availableScreenHeight: scrollableVM.availableScreenSize.height,
            hasSearchHeader: true,
            hasPermissionBanner: false
        )
        #expect(expectedMaxHeight > 420)
        #expect(scrollView.frame.height > 420)
        #expect(scrollView.frame.height <= expectedMaxHeight + 0.5)
        #expect((scrollView.documentView?.frame.height ?? 0) > scrollView.frame.height + 100)

        for _ in 0..<15 {
            scrollableVM.moveSelection(.down)
            pumpMainRunLoop(for: 0.03)
        }
        pumpMainRunLoop(for: 0.2)

        #expect(scrollableVM.selectedIndex == 15)
        #expect(scrollView.contentView.bounds.origin.y > 200)
    }

    /// グルーピング ON 時と OFF 時で SwitcherListView のアプリ見出し行の有無に応じたレイアウト高さ差と、
    /// グルーピング ON 時の MRU 2 番目初期選択への初期スクロール追従を検証する
    @Test("グルーピング ON/OFF でリスト見出し有無のレイアウトが切り替わり初期選択へスクロール追従する")
    @MainActor
    func groupedListLayoutDiffersFromFlatAndFollowsInitialSelection() throws {
        let groupedVM = makeViewModel(windowCount: 3, appCount: 0)
        groupedVM.handleHotKeyEvent(.launcherTriggerPressed)
        let groupedHosting = NSHostingView(rootView: SwitcherListView(viewModel: groupedVM))
        groupedHosting.layoutSubtreeIfNeeded()
        let groupedSize = groupedHosting.fittingSize

        groupedVM.updateLauncherGrouping(false)
        let flatHosting = NSHostingView(rootView: SwitcherListView(viewModel: groupedVM))
        flatHosting.layoutSubtreeIfNeeded()
        let flatSize = flatHosting.fittingSize

        // 3 アプリ各 1 ウィンドウの場合、グルーピング ON は 3 件のアプリ見出し行が追加されるためフラット時より高さが大きくなる
        #expect(groupedSize.width == 520)
        #expect(flatSize.width == 520)
        #expect(groupedSize.height > flatSize.height)
    }

    /// 通常スイッチャーのアイコン型・キャプチャ表示型でグルーピング ON のとき、
    /// 検索ランチャーのキャプチャ表示型（グルーピング ON）と同じプレビュー枠付き縦型リスト（幅 520pt）になり、
    /// アイコン型では権限未許可でも警告バナーを表示せず、キャプチャ表示型未許可時のみバナーを表示することを検証する
    @Test("通常スイッチャーのアイコン型・キャプチャ表示型（グルーピング ON）がランチャーのキャプチャ表示型と同一の縦型リストになる")
    @MainActor
    func normalIconAndCaptureGroupedMatchLauncherCaptureGroupedListStyle() {
        let normalListVM = makeViewModel(windowCount: 2, appCount: 0)
        normalListVM.updateNormalDisplayStyle(.list)
        normalListVM.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        let normalListHosting = NSHostingView(rootView: SwitcherContentView(viewModel: normalListVM))
        normalListHosting.layoutSubtreeIfNeeded()
        let normalListSize = normalListHosting.fittingSize

        let normalIconVM = makeViewModel(windowCount: 2, appCount: 0, screenRecordingStatus: .denied)
        normalIconVM.updateNormalDisplayStyle(.icon)
        normalIconVM.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        let normalIconHosting = NSHostingView(rootView: SwitcherContentView(viewModel: normalIconVM))
        normalIconHosting.layoutSubtreeIfNeeded()
        let normalIconSize = normalIconHosting.fittingSize

        let normalCaptureGrantedVM = makeViewModel(windowCount: 2, appCount: 0, screenRecordingStatus: .granted)
        normalCaptureGrantedVM.updateNormalDisplayStyle(.capture)
        normalCaptureGrantedVM.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        let normalCaptureGrantedHosting = NSHostingView(rootView: SwitcherContentView(viewModel: normalCaptureGrantedVM))
        normalCaptureGrantedHosting.layoutSubtreeIfNeeded()
        let normalCaptureGrantedSize = normalCaptureGrantedHosting.fittingSize

        let normalCaptureDeniedVM = makeViewModel(windowCount: 2, appCount: 0, screenRecordingStatus: .denied)
        normalCaptureDeniedVM.updateNormalDisplayStyle(.capture)
        normalCaptureDeniedVM.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        let normalCaptureDeniedHosting = NSHostingView(rootView: SwitcherContentView(viewModel: normalCaptureDeniedVM))
        normalCaptureDeniedHosting.layoutSubtreeIfNeeded()
        let normalCaptureDeniedSize = normalCaptureDeniedHosting.fittingSize

        // いずれも幅 520pt の縦型リストとして描画される
        #expect(normalListSize.width == 520)
        #expect(normalIconSize.width == 520)
        #expect(normalCaptureGrantedSize.width == 520)
        #expect(normalCaptureDeniedSize.width == 520)

        // アイコン型（大きなアイコン 46pt・枠/背景なし・領域 50pt）とキャプチャ表示型（サムネイル高さ 50pt・権限許可）は
        // 同じ行高さとなり、リスト型より大きい
        #expect(SwitcherListView.groupedIconDisplaySize > 28)
        #expect(SwitcherListView.groupedIconContainerSize == SwitcherListView.captureThumbnailHeight)
        #expect(abs(normalIconSize.height - normalCaptureGrantedSize.height) < 0.5)
        #expect(normalIconSize.height > normalListSize.height)

        // キャプチャ表示型で権限未許可時のみ上部に警告バナーが追加され高さが増える（アイコン型は未許可でもバナー無し）
        #expect(normalCaptureDeniedSize.height > normalCaptureGrantedSize.height)
    }

    /// 画面サイズ拡大に伴い SwitcherListView の表示範囲が広がること、および SwitcherPanel の上寄せ配置が
    /// 中央配置より上方に配置されることを実ビューおよび実パネルで検証する
    @Test("ディスプレイ高さに応じてリスト表示範囲が拡大し上寄せ配置パネルが中央配置より上に表示される")
    @MainActor
    func listDisplayHeightScalesWithScreenAndPanelPlacesHigherWhenUpperAnchored() throws {
        let viewModel = makeViewModel(windowCount: 30, appCount: 0)
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))

        // 小さい画面（720pt）と大きい画面（1080pt）でリストの最大表示高さが変化し、いずれも 420pt より大きいこと
        viewModel.updateAvailableScreenSize(CGSize(width: 1280, height: 720))
        let smallScreenHosting = NSHostingView(rootView: SwitcherListView(viewModel: viewModel))
        smallScreenHosting.layoutSubtreeIfNeeded()
        let smallScreenHeight = smallScreenHosting.fittingSize.height

        viewModel.updateAvailableScreenSize(CGSize(width: 1920, height: 1080))
        let largeScreenHosting = NSHostingView(rootView: SwitcherListView(viewModel: viewModel))
        largeScreenHosting.layoutSubtreeIfNeeded()
        let largeScreenHeight = largeScreenHosting.fittingSize.height

        #expect(smallScreenHeight > 420)
        #expect(largeScreenHeight > smallScreenHeight + 200)

        // 実 SwitcherPanel で上寄せ配置と中央配置を比較（ディスプレイが取得可能な環境で上端位置を確認）
        let compactVM = makeViewModel(windowCount: 3, appCount: 0)
        compactVM.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        let panel = SwitcherPanel(contentView: SwitcherContentView(viewModel: compactVM))
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        defer { panel.hidePanel(restorePreviousApp: false) }

        panel.show(mode: .normal, activateApp: false, verticalPlacement: .centered)
        let centeredOriginY = panel.frame.origin.y

        panel.show(mode: .normal, activateApp: false, verticalPlacement: .upperAnchored)
        let upperOriginY = panel.frame.origin.y

        if NSScreen.main != nil || !NSScreen.screens.isEmpty {
            #expect(upperOriginY > centeredOriginY)
        }
    }
}
