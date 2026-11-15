import AppKit
import Foundation
@testable import WintchCore

/// テスト用のウィンドウサービスモック
@MainActor
final class MockWindowService: WindowServicing {
    /// startObserving の呼び出し回数
    var startObservingCallCount = 0
    /// stopObserving の呼び出し回数
    var stopObservingCallCount = 0
    /// 返却する生ウィンドウ候補一覧
    var stubbedCandidates: [RawWindowCandidate] = []
    /// アクティブ化が要求されたウィンドウ履歴
    var activatedWindows: [WindowEntry] = []
    /// クローズが要求されたウィンドウ履歴
    var closedWindows: [WindowEntry] = []
    /// ウィンドウ ID ごとの closeWindow スタブ結果（未指定時は closeWindowDefaultResult を使用）
    var stubbedCloseWindowResults: [String: Bool] = [:]
    /// closeWindow のデフォルト戻り値
    var closeWindowDefaultResult = true
    /// 非同期のクローズ挙動（待機や割り込みテスト）を差し込む任意のフック
    var closeWindowHandler: ((WindowEntry) async -> Bool)?
    /// アプリケーション終了が要求された PID 履歴
    var terminatedPIDs: [Int32] = []
    /// PID ごとの terminateApplication スタブ結果（未指定時は terminateDefaultResult を使用）
    var stubbedTerminateResults: [Int32: Bool] = [:]
    /// terminateApplication のデフォルト戻り値
    var terminateDefaultResult = true
    /// 非同期のアプリ終了挙動を差し込む任意のフック
    var terminateHandler: ((Int32) async -> Bool)?

    /// 監視開始を記録する
    func startObserving() {
        startObservingCallCount += 1
    }

    /// 監視停止を記録する
    func stopObserving() {
        stopObservingCallCount += 1
    }

    /// スタブ設定されたウィンドウ候補一覧を返す
    /// - Returns: 生ウィンドウ候補の配列
    func fetchRawWindowCandidates() -> [RawWindowCandidate] {
        stubbedCandidates
    }

    /// 対象ウィンドウのアクティブ化要求を記録する
    /// - Parameter entry: アクティブ化対象ウィンドウ
    func activateWindow(_ entry: WindowEntry) {
        activatedWindows.append(entry)
    }

    /// 対象ウィンドウのクローズ要求を記録し、スタブ設定に応じた成否を返す
    /// - Parameter entry: クローズ対象ウィンドウ
    /// - Returns: スタブまたはハンドラが決定したクローズ成否
    func closeWindow(_ entry: WindowEntry) async -> Bool {
        closedWindows.append(entry)
        if let closeWindowHandler {
            return await closeWindowHandler(entry)
        }
        return stubbedCloseWindowResults[entry.id] ?? closeWindowDefaultResult
    }

    /// 対象アプリケーションの終了要求を記録し、スタブ設定に応じた成否を返す
    /// - Parameter pid: 終了対象プロセス ID
    /// - Returns: スタブまたはハンドラが決定した終了成否
    func terminateApplication(pid: Int32) async -> Bool {
        terminatedPIDs.append(pid)
        if let terminateHandler {
            return await terminateHandler(pid)
        }
        return stubbedTerminateResults[pid] ?? terminateDefaultResult
    }
}

/// テスト用のグローバルホットキー監視モック
@MainActor
final class MockHotKeyMonitor: HotKeyMonitoring {
    /// イベント通知クロージャ
    var onEvent: ((HotKeyEvent) -> Void)?
    /// システム無効化・権限剥奪等による監視中断通知クロージャ
    var onMonitoringInterrupted: (() -> Void)?
    /// 現在の監視モード
    var activeMode: HotKeyMonitorMode = .inactive {
        didSet {
            let nextIsActive = activeMode != .inactive
            if isSwitcherActive != nextIsActive {
                isSwitcherActive = nextIsActive
            }
        }
    }
    /// スイッチャー表示中フラグ
    var isSwitcherActive: Bool = false {
        didSet {
            let expectedMode: HotKeyMonitorMode = isSwitcherActive ? (activeMode == .inactive ? .normal : activeMode) : .inactive
            if activeMode != expectedMode {
                activeMode = expectedMode
            }
        }
    }
    /// ショートカット記録中のサスペンド状態
    var isSuspendedForRecording: Bool = false
    /// 更新された通常ショートカット設定履歴
    var updatedShortcuts: [ShortcutPreference] = []
    /// 更新されたランチャーショートカット設定履歴
    var updatedLauncherShortcuts: [LauncherShortcutPreference] = []
    /// 監視開始の戻り値スタブ
    var startMonitoringResult = true
    /// 監視中フラグ
    var isMonitoring = false

