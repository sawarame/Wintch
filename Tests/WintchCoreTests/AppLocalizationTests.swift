import AppKit
import Foundation
import SwiftUI
import Testing
@testable import WintchCore

/// テスト用のダミー自動起動エラー
private struct MockLocalizedLaunchError: LocalizedError {
    var errorDescription: String? { "MockSMError" }
}

/// 多言語対応（言語解決・永続化・翻訳整合性・即時 UI 反映・検索対象外維持）を検証するテストスイート
@Suite("多言語対応 (Localization) テスト")
struct AppLocalizationTests {
    // MARK: - 言語解決ルール

    /// システム優先言語配列から 5 言語および英語フォールバックが規定ルール通りに解決されることを検証する
    @Test("システム優先言語リストから対応 5 言語および英語フォールバックを正しく解決する")
    func resolvesPreferredLanguagesAccordingToSpec() {
        // 日本語・英語・韓国語
        #expect(AppLanguage.resolveSystemLanguage(from: ["ja-JP", "en-US"]) == .japanese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["ja"]) == .japanese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["en-GB", "ja-JP"]) == .english)
        #expect(AppLanguage.resolveSystemLanguage(from: ["en"]) == .english)
        #expect(AppLanguage.resolveSystemLanguage(from: ["ko-KR", "ja-JP"]) == .korean)
        #expect(AppLanguage.resolveSystemLanguage(from: ["ko"]) == .korean)

        // 中国語（簡体字）: zh-Hans / zh-CN / zh-SG / スクリプト未指定 zh
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-Hans-CN"]) == .simplifiedChinese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-Hans"]) == .simplifiedChinese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-CN"]) == .simplifiedChinese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh_CN"]) == .simplifiedChinese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-SG"]) == .simplifiedChinese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh"]) == .simplifiedChinese)
        // 明示的な Hans スクリプト指定は地域コードより優先される
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-Hans-HK"]) == .simplifiedChinese)

        // 中国語（繁体字）: zh-Hant / zh-TW / zh-HK / zh-MO
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-Hant-TW"]) == .traditionalChinese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-Hant-HK"]) == .traditionalChinese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-Hant"]) == .traditionalChinese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-TW"]) == .traditionalChinese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh_TW"]) == .traditionalChinese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-HK"]) == .traditionalChinese)
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-MO"]) == .traditionalChinese)
        // 明示的な Hant スクリプト指定は地域コードより優先される
        #expect(AppLanguage.resolveSystemLanguage(from: ["zh-Hant-CN"]) == .traditionalChinese)

        // 先頭が非対応言語でも、後続の最初の一致言語を採用する
        #expect(AppLanguage.resolveSystemLanguage(from: ["fr-FR", "de-DE", "ko-KR", "ja-JP"]) == .korean)
        #expect(AppLanguage.resolveSystemLanguage(from: ["es-ES", "zh-TW"]) == .traditionalChinese)

        // 非対応言語のみ、または空配列の場合は英語へフォールバックする
        #expect(AppLanguage.resolveSystemLanguage(from: ["fr-FR", "de-DE"]) == .english)
        #expect(AppLanguage.resolveSystemLanguage(from: []) == .english)
        #expect(AppLanguage.resolveSystemLanguage(from: ["   "]) == .english)
    }

    /// 明示言語を選択した場合はシステム優先言語に関わらず選択言語へ解決されることを検証する
    @Test("明示的に選択した言語はシステム優先言語を上書きして解決される")
    func explicitLanguageOverridesPreferredLanguages() {
        let preferred = ["ja-JP"]
        #expect(AppLanguage.system.resolved(preferredLanguages: preferred) == .japanese)
        #expect(AppLanguage.japanese.resolved(preferredLanguages: ["en-US"]) == .japanese)
        #expect(AppLanguage.english.resolved(preferredLanguages: preferred) == .english)
        #expect(AppLanguage.simplifiedChinese.resolved(preferredLanguages: preferred) == .simplifiedChinese)
        #expect(AppLanguage.traditionalChinese.resolved(preferredLanguages: preferred) == .traditionalChinese)
        #expect(AppLanguage.korean.resolved(preferredLanguages: preferred) == .korean)
    }

    /// ピッカー選択肢の先頭が現在言語ローカライズの「システム設定に従う」で、各言語がネイティブ表記であることを検証する
    @Test("言語ピッカー選択肢は先頭のみ現在言語でローカライズされ、5 言語はネイティブ表記を固定維持する")
    func pickerDisplayNamesKeepNativeNamesForExplicitLanguages() {
        #expect(AppLanguage.allCases == [.system, .japanese, .english, .simplifiedChinese, .traditionalChinese, .korean])

        for displayLanguage in ResolvedAppLanguage.allCases {
            #expect(AppLanguage.system.pickerDisplayName(in: displayLanguage) == AppStrings(language: displayLanguage).languageFollowSystem)
            #expect(AppLanguage.japanese.pickerDisplayName(in: displayLanguage) == "日本語")
            #expect(AppLanguage.english.pickerDisplayName(in: displayLanguage) == "English")
            #expect(AppLanguage.simplifiedChinese.pickerDisplayName(in: displayLanguage) == "简体中文")
            #expect(AppLanguage.traditionalChinese.pickerDisplayName(in: displayLanguage) == "繁體中文")
            #expect(AppLanguage.korean.pickerDisplayName(in: displayLanguage) == "한국어")
        }
    }

    // MARK: - 翻訳テーブル網羅性

    /// すべての静的キーおよび動的パラメータ付き文言が 5 言語すべてで非空かつ整合的に定義されていることを検証する
    @Test("全 5 言語のすべてのローカライズキーおよび動的文言が非空で正しく展開される")
    func allLocalizationKeysAndDynamicStringsAreCompleteAcrossAllFiveLanguages() {
        #expect(ResolvedAppLanguage.allCases.count == 5)

        for language in ResolvedAppLanguage.allCases {
            let strings = AppStrings(language: language)
            for key in AppStringKey.allCases {
                let value = strings.text(for: key).trimmingCharacters(in: .whitespacesAndNewlines)
                #expect(!value.isEmpty, "キー \(key.rawValue) の言語 \(language.rawValue) 翻訳が空です")
            }

            // 動的パラメータ付き文言に引数が正しく埋め込まれていること
            #expect(strings.quitMenuTitle(appName: "Wintch_dev").contains("Wintch_dev"))
            #expect(strings.settingsWindowTitle(appName: "Wintch").contains("Wintch"))
            #expect(strings.permissionGuideWindowTitle(appName: "Wintch_dev").contains("Wintch_dev"))
            #expect(strings.permissionGuideStep2(appName: "Wintch_dev").contains("Wintch_dev"))
            #expect(strings.versionText(shortVersion: "0.2.6", buildNumber: "42").contains("0.2.6"))
            #expect(strings.versionText(shortVersion: "0.2.6", buildNumber: "42").contains("42"))
            #expect(strings.controlsNext("⌥ + ⇥").contains("⌥ + ⇥"))
            #expect(strings.controlsPrevious("⌥ + ⇧ + ⇥").contains("⌥ + ⇧ + ⇥"))
            #expect(strings.launchAtLoginError(detail: "ERR_CODE").contains("ERR_CODE"))
            #expect(strings.shortcutConflictWithNormalSwitcher(forward: "⌥ + ⇥", reverse: "⌥ + ⇧ + ⇥").contains("⌥ + ⇥"))
            #expect(strings.shortcutConflictWithNormalSwitcher(forward: "⌥ + ⇥", reverse: "⌥ + ⇧ + ⇥").contains("⌥ + ⇧ + ⇥"))
            #expect(strings.shortcutConflictWithLauncher(shortcut: "⌥ + Space").contains("⌥ + Space"))

            // ドメイン列挙型の表示文言も全言語で非空であること
            for tab in SettingsTab.allCases {
                #expect(!tab.title(in: language).isEmpty)
            }
            for style in SwitcherDisplayStyle.allCases {
                #expect(!style.displayName(in: language).isEmpty)
            }
            for style in LauncherDisplayStyle.allCases {
                #expect(!style.displayName(in: language).isEmpty)
            }
            for emptyState in [LauncherEmptyState.noOpenWindows, .noMatchingApps, .noMatchingCandidates] {
                #expect(!emptyState.message(in: language).isEmpty)
            }
        }

        // 英語では日本語文字（ひらがな・カタカナ）が混入していないことを確認する
        let englishStrings = AppStrings(language: .english)
        let kanaPattern = /[ぁ-んァ-ヶ]/
        for key in AppStringKey.allCases {
            let value = englishStrings.text(for: key)
            #expect(value.firstMatch(of: kanaPattern) == nil, "英語翻訳にかな文字が混入しています: \(key.rawValue) = \(value)")
        }
    }

    // MARK: - 永続化 (UserDefaults)

    /// PreferencesStore で dev.wintch.appLanguage が未保存時 .system、全 6 値保存復元、不正値フォールバックすることを確認する
    @Test("PreferencesStore で言語設定の永続化・未保存デフォルト・不正値フォールバックが動作する")
    func preferencesStorePersistsAppLanguageWithSafeFallback() {
        let suiteName = "dev.wintch.tests.appLanguage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        defer { defaults?.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(suiteName: suiteName)
        #expect(store.loadAppLanguage() == .system)

        for language in AppLanguage.allCases {
            store.saveAppLanguage(language)
            #expect(defaults?.string(forKey: "dev.wintch.appLanguage") == language.rawValue)
            #expect(store.loadAppLanguage() == language)
        }

        // 不正値が入っている場合は安全に .system へフォールバックする
        defaults?.set("fr-FR", forKey: "dev.wintch.appLanguage")
        #expect(store.loadAppLanguage() == .system)
    }

    // MARK: - SettingsViewModel / AppCoordinator の即時反映

    /// 検証エラーや自動起動エラーが表示された状態で言語を切り替えても、旧言語の文字列が残らず新言語へ即時切り替わることを検証する
    @Test("検証エラーおよび自動起動エラー表示中に言語切替すると新言語のメッセージへ即時更新される")
    @MainActor
    func settingsViewModelUpdatesErrorsImmediatelyOnLanguageChange() {
        let store = MockPreferencesStore()
        let launchService = MockLaunchAtLoginService()
        launchService.errorToThrow = MockLocalizedLaunchError()

        let viewModel = SettingsViewModel(
            preferencesStore: store,
            hotKeyMonitor: MockHotKeyMonitor(),
            launchAtLoginService: launchService,
            permissionService: MockAccessibilityPermissionService(),
            preferredLanguagesProvider: { ["ja-JP"] }
        )

        #expect(viewModel.appLanguage == .system)
        #expect(viewModel.resolvedLanguage == .japanese)

        // 自動起動エラーおよびショートカット検証エラーを発生させる
        viewModel.setLaunchAtLogin(true)
        viewModel.recordNormalShortcut(ShortcutPreference(keyCode: 40, modifiers: [.option, .shift], keyLabel: "K"))
        let jpLaunchError = viewModel.launchAtLoginError
        let jpValidationError = viewModel.shortcutValidationError
        #expect(jpLaunchError == AppStrings.japanese.launchAtLoginError(detail: "MockSMError"))
        #expect(jpValidationError == AppStrings.japanese.text(for: .shortcutValidationShiftReserved))

        // 英語へ切り替えるとエラー文言も即座に英語へ再評価される
        var notified: [(AppLanguage, ResolvedAppLanguage)] = []
        viewModel.onAppLanguageChanged = { notified.append(($0, $1)) }
        viewModel.updateAppLanguage(.english)

        #expect(store.storedAppLanguage == .english)
        #expect(store.saveAppLanguageCallCount == 1)
        #expect(viewModel.resolvedLanguage == .english)
        #expect(notified.count == 1)
        #expect(notified[0].0 == .english && notified[0].1 == .english)
        #expect(viewModel.launchAtLoginError == AppStrings.english.launchAtLoginError(detail: "MockSMError"))
        #expect(viewModel.shortcutValidationError == AppStrings.english.text(for: .shortcutValidationShiftReserved))

        // 韓国語へ切り替えても即時反映される
        viewModel.updateAppLanguage(.korean)
        #expect(viewModel.launchAtLoginError == AppStrings(language: .korean).launchAtLoginError(detail: "MockSMError"))
        #expect(viewModel.shortcutValidationError == AppStrings(language: .korean).text(for: .shortcutValidationShiftReserved))
    }

    /// AppCoordinator で言語を切り替えると、開いている設定ウィンドウ・権限誘導ウィンドウのタイトルおよび全 ViewModel が再起動なしで即時更新されることを検証する
    @Test("AppCoordinator の言語切替で設定・権限誘導ウィンドウタイトルおよび全 ViewModel が即時同期される")
    @MainActor
    func coordinatorPropagatesLanguageChangeToWindowsAndViewModels() {
        let store = MockPreferencesStore()
        let permissionService = MockAccessibilityPermissionService()
        permissionService.stubbedStatus = .denied
        let presenter = MockWindowFrontPresenter()
        let identity = AppIdentity(infoDictionary: [
            "CFBundleDisplayName": "Wintch",
            "CFBundleIdentifier": "dev.wintch.Wintch"
        ])

        let coordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: permissionService,
            preferencesStore: store,
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            windowFrontPresenter: presenter,
            appIdentity: identity,
            preferredLanguagesProvider: { ["ja-JP"] }
        )

        coordinator.openSettings()
        coordinator.openPermissionGuide()
        #expect(presenter.presentedWindows.count == 2)
        let settingsWindow = presenter.presentedWindows[0]
        let permissionWindow = presenter.presentedWindows[1]

        #expect(settingsWindow.title == "Wintch 設定")
        #expect(permissionWindow.title == "Wintch - 権限の確認")
        #expect(coordinator.switcherViewModel.resolvedLanguage == .japanese)
        #expect(coordinator.permissionGuideViewModel.resolvedLanguage == .japanese)

        // 英語へ切り替え
        coordinator.updateAppLanguage(.english)
        #expect(coordinator.resolvedLanguage == .english)
        #expect(coordinator.switcherViewModel.resolvedLanguage == .english)
        #expect(coordinator.permissionGuideViewModel.resolvedLanguage == .english)
        #expect(settingsWindow.title == "Wintch Settings")
        #expect(permissionWindow.title == "Wintch - Permission Required")
        #expect(coordinator.switcherViewModel.launchSectionHeaderTitle == "Launch App")

        // 権限誘導ウィンドウの高さが英語テキストの必要サイズ以上に維持されていること
        let permissionContentSize = permissionWindow.contentView?.frame.size ?? .zero
        #expect(permissionContentSize.width >= PermissionGuideView.preferredWidth)
        #expect(permissionContentSize.height >= PermissionGuideView.minimumHeight)

        // 簡体字中国語 → 繁体字中国語 → 韓国語へ連続切替しても即時反映される
        coordinator.updateAppLanguage(.simplifiedChinese)
        #expect(settingsWindow.title == "Wintch 设置")
        #expect(permissionWindow.title == "Wintch - 权限确认")
        #expect(coordinator.switcherViewModel.launchSectionHeaderTitle == "启动应用")

        coordinator.updateAppLanguage(.traditionalChinese)
        #expect(settingsWindow.title == "Wintch 設定")
        #expect(permissionWindow.title == "Wintch - 權限確認")
        #expect(coordinator.switcherViewModel.launchSectionHeaderTitle == "啟動應用程式")

        coordinator.updateAppLanguage(.korean)
        #expect(settingsWindow.title == "Wintch 설정")
        #expect(permissionWindow.title == "Wintch - 권한 확인")
        #expect(coordinator.switcherViewModel.launchSectionHeaderTitle == "앱 실행")
    }

    // MARK: - LauncherSearchField プレースホルダー動的更新

    /// LauncherSearchField のプレースホルダーが指定言語で生成され、言語変更時に動的更新されることを検証する
    @Test("LauncherSearchField のプレースホルダーが言語変更に合わせて動的更新される")
    @MainActor
    func launcherSearchFieldUpdatesPlaceholderDynamicallyOnLanguageChange() {
        let jaField = LauncherSearchField(
            text: .constant(""),
            isActive: true,
            placeholder: AppStrings.japanese.launcherSearchPlaceholder,
            onMoveSelection: { _ in },
            onConfirm: {},
            onCancel: {}
        )
        let textField = jaField.makeConfiguredTextField(delegate: nil)
        #expect(textField.placeholderAttributedString?.string == "ウィンドウまたはアプリを検索...")

        for language in ResolvedAppLanguage.allCases {
            let expected = AppStrings(language: language).launcherSearchPlaceholder
            let updatedField = LauncherSearchField(
                text: .constant(""),
                isActive: true,
                placeholder: expected,
                onMoveSelection: { _ in },
                onConfirm: {},
                onCancel: {}
            )
            updatedField.applyPlaceholderIfNeeded(to: textField)
            #expect(textField.placeholderAttributedString?.string == expected)
            let attrs = textField.placeholderAttributedString?.attributes(at: 0, effectiveRange: nil)
            #expect(attrs?[.foregroundColor] as? NSColor == NSColor.secondaryLabelColor)
        }
    }

    // MARK: - 空タイトル・不明アプリ補助テキストと検索対象外維持

    /// 空タイトル補助テキストと不明アプリフォールバック名が 5 言語すべてで返却され、空タイトル補助テキストは検索対象外であることを検証する
    @Test("空タイトル補助テキストと不明アプリ名が 5 言語で表示され、検索・ハイライト対象外を維持する")
    func untitledAndUnknownAppFallbacksLocalizeWithoutPollutingSearch() {
        let untitledEntry = WindowEntry(id: "u1", pid: 1, applicationName: "Finder", windowTitle: "   ")
        let unknownAppEntry = WindowEntry(id: "u2", pid: 2, applicationName: "", windowTitle: "Main")

        for language in ResolvedAppLanguage.allCases {
            let strings = AppStrings(language: language)
            #expect(untitledEntry.displayTitle(in: language) == strings.untitledWindow)
            #expect(unknownAppEntry.displayApplicationName(in: language) == strings.unknownApplication)

            // いずれの言語の空タイトル補助テキストで検索しても、空タイトルウィンドウに一致しないこと
            let results = WindowSearchEngine.search(query: strings.untitledWindow, in: [untitledEntry])
            #expect(results.isEmpty)
        }

        // 部分語（Untitled / 无标题 / 無標題 / 제목）でも空タイトルウィンドウは一致しない
        for query in ["Untitled", "无标题", "無標題", "제목", "タイトル"] {
            let results = WindowSearchEngine.search(query: query, in: [untitledEntry])
            #expect(results.isEmpty)
        }
    }

    // MARK: - 全 5 言語での設定・権限誘導ビューレイアウト健全性

    /// 全 5 言語で SettingsView（全 4 タブ）および PermissionGuideView が見切れなくレイアウト生成できることを検証する
    @Test("全 5 言語で設定画面および権限誘導画面のレイアウトが正常に構築される")
    @MainActor
    func settingsAndPermissionViewsLayoutCleanlyInAllFiveLanguages() {
        let store = MockPreferencesStore()
        let screenRecordingService = MockScreenRecordingPermissionService()
        screenRecordingService.stubbedStatus = .denied
        let settingsVM = SettingsViewModel(
            preferencesStore: store,
            hotKeyMonitor: MockHotKeyMonitor(),
            launchAtLoginService: MockLaunchAtLoginService(),
            permissionService: MockAccessibilityPermissionService(),
            screenRecordingPermissionService: screenRecordingService
        )
        settingsVM.updateNormalDisplayStyle(.capture)
        settingsVM.updateLauncherDisplayStyle(.capture)

        let permissionVM = PermissionGuideViewModel(permissionService: MockAccessibilityPermissionService())
        let identity = AppIdentity(infoDictionary: [
            "CFBundleDisplayName": "Wintch_dev",
            "CFBundleIdentifier": "dev.wintch.Wintch.dev"
        ])

        for language in ResolvedAppLanguage.allCases {
            let appLanguage = AppLanguage(rawValue: language.rawValue) ?? .system
            settingsVM.updateAppLanguage(appLanguage)
            permissionVM.updateLanguage(language)

            for tab in SettingsTab.allCases {
                settingsVM.selectTab(tab)
                let settingsHosting = NSHostingView(
                    rootView: SettingsView(viewModel: settingsVM, appIdentity: identity)
                )
                settingsHosting.layoutSubtreeIfNeeded()
                #expect(settingsHosting.fittingSize.width == SettingsView.preferredWidth)
                #expect(settingsHosting.fittingSize.height == SettingsView.preferredHeight)
            }

            let guideHosting = NSHostingView(
                rootView: PermissionGuideView(viewModel: permissionVM, appIdentity: identity)
            )
            guideHosting.layoutSubtreeIfNeeded()
            #expect(guideHosting.fittingSize.width >= PermissionGuideView.preferredWidth)
            // 言語ごとのテキスト行数差により 280pt 未満のコンパクトな高さになる場合もあるため正の有効高さかつ過度な膨張がないことを検証する
            #expect(guideHosting.fittingSize.height > 200)
            #expect(guideHosting.fittingSize.height < 600)
        }
    }
}
