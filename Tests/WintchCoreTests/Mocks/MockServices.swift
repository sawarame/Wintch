import AppKit
import Foundation
@testable import WintchCore

/// テスト内で現在時刻を任意のステップで進めるためのスレッドセーフな可変クロック
final class MutableTestClock: @unchecked Sendable {
    /// 現在のテスト時刻
    private var current: Date
    /// 排他制御ロック
    private let lock = NSLock()

    /// 初期時刻を指定してテストクロックを初期化する
    /// - Parameter initial: 初期時刻
    init(initial: Date) {
        self.current = initial
    }

    /// 現在のテスト時刻を返す
    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// 現在時刻を指定秒数だけ進める
    /// - Parameter interval: 進める秒数
    func advance(by interval: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(interval)
        lock.unlock()
    }

    /// 現在時刻を指定時刻へ直接設定する
    /// - Parameter date: 設定する時刻
    func set(_ date: Date) {
        lock.lock()
        current = date
        lock.unlock()
    }
}

/// テスト用のウィンドウサービスモック
@MainActor
final class MockWindowService: WindowServicing {
    /// OS 通知を模擬したリアルタイムライフサイクルイベント通知ハンドラ
    var onWindowLifecycleEvent: ((WindowLifecycleEvent) -> Void)?
    /// OS 通知を模擬したバックグラウンド事前キャプチャ契機通知ハンドラ
    var onCapturePrefetchNeeded: ((WindowCapturePrefetchReason) -> Void)?
    /// OS 通知を模擬したスリープ／ディスプレイオフ／セッション状態変化通知ハンドラ
    var onSystemCaptureAvailabilityEvent: ((SystemCaptureAvailabilityEvent) -> Void)?
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
    /// ウィンドウ ID ごとの closeWindow スタブ結果（互換用：true は即時完了、false は送出失敗）
    var stubbedCloseWindowResults: [String: Bool] = [:]
    /// closeWindow のデフォルト戻り値（互換用）
    var closeWindowDefaultResult = true
    /// 非同期のクローズ挙動（互換用：true は即時完了、false は送出失敗）
    var closeWindowHandler: ((WindowEntry) async -> Bool)?
    /// ウィンドウ ID ごとの終了要求フェーズ結果スタブ（優先適用）
    var stubbedCloseWindowRequestResults: [String: WindowCloseRequestResult] = [:]
    /// 終了要求フェーズのデフォルト戻り値（指定時は互換プロパティより優先）
    var closeWindowDefaultRequestResult: WindowCloseRequestResult?
    /// 終了要求フェーズのカスタム非同期フック（優先適用）
    var requestCloseWindowHandler: ((WindowEntry) async -> WindowCloseRequestResult)?
    /// アプリケーション終了が要求された PID 履歴
    var terminatedPIDs: [Int32] = []
    /// PID ごとの terminateApplication スタブ結果（互換用：true は即時完了、false は送出失敗）
    var stubbedTerminateResults: [Int32: Bool] = [:]
    /// terminateApplication のデフォルト戻り値（互換用）
    var terminateDefaultResult = true
    /// 非同期のアプリ終了挙動（互換用：true は即時完了、false は送出失敗）
    var terminateHandler: ((Int32) async -> Bool)?
    /// PID ごとのアプリ終了要求フェーズ結果スタブ（優先適用）
    var stubbedTerminateRequestResults: [Int32: WindowCloseRequestResult] = [:]
    /// アプリ終了要求フェーズのデフォルト戻り値（指定時は互換プロパティより優先）
    var terminateDefaultRequestResult: WindowCloseRequestResult?
    /// アプリ終了要求フェーズのカスタム非同期フック（優先適用）
    var requestTerminateHandler: ((Int32) async -> WindowCloseRequestResult)?
    /// 生存中として扱うウィンドウ ID 集合（nil の場合は常に生存扱い）
    var aliveWindowIDs: Set<String>?
    /// フォールバック生存確認（isWindowAlive）のカスタム非同期フック
    var isWindowAliveHandler: ((WindowEntry) async -> Bool)?
    /// 稼働中として扱うアプリケーション PID 集合（nil の場合は常に稼働扱い）
    var runningApplicationPIDs: Set<Int32>?
    /// フォールバック生存確認（isApplicationRunning）のカスタム非同期フック
    var isApplicationRunningHandler: ((Int32) async -> Bool)?
    /// isWindowAlive が呼ばれた回数
    var isWindowAliveCallCount = 0
    /// isApplicationRunning が呼ばれた回数
    var isApplicationRunningCallCount = 0

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

