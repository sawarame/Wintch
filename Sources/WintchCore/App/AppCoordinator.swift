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

    /// スイッチャーパネルの状態管理 ViewModel
    public let switcherViewModel: SwitcherViewModel

    /// 設定画面の状態管理 ViewModel
    public let settingsViewModel: SettingsViewModel

    /// 権限誘導画面の状態管理 ViewModel
    public let permissionGuideViewModel: PermissionGuideViewModel

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

    /// フローティングスイッチャーパネル（遅延生成）
    private var switcherPanel: SwitcherPanel?
    /// 設定画面ウィンドウ（遅延生成）
    private var settingsWindow: NSWindow?
    /// 権限誘導画面ウィンドウ（遅延生成）
    private var permissionWindow: NSWindow?
    /// 開始済みフラグ
    private var isStarted = false

    /// 標準の本番サービス一式でコーディネーターを初期化する
    public convenience init() {
        self.init(
            windowService: WindowService(),
            hotKeyMonitor: HotKeyMonitorService(),
            permissionService: AccessibilityPermissionService(),
            preferencesStore: PreferencesStore(),
            launchAtLoginService: LaunchAtLoginService(),
            iconProvider: IconProviderService()
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
    public init(
        windowService: any WindowServicing,
        hotKeyMonitor: any HotKeyMonitoring,
        permissionService: any AccessibilityPermissionServicing,
        preferencesStore: any PreferencesStoring,
        launchAtLoginService: any LaunchAtLoginServicing,
        iconProvider: any IconProviding
    ) {
        self.windowService = windowService
        self.hotKeyMonitor = hotKeyMonitor
        self.permissionService = permissionService
        self.preferencesStore = preferencesStore
        self.launchAtLoginService = launchAtLoginService
        self.iconProvider = iconProvider
        self.permissionStatus = permissionService.currentStatus()

        self.switcherViewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: hotKeyMonitor,
            permissionService: permissionService,
            iconProvider: iconProvider
        )
        self.settingsViewModel = SettingsViewModel(
            preferencesStore: preferencesStore,
            hotKeyMonitor: hotKeyMonitor,
            launchAtLoginService: launchAtLoginService,
            permissionService: permissionService
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

        // 保存されている通常およびランチャーのショートカット設定をロードして監視サービスへ反映する
        let savedShortcut = preferencesStore.loadShortcut()
        let savedLauncherShortcut = preferencesStore.loadLauncherShortcut()
        hotKeyMonitor.updateShortcut(savedShortcut)
        hotKeyMonitor.updateLauncherShortcut(savedLauncherShortcut)

        // 初期の権限状態を確認し、監視を開始する
        updatePermissionState(permissionService.currentStatus())
        permissionService.startMonitoring { [weak self] latestStatus in
            self?.updatePermissionState(latestStatus)
        }
    }

    /// 設定画面を最前面に表示する
    public func openSettings() {
        settingsViewModel.refreshStatus()
        let window = ensureSettingsWindow()
        NSApplication.shared.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// アクセシビリティ権限誘導画面を最前面に表示する
    public func openPermissionGuide() {
        permissionGuideViewModel.refreshStatus()
        let window = ensurePermissionWindow()
        NSApplication.shared.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// アプリケーションを安全に終了する
    public func quit() {
        hotKeyMonitor.stopMonitoring()
        windowService.stopObserving()
        permissionService.stopMonitoring()
        NSApplication.shared.terminate(nil)
    }

    /// 権限状態の変化に応じて監視サービスの起動・停止および誘導画面の表示を切り替える
    /// - Parameter status: 最新の権限状態
    public func updatePermissionState(_ status: AccessibilityPermissionStatus) {
        permissionStatus = status
        settingsViewModel.refreshStatus()

        switch status {
        case .granted:
            isPermissionGuidePresented = false
            permissionWindow?.orderOut(nil)
            windowService.startObserving()
            hotKeyMonitor.startMonitoring()
        case .denied:
            switcherViewModel.cancel()
            hotKeyMonitor.stopMonitoring()
            windowService.stopObserving()
            isPermissionGuidePresented = true
            openPermissionGuide()
        }
    }

    /// 各 ViewModel とサービスのイベントコールバックを接続する
    private func setupBindings() {
        hotKeyMonitor.onEvent = { [weak self] event in
            self?.switcherViewModel.handleHotKeyEvent(event)
        }

        switcherViewModel.onModePresentationChanged = { [weak self] mode, reason in
            guard let self else { return }
            switch mode {
            case .normal, .launcher:
                self.ensureSwitcherPanel().show(mode: mode)
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

        permissionGuideViewModel.onPermissionGranted = { [weak self] in
            self?.updatePermissionState(.granted)
        }
    }

    /// フローティングスイッチャーパネルを必要に応じて生成して返す
    /// - Returns: 設定済みの SwitcherPanel
    private func ensureSwitcherPanel() -> SwitcherPanel {
        if let panel = switcherPanel {
            return panel
        }
        let listView = SwitcherListView(
            viewModel: switcherViewModel,
            onContentHeightChanged: { [weak self] newHeight in
                self?.switcherPanel?.updateAnchoredHeight(to: newHeight)
            }
        )
        let panel = SwitcherPanel(contentView: listView)
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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Wintch 設定"
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        settingsWindow = window
        return window
    }

    /// 権限誘導画面用の NSWindow を必要に応じて生成して返す
    /// - Returns: 設定済みの NSWindow
    private func ensurePermissionWindow() -> NSWindow {
        if let permissionWindow {
            return permissionWindow
        }
        let hostingView = NSHostingView(rootView: PermissionGuideView(viewModel: permissionGuideViewModel))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Wintch - 権限の確認"
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        permissionWindow = window
        return window
    }
}