    /// 通常ショートカット設定更新を記録する
    /// - Parameter preference: 更新された設定
    func updateShortcut(_ preference: ShortcutPreference) {
        updatedShortcuts.append(preference)
    }

    /// ランチャーショートカット設定更新を記録する
    /// - Parameter preference: 更新されたランチャー設定
    func updateLauncherShortcut(_ preference: LauncherShortcutPreference) {
        updatedLauncherShortcuts.append(preference)
    }

    /// 監視開始を記録する
    /// - Returns: スタブ設定された結果
    @discardableResult
    func startMonitoring() -> Bool {
        isMonitoring = startMonitoringResult
        return startMonitoringResult
    }

    /// 監視停止を記録する
    func stopMonitoring() {
        isMonitoring = false
    }

    /// テストから擬似イベントを送信するヘルパー
    /// - Parameter event: 送信するイベント
    func simulateEvent(_ event: HotKeyEvent) {
        onEvent?(event)
    }

    /// テストから監視中断イベント（タップ無効化／権限剥奪）を擬似発火するヘルパー
    func simulateMonitoringInterrupted() {
        isMonitoring = false
        activeMode = .inactive
        onMonitoringInterrupted?()
    }
}

/// テスト用のアクセシビリティ権限サービスモック
@MainActor
final class MockAccessibilityPermissionService: AccessibilityPermissionServicing {
    /// 現在の権限状態スタブ
    var stubbedStatus: AccessibilityPermissionStatus = .granted
    /// 状態監視のコールバック
    var onChangeCallback: ((AccessibilityPermissionStatus) -> Void)?
    /// 設定画面を開いた回数
    var openSettingsCallCount = 0
    /// 監視中フラグ
    var isMonitoring = false

    /// 現在の権限状態を返す
    /// - Returns: スタブ設定された権限状態
    func currentStatus() -> AccessibilityPermissionStatus {
        stubbedStatus
    }

    /// 権限監視の開始を記録する
    /// - Parameter onChange: 権限変化時コールバック
    func startMonitoring(onChange: @escaping (AccessibilityPermissionStatus) -> Void) {
        isMonitoring = true
        onChangeCallback = onChange
    }

    /// 権限監視を停止する
    func stopMonitoring() {
        isMonitoring = false
        onChangeCallback = nil
    }

    /// システム設定を開く操作を記録する
    func openAccessibilitySettings() {
        openSettingsCallCount += 1
    }

    /// テストから権限状態の変更を通知するヘルパー
    /// - Parameter newStatus: 新しい権限状態
    func simulateStatusChange(_ newStatus: AccessibilityPermissionStatus) {
        stubbedStatus = newStatus
        onChangeCallback?(newStatus)
    }
}

/// テスト用の設定永続化ストアモック
final class MockPreferencesStore: PreferencesStoring, @unchecked Sendable {
    /// メモリ上に保持している通常ショートカット設定
    var storedShortcut: ShortcutPreference = .default
    /// メモリ上に保持しているランチャーショートカット設定
    var storedLauncherShortcut: LauncherShortcutPreference = .default
    /// メモリ上に保持している通常スイッチャーの表示形式設定
    var storedNormalDisplayStyle: SwitcherDisplayStyle = .default
    /// saveShortcut が呼ばれた回数
    var saveCallCount = 0
    /// saveLauncherShortcut が呼ばれた回数
    var saveLauncherCallCount = 0
    /// saveNormalDisplayStyle が呼ばれた回数
    var saveNormalDisplayStyleCallCount = 0

    /// メモリ上の通常ショートカット設定を読み込む
    /// - Returns: 保持している設定
    func loadShortcut() -> ShortcutPreference {
        storedShortcut
    }

