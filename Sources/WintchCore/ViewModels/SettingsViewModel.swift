import Foundation
import Observation

/// ショートカット設定のエラー発生元セクション
public enum ShortcutValidationTarget: Equatable, Sendable {
    /// 通常スイッチャー設定
    case normal
    /// 検索ランチャー設定
    case launcher
}

/// 設定画面からの手動アップデート確認状態
public enum ManualUpdateCheckState: Equatable, Sendable {
    /// 未実行または初期状態
    case idle
    /// GitHub Releases へ問い合わせ中
    case checking
    /// 現在が最新安定版
    case upToDate
    /// 新しい安定版を検出
    case updateAvailable(SemanticVersion)
    /// ローカル開発版のため自動更新対象外であることを案内
    case developmentBuild(latestRelease: AppReleaseInfo?)
    /// 通信・解析エラー
    case failed(AppUpdateError)
}

/// 設定画面の状態管理（選択中メニュー、通常/ランチャーショートカット、記録状態、表示形式、自動起動、権限ステータス）を行う ViewModel
@MainActor
@Observable
public final class SettingsViewModel {
    /// サイドバーで現在選択中のメニュー（アプリ起動時は「一般」、ウィンドウ再オープン時は前回値を維持）
    public private(set) var selectedTab: SettingsTab = .general

    /// 現在の通常スイッチャー用ショートカット設定
    public private(set) var shortcut: ShortcutPreference

    /// 現在の検索ランチャー用ショートカット設定
    public private(set) var launcherShortcut: LauncherShortcutPreference

    /// 通常スイッチャーのショートカットレコーダーがキー入力待機中かどうか
    public private(set) var isRecordingNormalShortcut: Bool = false

    /// ランチャーショートカットレコーダーがキー入力待機中かどうか
    public private(set) var isRecordingLauncherShortcut: Bool = false

    /// 現在のアプリ表示言語設定（システム設定追従または 5 言語）
    public private(set) var appLanguage: AppLanguage

    /// 現在の UI 描画に適用されている解決済み言語
    public private(set) var resolvedLanguage: ResolvedAppLanguage

    /// 現在の解決済み言語に対応するローカライズ文言テーブル
    public var strings: AppStrings {
        AppStrings(language: resolvedLanguage)
    }

    /// ショートカットの妥当性検証または重複チェックのエラーメッセージ（現在の表示言語で動的に生成）
    public var shortcutValidationError: String? {
        shortcutValidationFailure?.message(in: resolvedLanguage)
    }

    /// エラーを表示すべきセクション対象
    public private(set) var shortcutValidationTarget: ShortcutValidationTarget?

    /// ログイン時自動起動の有効状態
    public private(set) var isLaunchAtLoginEnabled: Bool

    /// 起動時のバージョンアップ自動チェック有効状態（初期値: false / オプトイン）
    public private(set) var isAutoCheckForUpdatesEnabled: Bool

    /// 設定画面「アプリ情報」からの手動アップデート確認状態
    public private(set) var manualUpdateCheckState: ManualUpdateCheckState = .idle

    /// 手動アップデート確認が現在進行中かどうか
    public var isCheckingForUpdates: Bool {
        manualUpdateCheckState == .checking
    }

    /// 手動アップデート確認の結果メッセージ（現在の表示言語で動的に生成）
    public var manualUpdateStatusMessage: String? {
        switch manualUpdateCheckState {
        case .idle, .checking:
            return nil
        case .upToDate:
            return strings.settingsUpToDateMessage
        case let .updateAvailable(version):
            return strings.settingsUpdateAvailableMessage(version: version.normalizedString)
        case let .developmentBuild(latestRelease):
            return strings.updateDevelopmentBuildNotice(latestVersion: latestRelease?.version.normalizedString)
        case let .failed(error):
            return error.localizedMessage(in: resolvedLanguage)
        }
    }

    /// 手動確認時に GitHub Releases への誘導ボタンを表示すべきかどうか
    public var shouldShowOpenReleasesLink: Bool {
        switch manualUpdateCheckState {
        case .developmentBuild, .failed:
            return true
        case .idle, .checking, .upToDate, .updateAvailable:
            return false
        }
    }

