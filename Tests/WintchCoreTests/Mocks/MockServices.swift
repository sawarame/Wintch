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
}

/// テスト用のグローバルホットキー監視モック
@MainActor
final class MockHotKeyMonitor: HotKeyMonitoring {
    /// イベント通知クロージャ
    var onEvent: ((HotKeyEvent) -> Void)?
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
    /// saveShortcut が呼ばれた回数
    var saveCallCount = 0
    /// saveLauncherShortcut が呼ばれた回数
    var saveLauncherCallCount = 0

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
    /// 返却するアイコンマップ
    var stubbedIcons: [Int32: NSImage] = [:]

    /// PID に対応するスタブアイコンを返す
    /// - Parameter pid: プロセス ID
    /// - Returns: 設定されていれば画像、なければ nil
    func icon(for pid: Int32) -> NSImage? {
        stubbedIcons[pid]
    }
}
