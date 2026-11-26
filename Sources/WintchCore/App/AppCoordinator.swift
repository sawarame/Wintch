import AppKit
import Observation
import OSLog
import SwiftUI

/// アプリケーション全体の依存関係、権限監視、メニューバー、各種ウィンドウ表示を統括するコーディネーター
@MainActor
@Observable
public final class AppCoordinator {
    /// 診断ログ出力用ロガー
    private static let logger = Logger(subsystem: "dev.wintch.Wintch", category: "AppCoordinator")

    /// 現在のアクセシビリティ権限状態
    public private(set) var permissionStatus: AccessibilityPermissionStatus

    /// 権限未許可時の誘導画面を表示すべきかどうか
    public var isPermissionGuidePresented: Bool = false

    /// 更新確認ダイアログを表示中かどうか
    public private(set) var isUpdatePromptPresented: Bool = false

    /// 実行中アプリケーションの表示名・識別情報
    public let appIdentity: AppIdentity

    /// 実行中アプリケーションのバージョン情報
    public let versionInfo: AppVersionInfo

    /// スイッチャーパネルの状態管理 ViewModel
    public let switcherViewModel: SwitcherViewModel

    /// 設定画面の状態管理 ViewModel
    public let settingsViewModel: SettingsViewModel

    /// 権限誘導画面の状態管理 ViewModel
    public let permissionGuideViewModel: PermissionGuideViewModel

    /// 更新確認ダイアログの状態管理 ViewModel
    public let updateViewModel: UpdateViewModel

    /// 現在の通常スイッチャー表示形式
    public var normalDisplayStyle: SwitcherDisplayStyle {
        settingsViewModel.normalDisplayStyle
    }

    /// 現在の検索ランチャー表示形式
    public var launcherDisplayStyle: LauncherDisplayStyle {
        settingsViewModel.launcherDisplayStyle
    }

    /// 現在の通常スイッチャーのアプリグルーピング設定
    public var isNormalSwitcherGroupedByApp: Bool {
        settingsViewModel.isNormalSwitcherGroupedByApp
    }

    /// 現在の検索ランチャーのアプリグルーピング設定
    public var isLauncherGroupedByApp: Bool {
        settingsViewModel.isLauncherGroupedByApp
    }

    /// 現在のアプリ表示言語設定
    public var appLanguage: AppLanguage {
        settingsViewModel.appLanguage
    }

    /// 現在の UI 描画に適用されている解決済み言語
    public var resolvedLanguage: ResolvedAppLanguage {
        settingsViewModel.resolvedLanguage
    }

    /// 現在の解決済み言語に対応するローカライズ文言テーブル
    public var strings: AppStrings {
        settingsViewModel.strings
    }

    /// ウィンドウ情報サービス
    private let windowService: any WindowServicing
    /// グローバルホットキー監視サービス
    private let hotKeyMonitor: any HotKeyMonitoring
    /// アクセシビリティ権限サービス
    private let permissionService: any AccessibilityPermissionServicing
    /// 設定ストア
    private let preferencesStore: any PreferencesStoring
    /// ログイン時自動起動サービス
    private let launchAtLoginService: any LaunchAtLoginServicing
    /// アプリアイコン取得サービス
    private let iconProvider: any IconProviding
    /// インストール済みアプリ取得・起動サービス
    private let installedAppService: any InstalledAppServicing
    /// 画面収録権限確認・遷移サービス
    private let screenRecordingPermissionService: any ScreenRecordingPermissionServicing
    /// ウィンドウサムネイルキャプチャサービス
    private let windowCaptureService: any WindowCaptureServicing
    /// 標準ウィンドウ最前面表示プレゼンター
    private let windowFrontPresenter: any WindowFrontPresenting
    /// アップデート確認・適用サービス
    private let updateService: any AppUpdateServicing

    /// フローティングスイッチャーパネル（遅延生成）
    private var switcherPanel: SwitcherPanel?
    /// 設定画面ウィンドウ（遅延生成）
    private var settingsWindow: NSWindow?
    /// 権限誘導画面ウィンドウ（遅延生成）
    private var permissionWindow: NSWindow?
    /// 更新確認ダイアログウィンドウ（遅延生成）
    private var updateWindow: NSWindow?
    /// 権限誘導画面の表示中に保留された自動チェック検出アップデート情報
    private var pendingAutomaticUpdate: (release: AppReleaseInfo, currentVersion: SemanticVersion)?
    /// 起動時自動アップデート確認タスク
    private var automaticUpdateCheckTask: Task<Void, Never>?
    /// 起動時自動アップデート確認タスクが実行中かどうか（テストでの確定完了待機用）
    internal var isAutomaticUpdateCheckRunning: Bool {
        automaticUpdateCheckTask != nil
    }
    /// 開始済みフラグ
    private var isStarted = false

