import SwiftUI
import Testing
@testable import WintchCore

/// メニューバー表示設定の入り口分離構成・双方向同期・多言語対応を検証するテストスイート
@Suite("メニューバーコンテンツビュー (MenuBarContentView) テスト")
struct MenuBarContentViewTests {
    /// 「表示形式」セクション配下に通常スイッチャーと検索ランチャーの 2 つの独立したサブメニュー入り口が定義されることを検証する
    @Test("通常スイッチャーと検索ランチャーが 2 つの独立したサブメニュー入り口として全 5 言語で定義される")
    func displaySubmenuDescriptorsSeparateNormalSwitcherAndSearchLauncherInAllLanguages() {
        for language in ResolvedAppLanguage.allCases {
            let strings = AppStrings(language: language)
            let descriptors = MenuBarContentView.displaySubmenuDescriptors(in: language)

            #expect(descriptors.count == 2)
            #expect(descriptors.map(\.kind) == [.normalSwitcher, .searchLauncher])

            // 1 番目: 通常スイッチャー（リスト型 / アイコン型 / キャプチャ表示型 + グルーピング）
            let normal = descriptors[0]
            #expect(normal.title == strings.menuBarNormalSwitcher)
            #expect(normal.displayStyleTitles == SwitcherDisplayStyle.allCases.map { $0.displayName(in: language) })
            #expect(normal.displayStyleTitles.count == 3)
            #expect(normal.groupByAppTitle == strings.groupByAppToggle)

            // 2 番目: 検索ランチャー（リスト型 / キャプチャ表示型 + グルーピング）
            let launcher = descriptors[1]
            #expect(launcher.title == strings.menuBarSearchLauncher)
            #expect(launcher.displayStyleTitles == LauncherDisplayStyle.allCases.map { $0.displayName(in: language) })
            #expect(launcher.displayStyleTitles.count == 2)
            #expect(launcher.groupByAppTitle == strings.groupByAppToggle)

            // 入り口タイトル同士が重複せず明確に区別できること
            #expect(normal.title != launcher.title)
        }
    }

    /// メニューバー各サブメニューのバインディング経由での変更が設定・永続化・キャッシュ破棄・オプトイン権限原則と整合することを検証する
    @Test("メニューバー各サブメニューのバインディング変更が即時同期・永続化され、非キャプチャ時は画面収録権限を参照しない")
    @MainActor
    func menuBarBindingsSyncPreferencesAndRespectOptInScreenRecording() {
        let store = MockPreferencesStore()
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
            windowCaptureService: captureService,
            windowFrontPresenter: MockWindowFrontPresenter(),
            preferredLanguagesProvider: { ["ja-JP"] }
        )

        let view = MenuBarContentView(coordinator: coordinator)

        // 初期状態は双方リスト型・グルーピング ON であり、画面収録権限には一切触れない
        #expect(view.normalDisplayStyleBinding.wrappedValue == .list)
        #expect(view.launcherDisplayStyleBinding.wrappedValue == .list)
        #expect(view.normalGroupingBinding.wrappedValue == true)
        #expect(view.launcherGroupingBinding.wrappedValue == true)
        #expect(screenRecordingService.currentStatusCallCount == 0)
        #expect(screenRecordingService.requestPermissionCallCount == 0)

        // 通常スイッチャーをアイコン型へ変更しても画面収録権限を参照しない
        view.normalDisplayStyleBinding.wrappedValue = .icon
        #expect(coordinator.normalDisplayStyle == .icon)
        #expect(coordinator.settingsViewModel.normalDisplayStyle == .icon)
        #expect(coordinator.switcherViewModel.normalDisplayStyle == .icon)
        #expect(store.storedNormalDisplayStyle == .icon)
        #expect(screenRecordingService.currentStatusCallCount == 0)
        #expect(screenRecordingService.requestPermissionCallCount == 0)

        // グルーピング設定を通常スイッチャー・検索ランチャーで独立して切り替えられること
        view.normalGroupingBinding.wrappedValue = false
        #expect(coordinator.isNormalSwitcherGroupedByApp == false)
        #expect(coordinator.isLauncherGroupedByApp == true)
        #expect(store.storedGroupNormalSwitcherByApp == false)
        #expect(store.storedGroupLauncherByApp == true)

        view.launcherGroupingBinding.wrappedValue = false
        #expect(coordinator.isLauncherGroupedByApp == false)
        #expect(store.storedGroupLauncherByApp == false)

        // キャプチャ表示型へ切り替えても権限リクエストダイアログは自動発火せず、双方非キャプチャ復帰時にキャッシュが全破棄される
        view.normalDisplayStyleBinding.wrappedValue = .capture
        view.launcherDisplayStyleBinding.wrappedValue = .capture
        #expect(screenRecordingService.requestPermissionCallCount == 0)

        let clearCountBefore = captureService.clearCacheCallCount
        view.normalDisplayStyleBinding.wrappedValue = .list
        // 検索ランチャーがまだキャプチャ表示型なので共有キャッシュは維持される
        #expect(captureService.clearCacheCallCount == clearCountBefore)

        view.launcherDisplayStyleBinding.wrappedValue = .list
        // 双方とも非キャプチャになった時点で共有キャッシュが全破棄される
        #expect(captureService.clearCacheCallCount == clearCountBefore + 1)
    }

    /// 全 5 言語およびアクセシビリティ権限状態の組み合わせで MenuBarContentView の body が安全に構築できることを検証する
    @Test("全 5 言語および権限状態の組み合わせで MenuBarContentView を構築できる")
    @MainActor
    func menuBarContentViewBuildsCleanlyAcrossLanguagesAndPermissionStates() {
        for status in [AccessibilityPermissionStatus.granted, .denied] {
            let permissionService = MockAccessibilityPermissionService()
            permissionService.stubbedStatus = status
            let coordinator = AppCoordinator(
                windowService: MockWindowService(),
                hotKeyMonitor: MockHotKeyMonitor(),
                permissionService: permissionService,
                preferencesStore: MockPreferencesStore(),
                launchAtLoginService: MockLaunchAtLoginService(),
                iconProvider: MockIconProvider(),
                installedAppService: MockInstalledAppService(),
                windowFrontPresenter: MockWindowFrontPresenter(),
                preferredLanguagesProvider: { ["ja-JP"] }
            )

            for language in ResolvedAppLanguage.allCases {
                let appLanguage = AppLanguage(rawValue: language.rawValue) ?? .system
                coordinator.updateAppLanguage(appLanguage)
                let view = MenuBarContentView(coordinator: coordinator)
                _ = view.body
                #expect(coordinator.resolvedLanguage == language)
            }
        }
    }
}