    /// 対象ウィンドウのクローズ要求を記録し、スタブ設定に応じた要求フェーズ結果を返す
    /// - Parameter entry: クローズ対象ウィンドウ
    /// - Returns: スタブまたはハンドラが決定した要求フェーズ結果
    func requestCloseWindow(_ entry: WindowEntry) async -> WindowCloseRequestResult {
        closedWindows.append(entry)
        if let requestCloseWindowHandler {
            return await requestCloseWindowHandler(entry)
        }
        if let closeWindowHandler {
            let succeeded = await closeWindowHandler(entry)
            return succeeded ? .alreadyClosed() : .failed()
        }
        if let result = stubbedCloseWindowRequestResults[entry.id] {
            return result
        }
        if let boolResult = stubbedCloseWindowResults[entry.id] {
            return boolResult ? .alreadyClosed() : .failed()
        }
        if let closeWindowDefaultRequestResult {
            return closeWindowDefaultRequestResult
        }
        return closeWindowDefaultResult ? .alreadyClosed() : .failed()
    }

    /// 対象アプリケーションの終了要求を記録し、スタブ設定に応じた要求フェーズ結果を返す
    /// - Parameter pid: 終了対象プロセス ID
    /// - Returns: スタブまたはハンドラが決定した要求フェーズ結果
    func requestTerminateApplication(pid: Int32) async -> WindowCloseRequestResult {
        terminatedPIDs.append(pid)
        if let requestTerminateHandler {
            return await requestTerminateHandler(pid)
        }
        if let terminateHandler {
            let succeeded = await terminateHandler(pid)
            return succeeded ? .alreadyClosed() : .failed()
        }
        if let result = stubbedTerminateRequestResults[pid] {
            return result
        }
        if let boolResult = stubbedTerminateResults[pid] {
            return boolResult ? .alreadyClosed() : .failed()
        }
        if let terminateDefaultRequestResult {
            return terminateDefaultRequestResult
        }
        return terminateDefaultResult ? .alreadyClosed() : .failed()
    }

    /// 指定ウィンドウが現在も生存しているかをスタブ設定に従って返す
    /// - Parameter entry: 確認対象のウィンドウ項目
    /// - Returns: 生存している場合は true
    func isWindowAlive(_ entry: WindowEntry) async -> Bool {
        isWindowAliveCallCount += 1
        if let isWindowAliveHandler {
            return await isWindowAliveHandler(entry)
        }
        if let aliveWindowIDs {
            return aliveWindowIDs.contains(entry.id)
        }
        return true
    }

    /// 指定アプリケーションが現在も稼働中かをスタブ設定に従って返す
    /// - Parameter pid: 確認対象のプロセス ID
    /// - Returns: 稼働中の場合は true
    func isApplicationRunning(pid: Int32) async -> Bool {
        isApplicationRunningCallCount += 1
        if let isApplicationRunningHandler {
            return await isApplicationRunningHandler(pid)
        }
        if let runningApplicationPIDs {
            return runningApplicationPIDs.contains(pid)
        }
        return true
    }

    /// テストから個別ウィンドウ破棄のリアルタイム通知を模擬発火する
    /// - Parameters:
    ///   - windowID: 破棄されたウィンドウ ID
    ///   - cgWindowID: 紐付いていた CoreGraphics ウィンドウ ID（任意）
    ///   - pid: 所有プロセスの PID
    func simulateWindowClosed(windowID: String, cgWindowID: UInt32? = nil, pid: Int32) {
        onWindowLifecycleEvent?(.windowClosed(windowID: windowID, cgWindowID: cgWindowID, pid: pid))
    }

    /// テストからアプリケーション終了のリアルタイム通知を模擬発火する
    /// - Parameter pid: 終了したプロセスの PID
    func simulateApplicationTerminated(pid: Int32) {
        onWindowLifecycleEvent?(.applicationTerminated(pid: pid))
    }

    /// テストからバックグラウンド事前キャプチャ契機通知を模擬発火する
    /// - Parameter reason: 模擬発火する契機種別
    func simulateCapturePrefetchNeeded(_ reason: WindowCapturePrefetchReason) {
        onCapturePrefetchNeeded?(reason)
    }