    /// 手動確認結果に対応する GitHub リリース URL（未特定時は Releases 一覧）
    public var manualUpdateReleaseURL: URL {
        if case let .developmentBuild(latestRelease) = manualUpdateCheckState,
           let releaseURL = latestRelease?.releaseURL {
            return releaseURL
        }
        return GitHubReleaseParser.releasesPageURL
    }

    /// 自動起動設定の更新に失敗した場合のエラーメッセージ（現在の表示言語で動的に生成）
    public var launchAtLoginError: String? {
        launchAtLoginErrorDetail.map { strings.launchAtLoginError(detail: $0) }
    }

    /// 現在のアクセシビリティ権限状態
    public private(set) var permissionStatus: AccessibilityPermissionStatus

    /// 通常スイッチャーの表示形式設定（リスト型／アイコン型／キャプチャ表示型）
    public private(set) var normalDisplayStyle: SwitcherDisplayStyle

    /// 検索ランチャーの表示形式設定（リスト型／キャプチャ表示型）
    public private(set) var launcherDisplayStyle: LauncherDisplayStyle

    /// 通常スイッチャーでウィンドウをアプリごとにグルーピングするかどうか（初期値: true）
    public private(set) var isNormalSwitcherGroupedByApp: Bool

    /// 検索ランチャーでウィンドウをアプリごとにグルーピングするかどうか（初期値: true）
    public private(set) var isLauncherGroupedByApp: Bool

    /// スイッチャー・ランチャー共通のウィンドウタイトル省略位置設定（初期値: .middle）
    public private(set) var windowTitleTruncationMode: WindowTitleTruncationMode

    /// 画面収録権限状態（通常スイッチャーまたは検索ランチャーのいずれかでキャプチャ表示型が選択されている場合のみ確認対象となる）
    public private(set) var screenRecordingStatus: ScreenRecordingPermissionStatus = .denied

    /// 通常スイッチャーまたは検索ランチャーのいずれかでキャプチャ表示型が選択されているか
    public var usesCaptureDisplayStyle: Bool {
        normalDisplayStyle == .capture || launcherDisplayStyle == .capture
    }

    /// 通常スイッチャーの表示形式が変更された際に上位コーディネーターへ通知するコールバック
    public var onNormalDisplayStyleChanged: ((SwitcherDisplayStyle) -> Void)?

    /// 検索ランチャーの表示形式が変更された際に上位コーディネーターへ通知するコールバック
    public var onLauncherDisplayStyleChanged: ((LauncherDisplayStyle) -> Void)?

    /// 通常スイッチャーのアプリグルーピング設定が変更された際に上位コーディネーターへ通知するコールバック
    public var onNormalSwitcherGroupingChanged: ((Bool) -> Void)?

    /// 検索ランチャーのアプリグルーピング設定が変更された際に上位コーディネーターへ通知するコールバック
    public var onLauncherGroupingChanged: ((Bool) -> Void)?

    /// ウィンドウタイトルの省略位置設定が変更された際に上位コーディネーターへ通知するコールバック
    public var onWindowTitleTruncationModeChanged: ((WindowTitleTruncationMode) -> Void)?

    /// アプリ表示言語設定が変更された際に上位コーディネーターへ通知するコールバック
    public var onAppLanguageChanged: ((AppLanguage, ResolvedAppLanguage) -> Void)?

    /// バージョンアップ自動チェック設定が変更された際に上位コーディネーターへ通知するコールバック
    public var onAutoCheckForUpdatesChanged: ((Bool) -> Void)?

    /// 手動確認で新しい安定版を検出した際に更新ダイアログ表示を要求するコールバック
    public var onUpdateAvailable: ((AppReleaseInfo, SemanticVersion) -> Void)?

