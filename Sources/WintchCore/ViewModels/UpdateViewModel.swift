import Foundation
import Observation

/// 更新確認ダイアログの現在の進行状態
public enum UpdatePromptPhase: Equatable, Sendable {
    /// ユーザー操作待機中
    case ready
    /// ダウンロード・展開・検証・差し替え準備中
    case inProgress(UpdateProgressPhase)
    /// 更新適用エラー発生
    case failed(AppUpdateError)
}

/// 更新確認ダイアログの状態管理およびアップデート適用フローを制御する ViewModel
@MainActor
@Observable
public final class UpdateViewModel {
    /// 現在の UI 描画に適用されている解決済み言語
    public private(set) var resolvedLanguage: ResolvedAppLanguage

    /// 現在の解決済み言語に対応するローカライズ文言テーブル
    public var strings: AppStrings {
        AppStrings(language: resolvedLanguage)
    }

    /// 現在のアプリバージョン表示文字列
    public private(set) var currentVersionText: String

    /// 提示中の新リリース情報
    public private(set) var release: AppReleaseInfo?

    /// 現在の実行環境におけるアプリ内自動差し替えの可否
    public private(set) var installEligibility: UpdateInstallEligibility = .eligible

    /// 現在の更新進行状態
    public private(set) var phase: UpdatePromptPhase = .ready

    /// アップデート処理を実行中かどうか
    public var isUpdating: Bool {
        if case .inProgress = phase {
            return true
        }
        return false
    }

    /// 現在の環境で「今すぐアップデート」による自動差し替えが可能かどうか
    public var canInstallInPlace: Bool {
        installEligibility.canInstallInPlace
    }

    /// 自動差し替え不可環境の場合の理由メッセージ（可能時は nil）
    public var eligibilityNoticeMessage: String? {
        strings.updateInstallEligibilityReason(for: installEligibility)
    }

    /// 更新適用エラー発生時のローカライズ済みエラーメッセージ
    public var errorMessage: String? {
        if case let .failed(error) = phase {
            return error.localizedMessage(in: resolvedLanguage)
        }
        return nil
    }

    /// 現在の進捗フェーズに対応するローカライズ済みステータスメッセージ
    public var progressMessage: String? {
        guard case let .inProgress(progress) = phase else { return nil }
        switch progress {
        case .downloading:
            return strings.updateStatusDownloading
        case .extracting:
            return strings.updateStatusExtracting
        case .verifying:
            return strings.updateStatusVerifying
        case .installing:
            return strings.updateStatusInstalling
        }
    }

    /// ダウンロード進捗率（0.0〜1.0、不定時は nil）
    public var downloadFractionCompleted: Double? {
        guard case let .inProgress(.downloading(fraction)) = phase else { return nil }
        return fraction
    }

    /// ダイアログ閉鎖を上位コーディネーターへ要求するコールバック
    public var onCloseRequested: (() -> Void)?

    /// ヘルパープロセス起動完了後にアプリ終了・再起動を上位コーディネーターへ要求するコールバック
    public var onQuitForRestartRequested: (() -> Void)?

    /// アップデート実行サービス
    private let updateService: any AppUpdateServicing
    /// 設定永続化ストア
    private let preferencesStore: any PreferencesStoring
    /// 実行中アプリの識別情報
    private let appIdentity: AppIdentity
    /// 実行中アプリのバージョン情報
    private let versionInfo: AppVersionInfo
    /// 進行中の更新適用タスク
    private var updateTask: Task<Void, Never>?

    /// UpdateViewModel を初期化する
    /// - Parameters:
    ///   - updateService: アップデートサービス
    ///   - preferencesStore: 設定永続化ストア
    ///   - appIdentity: 実行中アプリの識別情報
    ///   - versionInfo: 実行中アプリのバージョン情報
    ///   - resolvedLanguage: 初期表示言語
    public init(
        updateService: any AppUpdateServicing,
        preferencesStore: any PreferencesStoring,
        appIdentity: AppIdentity = .current,
        versionInfo: AppVersionInfo = .current,
        resolvedLanguage: ResolvedAppLanguage = .japanese
    ) {
        self.updateService = updateService
        self.preferencesStore = preferencesStore
        self.appIdentity = appIdentity
        self.versionInfo = versionInfo
        self.resolvedLanguage = resolvedLanguage
        self.currentVersionText = versionInfo.shortVersion
    }

    /// 表示言語を更新する
    /// - Parameter language: 新しい解決済み言語
    public func updateLanguage(_ language: ResolvedAppLanguage) {
        resolvedLanguage = language
    }

    /// 検出された新リリース情報をセットし、差し替え可否を評価してダイアログ状態を初期化する
    /// - Parameters:
    ///   - release: 提示する新リリース情報
    ///   - currentVersion: 現在のバージョン
    public func present(release: AppReleaseInfo, currentVersion: SemanticVersion) {
        // 既に更新適用処理が進行中の場合は状態を上書きしない
        guard !isUpdating else { return }
        self.release = release
        self.currentVersionText = currentVersion.normalizedString
        self.installEligibility = updateService.evaluateInstallEligibility(
            appIdentity: appIdentity,
            versionInfo: versionInfo
        )
        self.phase = .ready
    }

    /// 「今すぐアップデート」操作を開始し、ダウンロード・検証・差し替えヘルパー起動を実行する
    public func startUpdate() {
        guard !isUpdating, let release else { return }
        let latestEligibility = updateService.evaluateInstallEligibility(
            appIdentity: appIdentity,
            versionInfo: versionInfo
        )
        installEligibility = latestEligibility
        guard latestEligibility.canInstallInPlace else {
            phase = .failed(.installNotEligible(latestEligibility))
            return
        }

        phase = .inProgress(.downloading(fractionCompleted: 0))
        let updateService = self.updateService
        let appIdentity = self.appIdentity
        let versionInfo = self.versionInfo

        updateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await updateService.downloadVerifyAndScheduleInstall(
                    release: release,
                    appIdentity: appIdentity,
                    versionInfo: versionInfo
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.phase = .inProgress(progress)
                    }
                }
                self.phase = .inProgress(.installing)
                self.onQuitForRestartRequested?()
            } catch let error as AppUpdateError {
                self.phase = .failed(error)
            } catch {
                self.phase = .failed(.networkError(error.localizedDescription))
            }
            self.updateTask = nil
        }
    }

    /// 「後で」操作を実行し、スキップ設定を保存せずにダイアログを閉じる
    public func deferUpdate() {
        guard !isUpdating else { return }
        onCloseRequested?()
    }

    /// 「このバージョンをスキップ」操作を実行し、対象バージョンを永続化してダイアログを閉じる
    public func skipThisVersion() {
        guard !isUpdating, let release else { return }
        preferencesStore.saveSkippedUpdateVersion(release.version.normalizedString)
        onCloseRequested?()
    }

    /// 現在のリリース（または Releases 一覧）の GitHub ページをブラウザで開く
    public func openReleasePage() {
        let targetURL = release?.releaseURL ?? GitHubReleaseParser.releasesPageURL
        updateService.openReleasePage(url: targetURL)
    }
}