    /// テストからスリープ／ディスプレイオフ／セッション状態変化通知を模擬発火する
    /// - Parameter event: 模擬発火するシステム状態変化イベント
    func simulateSystemCaptureAvailabilityEvent(_ event: SystemCaptureAvailabilityEvent) {
        onSystemCaptureAvailabilityEvent?(event)
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
    /// 通常スイッチャー表示時の一時アクティブ化要求フラグ
    var requiresAppActivationOnPresentation: Bool = false
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
    /// メモリ上に保持している検索ランチャーの表示形式設定
    var storedLauncherDisplayStyle: LauncherDisplayStyle = .default
    /// メモリ上に保持している通常スイッチャーのアプリグルーピング設定
    var storedGroupNormalSwitcherByApp: Bool = true
    /// メモリ上に保持している検索ランチャーのアプリグルーピング設定
    var storedGroupLauncherByApp: Bool = true
    /// メモリ上に保持しているアプリ表示言語設定
    var storedAppLanguage: AppLanguage = .default
    /// メモリ上に保持しているバージョンアップ自動チェック設定
    var storedAutoCheckForUpdates: Bool = false
    /// メモリ上に保持しているスキップ対象バージョン
    var storedSkippedUpdateVersion: String? = nil
    /// saveShortcut が呼ばれた回数
    var saveCallCount = 0
    /// saveLauncherShortcut が呼ばれた回数
    var saveLauncherCallCount = 0
    /// saveNormalDisplayStyle が呼ばれた回数
    var saveNormalDisplayStyleCallCount = 0
    /// saveLauncherDisplayStyle が呼ばれた回数
    var saveLauncherDisplayStyleCallCount = 0
    /// saveGroupNormalSwitcherByApp が呼ばれた回数
    var saveGroupNormalSwitcherByAppCallCount = 0
    /// saveGroupLauncherByApp が呼ばれた回数
    var saveGroupLauncherByAppCallCount = 0
    /// saveAppLanguage が呼ばれた回数
    var saveAppLanguageCallCount = 0
    /// saveAutoCheckForUpdates が呼ばれた回数
    var saveAutoCheckForUpdatesCallCount = 0
    /// saveSkippedUpdateVersion が呼ばれた回数
    var saveSkippedUpdateVersionCallCount = 0

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

    /// メモリ上の検索ランチャー表示形式を読み込む
    /// - Returns: 保持している検索ランチャー表示形式設定
    func loadLauncherDisplayStyle() -> LauncherDisplayStyle {
        storedLauncherDisplayStyle
    }

    /// メモリ上の検索ランチャー表示形式を保存する
    /// - Parameter style: 保存する検索ランチャー表示形式設定
    func saveLauncherDisplayStyle(_ style: LauncherDisplayStyle) {
        storedLauncherDisplayStyle = style
        saveLauncherDisplayStyleCallCount += 1
    }

    /// メモリ上の通常スイッチャーのアプリグルーピング設定を読み込む
    /// - Returns: 保持している設定値
    func loadGroupNormalSwitcherByApp() -> Bool {
        storedGroupNormalSwitcherByApp
    }

    /// メモリ上の通常スイッチャーのアプリグルーピング設定を保存する
    /// - Parameter enabled: 保存する設定値
    func saveGroupNormalSwitcherByApp(_ enabled: Bool) {
        storedGroupNormalSwitcherByApp = enabled
        saveGroupNormalSwitcherByAppCallCount += 1
    }

    /// メモリ上の検索ランチャーのアプリグルーピング設定を読み込む
    /// - Returns: 保持している設定値
    func loadGroupLauncherByApp() -> Bool {
        storedGroupLauncherByApp
    }

    /// メモリ上の検索ランチャーのアプリグルーピング設定を保存する
    /// - Parameter enabled: 保存する設定値
    func saveGroupLauncherByApp(_ enabled: Bool) {
        storedGroupLauncherByApp = enabled
        saveGroupLauncherByAppCallCount += 1
    }

    /// メモリ上のアプリ表示言語設定を読み込む
    /// - Returns: 保持している言語設定
    func loadAppLanguage() -> AppLanguage {
        storedAppLanguage
    }

    /// メモリ上のアプリ表示言語設定を保存する
    /// - Parameter language: 保存する言語設定
    func saveAppLanguage(_ language: AppLanguage) {
        storedAppLanguage = language
        saveAppLanguageCallCount += 1
    }

    /// メモリ上のバージョンアップ自動チェック設定を読み込む
    /// - Returns: 保持している設定値
    func loadAutoCheckForUpdates() -> Bool {
        storedAutoCheckForUpdates
    }

    /// メモリ上のバージョンアップ自動チェック設定を保存する
    /// - Parameter enabled: 保存する設定値
    func saveAutoCheckForUpdates(_ enabled: Bool) {
        storedAutoCheckForUpdates = enabled
        saveAutoCheckForUpdatesCallCount += 1
    }

    /// メモリ上のスキップ対象バージョンを読み込む
    /// - Returns: 保持しているバージョン文字列
    func loadSkippedUpdateVersion() -> String? {
        storedSkippedUpdateVersion
    }

    /// メモリ上のスキップ対象バージョンを保存する
    /// - Parameter version: 保存するバージョン文字列
    func saveSkippedUpdateVersion(_ version: String?) {
        let trimmed = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        storedSkippedUpdateVersion = trimmed.isEmpty ? nil : trimmed
        saveSkippedUpdateVersionCallCount += 1
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
    /// markAccessRevoked が呼ばれた回数
    var markAccessRevokedCallCount = 0

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

    /// セッション内の画面収録権限失効を記録し、以降のステータスを未許可へ切り替える
    func markAccessRevoked() {
        markAccessRevokedCallCount += 1
        stubbedStatus = .denied
    }
}

/// テスト用のウィンドウキャプチャサービスモック
@MainActor
final class MockWindowCaptureService: WindowCaptureServicing {
    /// メモリキャッシュとして返却するサムネイルマップ
    var cachedThumbnails: [UInt32: NSImage] = [:]
    /// キャッシュ済みサムネイルごとの最終取得時刻マップ
    var cachedThumbnailTimestamps: [UInt32: Date] = [:]
    /// キャプチャ格納時にタイムスタンプを記録するための現在時刻プロバイダ
    var nowProvider: @Sendable () -> Date = Date.init
    /// 非同期取得時に返却・差し込みを行うスタブサムネイルマップ
    var stubbedAsyncThumbnails: [UInt32: NSImage] = [:]
    /// captureThumbnails の非同期挙動を差し込む任意フック
    var captureHandler: (([UInt32], @escaping @MainActor (UInt32, NSImage) -> Void) async -> Void)?
    /// captureThumbnails が呼ばれた際の引数履歴
    var capturedRequestWindowIDs: [[UInt32]] = []
    /// invalidateThumbnail が呼ばれたウィンドウ ID 履歴
    var invalidatedWindowIDs: [UInt32] = []
    /// pruneCache(keeping:) が呼ばれた際の保持対象ウィンドウ ID 集合履歴
    var prunedKeepingWindowIDsHistory: [Set<UInt32>] = []
    /// cachedThumbnail(for:) が呼ばれたウィンドウ ID の呼び出し順履歴
    var cachedThumbnailLookupOrder: [UInt32] = []
    /// clearCache が呼ばれた回数
    var clearCacheCallCount = 0

    /// キャッシュ済みサムネイルを返す
    /// - Parameter cgWindowID: CoreGraphics ウィンドウ ID
    /// - Returns: キャッシュにあれば画像、なければ nil
    func cachedThumbnail(for cgWindowID: UInt32) -> NSImage? {
        cachedThumbnailLookupOrder.append(cgWindowID)
        return cachedThumbnails[cgWindowID]
    }

    /// 指定ウィンドウのサムネイルがキャッシュ済みかを副作用なしで確認する
    /// - Parameter cgWindowID: CoreGraphics ウィンドウ ID
    /// - Returns: キャッシュに保持されていれば true
    func hasCachedThumbnail(for cgWindowID: UInt32) -> Bool {
        cachedThumbnails[cgWindowID] != nil
    }

    /// 指定ウィンドウのサムネイル最終取得時刻を副作用なしで返す
    /// - Parameter cgWindowID: CoreGraphics ウィンドウ ID
    /// - Returns: 記録されていれば最終取得時刻、未保持時は nil
    func lastCapturedAt(for cgWindowID: UInt32) -> Date? {
        guard cachedThumbnails[cgWindowID] != nil else { return nil }
        return cachedThumbnailTimestamps[cgWindowID]
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
                guard let self else { return }
                self.cachedThumbnails[windowID] = image
                self.cachedThumbnailTimestamps[windowID] = self.nowProvider()
                onCaptured(windowID, image)
            }
            return
        }
        for windowID in cgWindowIDs {
            if Task.isCancelled { break }
            if let image = stubbedAsyncThumbnails[windowID] {
                cachedThumbnails[windowID] = image
                cachedThumbnailTimestamps[windowID] = nowProvider()
                onCaptured(windowID, image)
            }
        }
    }