    /// 設定永続化ストア
    private let preferencesStore: any PreferencesStoring
    /// グローバルホットキー監視サービス
    private let hotKeyMonitor: any HotKeyMonitoring
    /// ログイン時自動起動管理サービス
    private let launchAtLoginService: any LaunchAtLoginServicing
    /// アクセシビリティ権限管理サービス
    private let permissionService: any AccessibilityPermissionServicing
    /// 画面収録権限管理サービス（キャプチャ表示型選択時のみ使用）
    private let screenRecordingPermissionService: (any ScreenRecordingPermissionServicing)?
    /// アップデート確認・誘導サービス
    private let updateService: any AppUpdateServicing
    /// 実行中アプリの識別情報
    private let appIdentity: AppIdentity
    /// 実行中アプリのバージョン情報
    private let versionInfo: AppVersionInfo
    /// システム優先言語リストの取得クロージャ（テスト時に任意の言語配列を注入可能）
    private let preferredLanguagesProvider: @Sendable () -> [String]
    /// 現在のショートカット検証失敗理由（言語切替時に現在言語へ再評価するため構造化保持する）
    private var shortcutValidationFailure: ShortcutValidationFailure?
    /// 自動起動設定更新失敗時の OS エラー詳細文言（言語切替時に現在言語へ再評価するため保持する）
    private var launchAtLoginErrorDetail: String?
    /// 進行中の手動アップデート確認タスク
    private var manualUpdateCheckTask: Task<Void, Never>?

    /// 設定 ViewModel を初期化する
    /// - Parameters:
    ///   - preferencesStore: 設定永続化ストア
    ///   - hotKeyMonitor: ホットキー監視サービス
    ///   - launchAtLoginService: ログイン時自動起動サービス
    ///   - permissionService: アクセシビリティ権限サービス
    ///   - screenRecordingPermissionService: 画面収録権限サービス（省略時は未設定）
    ///   - updateService: アップデート確認・誘導サービス
    ///   - appIdentity: 実行中アプリの識別情報
    ///   - versionInfo: 実行中アプリのバージョン情報
    ///   - preferredLanguagesProvider: システム優先言語配列の提供クロージャ（既定値は `Locale.preferredLanguages`）
    public init(
        preferencesStore: any PreferencesStoring,
        hotKeyMonitor: any HotKeyMonitoring,
        launchAtLoginService: any LaunchAtLoginServicing,
        permissionService: any AccessibilityPermissionServicing,
        screenRecordingPermissionService: (any ScreenRecordingPermissionServicing)? = nil,
        updateService: any AppUpdateServicing = AppUpdateService(),
        appIdentity: AppIdentity = .current,
        versionInfo: AppVersionInfo = .current,
        preferredLanguagesProvider: @escaping @Sendable () -> [String] = { Locale.preferredLanguages }
    ) {
        self.preferencesStore = preferencesStore
        self.hotKeyMonitor = hotKeyMonitor
        self.launchAtLoginService = launchAtLoginService
        self.permissionService = permissionService
        self.screenRecordingPermissionService = screenRecordingPermissionService
        self.updateService = updateService
        self.appIdentity = appIdentity
        self.versionInfo = versionInfo
        self.preferredLanguagesProvider = preferredLanguagesProvider
        self.shortcut = preferencesStore.loadShortcut()
        self.launcherShortcut = preferencesStore.loadLauncherShortcut()
        let loadedLanguage = preferencesStore.loadAppLanguage()
        self.appLanguage = loadedLanguage
        self.resolvedLanguage = loadedLanguage.resolved(preferredLanguages: preferredLanguagesProvider())
        let loadedStyle = preferencesStore.loadNormalDisplayStyle()
        let loadedLauncherStyle = preferencesStore.loadLauncherDisplayStyle()
        self.normalDisplayStyle = loadedStyle
        self.launcherDisplayStyle = loadedLauncherStyle
        self.isNormalSwitcherGroupedByApp = preferencesStore.loadGroupNormalSwitcherByApp()
        self.isLauncherGroupedByApp = preferencesStore.loadGroupLauncherByApp()
        self.windowTitleTruncationMode = preferencesStore.loadWindowTitleTruncationMode()
        self.isLaunchAtLoginEnabled = launchAtLoginService.isEnabled
        self.isAutoCheckForUpdatesEnabled = preferencesStore.loadAutoCheckForUpdates()
        self.permissionStatus = permissionService.currentStatus()
        if loadedStyle == .capture || loadedLauncherStyle == .capture {
            self.screenRecordingStatus = screenRecordingPermissionService?.currentStatus() ?? .denied
        }
    }

    /// 通常スイッチャーの修飾キーを更新し、競合がなければ永続化および監視サービスへ即時反映する（互換用）
    /// - Parameter modifier: 新しい修飾キー
    public func updateModifier(_ modifier: ModifierKeyOption) {
        let candidate = ShortcutPreference(
            keyCode: shortcut.keyCode,
            modifiers: [modifier.shortcutModifierFlag],
            keyLabel: shortcut.keyLabel
        )
        applyNormalShortcutIfValid(candidate)
    }

