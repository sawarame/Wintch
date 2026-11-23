import Foundation

/// GitHub Releases からの更新確認・安全なアプリ内アップデート実行・ブラウザ誘導を隔離提供するサービス契約
public protocol AppUpdateServicing: Sendable {
    /// GitHub Releases API から最新の安定版リリース情報を取得する
    /// - Returns: 検証済みの安定版リリース情報
    func fetchLatestStableRelease() async throws -> AppReleaseInfo

    /// 現在の実行環境でアプリ内自動差し替えが可能かを事前判定する
    /// - Parameters:
    ///   - appIdentity: 実行中アプリの識別情報
    ///   - versionInfo: 実行中アプリのバージョン情報
    /// - Returns: 差し替え可否判定結果
    func evaluateInstallEligibility(
        appIdentity: AppIdentity,
        versionInfo: AppVersionInfo
    ) -> UpdateInstallEligibility

    /// 指定リリースの配布 ZIP をダウンロード・検証・展開し、差し替えおよび再起動を行うヘルパープロセスを起動する
    /// - Parameters:
    ///   - release: 適用対象の安定版リリース情報
    ///   - appIdentity: 実行中アプリの識別情報
    ///   - versionInfo: 実行中アプリのバージョン情報
    ///   - onProgress: ダウンロードおよび検証の進捗フェーズ通知コールバック
    func downloadVerifyAndScheduleInstall(
        release: AppReleaseInfo,
        appIdentity: AppIdentity,
        versionInfo: AppVersionInfo,
        onProgress: @escaping @Sendable (UpdateProgressPhase) -> Void
    ) async throws

    /// 指定された GitHub Release 関連ページを規定ブラウザで開く
    /// - Parameter url: 開く対象の URL（安全でない場合は Releases 一覧ページへフォールバック）
    func openReleasePage(url: URL)
}