    /// 指定ウィンドウのキャッシュを削除する
    /// - Parameter cgWindowID: 削除対象のウィンドウ ID
    func invalidateThumbnail(for cgWindowID: UInt32) {
        invalidatedWindowIDs.append(cgWindowID)
        cachedThumbnails.removeValue(forKey: cgWindowID)
        cachedThumbnailTimestamps.removeValue(forKey: cgWindowID)
    }

    /// 現在生存しているウィンドウ ID 集合に含まれないキャッシュを破棄する
    /// - Parameter activeCGWindowIDs: 保持を継続するウィンドウ ID 集合
    func pruneCache(keeping activeCGWindowIDs: Set<UInt32>) {
        prunedKeepingWindowIDsHistory.append(activeCGWindowIDs)
        for key in Array(cachedThumbnails.keys) where !activeCGWindowIDs.contains(key) {
            cachedThumbnails.removeValue(forKey: key)
            cachedThumbnailTimestamps.removeValue(forKey: key)
        }
        for key in Array(cachedThumbnailTimestamps.keys) where !activeCGWindowIDs.contains(key) {
            cachedThumbnailTimestamps.removeValue(forKey: key)
        }
    }

    /// 全キャッシュを破棄する
    func clearCache() {
        clearCacheCallCount += 1
        cachedThumbnails.removeAll()
        cachedThumbnailTimestamps.removeAll()
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

/// テスト用の標準ウィンドウ最前面表示プレゼンターモック
@MainActor
final class MockWindowFrontPresenter: WindowFrontPresenting {
    /// presentFrontmost に渡されたウィンドウの履歴
    var presentedWindows: [NSWindow] = []

    /// 指定ウィンドウを最前面表示対象として記録する
    /// - Parameter window: 表示対象の NSWindow
    func presentFrontmost(_ window: NSWindow) {
        presentedWindows.append(window)
    }
}

/// テスト用のアプリアップデートサービスモック
final class MockAppUpdateService: AppUpdateServicing, @unchecked Sendable {
    /// fetchLatestStableRelease の返却結果スタブ
    var stubbedReleaseResult: Result<AppReleaseInfo, Error> = .failure(AppUpdateError.noStableRelease)
    /// fetchLatestStableRelease のカスタム非同期ハンドラ
    var fetchHandler: (() async throws -> AppReleaseInfo)?
    /// evaluateInstallEligibility の返却スタブ
    var stubbedEligibility: UpdateInstallEligibility = .eligible
    /// downloadVerifyAndScheduleInstall のカスタム非同期ハンドラ
    var installHandler: ((AppReleaseInfo, @escaping @Sendable (UpdateProgressPhase) -> Void) async throws -> Void)?
    /// fetchLatestStableRelease が呼ばれた回数
    var fetchCallCount = 0
    /// downloadVerifyAndScheduleInstall が呼ばれた回数
    var installCallCount = 0
    /// openReleasePage で開かれた URL 履歴
    var openedURLs: [URL] = []

    /// スタブまたはハンドラに従って最新安定版リリース情報を返す
    /// - Returns: スタブ設定されたリリース情報
    func fetchLatestStableRelease() async throws -> AppReleaseInfo {
        fetchCallCount += 1
        if let fetchHandler {
            return try await fetchHandler()
        }
        return try stubbedReleaseResult.get()
    }

    /// スタブ設定された差し替え可否を返す
    /// - Parameters:
    ///   - appIdentity: 実行中アプリ識別情報
    ///   - versionInfo: 実行中アプリバージョン情報
    /// - Returns: スタブ設定された差し替え可否
    func evaluateInstallEligibility(
        appIdentity: AppIdentity,
        versionInfo: AppVersionInfo
    ) -> UpdateInstallEligibility {
        stubbedEligibility
    }

    /// アップデート実行要求を記録し、ハンドラまたは進捗シミュレーションを実行する
    /// - Parameters:
    ///   - release: 適用対象リリース
    ///   - appIdentity: 実行中アプリ識別情報
    ///   - versionInfo: 実行中アプリバージョン情報
    ///   - onProgress: 進捗通知コールバック
    func downloadVerifyAndScheduleInstall(
        release: AppReleaseInfo,
        appIdentity: AppIdentity,
        versionInfo: AppVersionInfo,
        onProgress: @escaping @Sendable (UpdateProgressPhase) -> Void
    ) async throws {
        installCallCount += 1
        if let installHandler {
            try await installHandler(release, onProgress)
            return
        }
        onProgress(.downloading(fractionCompleted: 0.5))
        onProgress(.extracting)
        onProgress(.verifying)
        onProgress(.installing)
    }

    /// ブラウザ誘導先 URL を記録する
    /// - Parameter url: 開く対象 URL
    func openReleasePage(url: URL) {
        openedURLs.append(url)
    }
}