    /// 通常スイッチャーのトリガーキーを更新し、競合がなければ永続化および監視サービスへ即時反映する（互換用）
    /// - Parameter trigger: 新しいトリガーキー
    public func updateTrigger(_ trigger: TriggerKeyOption) {
        let candidate = ShortcutPreference(
            keyCode: trigger.keyCode,
            modifiers: shortcut.modifiers,
            keyLabel: trigger.symbol
        )
        applyNormalShortcutIfValid(candidate)
    }

    /// 通常スイッチャーショートカットの記録待機を開始し、グローバルホットキー監視を一時停止する
    public func beginRecordingNormalShortcut() {
        isRecordingLauncherShortcut = false
        shortcutValidationFailure = nil
        shortcutValidationTarget = nil
        isRecordingNormalShortcut = true
        hotKeyMonitor.isSuspendedForRecording = true
    }

    /// 通常スイッチャーショートカットの記録待機をキャンセル・終了し、必要なら監視を再開する
    public func cancelRecordingNormalShortcut() {
        guard isRecordingNormalShortcut else { return }
        isRecordingNormalShortcut = false
        syncRecordingSuspension()
    }

    /// レコーダーから受け取った通常スイッチャーショートカット候補を検証し、有効なら保存・反映する
    /// - Parameter candidate: 入力された通常スイッチャーショートカット候補
    public func recordNormalShortcut(_ candidate: ShortcutPreference) {
        guard applyNormalShortcutIfValid(candidate) else { return }
        cancelRecordingNormalShortcut()
    }

    /// ランチャーショートカットの記録待機を開始し、グローバルホットキー監視を一時停止する
    public func beginRecordingLauncherShortcut() {
        isRecordingNormalShortcut = false
        shortcutValidationFailure = nil
        shortcutValidationTarget = nil
        isRecordingLauncherShortcut = true
        hotKeyMonitor.isSuspendedForRecording = true
    }

    /// ランチャーショートカットの記録待機をキャンセル・終了し、必要なら監視を再開する
    public func cancelRecordingLauncherShortcut() {
        guard isRecordingLauncherShortcut else { return }
        isRecordingLauncherShortcut = false
        syncRecordingSuspension()
    }

    /// レコーダーから受け取ったランチャーショートカット候補を検証し、有効なら保存・反映する
    /// - Parameter candidate: 入力されたショートカット候補
    public func recordLauncherShortcut(_ candidate: LauncherShortcutPreference) {
        if let failure = ShortcutConflictValidator.evaluateLauncherShortcut(candidate, against: shortcut) {
            shortcutValidationFailure = failure
            shortcutValidationTarget = .launcher
            return
        }

        shortcutValidationFailure = nil
        shortcutValidationTarget = nil
        launcherShortcut = candidate
        preferencesStore.saveLauncherShortcut(candidate)
        hotKeyMonitor.updateLauncherShortcut(candidate)
        cancelRecordingLauncherShortcut()
    }

    /// 進行中のすべてのショートカット記録待機を解除し、ホットキー監視を再開する
    public func cancelAllRecordings() {
        isRecordingNormalShortcut = false
        isRecordingLauncherShortcut = false
        hotKeyMonitor.isSuspendedForRecording = false
    }

    /// サイドバーの選択中メニューを切り替える
    /// 別メニューへの遷移時は、進行中のショートカット記録待機を自動キャンセルし、未解消の検証エラーをクリアする
    /// - Parameter tab: 切り替え先のメニュー種別
    public func selectTab(_ tab: SettingsTab) {
        guard selectedTab != tab else { return }
        cancelAllRecordings()
        shortcutValidationFailure = nil
        shortcutValidationTarget = nil
        selectedTab = tab
    }

