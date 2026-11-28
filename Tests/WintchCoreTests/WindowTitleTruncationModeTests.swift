import AppKit
import Foundation
import SwiftUI
import Testing
@testable import WintchCore

/// ウィンドウタイトルの省略位置設定（Domain・永続化・ViewModel・Coordinator・UI 適用）を検証するテストスイート
@Suite("WindowTitleTruncationMode テスト")
struct WindowTitleTruncationModeTests {
    /// デフォルト値が途中省略であり、全ケース・表示名・SwiftUI 変換が仕様通りであることを検証する
    @Test("デフォルト値・表示名・SwiftUI Text.TruncationMode への変換が仕様通りである")
    func defaultValueDisplayNamesAndSwiftUIMapping() {
        #expect(WindowTitleTruncationMode.default == .middle)
        #expect(WindowTitleTruncationMode.allCases == [.middle, .tail])
        #expect(WindowTitleTruncationMode.middle.displayName == "途中を省略")
        #expect(WindowTitleTruncationMode.tail.displayName == "末尾を省略")
        #expect(WindowTitleTruncationMode.middle.swiftUITruncationMode == .middle)
        #expect(WindowTitleTruncationMode.tail.swiftUITruncationMode == .tail)

        for language in ResolvedAppLanguage.allCases {
            for mode in WindowTitleTruncationMode.allCases {
                #expect(!mode.displayName(in: language).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    /// PreferencesStore で保存・読み込み・未保存デフォルト・不正値フォールバックが機能することを検証する
    @Test("PreferencesStore でタイトル省略位置の保存・読み込み・未保存および不正値フォールバックが動作する")
    func preferencesStorePersistsTruncationModeWithFallback() {
        let suiteName = "dev.wintch.tests.titleTruncationMode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        defer { defaults?.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(suiteName: suiteName)

        // 未保存時はデフォルトの .middle が返る
        #expect(store.loadWindowTitleTruncationMode() == .middle)

        // 全ケースの保存と読み込み
        for mode in WindowTitleTruncationMode.allCases {
            store.saveWindowTitleTruncationMode(mode)
            #expect(store.loadWindowTitleTruncationMode() == mode)
            #expect(defaults?.string(forKey: "dev.wintch.windowTitleTruncationMode") == mode.rawValue)
        }

        // 不正値や空文字が保存されていた場合はデフォルトの .middle へフォールバックする
        defaults?.set("head", forKey: "dev.wintch.windowTitleTruncationMode")
        #expect(store.loadWindowTitleTruncationMode() == .middle)

        defaults?.set("", forKey: "dev.wintch.windowTitleTruncationMode")
        #expect(store.loadWindowTitleTruncationMode() == .middle)
    }

    /// SettingsViewModel での読み込み・更新・永続化・同値スキップ・コールバック通知を検証する
    @Test("SettingsViewModel でタイトル省略位置が永続化され変更コールバックが発火する")
    @MainActor
    func settingsViewModelPersistsAndNotifiesTruncationMode() {
        let store = MockPreferencesStore()
        store.storedWindowTitleTruncationMode = .tail

        let viewModel = SettingsViewModel(
            preferencesStore: store,
            hotKeyMonitor: MockHotKeyMonitor(),
            launchAtLoginService: MockLaunchAtLoginService(),
            permissionService: MockAccessibilityPermissionService()
        )

        #expect(viewModel.windowTitleTruncationMode == .tail)

        var notifiedModes: [WindowTitleTruncationMode] = []
        viewModel.onWindowTitleTruncationModeChanged = { notifiedModes.append($0) }

        // 同じ値の再設定では保存・通知を行わない
        viewModel.updateWindowTitleTruncationMode(.tail)
        #expect(store.saveWindowTitleTruncationModeCallCount == 0)
        #expect(notifiedModes.isEmpty)

        // 別値へ変更すると永続化と通知が即時実行される
        viewModel.updateWindowTitleTruncationMode(.middle)
        #expect(viewModel.windowTitleTruncationMode == .middle)
        #expect(store.storedWindowTitleTruncationMode == .middle)
        #expect(store.saveWindowTitleTruncationModeCallCount == 1)
        #expect(notifiedModes == [.middle])
    }

    /// AppCoordinator 経由で設定変更が永続化され、SwitcherViewModel へ即時同期されることを検証する
    @Test("AppCoordinator が起動時復元および設定変更時の SwitcherViewModel 即時同期を行う")
    @MainActor
    func coordinatorSyncsTruncationModeWithSwitcherViewModel() {
        let store = MockPreferencesStore()
        store.storedWindowTitleTruncationMode = .tail

        let coordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            preferencesStore: store,
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService()
        )

        // 初期化時点で保存済みの値が反映されている
        #expect(coordinator.windowTitleTruncationMode == .tail)
        #expect(coordinator.settingsViewModel.windowTitleTruncationMode == .tail)
        #expect(coordinator.switcherViewModel.windowTitleTruncationMode == .tail)

        // start() 時の再ロードでも保存値と整合する
        coordinator.start()
        #expect(coordinator.switcherViewModel.windowTitleTruncationMode == .tail)

        // SettingsViewModel からの変更が SwitcherViewModel へ即時反映・永続化される
        coordinator.settingsViewModel.updateWindowTitleTruncationMode(.middle)
        #expect(store.storedWindowTitleTruncationMode == .middle)
        #expect(store.saveWindowTitleTruncationModeCallCount == 1)
        #expect(coordinator.windowTitleTruncationMode == .middle)
        #expect(coordinator.switcherViewModel.windowTitleTruncationMode == .middle)

        // AppCoordinator 経由の更新メソッドでも双方向同期・永続化される
        coordinator.updateWindowTitleTruncationMode(.tail)
        #expect(store.storedWindowTitleTruncationMode == .tail)
        #expect(store.saveWindowTitleTruncationModeCallCount == 2)
        #expect(coordinator.settingsViewModel.windowTitleTruncationMode == .tail)
        #expect(coordinator.switcherViewModel.windowTitleTruncationMode == .tail)
    }

    /// SettingsView の「一般」タブでタイトル省略位置 Picker を追加しても設定ウィンドウ内に見切れず収まることを検証する
    @Test("SettingsView の一般タブにタイトル省略位置設定が配置され見切れずにレイアウトされる")
    @MainActor
    func settingsViewGeneralTabFitsWithoutClippingAcrossLanguages() {
        for language in AppLanguage.allCases where language != .system {
            let store = MockPreferencesStore()
            store.storedAppLanguage = language
            let viewModel = SettingsViewModel(
                preferencesStore: store,
                hotKeyMonitor: MockHotKeyMonitor(),
                launchAtLoginService: MockLaunchAtLoginService(),
                permissionService: MockAccessibilityPermissionService()
            )
            let settingsView = SettingsView(
                viewModel: viewModel,
                appIdentity: AppIdentity(
                    infoDictionary: [
                        "CFBundleDisplayName": "Wintch",
                        "CFBundleIdentifier": "dev.wintch.Wintch"
                    ]
                ),
                versionInfo: AppVersionInfo(
                    infoDictionary: [
                        "CFBundleShortVersionString": "0.4.9",
                        "CFBundleVersion": "100"
                    ]
                )
            )

            let hostingView = NSHostingView(rootView: settingsView)
            hostingView.frame = NSRect(
                x: 0,
                y: 0,
                width: SettingsView.preferredWidth,
                height: SettingsView.preferredHeight
            )
            hostingView.layoutSubtreeIfNeeded()
            let fittingSize = hostingView.fittingSize

            #expect(fittingSize.width <= SettingsView.preferredWidth)
            #expect(fittingSize.height <= SettingsView.preferredHeight)
        }
    }

    /// リスト型・アイコン型・キャプチャ表示型・検索ランチャー（ハイライト表示・キャプチャ行含む）で
    /// タイトル省略位置（.middle / .tail）を切り替えても正常にレイアウト描画できることを検証する
    @Test("全表示形式と検索ランチャーでタイトル省略位置設定の切り替えが安全に描画反映される")
    @MainActor
    func switcherAndLauncherViewsRenderWithBothTruncationModes() {
        let longTitle = "VeryLongProjectRepositoryName/Sources/WintchCore/Views/SwitcherListViewControllerFeatureBranch.swift — Edited"
        let windowService = MockWindowService()
        windowService.stubbedCandidates = [
            RawWindowCandidate(
                id: "w1",
                cgWindowID: 101,
                pid: 10,
                bundleIdentifier: "com.example.editor",
                applicationName: "LongEditorApplicationName",
                title: longTitle,
                lastActivatedAt: Date()
            ),
            RawWindowCandidate(
                id: "w2",
                cgWindowID: 102,
                pid: 10,
                bundleIdentifier: "com.example.editor",
                applicationName: "LongEditorApplicationName",
                title: "SecondWindow-\(longTitle)",
                lastActivatedAt: Date().addingTimeInterval(-10)
            )
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            screenRecordingPermissionService: MockScreenRecordingPermissionService(),
            windowCaptureService: MockWindowCaptureService(),
            normalDisplayStyle: .list,
            launcherDisplayStyle: .list,
            isNormalSwitcherGroupedByApp: false,
            isLauncherGroupedByApp: false,
            windowTitleTruncationMode: .middle
        )

        for mode in WindowTitleTruncationMode.allCases {
            viewModel.updateWindowTitleTruncationMode(mode)
            #expect(viewModel.windowTitleTruncationMode == mode)

            // 通常スイッチャー（リスト型・フラット／グルーピング、アイコン型、キャプチャ表示型）
            for style in SwitcherDisplayStyle.allCases {
                viewModel.updateNormalDisplayStyle(style)
                for isGrouped in [false, true] {
                    viewModel.updateNormalSwitcherGrouping(isGrouped)
                    viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))

                    let hostingView = NSHostingView(rootView: SwitcherContentView(viewModel: viewModel))
                    hostingView.layoutSubtreeIfNeeded()
                    #expect(hostingView.fittingSize.width > 0)
                    #expect(hostingView.fittingSize.height > 0)

                    viewModel.cancel(reason: .cancelled)
                }
            }

            // 検索ランチャー（リスト型・キャプチャ表示型、フラット／グルーピング、検索ハイライト付き）
            for launcherStyle in LauncherDisplayStyle.allCases {
                viewModel.updateLauncherDisplayStyle(launcherStyle)
                for isGrouped in [false, true] {
                    viewModel.updateLauncherGrouping(isGrouped)
                    viewModel.handleHotKeyEvent(.launcherTriggerPressed)
                    viewModel.updateSearchQuery("Branch")

                    let hostingView = NSHostingView(rootView: SwitcherContentView(viewModel: viewModel))
                    hostingView.layoutSubtreeIfNeeded()
                    #expect(hostingView.fittingSize.width > 0)
                    #expect(hostingView.fittingSize.height > 0)

                    viewModel.cancel(reason: .cancelled)
                }
            }
        }
    }
}