    /// 標準の本番サービス一式でコーディネーターを初期化する
    public convenience init() {
        let screenRecordingPermissionService = ScreenRecordingPermissionService()
        self.init(
            windowService: WindowService(),
            hotKeyMonitor: HotKeyMonitorService(),
            permissionService: AccessibilityPermissionService(),
            preferencesStore: PreferencesStore(),
            launchAtLoginService: LaunchAtLoginService(),
            iconProvider: IconProviderService(),
            installedAppService: InstalledAppService(),
            screenRecordingPermissionService: screenRecordingPermissionService,
            windowCaptureService: WindowCaptureService(
                screenRecordingPermissionService: screenRecordingPermissionService
            )
        )
    }

    /// テストやカスタマイズ用に依存サービスを注入してコーディネーターを初期化する
    /// - Parameters:
    ///   - windowService: ウィンドウ情報サービス
    ///   - hotKeyMonitor: ホットキー監視サービス
    ///   - permissionService: 権限監視サービス
    ///   - preferencesStore: 設定ストア
    ///   - launchAtLoginService: ログイン時自動起動サービス
    ///   - iconProvider: アイコン取得サービス
    ///   - installedAppService: インストール済みアプリ取得・起動サービス
    ///   - screenRecordingPermissionService: 画面収録権限サービス
    ///   - windowCaptureService: ウィンドウキャプチャサービス
    ///   - windowFrontPresenter: 標準ウィンドウ最前面表示プレゼンター
    ///   - updateService: アップデート確認・適用サービス
    ///   - appIdentity: アプリ識別情報（既定値はメインバンドルから取得）
    ///   - versionInfo: アプリバージョン情報（既定値はメインバンドルから取得）
    ///   - preferredLanguagesProvider: システム優先言語配列の提供クロージャ（既定値は `Locale.preferredLanguages`）
    public init(
        windowService: any WindowServicing,
        hotKeyMonitor: any HotKeyMonitoring,
        permissionService: any AccessibilityPermissionServicing,
        preferencesStore: any PreferencesStoring,
        launchAtLoginService: any LaunchAtLoginServicing,
        iconProvider: any IconProviding,
        installedAppService: any InstalledAppServicing = InstalledAppService(),
        screenRecordingPermissionService: any ScreenRecordingPermissionServicing = ScreenRecordingPermissionService(),
        windowCaptureService: any WindowCaptureServicing = WindowCaptureService(),
        windowFrontPresenter: any WindowFrontPresenting = WindowFrontPresenter(),
        updateService: any AppUpdateServicing = AppUpdateService(),
        appIdentity: AppIdentity = .current,
        versionInfo: AppVersionInfo = .current,
        preferredLanguagesProvider: @escaping @Sendable () -> [String] = { Locale.preferredLanguages }
    ) {
        self.appIdentity = appIdentity
        self.versionInfo = versionInfo
        self.windowService = windowService
        self.hotKeyMonitor = hotKeyMonitor
        self.permissionService = permissionService
        self.preferencesStore = preferencesStore
        self.launchAtLoginService = launchAtLoginService
        self.iconProvider = iconProvider
        self.installedAppService = installedAppService
        self.screenRecordingPermissionService = screenRecordingPermissionService
        self.windowCaptureService = windowCaptureService
        self.windowFrontPresenter = windowFrontPresenter
        self.updateService = updateService
        self.permissionStatus = permissionService.currentStatus()

        let initialDisplayStyle = preferencesStore.loadNormalDisplayStyle()
        let initialLauncherDisplayStyle = preferencesStore.loadLauncherDisplayStyle()
        let initialNormalGrouping = preferencesStore.loadGroupNormalSwitcherByApp()
        let initialLauncherGrouping = preferencesStore.loadGroupLauncherByApp()
        let settingsViewModel = SettingsViewModel(
            preferencesStore: preferencesStore,
            hotKeyMonitor: hotKeyMonitor,
            launchAtLoginService: launchAtLoginService,
            permissionService: permissionService,
            screenRecordingPermissionService: screenRecordingPermissionService,
            updateService: updateService,
            appIdentity: appIdentity,
            versionInfo: versionInfo,
            preferredLanguagesProvider: preferredLanguagesProvider
        )
        let initialResolvedLanguage = settingsViewModel.resolvedLanguage
        self.settingsViewModel = settingsViewModel
        self.switcherViewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            installedAppService: installedAppService,
            screenRecordingPermissionService: screenRecordingPermissionService,
            windowCaptureService: windowCaptureService,
            normalDisplayStyle: initialDisplayStyle,
            launcherDisplayStyle: initialLauncherDisplayStyle,
            isNormalSwitcherGroupedByApp: initialNormalGrouping,
            isLauncherGroupedByApp: initialLauncherGrouping,
            resolvedLanguage: initialResolvedLanguage
        )
        self.permissionGuideViewModel = PermissionGuideViewModel(
            permissionService: permissionService,
            resolvedLanguage: initialResolvedLanguage
        )
        self.updateViewModel = UpdateViewModel(
            updateService: updateService,
            preferencesStore: preferencesStore,
            appIdentity: appIdentity,
            versionInfo: versionInfo,
            resolvedLanguage: initialResolvedLanguage
        )