    /// メモリ上の通常ショートカット設定を保存する
    /// - Parameter preference: 保存する設定
    func saveShortcut(_ preference: ShortcutPreference) {
        storedShortcut = preference
        saveCallCount += 1
    }

    /// メモリ上のランチャーショートカット設定を読み込む
    /// - Returns: 保持しているランチャー設定
    func loadLauncherShortcut() -> LauncherShortcutPreference {
        storedLauncherShortcut
    }

    /// メモリ上のランチャーショートカット設定を保存する
    /// - Parameter preference: 保存するランチャー設定
    func saveLauncherShortcut(_ preference: LauncherShortcutPreference) {
        storedLauncherShortcut = preference
        saveLauncherCallCount += 1
    }

    /// メモリ上の通常スイッチャー表示形式を読み込む
    /// - Returns: 保持している表示形式設定
    func loadNormalDisplayStyle() -> SwitcherDisplayStyle {
        storedNormalDisplayStyle
    }

    /// メモリ上の通常スイッチャー表示形式を保存する
    /// - Parameter style: 保存する表示形式設定
    func saveNormalDisplayStyle(_ style: SwitcherDisplayStyle) {
        storedNormalDisplayStyle = style
        saveNormalDisplayStyleCallCount += 1
    }
}

/// テスト用の画面収録権限サービスモック
@MainActor
final class MockScreenRecordingPermissionService: ScreenRecordingPermissionServicing {
    /// 返却する画面収録権限状態スタブ
    var stubbedStatus: ScreenRecordingPermissionStatus = .granted
    /// requestPermission() の戻り値スタブ（nil の場合は stubbedStatus == .granted）
    var requestPermissionResult: Bool?
    /// currentStatus が呼ばれた回数
    var currentStatusCallCount = 0
    /// requestPermission が呼ばれた回数
    var requestPermissionCallCount = 0
    /// openSystemSettings が呼ばれた回数
    var openSystemSettingsCallCount = 0

    /// 現在の画面収録権限状態を返す
    /// - Returns: スタブ設定された画面収録権限状態
    func currentStatus() -> ScreenRecordingPermissionStatus {
        currentStatusCallCount += 1
        return stubbedStatus
    }

    /// 画面収録権限リクエストを記録する
    /// - Returns: 設定されたスタブ結果
    @discardableResult
    func requestPermission() -> Bool {
        requestPermissionCallCount += 1
        if let requestPermissionResult {
            return requestPermissionResult
        }
        return stubbedStatus == .granted
    }

    /// システム設定遷移要求を記録する
    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}

/// テスト用のウィンドウキャプチャサービスモック
@MainActor
final class MockWindowCaptureService: WindowCaptureServicing {
    /// メモリキャッシュとして返却するサムネイルマップ
    var cachedThumbnails: [UInt32: NSImage] = [:]
    /// 非同期取得時に返却・差し込みを行うスタブサムネイルマップ
    var stubbedAsyncThumbnails: [UInt32: NSImage] = [:]
    /// captureThumbnails の非同期挙動を差し込む任意フック
    var captureHandler: (([UInt32], @escaping @MainActor (UInt32, NSImage) -> Void) async -> Void)?
    /// captureThumbnails が呼ばれた際の引数履歴
    var capturedRequestWindowIDs: [[UInt32]] = []
    /// invalidateThumbnail が呼ばれたウィンドウ ID 履歴
    var invalidatedWindowIDs: [UInt32] = []
    /// clearCache が呼ばれた回数
    var clearCacheCallCount = 0

    /// キャッシュ済みサムネイルを返す
    /// - Parameter cgWindowID: CoreGraphics ウィンドウ ID
    /// - Returns: キャッシュにあれば画像、なければ nil
    func cachedThumbnail(for cgWindowID: UInt32) -> NSImage? {
        cachedThumbnails[cgWindowID]
    }

