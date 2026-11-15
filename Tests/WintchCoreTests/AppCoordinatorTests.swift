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
}