    /// ログイン時自動起動の有効・無効を切り替える
    /// - Parameter enabled: 有効にする場合は true
    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
            launchAtLoginErrorDetail = nil
        } catch {
            launchAtLoginErrorDetail = error.localizedDescription
        }
        // OS 側の実ステータスと常に同期する
        isLaunchAtLoginEnabled = launchAtLoginService.isEnabled
    }

    /// 起動時のバージョンアップ自動チェック設定を変更して永続化する
    /// - Parameter enabled: 有効にする場合は true
    public func setAutoCheckForUpdates(_ enabled: Bool) {
        guard isAutoCheckForUpdatesEnabled != enabled else { return }
        isAutoCheckForUpdatesEnabled = enabled
        preferencesStore.saveAutoCheckForUpdates(enabled)
        onAutoCheckForUpdatesChanged?(enabled)
    }

    /// 設定画面「アプリ情報」から手動で最新安定版リリースを確認する（確認中の重複実行を防止）
    public func checkForUpdatesManually() {
        guard !isCheckingForUpdates else { return }
        manualUpdateCheckState = .checking

        let updateService = self.updateService
        let appIdentity = self.appIdentity
        let versionInfo = self.versionInfo
        let skippedVersion = preferencesStore.loadSkippedUpdateVersion()

        manualUpdateCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let release = try await updateService.fetchLatestStableRelease()
                let decision = UpdateCheckPolicy.evaluate(
                    release: release,
                    currentVersionInfo: versionInfo,
                    appIdentity: appIdentity,
                    skippedVersion: skippedVersion,
                    trigger: .manual
                )
                switch decision {
                case .upToDate:
                    self.manualUpdateCheckState = .upToDate
                case let .updateAvailable(currentVersion, availableRelease):
                    self.manualUpdateCheckState = .updateAvailable(availableRelease.version)
                    self.onUpdateAvailable?(availableRelease, currentVersion)
                case let .developmentBuildNotice(latestRelease):
                    self.manualUpdateCheckState = .developmentBuild(latestRelease: latestRelease)
                case .skipped, .suppressedDevelopmentBuild:
                    // 手動確認では通常到達しないが安全側へフォールバックする
                    self.manualUpdateCheckState = .upToDate
                }
            } catch let error as AppUpdateError {
                self.manualUpdateCheckState = .failed(error)
            } catch {
                self.manualUpdateCheckState = .failed(.networkError(error.localizedDescription))
            }
            self.manualUpdateCheckTask = nil
        }
    }

    /// 手動アップデート確認の結果に応じた GitHub Releases ページを既定ブラウザで開く
    public func openUpdateReleasePage() {
        updateService.openReleasePage(url: manualUpdateReleaseURL)
    }

    /// アプリの表示言語設定を変更して永続化し、解決済み言語をアプリ全体へ即時通知する
    /// - Parameter language: 新しい言語設定（`.system` または 5 言語）
    public func updateAppLanguage(_ language: AppLanguage) {
        guard appLanguage != language else { return }
        appLanguage = language
        preferencesStore.saveAppLanguage(language)
        resolvedLanguage = language.resolved(preferredLanguages: preferredLanguagesProvider())
        onAppLanguageChanged?(language, resolvedLanguage)
    }

    /// 外部（システム設定）での変更を UI へ再同期する
    /// - Parameter overridePermissionStatus: コーディネーター側で確定済みの権限状態を直接反映する場合に指定
    public func refreshStatus(permissionStatus overridePermissionStatus: AccessibilityPermissionStatus? = nil) {
        isLaunchAtLoginEnabled = launchAtLoginService.isEnabled
        permissionStatus = overridePermissionStatus ?? permissionService.currentStatus()
        // 「システム設定に従う」選択時は OS 優先言語の変化も再評価して反映する
        if appLanguage == .system {
            let latestResolved = appLanguage.resolved(preferredLanguages: preferredLanguagesProvider())
            if resolvedLanguage != latestResolved {
                resolvedLanguage = latestResolved
                onAppLanguageChanged?(appLanguage, latestResolved)
            }
        }
        // 通常スイッチャー・検索ランチャーの双方が非キャプチャの間は画面収録権限を一切確認しない（最小権限原則）
        if usesCaptureDisplayStyle {
            screenRecordingStatus = screenRecordingPermissionService?.currentStatus() ?? .denied
        }
    }

    /// 通常スイッチャーの表示形式を変更して永続化し、関連ステータスを更新する
    /// - Parameter style: 新しい表示形式（リスト型／アイコン型／キャプチャ表示型）
    public func updateNormalDisplayStyle(_ style: SwitcherDisplayStyle) {
        guard normalDisplayStyle != style else { return }
        normalDisplayStyle = style
        preferencesStore.saveNormalDisplayStyle(style)
        syncScreenRecordingStatus()
        onNormalDisplayStyleChanged?(style)
    }

    /// 検索ランチャーの表示形式を変更して永続化し、関連ステータスを更新する
    /// - Parameter style: 新しい表示形式（リスト型／キャプチャ表示型）
    public func updateLauncherDisplayStyle(_ style: LauncherDisplayStyle) {
        guard launcherDisplayStyle != style else { return }
        launcherDisplayStyle = style
        preferencesStore.saveLauncherDisplayStyle(style)
        syncScreenRecordingStatus()
        onLauncherDisplayStyleChanged?(style)
    }

    /// 通常スイッチャーのアプリグルーピング設定を変更して永続化し、上位へ即時通知する
    /// - Parameter enabled: アプリごとにグルーピングする場合は true
    public func updateNormalSwitcherGrouping(_ enabled: Bool) {
        guard isNormalSwitcherGroupedByApp != enabled else { return }
        isNormalSwitcherGroupedByApp = enabled
        preferencesStore.saveGroupNormalSwitcherByApp(enabled)
        onNormalSwitcherGroupingChanged?(enabled)
    }

    /// 検索ランチャーのアプリグルーピング設定を変更して永続化し、上位へ即時通知する
    /// - Parameter enabled: アプリごとにグルーピングする場合は true
    public func updateLauncherGrouping(_ enabled: Bool) {
        guard isLauncherGroupedByApp != enabled else { return }
        isLauncherGroupedByApp = enabled
        preferencesStore.saveGroupLauncherByApp(enabled)
        onLauncherGroupingChanged?(enabled)
    }

    /// ウィンドウタイトルの省略位置設定を変更して永続化し、上位へ即時通知する
    /// - Parameter mode: 新しい省略位置設定（途中を省略／末尾を省略）
    public func updateWindowTitleTruncationMode(_ mode: WindowTitleTruncationMode) {
        guard windowTitleTruncationMode != mode else { return }
        windowTitleTruncationMode = mode
        preferencesStore.saveWindowTitleTruncationMode(mode)
        onWindowTitleTruncationModeChanged?(mode)
    }

    /// いずれかのモードでキャプチャ表示型が選択されている場合のみ、OS の画面収録権限許可をリクエストする
    public func requestScreenRecordingPermission() {
        guard usesCaptureDisplayStyle else { return }
        _ = screenRecordingPermissionService?.requestPermission()
        screenRecordingStatus = screenRecordingPermissionService?.currentStatus() ?? .denied
    }

    /// いずれかのモードでキャプチャ表示型が選択されている場合のみ、システム設定の画面収録ペインを開く
    public func openScreenRecordingSettings() {
        guard usesCaptureDisplayStyle else { return }
        screenRecordingPermissionService?.openSystemSettings()
    }

    /// 現在の表示形式設定に応じて画面収録権限ステータスを同期する（双方非キャプチャ時は確認を行わず .denied へ戻す）
    private func syncScreenRecordingStatus() {
        if usesCaptureDisplayStyle {
            screenRecordingStatus = screenRecordingPermissionService?.currentStatus() ?? .denied
        } else {
            screenRecordingStatus = .denied
        }
    }

    /// アクセシビリティ権限設定画面を開く
    public func openAccessibilitySettings() {
        permissionService.openAccessibilitySettings()
    }

    /// 通常ショートカット候補をランチャーとの競合チェック付きで適用・保存する
    /// - Parameter candidate: 変更候補のショートカット設定
    /// - Returns: 検証を通過して適用された場合は true
    @discardableResult
    private func applyNormalShortcutIfValid(_ candidate: ShortcutPreference) -> Bool {
        if let failure = ShortcutConflictValidator.evaluateNormalShortcut(candidate, against: launcherShortcut) {
            shortcutValidationFailure = failure
            shortcutValidationTarget = .normal
            return false
        }

        shortcutValidationFailure = nil
        shortcutValidationTarget = nil
        shortcut = candidate
        preferencesStore.saveShortcut(candidate)
        hotKeyMonitor.updateShortcut(candidate)
        return true
    }

    /// いずれかのレコーダーが待機中かどうかに合わせて監視サスペンド状態を同期する
    private func syncRecordingSuspension() {
        hotKeyMonitor.isSuspendedForRecording = isRecordingNormalShortcut || isRecordingLauncherShortcut
    }
}