    /// 非同期キャプチャ取得を実行し、完了ごとにコールバックとキャッシュ更新を行う
    /// - Parameters:
    ///   - cgWindowIDs: 取得対象のウィンドウ ID 配列
    ///   - maxPixelSize: 上限ピクセルサイズ
    ///   - onCaptured: 取得完了コールバック
    func captureThumbnails(
        for cgWindowIDs: [UInt32],
        maxPixelSize: CGSize,
        onCaptured: @escaping @MainActor (UInt32, NSImage) -> Void
    ) async {
        capturedRequestWindowIDs.append(cgWindowIDs)
        if let captureHandler {
            await captureHandler(cgWindowIDs) { [weak self] windowID, image in
                self?.cachedThumbnails[windowID] = image
                onCaptured(windowID, image)
            }
            return
        }
        for windowID in cgWindowIDs {
            if Task.isCancelled { break }
            if let image = stubbedAsyncThumbnails[windowID] {
                cachedThumbnails[windowID] = image
                onCaptured(windowID, image)
            }
        }
    }

    /// 指定ウィンドウのキャッシュを削除する
    /// - Parameter cgWindowID: 削除対象のウィンドウ ID
    func invalidateThumbnail(for cgWindowID: UInt32) {
        invalidatedWindowIDs.append(cgWindowID)
        cachedThumbnails.removeValue(forKey: cgWindowID)
    }

    /// 全キャッシュを破棄する
    func clearCache() {
        clearCacheCallCount += 1
        cachedThumbnails.removeAll()
    }
}

/// テスト用のログイン時自動起動サービスモック
@MainActor
final class MockLaunchAtLoginService: LaunchAtLoginServicing {
    /// 自動起動状態スタブ
    var isEnabled: Bool = false
    /// setEnabled 時にスローするエラー（設定された場合）
    var errorToThrow: Error?

    /// 自動起動の有効・無効を切り替える
    /// - Parameter enabled: 有効にする場合は true
    func setEnabled(_ enabled: Bool) throws {
        if let errorToThrow {
            throw errorToThrow
        }
        isEnabled = enabled
    }
}

/// テスト用のアイコンプロバイダモック
@MainActor
final class MockIconProvider: IconProviding {
    /// PID ごとに返却するアイコンマップ
    var stubbedIcons: [Int32: NSImage] = [:]
    /// アプリ URL ごとに返却するアイコンマップ
    var stubbedAppIcons: [URL: NSImage] = [:]

    /// PID に対応するスタブアイコンを返す
    /// - Parameter pid: プロセス ID
    /// - Returns: 設定されていれば画像、なければ nil
    func icon(for pid: Int32) -> NSImage? {
        stubbedIcons[pid]
    }

    /// アプリバンドル URL に対応するスタブアイコンを返す
    /// - Parameter url: アプリケーションバンドルの URL
    /// - Returns: 設定されていれば画像、なければ nil
    func icon(forAppURL url: URL) -> NSImage? {
        stubbedAppIcons[url.standardizedFileURL]
    }
}

/// テスト用のインストール済みアプリ取得・起動サービスモック
@MainActor
final class MockInstalledAppService: InstalledAppServicing {
    /// キャッシュ済みとして返却する起動可能アプリ配列
    var stubbedApps: [LaunchableApp] = []
    /// refreshInstalledApps 実行時に返すアプリ配列（nil の場合は stubbedApps を返す）
    var refreshedApps: [LaunchableApp]?
    /// 非同期リフレッシュの待機や差し込みを行う任意のフック
    var refreshHandler: (() async -> [LaunchableApp])?
    /// refreshInstalledApps が呼ばれた回数
    var refreshCallCount = 0
    /// launchApplication で起動が要求されたアプリ履歴
    var launchedApps: [LaunchableApp] = []

    /// スタブ設定されたキャッシュ済みアプリ一覧を返す
    /// - Returns: 起動可能アプリの配列
    func cachedInstalledApps() -> [LaunchableApp] {
        stubbedApps
    }

    /// 非同期リフレッシュを実行し、更新後のアプリ一覧をキャッシュおよび返却する
    /// - Returns: 更新後の起動可能アプリ配列
    @discardableResult
    func refreshInstalledApps() async -> [LaunchableApp] {
        refreshCallCount += 1
        let next: [LaunchableApp]
        if let refreshHandler {
            next = await refreshHandler()
        } else {
            next = refreshedApps ?? stubbedApps
        }
        stubbedApps = next
        return next
    }

    /// アプリケーション起動要求を記録する
    /// - Parameter app: 起動対象のアプリケーション情報
    func launchApplication(_ app: LaunchableApp) {
        launchedApps.append(app)
    }
}
