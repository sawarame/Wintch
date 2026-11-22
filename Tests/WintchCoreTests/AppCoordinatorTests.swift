import AppKit
import SwiftUI
import Testing
@testable import WintchCore

/// AppCoordinator の権限状態遷移および監視中断時の安全停止を検証するテストスイート
@Suite("AppCoordinator テスト")
struct AppCoordinatorTests {
    /// 監視中断（tapDisabledByUserInput や権限剥奪検知）時に全監視を停止し未許可状態へ遷移することを検証する
    @Test("監視中断通知を受けると監視を停止し権限誘導状態へ遷移する")
    @MainActor
    func monitoringInterruptedTransitionsToDeniedState() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        permissionService.stubbedStatus = .granted

        let coordinator = AppCoordinator(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            preferencesStore: MockPreferencesStore(),
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService()
        )

        coordinator.start()
        #expect(coordinator.permissionStatus == .granted)
        #expect(hotKeyMonitor.isMonitoring == true)
        #expect(windowService.startObservingCallCount == 1)

        // 権限サービスがキャッシュにより .granted を返したままでも、監視中断通知で確実に .denied へ遷移する
        hotKeyMonitor.simulateMonitoringInterrupted()

        #expect(coordinator.permissionStatus == .denied)
        #expect(coordinator.isPermissionGuidePresented == true)
        #expect(coordinator.settingsViewModel.permissionStatus == .denied)
        #expect(coordinator.permissionGuideViewModel.status == .denied)
        #expect(hotKeyMonitor.isMonitoring == false)
        #expect(windowService.stopObservingCallCount == 1)
    }

    /// ホットキー監視の開始に失敗した場合に .granted へ遷移せず安全に .denied に留まることを検証する
    @Test("startMonitoring 失敗時は権限許可扱いとせず未許可状態を維持する")
    @MainActor
    func startMonitoringFailureKeepsDeniedState() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        hotKeyMonitor.startMonitoringResult = false
        let permissionService = MockAccessibilityPermissionService()
        permissionService.stubbedStatus = .granted

        let coordinator = AppCoordinator(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            preferencesStore: MockPreferencesStore(),
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService()
        )

        coordinator.start()

        #expect(coordinator.permissionStatus == .denied)
        #expect(coordinator.isPermissionGuidePresented == true)
        #expect(coordinator.settingsViewModel.permissionStatus == .denied)
        #expect(coordinator.permissionGuideViewModel.status == .denied)
        #expect(hotKeyMonitor.isMonitoring == false)
        #expect(windowService.startObservingCallCount == 0)
    }

    /// 権限剥奪後に再付与された場合、監視と誘導画面状態が正常に復帰することを検証する
    @Test("権限の剥奪から再許可への状態遷移で監視が停止・再開される")
    @MainActor
    func permissionRevocationAndRegrantLifecycle() {
        let windowService = MockWindowService()
        let hotKeyMonitor = MockHotKeyMonitor()
        let permissionService = MockAccessibilityPermissionService()
        permissionService.stubbedStatus = .granted

        let coordinator = AppCoordinator(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            preferencesStore: MockPreferencesStore(),
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService()
        )

        coordinator.start()
        #expect(coordinator.permissionStatus == .granted)
        #expect(hotKeyMonitor.isMonitoring == true)

        permissionService.simulateStatusChange(.denied)
        #expect(coordinator.permissionStatus == .denied)
        #expect(coordinator.isPermissionGuidePresented == true)
        #expect(hotKeyMonitor.isMonitoring == false)
        #expect(windowService.stopObservingCallCount == 1)

        permissionService.simulateStatusChange(.granted)
        #expect(coordinator.permissionStatus == .granted)
        #expect(coordinator.isPermissionGuidePresented == false)
        #expect(hotKeyMonitor.isMonitoring == true)
        #expect(windowService.startObservingCallCount == 2)
    }

    /// 設定画面で表示形式を切り替えた際に SwitcherViewModel へ即座に同期され、
    /// リスト型復帰時にキャプチャキャッシュもクリアされることを検証する
    @Test("表示形式の変更が SettingsViewModel から SwitcherViewModel へ即時反映されリスト復帰でキャッシュ消去される")
    @MainActor
    func displayStyleSyncsBetweenSettingsAndSwitcher() {
        let store = MockPreferencesStore()
        store.storedNormalDisplayStyle = .capture
        let screenRecordingService = MockScreenRecordingPermissionService()
        let captureService = MockWindowCaptureService()

        let coordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            preferencesStore: store,
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: captureService
        )

        coordinator.start()
        #expect(coordinator.switcherViewModel.normalDisplayStyle == .capture)
        #expect(coordinator.settingsViewModel.normalDisplayStyle == .capture)

        // リスト型へ切り替えると即座に反映され、キャッシュ全消去が呼ばれる
        coordinator.settingsViewModel.updateNormalDisplayStyle(.list)
        #expect(coordinator.switcherViewModel.normalDisplayStyle == .list)
        #expect(captureService.clearCacheCallCount == 1)

        // 再びキャプチャ表示型へ切り替えると即座に反映される
        coordinator.settingsViewModel.updateNormalDisplayStyle(.capture)
        #expect(coordinator.switcherViewModel.normalDisplayStyle == .capture)
        #expect(coordinator.normalDisplayStyle == .capture)

        // アイコン型へ切り替えた場合も即座に反映され、キャプチャキャッシュが全消去される
        coordinator.settingsViewModel.updateNormalDisplayStyle(.icon)
        #expect(coordinator.switcherViewModel.normalDisplayStyle == .icon)
        #expect(coordinator.normalDisplayStyle == .icon)
        #expect(captureService.clearCacheCallCount == 2)
    }

    /// メニューバー相当の共有経路（AppCoordinator.updateNormalDisplayStyle）からの切り替えで
    /// 永続化・SettingsViewModel・SwitcherViewModel への双方向同期およびキャッシュ破棄が行われ、
    /// 権限未許可時も設定画面や権限ダイアログを開かないことを検証する
    @Test("コーディネーター経由の表示形式切り替えが永続化・双方向同期・キャッシュ破棄され権限ダイアログを開かない")
    @MainActor
    func coordinatorDisplayStyleUpdateSyncsPersistsClearsCacheWithoutPrompting() {
        let store = MockPreferencesStore()
        store.storedNormalDisplayStyle = .list
        let windowService = MockWindowService()
        windowService.stubbedCandidates = [
            RawWindowCandidate(
                id: "w1",
                cgWindowID: 101,
                pid: 10,
                applicationName: "Safari",
                title: "Docs",
                lastActivatedAt: Date()
            )
        ]
        let permissionService = MockAccessibilityPermissionService()
        permissionService.stubbedStatus = .granted
        let screenRecordingService = MockScreenRecordingPermissionService()
        screenRecordingService.stubbedStatus = .denied
        let captureService = MockWindowCaptureService()
        let presenter = MockWindowFrontPresenter()

        let coordinator = AppCoordinator(
            windowService: windowService,
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: permissionService,
            preferencesStore: store,
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: captureService,
            windowFrontPresenter: presenter
        )

        coordinator.start()
        #expect(coordinator.normalDisplayStyle == .list)
        #expect(coordinator.settingsViewModel.normalDisplayStyle == .list)
        #expect(coordinator.switcherViewModel.normalDisplayStyle == .list)

        // 画面収録権限が未許可の状態でキャプチャ表示型へ切り替えても、設定画面や OS 権限ダイアログは開かない
        coordinator.updateNormalDisplayStyle(.capture)
        #expect(coordinator.normalDisplayStyle == .capture)
        #expect(coordinator.settingsViewModel.normalDisplayStyle == .capture)
        #expect(coordinator.switcherViewModel.normalDisplayStyle == .capture)
        #expect(store.storedNormalDisplayStyle == .capture)
        #expect(store.saveNormalDisplayStyleCallCount == 1)
        #expect(coordinator.settingsViewModel.screenRecordingStatus == .denied)
        #expect(screenRecordingService.requestPermissionCallCount == 0)
        #expect(screenRecordingService.openSystemSettingsCallCount == 0)
        #expect(presenter.presentedWindows.isEmpty)

        // 権限許可状態で通常スイッチャーを起動してサムネイルを保持させた状態でリスト型へ戻す
        screenRecordingService.stubbedStatus = .granted
        captureService.cachedThumbnails[101] = NSImage(size: NSSize(width: 64, height: 64))
        let clearCountBeforeList = captureService.clearCacheCallCount
        coordinator.switcherViewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(coordinator.switcherViewModel.capturedThumbnails[101] != nil)

        coordinator.updateNormalDisplayStyle(.list)
        #expect(coordinator.normalDisplayStyle == .list)
        #expect(coordinator.settingsViewModel.normalDisplayStyle == .list)
        #expect(coordinator.switcherViewModel.normalDisplayStyle == .list)
        #expect(store.storedNormalDisplayStyle == .list)
        #expect(store.saveNormalDisplayStyleCallCount == 2)
        #expect(coordinator.switcherViewModel.capturedThumbnails.isEmpty)
        #expect(captureService.cachedThumbnails.isEmpty)
        #expect(captureService.clearCacheCallCount == clearCountBeforeList + 1)

        // 後続テストや他テストへの影響を防ぐためパネルを閉じておく
        coordinator.switcherViewModel.cancel()

        // 設定画面側（SettingsViewModel）から変更した場合もコーディネーター参照値に即時反映される
        coordinator.settingsViewModel.updateNormalDisplayStyle(.capture)
        #expect(coordinator.normalDisplayStyle == .capture)
        #expect(coordinator.switcherViewModel.normalDisplayStyle == .capture)
    }

    /// 検索ランチャー表示形式のコーディネーター経由切り替え・永続化・双方向同期、
    /// および通常／ランチャー双方のキャプチャ状態に応じたキャッシュ保持・全破棄を検証する
    @Test("ランチャー表示形式の個別同期と通常・ランチャー双方非キャプチャ時のみのキャッシュ全破棄を検証する")
    @MainActor
    func coordinatorLauncherDisplayStyleSyncAndSharedCacheLifecycle() {
        let store = MockPreferencesStore()
        store.storedNormalDisplayStyle = .list
        store.storedLauncherDisplayStyle = .list
        let windowService = MockWindowService()
        windowService.stubbedCandidates = [
            RawWindowCandidate(
                id: "w1",
                cgWindowID: 201,
                pid: 10,
                applicationName: "Safari",
                title: "Docs",
                lastActivatedAt: Date()
            )
        ]
        let screenRecordingService = MockScreenRecordingPermissionService()
        screenRecordingService.stubbedStatus = .denied
        let captureService = MockWindowCaptureService()
        let presenter = MockWindowFrontPresenter()

        let coordinator = AppCoordinator(
            windowService: windowService,
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            preferencesStore: store,
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            screenRecordingPermissionService: screenRecordingService,
            windowCaptureService: captureService,
            windowFrontPresenter: presenter
        )

        coordinator.start()
        #expect(coordinator.normalDisplayStyle == .list)
        #expect(coordinator.launcherDisplayStyle == .list)
        #expect(coordinator.switcherViewModel.launcherDisplayStyle == .list)

        // 画面収録権限未許可でランチャーをキャプチャ表示型へ切り替えても設定画面や OS 権限ダイアログは開かない
        coordinator.updateLauncherDisplayStyle(.capture)
        #expect(coordinator.launcherDisplayStyle == .capture)
        #expect(coordinator.settingsViewModel.launcherDisplayStyle == .capture)
        #expect(coordinator.switcherViewModel.launcherDisplayStyle == .capture)
        #expect(store.storedLauncherDisplayStyle == .capture)
        #expect(store.saveLauncherDisplayStyleCallCount == 1)
        #expect(screenRecordingService.requestPermissionCallCount == 0)
        #expect(screenRecordingService.openSystemSettingsCallCount == 0)
        #expect(presenter.presentedWindows.isEmpty)

        // 両方をキャプチャ表示型にし、ランチャー起動でサムネイルキャッシュを保持させた状態を作る
        screenRecordingService.stubbedStatus = .granted
        coordinator.updateNormalDisplayStyle(.capture)
        captureService.cachedThumbnails[201] = NSImage(size: NSSize(width: 80, height: 50))
        coordinator.switcherViewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(coordinator.switcherViewModel.capturedThumbnails[201] != nil)
        coordinator.switcherViewModel.cancel()

        // 通常側のみリスト型へ戻してもランチャー側がキャプチャ表示型のため共有キャッシュは維持される
        let clearCountBeforeNormalRevert = captureService.clearCacheCallCount
        coordinator.updateNormalDisplayStyle(.list)
        #expect(coordinator.normalDisplayStyle == .list)
        #expect(coordinator.launcherDisplayStyle == .capture)
        #expect(captureService.clearCacheCallCount == clearCountBeforeNormalRevert)
        #expect(captureService.cachedThumbnails[201] != nil)

        // ランチャー側もリスト型へ戻すと双方が非キャプチャとなり即座にキャッシュが全破棄される
        coordinator.updateLauncherDisplayStyle(.list)
        #expect(coordinator.launcherDisplayStyle == .list)
        #expect(coordinator.switcherViewModel.launcherDisplayStyle == .list)
        #expect(store.storedLauncherDisplayStyle == .list)
        #expect(store.saveLauncherDisplayStyleCallCount == 2)
        #expect(captureService.clearCacheCallCount == clearCountBeforeNormalRevert + 1)
        #expect(captureService.cachedThumbnails.isEmpty)
    }

    /// 開発版と配布版それぞれの AppIdentity が AppCoordinator に正しく保持されることを検証する
    @Test("注入された開発版および配布版の AppIdentity を保持する")
    @MainActor
    func retainsInjectedAppIdentity() {
        let devIdentity = AppIdentity(infoDictionary: [
            "CFBundleDisplayName": "Wintch_dev",
            "CFBundleIdentifier": "dev.wintch.Wintch.dev"
        ])
        let releaseIdentity = AppIdentity(infoDictionary: [
            "CFBundleDisplayName": "Wintch",
            "CFBundleIdentifier": "dev.wintch.Wintch"
        ])

        let devCoordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            preferencesStore: MockPreferencesStore(),
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            appIdentity: devIdentity
        )
        #expect(devCoordinator.appIdentity.displayName == "Wintch_dev")
        #expect(devCoordinator.appIdentity.isDevelopment == true)
        #expect(devCoordinator.appIdentity.settingsWindowTitle == "Wintch_dev 設定")

        let releaseCoordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            preferencesStore: MockPreferencesStore(),
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            appIdentity: releaseIdentity
        )
        #expect(releaseCoordinator.appIdentity.displayName == "Wintch")
        #expect(releaseCoordinator.appIdentity.isDevelopment == false)
        #expect(releaseCoordinator.appIdentity.settingsWindowTitle == "Wintch 設定")
    }

    /// メニューバーからの設定画面表示が WindowFrontPresenting を通じて固定サイズで実行され、
    /// 再オープン時も同一ウィンドウインスタンスおよび前回選択メニューを保持することを検証する
    @Test("openSettings は固定サイズの設定ウィンドウを最前面表示し再表示時も選択メニューを維持する")
    @MainActor
    func openSettingsDelegatesToWindowFrontPresenterAndRetainsSelectedTab() {
        let presenter = MockWindowFrontPresenter()
        let coordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            preferencesStore: MockPreferencesStore(),
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            windowFrontPresenter: presenter
        )

        #expect(coordinator.settingsViewModel.selectedTab == .general)

        coordinator.openSettings()
        #expect(presenter.presentedWindows.count == 1)
        let firstSettingsWindow = presenter.presentedWindows[0]
        #expect(firstSettingsWindow.title == coordinator.appIdentity.settingsWindowTitle)
        #expect(firstSettingsWindow.isReleasedWhenClosed == false)
        #expect(firstSettingsWindow.styleMask.contains(.resizable) == false)
        let contentSize = firstSettingsWindow.contentView?.frame.size ?? .zero
        #expect(contentSize.width == SettingsView.preferredWidth)
        #expect(contentSize.height == SettingsView.preferredHeight)

        // 別メニューを選択してウィンドウを再オープンしても同一ウィンドウと選択メニューが維持される
        coordinator.settingsViewModel.selectTab(.system)
        coordinator.openSettings()
        #expect(presenter.presentedWindows.count == 2)
        #expect(presenter.presentedWindows[1] === firstSettingsWindow)
        #expect(coordinator.settingsViewModel.selectedTab == .system)
    }

    /// 権限誘導画面が未許可時のみ最前面表示プレゼンターへ委譲され、権限許可済み時は表示されないことを検証する
    @Test("openPermissionGuide と権限剥奪検知時のみ権限誘導ウィンドウを最前面表示する")
    @MainActor
    func permissionGuideDelegatesToWindowFrontPresenterOnlyWhenDenied() {
        let permissionService = MockAccessibilityPermissionService()
        permissionService.stubbedStatus = .granted
        let presenter = MockWindowFrontPresenter()

        let coordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: permissionService,
            preferencesStore: MockPreferencesStore(),
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            windowFrontPresenter: presenter
        )

        coordinator.start()
        // 権限許可済み時は openPermissionGuide() を呼んでも誘導画面を表示しない
        coordinator.openPermissionGuide()
        #expect(presenter.presentedWindows.isEmpty)

        // 権限剥奪を検知すると権限誘導ウィンドウを最前面表示する
        permissionService.simulateStatusChange(.denied)
        #expect(presenter.presentedWindows.count == 1)
        let guideWindow = presenter.presentedWindows[0]
        #expect(guideWindow.title == coordinator.appIdentity.permissionGuideWindowTitle)
        #expect(guideWindow.isReleasedWhenClosed == false)

        // メニューバーから権限誘導画面を再表示した際も同一ウィンドウで最前面表示する
        coordinator.openPermissionGuide()
        #expect(presenter.presentedWindows.count == 2)
        #expect(presenter.presentedWindows[1] === guideWindow)
    }

    /// 権限誘導ウィンドウのコンテンツ領域が PermissionGuideView の必要サイズ以上に設定され、テキストが途切れないことを検証する
    @Test("権限誘導ウィンドウはビューの必要高さ以上に確保され固定 280pt で切り詰められない")
    @MainActor
    func permissionGuideWindowMatchesRequiredFittingSize() {
        let permissionService = MockAccessibilityPermissionService()
        permissionService.stubbedStatus = .denied
        let presenter = MockWindowFrontPresenter()

        let coordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: permissionService,
            preferencesStore: MockPreferencesStore(),
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            windowFrontPresenter: presenter
        )

        coordinator.openPermissionGuide()
        #expect(presenter.presentedWindows.count == 1)

        let guideWindow = presenter.presentedWindows[0]
        let expectedHostingView = NSHostingView(
            rootView: PermissionGuideView(
                viewModel: coordinator.permissionGuideViewModel,
                appIdentity: coordinator.appIdentity
            )
        )
        expectedHostingView.layoutSubtreeIfNeeded()
        let requiredSize = expectedHostingView.fittingSize

        let contentSize = guideWindow.contentView?.frame.size ?? .zero
        #expect(contentSize.width >= PermissionGuideView.preferredWidth)
        #expect(contentSize.height >= requiredSize.height)
        #expect(contentSize.height > PermissionGuideView.minimumHeight)
    }

    /// 通常スイッチャー・検索ランチャーのアプリグルーピング設定がコーディネーター・設定 ViewModel・スイッチャー ViewModel 間で双方向即時同期され永続化されることを検証する
    @Test("グルーピング設定がコーディネーター・設定・スイッチャー間で個別に双方向同期・永続化される")
    @MainActor
    func coordinatorSyncsAppGroupingIndependently() {
        let store = MockPreferencesStore()
        store.storedGroupNormalSwitcherByApp = true
        store.storedGroupLauncherByApp = false

        let coordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            preferencesStore: store,
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService()
        )

        coordinator.start()
        #expect(coordinator.isNormalSwitcherGroupedByApp == true)
        #expect(coordinator.switcherViewModel.isNormalSwitcherGroupedByApp == true)
        #expect(coordinator.isLauncherGroupedByApp == false)
        #expect(coordinator.switcherViewModel.isLauncherGroupedByApp == false)

        // メニューバー相当のコーディネーター経路から通常スイッチャーを OFF に変更
        coordinator.updateNormalSwitcherGrouping(false)
        #expect(coordinator.isNormalSwitcherGroupedByApp == false)
        #expect(coordinator.settingsViewModel.isNormalSwitcherGroupedByApp == false)
        #expect(coordinator.switcherViewModel.isNormalSwitcherGroupedByApp == false)
        #expect(store.storedGroupNormalSwitcherByApp == false)
        #expect(store.saveGroupNormalSwitcherByAppCallCount == 1)

        // 設定画面（SettingsViewModel）経路から検索ランチャーを ON に変更
        coordinator.settingsViewModel.updateLauncherGrouping(true)
        #expect(coordinator.isLauncherGroupedByApp == true)
        #expect(coordinator.switcherViewModel.isLauncherGroupedByApp == true)
        #expect(store.storedGroupLauncherByApp == true)
        #expect(store.saveGroupLauncherByAppCallCount == 1)
    }
}
