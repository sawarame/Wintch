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
        appCount: Int
    ) -> SwitcherViewModel {
        let windowService = MockWindowService()
        let now = Date()
        windowService.stubbedCandidates = (0..<windowCount).map { index in
            RawWindowCandidate(
                id: "win-\(index)",
                cgWindowID: UInt32(1000 + index),
                pid: Int32(100 + index),
                bundleIdentifier: "com.example.win\(index)",
                applicationName: "SampleApp\(index)",
                title: "Document Window \(index)",
                lastActivatedAt: now.addingTimeInterval(TimeInterval(-index * 10))
            )
        }

        let installedAppService = MockInstalledAppService()
        installedAppService.stubbedApps = (0..<appCount).map { index in
            LaunchableApp(
                id: "/Applications/SampleLaunch\(index).app",
                displayName: "SampleLaunch\(index)",
                alternateName: "Sample",
                bundleIdentifier: "com.example.launch\(index)",
                bundleURL: URL(fileURLWithPath: "/Applications/SampleLaunch\(index).app")
            )
        }

        return SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            iconProvider: MockIconProvider(),
            installedAppService: installedAppService,
            normalDisplayStyle: .list
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
        // 最大高さ（420pt）を超えてスクロール可能なコンテンツが存在すること
        #expect(scrollView.frame.height <= 420.5)
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
        #expect(scrollView.frame.height <= 420.5)
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
        #expect(scrollView.frame.height < 420)
        #expect(scrollView.contentView.bounds.origin.y == 0)

        for _ in 0..<3 {
            viewModel.moveSelection(.down)
            pumpMainRunLoop(for: 0.04)
            #expect(scrollView.contentView.bounds.origin.y == 0)
        }
    }
}
