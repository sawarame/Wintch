import AppKit
import Observation
import SwiftUI

/// アプリケーション全体の依存関係、権限監視、メニューバー、各種ウィンドウ表示を統括するコーディネーター
@MainActor
@Observable
public final class AppCoordinator {
    /// 現在のアクセシビリティ権限状態
    public private(set) var permissionStatus: AccessibilityPermissionStatus

    /// 権限未許可時の誘導画面を表示すべきかどうか
    public var isPermissionGuidePresented: Bool = false

    /// 実行中アプリケーションの表示名・識別情報
    public let appIdentity: AppIdentity

    /// スイッチャーパネルの状態管理 ViewModel
    public let switcherViewModel: SwitcherViewModel

    /// 設定画面の状態管理 ViewModel
    public let settingsViewModel: SettingsViewModel

    /// 権限誘導画面の状態管理 ViewModel
    public let permissionGuideViewModel: PermissionGuideViewModel

    /// 現在の通常スイッチャー表示形式
    public var normalDisplayStyle: SwitcherDisplayStyle {
        settingsViewModel.normalDisplayStyle
    }

    /// 現在の検索ランチャー表示形式
    public var launcherDisplayStyle: LauncherDisplayStyle {
        settingsViewModel.launcherDisplayStyle
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

    /// フローティングスイッチャーパネル（遅延生成）
    private var switcherPanel: SwitcherPanel?
    /// 設定画面ウィンドウ（遅延生成）
    private var settingsWindow: NSWindow?
    /// 「Wintchについて」ウィンドウ（遅延生成）
    private var aboutWindow: NSWindow?
    /// 権限誘導画面ウィンドウ（遅延生成）
    private var permissionWindow: NSWindow?
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
    ///   - appIdentity: アプリ識別情報（既定値はメインバンドルから取得）
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
        appIdentity: AppIdentity = .current
    ) {
        self.appIdentity = appIdentity
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
        self.permissionStatus = permissionService.currentStatus()

        let initialDisplayStyle = preferencesStore.loadNormalDisplayStyle()
        let initialLauncherDisplayStyle = preferencesStore.loadLauncherDisplayStyle()
        self.switcherViewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider,
            installedAppService: installedAppService,
            screenRecordingPermissionService: screenRecordingPermissionService,
            windowCaptureService: windowCaptureService,
            normalDisplayStyle: initialDisplayStyle,
            launcherDisplayStyle: initialLauncherDisplayStyle
        )
        self.settingsViewModel = SettingsViewModel(
            preferencesStore: preferencesStore,
            hotKeyMonitor: hotKeyMonitor,
            launchAtLoginService: launchAtLoginService,
            permissionService: permissionService,
            screenRecordingPermissionService: screenRecordingPermissionService
        )
        self.permissionGuideViewModel = PermissionGuideViewModel(
            permissionService: permissionService
        )

        setupBindings()
    }

    /// アプリ起動時の初期化処理と権限監視を開始する
    public func start() {
        guard !isStarted else { return }
        isStarted = true

        // 保存されている通常およびランチャーのショートカット設定ならびに表示形式をロードして反映する
        let savedShortcut = preferencesStore.loadShortcut()
        let savedLauncherShortcut = preferencesStore.loadLauncherShortcut()
        let savedDisplayStyle = preferencesStore.loadNormalDisplayStyle()
        let savedLauncherDisplayStyle = preferencesStore.loadLauncherDisplayStyle()
        hotKeyMonitor.updateShortcut(savedShortcut)
        hotKeyMonitor.updateLauncherShortcut(savedLauncherShortcut)
        switcherViewModel.updateNormalDisplayStyle(savedDisplayStyle)
        switcherViewModel.updateLauncherDisplayStyle(savedLauncherDisplayStyle)

        // 初期の権限状態を確認し、監視を開始する
        updatePermissionState(permissionService.currentStatus())
        permissionService.startMonitoring { [weak self] latestStatus in
            self?.updatePermissionState(latestStatus)
        }

        // 初回ランチャー検索から即時応答できるようインストール済みアプリ一覧をバックグラウンドで事前収集する
        switcherViewModel.preloadInstalledApps()
    }

    /// 設定画面を最前面に表示する
    public func openSettings() {
        settingsViewModel.refreshStatus()
        let window = ensureSettingsWindow()
        windowFrontPresenter.presentFrontmost(window)
    }

    /// 「Wintchについて」画面を最前面に表示する
    public func openAbout() {
        let window = ensureAboutWindow()
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
            windowService.startObserving()
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
                    activateApp: self.switcherViewModel.shouldActivateAppForCurrentSession
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
        let hostingView = NSHostingView(rootView: SettingsView(viewModel: settingsViewModel))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = appIdentity.settingsWindowTitle
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        settingsWindow = window
        return window
    }

    /// 「〜について」画面用の NSWindow を必要に応じて生成して返す
    /// - Returns: 設定済みの NSWindow
    private func ensureAboutWindow() -> NSWindow {
        if let aboutWindow {
            return aboutWindow
        }
        let hostingView = NSHostingView(rootView: AboutView(appIdentity: appIdentity))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = appIdentity.aboutMenuTitle
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        aboutWindow = window
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
        window.title = appIdentity.permissionGuideWindowTitle
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.setContentSize(contentSize)
        permissionWindow = window
        return window
    }
}