        setupBindings()
    }

    /// アプリ起動時の初期化処理と権限監視を開始する
    public func start() {
        guard !isStarted else { return }
        isStarted = true

        // 保存されている通常およびランチャーのショートカット設定ならびに表示形式・グルーピング・言語設定をロードして反映する
        let savedShortcut = preferencesStore.loadShortcut()
        let savedLauncherShortcut = preferencesStore.loadLauncherShortcut()
        let savedDisplayStyle = preferencesStore.loadNormalDisplayStyle()
        let savedLauncherDisplayStyle = preferencesStore.loadLauncherDisplayStyle()
        let savedNormalGrouping = preferencesStore.loadGroupNormalSwitcherByApp()
        let savedLauncherGrouping = preferencesStore.loadGroupLauncherByApp()
        let savedAppLanguage = preferencesStore.loadAppLanguage()
        hotKeyMonitor.updateShortcut(savedShortcut)
        hotKeyMonitor.updateLauncherShortcut(savedLauncherShortcut)
        switcherViewModel.updateNormalDisplayStyle(savedDisplayStyle)
        switcherViewModel.updateLauncherDisplayStyle(savedLauncherDisplayStyle)
        switcherViewModel.updateNormalSwitcherGrouping(savedNormalGrouping)
        switcherViewModel.updateLauncherGrouping(savedLauncherGrouping)
        settingsViewModel.updateAppLanguage(savedAppLanguage)
        applyResolvedLanguage(settingsViewModel.resolvedLanguage)

        // 初期の権限状態を確認し、監視を開始する
        updatePermissionState(permissionService.currentStatus())
        permissionService.startMonitoring { [weak self] latestStatus in
            self?.updatePermissionState(latestStatus)
        }

        // 初回ランチャー検索から即時応答できるようインストール済みアプリ一覧をバックグラウンドで事前収集する
        switcherViewModel.preloadInstalledApps()

        // オプトイン設定が有効な配布版のみ、起動・ホットキー監視をブロックせず非同期で最新バージョンを確認する
        scheduleAutomaticUpdateCheckIfNeeded()
    }

    /// 起動時の自動アップデート確認を必要に応じて非同期バックグラウンド実行する
    private func scheduleAutomaticUpdateCheckIfNeeded() {
        let isAutoCheckEnabled = preferencesStore.loadAutoCheckForUpdates()
        guard UpdateCheckPolicy.shouldPerformAutomaticCheck(
            isAutoCheckEnabled: isAutoCheckEnabled,
            appIdentity: appIdentity,
            versionInfo: versionInfo
        ) else {
            return
        }

        automaticUpdateCheckTask?.cancel()
        let updateService = self.updateService
        let appIdentity = self.appIdentity
        let versionInfo = self.versionInfo
        let skippedVersion = preferencesStore.loadSkippedUpdateVersion()

        automaticUpdateCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.automaticUpdateCheckTask = nil }
            do {
                let release = try await updateService.fetchLatestStableRelease()
                guard !Task.isCancelled else { return }

                let decision = UpdateCheckPolicy.evaluate(
                    release: release,
                    currentVersionInfo: versionInfo,
                    appIdentity: appIdentity,
                    skippedVersion: skippedVersion,
                    trigger: .automatic
                )
                guard case let .updateAvailable(currentVersion, availableRelease) = decision else {
                    return
                }

                // アクセシビリティ権限誘導画面の表示中は重複表示を避け、権限許可後に提示する
                if self.isPermissionGuidePresented {
                    self.pendingAutomaticUpdate = (availableRelease, currentVersion)
                } else {
                    self.presentUpdatePrompt(release: availableRelease, currentVersion: currentVersion)
                }
            } catch {
                // 起動時自動チェックの通信エラーやレート制限はログ出力のみでサイレント終了する
                Self.logger.info("起動時自動アップデート確認をスキップしました: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 更新確認ダイアログを最前面に表示する
    /// - Parameters:
    ///   - release: 提示対象の新リリース情報
    ///   - currentVersion: 現在のアプリバージョン
    public func presentUpdatePrompt(release: AppReleaseInfo, currentVersion: SemanticVersion) {
        pendingAutomaticUpdate = nil
        updateViewModel.present(release: release, currentVersion: currentVersion)
        isUpdatePromptPresented = true
        let window = ensureUpdateWindow()
        windowFrontPresenter.presentFrontmost(window)
    }

    /// 更新確認ダイアログを閉じる
    public func closeUpdatePromptWindow() {
        isUpdatePromptPresented = false
        updateWindow?.orderOut(nil)
    }

    /// 設定画面を最前面に表示する
    public func openSettings() {
        settingsViewModel.refreshStatus()
        let window = ensureSettingsWindow()
        windowFrontPresenter.presentFrontmost(window)
    }

    /// アクセシビリティ権限誘導画面を最前面に表示する
    public func openPermissionGuide() {
        permissionGuideViewModel.refreshStatus()
        // 再確認の結果すでに権限が回復していた場合は誘導画面を表示しない
        guard permissionStatus == .denied else { return }
        presentPermissionGuideWindow()
    }

    /// アプリケーションを安全に終了する
    public func quit() {
        automaticUpdateCheckTask?.cancel()
        switcherViewModel.stopBackgroundCaptureWork()
        hotKeyMonitor.stopMonitoring()
        windowService.stopObserving()
        permissionService.stopMonitoring()
        NSApplication.shared.terminate(nil)
    }

    /// 通常スイッチャーの表示形式を更新し、永続化・スイッチャー状態・設定画面を即時同期する
    /// - Parameter style: 新しい表示形式
    public func updateNormalDisplayStyle(_ style: SwitcherDisplayStyle) {
        settingsViewModel.updateNormalDisplayStyle(style)
    }

    /// 検索ランチャーの表示形式を更新し、永続化・スイッチャー状態・設定画面を即時同期する
    /// - Parameter style: 新しい検索ランチャー表示形式
    public func updateLauncherDisplayStyle(_ style: LauncherDisplayStyle) {
        settingsViewModel.updateLauncherDisplayStyle(style)
    }

    /// 通常スイッチャーのアプリグルーピング設定を更新し、永続化・スイッチャー状態・設定画面を即時同期する
    /// - Parameter enabled: アプリごとにグルーピングする場合は true
    public func updateNormalSwitcherGrouping(_ enabled: Bool) {
        settingsViewModel.updateNormalSwitcherGrouping(enabled)
    }

    /// 検索ランチャーのアプリグルーピング設定を更新し、永続化・スイッチャー状態・設定画面を即時同期する
    /// - Parameter enabled: アプリごとにグルーピングする場合は true
    public func updateLauncherGrouping(_ enabled: Bool) {
        settingsViewModel.updateLauncherGrouping(enabled)
    }

    /// アプリの表示言語設定を更新し、永続化・全 ViewModel・ウィンドウタイトルへ即時同期する
    /// - Parameter language: 新しい言語設定
    public func updateAppLanguage(_ language: AppLanguage) {
        settingsViewModel.updateAppLanguage(language)
    }

    /// 権限状態の変化に応じて監視サービスの起動・停止および誘導画面の表示を切り替える
    /// - Parameter status: 最新の権限状態
    public func updatePermissionState(_ status: AccessibilityPermissionStatus) {
        switch status {
        case .granted:
            // CGEventTap の作成・有効化に失敗した場合は未許可扱いとして安全に誘導画面を維持する
            guard hotKeyMonitor.startMonitoring() else {
                transitionToDeniedState()
                return
            }
            permissionStatus = .granted
            settingsViewModel.refreshStatus(permissionStatus: .granted)
            permissionGuideViewModel.syncStatus(.granted)
            isPermissionGuidePresented = false
            permissionWindow?.orderOut(nil)
            switcherViewModel.enableBackgroundCapturePrefetch()
            windowService.startObserving()
            // 権限誘導画面の表示中に保留していた起動時自動チェックの更新通知があればここで提示する
            if let pending = pendingAutomaticUpdate {
                presentUpdatePrompt(release: pending.release, currentVersion: pending.currentVersion)
            }
        case .denied:
            transitionToDeniedState()
        }
    }

    /// 監視中に OS 側のイベントタップ無効化／権限剥奪を検知した際の安全停止処理
    private func handleMonitoringInterrupted() {
        transitionToDeniedState()
    }

    /// 権限未許可または監視中断時の安全停止と誘導状態への遷移を一元実行する
    private func transitionToDeniedState() {
        let shouldPresentGuide = permissionStatus != .denied || !isPermissionGuidePresented
        permissionStatus = .denied
        settingsViewModel.refreshStatus(permissionStatus: .denied)
        permissionGuideViewModel.syncStatus(.denied)
        switcherViewModel.cancel()
        switcherViewModel.stopBackgroundCaptureWork()
        hotKeyMonitor.stopMonitoring()
        windowService.stopObserving()
        isPermissionGuidePresented = true
        if shouldPresentGuide {
            presentPermissionGuideWindow()
        }
    }

    /// 再帰的な権限再チェックを発火させずに権限誘導ウィンドウを前面表示する
    private func presentPermissionGuideWindow() {
        let window = ensurePermissionWindow()
        windowFrontPresenter.presentFrontmost(window)
    }

    /// 各 ViewModel とサービスのイベントコールバックを接続する
    private func setupBindings() {
        hotKeyMonitor.onEvent = { [weak self] event in
            self?.switcherViewModel.handleHotKeyEvent(event)
        }

        hotKeyMonitor.onMonitoringInterrupted = { [weak self] in
            self?.handleMonitoringInterrupted()
        }

        switcherViewModel.onModePresentationChanged = { [weak self] mode, reason in
            guard let self else { return }
            switch mode {
            case .normal, .launcher:
                self.ensureSwitcherPanel().show(
                    mode: mode,
                    activateApp: self.switcherViewModel.shouldActivateAppForCurrentSession,
                    verticalPlacement: self.switcherViewModel.panelVerticalPlacement
                )
            case .inactive:
                // ランチャーモードで Esc / トグル終了した場合のみ直前アプリへフォーカスを戻す
                let shouldRestore = reason == .cancelled
                self.switcherPanel?.hidePanel(restorePreviousApp: shouldRestore)
            }
        }

        switcherViewModel.onSearchResultsUpdated = { [weak self] in
            // SwiftUI の状態更新に伴うレイアウト反映後にパネル上端固定リサイズを行う
            Task { @MainActor [weak self] in
                self?.switcherPanel?.updateAnchoredHeightIfNeeded()
            }
        }

        switcherViewModel.onPermissionDenied = { [weak self] in
            self?.updatePermissionState(.denied)
        }

        switcherViewModel.onPanelFocusRestoreNeeded = { [weak self] mode in
            self?.switcherPanel?.restoreFocusIfNeeded(mode: mode)
        }

        permissionGuideViewModel.onPermissionGranted = { [weak self] in
            self?.updatePermissionState(.granted)
        }

        settingsViewModel.onNormalDisplayStyleChanged = { [weak self] newStyle in
            self?.switcherViewModel.updateNormalDisplayStyle(newStyle)
        }

        settingsViewModel.onLauncherDisplayStyleChanged = { [weak self] newStyle in
            self?.switcherViewModel.updateLauncherDisplayStyle(newStyle)
        }

        settingsViewModel.onNormalSwitcherGroupingChanged = { [weak self] isGrouped in
            self?.switcherViewModel.updateNormalSwitcherGrouping(isGrouped)
        }

        settingsViewModel.onLauncherGroupingChanged = { [weak self] isGrouped in
            self?.switcherViewModel.updateLauncherGrouping(isGrouped)
        }

        settingsViewModel.onAppLanguageChanged = { [weak self] _, newResolvedLanguage in
            self?.applyResolvedLanguage(newResolvedLanguage)
        }

        settingsViewModel.onUpdateAvailable = { [weak self] release, currentVersion in
            self?.presentUpdatePrompt(release: release, currentVersion: currentVersion)
        }

        updateViewModel.onCloseRequested = { [weak self] in
            self?.closeUpdatePromptWindow()
        }

        updateViewModel.onQuitForRestartRequested = { [weak self] in
            self?.quit()
        }
    }

    /// 解決済み言語の変更を全 ViewModel・ウィンドウタイトル・権限誘導ウィンドウサイズへ即時反映する
    /// - Parameter language: 新しい解決済み言語
    private func applyResolvedLanguage(_ language: ResolvedAppLanguage) {
        switcherViewModel.updateLanguage(language)
        permissionGuideViewModel.updateLanguage(language)
        updateViewModel.updateLanguage(language)
        settingsWindow?.title = appIdentity.settingsWindowTitle(in: language)
        updateWindow?.title = appIdentity.updateWindowTitle(in: language)
        if let permissionWindow {
            permissionWindow.title = appIdentity.permissionGuideWindowTitle(in: language)
            resizePermissionWindowToFit(permissionWindow)
        }
    }

    /// 権限誘導ウィンドウのコンテンツ必要サイズを再計測し、言語ごとの行数変化によるテキスト見切れを防ぐ
    /// - Parameter window: 対象の権限誘導ウィンドウ
    private func resizePermissionWindowToFit(_ window: NSWindow) {
        guard let hostingView = window.contentView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let contentSize = NSSize(
            width: max(fittingSize.width, PermissionGuideView.preferredWidth),
            height: max(fittingSize.height, PermissionGuideView.minimumHeight)
        )
        window.setContentSize(contentSize)
    }

    /// フローティングスイッチャーパネルを必要に応じて生成して返す
    /// - Returns: 設定済みの SwitcherPanel
    private func ensureSwitcherPanel() -> SwitcherPanel {
        if let panel = switcherPanel {
            return panel
        }
        let contentView = SwitcherContentView(
            viewModel: switcherViewModel,
            onContentSizeChanged: { [weak self] newSize in
                self?.switcherPanel?.updateAnchoredSize(to: newSize)
            }
        )
        let panel = SwitcherPanel(contentView: contentView)
        panel.onPrepareScreenSize = { [weak self] size in
            self?.switcherViewModel.updateAvailableScreenSize(size)
        }
        panel.onResignActive = { [weak self] in
            self?.switcherViewModel.cancel(reason: .resignedActive)
        }
        switcherPanel = panel
        return panel
    }

    /// 設定画面用の NSWindow を必要に応じて生成して返す
    /// - Returns: 設定済みの NSWindow
    private func ensureSettingsWindow() -> NSWindow {
        if let settingsWindow {
            return settingsWindow
        }
        let hostingView = NSHostingView(
            rootView: SettingsView(
                viewModel: settingsViewModel,
                appIdentity: appIdentity,
                versionInfo: versionInfo
            )
        )
        let contentSize = NSSize(
            width: SettingsView.preferredWidth,
            height: SettingsView.preferredHeight
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = appIdentity.settingsWindowTitle(in: resolvedLanguage)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.setContentSize(contentSize)
        settingsWindow = window
        return window
    }

    /// 権限誘導画面用の NSWindow を必要に応じて生成して返す
    /// - Returns: 設定済みの NSWindow
    private func ensurePermissionWindow() -> NSWindow {
        if let permissionWindow {
            return permissionWindow
        }
        let hostingView = NSHostingView(
            rootView: PermissionGuideView(viewModel: permissionGuideViewModel, appIdentity: appIdentity)
        )
        // SwiftUI の複数行テキスト折り返しを含む必要サイズを計測し、固定高さによる途中切れを防ぐ
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let contentSize = NSSize(
            width: max(fittingSize.width, PermissionGuideView.preferredWidth),
            height: max(fittingSize.height, PermissionGuideView.minimumHeight)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = appIdentity.permissionGuideWindowTitle(in: resolvedLanguage)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.setContentSize(contentSize)
        permissionWindow = window
        return window
    }

    /// 更新確認ダイアログ用の NSWindow を必要に応じて生成して返す
    /// - Returns: 設定済みの NSWindow
    private func ensureUpdateWindow() -> NSWindow {
        if let updateWindow {
            return updateWindow
        }
        let hostingView = NSHostingView(
            rootView: UpdatePromptView(
                viewModel: updateViewModel,
                appIdentity: appIdentity
            )
        )
        let contentSize = NSSize(
            width: UpdatePromptView.preferredWidth,
            height: UpdatePromptView.preferredHeight
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = appIdentity.updateWindowTitle(in: resolvedLanguage)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.setContentSize(contentSize)
        updateWindow = window
        return window
    }
}
