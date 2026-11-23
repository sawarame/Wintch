import Foundation

/// GitHub Releases から取得した安定版リリース情報
public struct AppReleaseInfo: Equatable, Sendable {
    /// 解析済みセマンティックバージョン
    public let version: SemanticVersion

    /// GitHub リリースタグ名（例: `"v0.3.0"`）
    public let tagName: String

    /// GitHub Release ページの URL
    public let releaseURL: URL

    /// 配布用 ZIP アセットのダウンロード URL
    public let downloadURL: URL

    /// 配布用 ZIP アセットファイル名（例: `"Wintch-v0.3.0.zip"`）
    public let assetName: String

    /// アセットに添付された期待 SHA-256 ダイジェスト（小文字 64 桁 hex、未提供時は nil）
    public let expectedSHA256: String?

    /// リリースノート本文
    public let releaseNotes: String

    /// リリース公開日時（取得できた場合）
    public let publishedAt: Date?

    /// リリース情報を初期化する
    /// - Parameters:
    ///   - version: セマンティックバージョン
    ///   - tagName: リリースタグ名
    ///   - releaseURL: GitHub Release ページ URL
    ///   - downloadURL: 配布用 ZIP のダウンロード URL
    ///   - assetName: アセットファイル名
    ///   - expectedSHA256: 期待 SHA-256（小文字 hex、任意）
    ///   - releaseNotes: リリースノート本文
    ///   - publishedAt: 公開日時（任意）
    public init(
        version: SemanticVersion,
        tagName: String,
        releaseURL: URL,
        downloadURL: URL,
        assetName: String,
        expectedSHA256: String? = nil,
        releaseNotes: String = "",
        publishedAt: Date? = nil
    ) {
        self.version = version
        self.tagName = tagName
        self.releaseURL = releaseURL
        self.downloadURL = downloadURL
        self.assetName = assetName
        self.expectedSHA256 = expectedSHA256
        self.releaseNotes = releaseNotes
        self.publishedAt = publishedAt
    }
}

/// アップデート確認の起動経路
public enum UpdateCheckTrigger: Equatable, Sendable {
    /// アプリ起動時の自動バックグラウンドチェック
    case automatic
    /// 設定画面からの手動確認
    case manual
}

/// バージョン確認結果の判定種別
public enum UpdateCheckDecision: Equatable, Sendable {
    /// 現在のバージョンが最新（またはリリース以上）
    case upToDate(currentVersion: SemanticVersion)
    /// 新しい安定版リリースが利用可能
    case updateAvailable(currentVersion: SemanticVersion, release: AppReleaseInfo)
    /// 起動時自動チェックでユーザーがスキップ済みのバージョンのため非通知
    case skipped(version: SemanticVersion)
    /// 起動時自動チェックにおいて開発版のためチェックを抑止
    case suppressedDevelopmentBuild
    /// 手動確認においてローカル開発版であることを案内する状態
    case developmentBuildNotice(latestRelease: AppReleaseInfo?)
}

/// アプリ内自動差し替えの実行可否と不可理由
public enum UpdateInstallEligibility: Equatable, Sendable {
    /// アプリ内自動差し替えを実行可能
    case eligible
    /// ローカル開発版（Wintch_dev または dev バージョン）のため無効
    case developmentBuild
    /// App Translocation 環境のため無効
    case appTranslocated
    /// `.app` バンドルとして実行されていないため無効
    case notAppBundle
    /// 読み取り専用ボリュームまたは書き込み権限不足のため無効
    case readOnlyOrUnwritable

    /// アプリ内自動差し替えを実行できるかどうか
    public var canInstallInPlace: Bool {
        self == .eligible
    }

    /// バンドル情報とファイルシステム状態から差し替え可否を純粋判定する
    /// - Parameters:
    ///   - appIdentity: 実行中アプリ識別情報
    ///   - versionInfo: 実行中アプリバージョン情報
    ///   - bundleURL: 実行中アプリバンドル URL
    ///   - isVolumeReadOnly: 配置ボリュームが読み取り専用かどうか
    ///   - isBundleWritable: バンドル自体への書き込み権限があるか
    ///   - isParentDirectoryWritable: バンドルの親ディレクトリへの書き込み権限があるか
    /// - Returns: 差し替え可否判定結果
    public static func evaluate(
        appIdentity: AppIdentity,
        versionInfo: AppVersionInfo,
        bundleURL: URL,
        isVolumeReadOnly: Bool,
        isBundleWritable: Bool,
        isParentDirectoryWritable: Bool
    ) -> UpdateInstallEligibility {
        if appIdentity.isDevelopment || SemanticVersion(string: versionInfo.shortVersion) == nil {
            return .developmentBuild
        }
        let path = bundleURL.path
        if path.contains("/AppTranslocation/") {
            return .appTranslocated
        }
        guard bundleURL.pathExtension.lowercased() == "app" else {
            return .notAppBundle
        }
        if isVolumeReadOnly || !isBundleWritable || !isParentDirectoryWritable {
            return .readOnlyOrUnwritable
        }
        return .eligible
    }
}

/// アプリ内アップデート実行中の進捗フェーズ
public enum UpdateProgressPhase: Equatable, Sendable {
    /// 配布用 ZIP をダウンロード中（進捗率 0.0〜1.0、不明時は nil）
    case downloading(fractionCompleted: Double?)
    /// ダウンロード ZIP の展開中
    case extracting
    /// ハッシュ・Info.plist・コード署名／Team ID を検証中
    case verifying
    /// 新バージョンの配置および再起動を準備中
    case installing
}

/// アップデート確認・適用処理で発生し得るエラー
public enum AppUpdateError: Error, Equatable, Sendable {
    /// HTTP ステータス異常
    case invalidHTTPStatus(Int)
    /// GitHub API レート制限到達
    case rateLimited
    /// ネットワーク通信エラー
    case networkError(String)
    /// レスポンス JSON の解析失敗
    case invalidResponse
    /// 対象の安定版リリースが存在しない（ドラフト・プレリリースのみ等）
    case noStableRelease
    /// 期待する配布 ZIP アセットが見つからない
    case missingReleaseAsset(expectedName: String)
    /// 許可されていないスキームまたはホストの URL を検出
    case untrustedDownloadURL
    /// SHA-256 チェックサム不一致
    case checksumMismatch
    /// ZIP 展開失敗または内部に Wintch.app が見つからない
    case extractionFailed(String)
    /// 展開後の Info.plist 検証失敗（Bundle ID またはバージョン不一致）
    case invalidBundleMetadata(String)
    /// コード署名検証失敗
    case codeSignatureInvalid(String)
    /// 署名 Team ID 不一致または未署名
    case teamIdentifierMismatch
    /// 自動差し替え不可環境
    case installNotEligible(UpdateInstallEligibility)
    /// 差し替えヘルパープロセスの起動失敗
    case helperLaunchFailed(String)

    /// 指定言語でのユーザー向けエラーメッセージを返す
    /// - Parameter language: 表示対象の解決済み言語
    /// - Returns: ローカライズ済みのエラーメッセージ
    public func localizedMessage(in language: ResolvedAppLanguage) -> String {
        AppStrings(language: language).updateErrorMessage(for: self)
    }
}

/// GitHub Release 関連 URL およびダイジェストの安全性を検証する純粋ロジック
public enum UpdateURLValidator {
    /// リリースページ URL として許可するホスト名
    private static let allowedReleaseHosts: Set<String> = [
        "github.com"
    ]

    /// リリースページ URL が安全な GitHub HTTPS URL か検証する
    /// - Parameter url: 検証対象 URL
    /// - Returns: 許可する場合は true
    public static func isAllowedReleasePageURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedReleaseHosts.contains(host) else {
            return false
        }
        return url.path.lowercased().hasPrefix("/sawarame/wintch/")
            || url.path.lowercased() == "/sawarame/wintch/releases"
    }

    /// アセットダウンロード URL（およびリダイレクト先）が信頼できる GitHub HTTPS ホストか検証する
    /// - Parameter url: 検証対象 URL
    /// - Returns: 許可する場合は true
    public static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return false
        }
        if host == "github.com" {
            return true
        }
        return host.hasSuffix(".githubusercontent.com")
    }

    /// GitHub Release アセットの `digest` フィールドから SHA-256 の 64 桁小文字 hex を抽出する
    /// - Parameter rawDigest: API レスポンスの `digest` 値（例: `"sha256:0123..."`）
    /// - Returns: 有効な SHA-256 hex 文字列。未指定時は nil。`sha256:` 付きで形式不正な場合はエラーを投げる
    public static func parseSHA256Digest(_ rawDigest: String?) throws -> String? {
        guard let rawDigest else { return nil }
        let trimmed = rawDigest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()
        guard lowercased.hasPrefix("sha256:") else {
            // 他の未知アルゴリズムが将来付与された場合は安全のため nil 扱いとせず無視するか判定するが、
            // ここでは sha256 以外の未知形式は無視して署名検証に委ねる
            return nil
        }

        let hex = String(lowercased.dropFirst("sha256:".count))
        let isValidHex = hex.count == 64 && hex.allSatisfy { ch in
            (ch >= "0" && ch <= "9") || (ch >= "a" && ch <= "f")
        }
        guard isValidHex else {
            throw AppUpdateError.invalidResponse
        }
        return hex
    }
}

/// GitHub Releases API レスポンスをデコード・検証して `AppReleaseInfo` を構築するパーサー
public enum GitHubReleaseParser {
    /// Wintch リポジトリの最新安定版リリース取得エンドポイント
    public static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/sawarame/Wintch/releases/latest")!

    /// Wintch リポジトリの GitHub Releases 一覧ページ URL
    public static let releasesPageURL = URL(string: "https://github.com/sawarame/Wintch/releases")!

    /// API レスポンスのリリース JSON 表現
    private struct ReleasePayload: Decodable {
        let tagName: String
        let htmlURL: String
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let publishedAt: String?
        let assets: [AssetPayload]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
            case draft
            case prerelease
            case publishedAt = "published_at"
            case assets
        }
    }

    /// API レスポンスのアセット JSON 表現
    private struct AssetPayload: Decodable {
        let name: String
        let browserDownloadURL: String
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case digest
        }
    }

    /// GitHub Releases API の JSON データから安定版リリース情報を抽出・検証する
    /// - Parameter data: API レスポンス本文データ
    /// - Returns: 検証済みの安定版リリース情報
    public static func parseStableRelease(from data: Data) throws -> AppReleaseInfo {
        let payload: ReleasePayload
        do {
            payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        } catch {
            throw AppUpdateError.invalidResponse
        }

        // ドラフトまたはプレリリースは常に除外する
        guard !payload.draft, !payload.prerelease else {
            throw AppUpdateError.noStableRelease
        }

        // タグ名から SemVer を解析し、プレリリース識別子付きタグも除外する
        guard let version = SemanticVersion(string: payload.tagName), !version.isPrerelease else {
            throw AppUpdateError.noStableRelease
        }

        // 期待ファイル名 `Wintch-v<VERSION>.zip` の配布アセットを抽出する
        let expectedAssetName = "Wintch-v\(version.normalizedString).zip"
        guard let asset = payload.assets.first(where: { $0.name == expectedAssetName }) else {
            throw AppUpdateError.missingReleaseAsset(expectedName: expectedAssetName)
        }

        guard let releaseURL = URL(string: payload.htmlURL),
              UpdateURLValidator.isAllowedReleasePageURL(releaseURL),
              let downloadURL = URL(string: asset.browserDownloadURL),
              UpdateURLValidator.isAllowedDownloadURL(downloadURL) else {
            throw AppUpdateError.untrustedDownloadURL
        }

        let expectedSHA256 = try UpdateURLValidator.parseSHA256Digest(asset.digest)
        let publishedAt = payload.publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }

        return AppReleaseInfo(
            version: version,
            tagName: payload.tagName,
            releaseURL: releaseURL,
            downloadURL: downloadURL,
            assetName: asset.name,
            expectedSHA256: expectedSHA256,
            releaseNotes: (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            publishedAt: publishedAt
        )
    }
}

/// 自動チェック実行可否・更新要否・スキップ対象を判定する純粋ドメインポリシー
public enum UpdateCheckPolicy {
    /// 起動時の自動バージョンチェックを実行すべきか判定する
    /// - Parameters:
    ///   - isAutoCheckEnabled: ユーザー設定の「バージョンアップを自動チェック」が ON か
    ///   - appIdentity: 実行中アプリの識別情報
    ///   - versionInfo: 実行中アプリのバージョン情報
    /// - Returns: 起動時ネットワーク確認を実行すべき場合は true
    public static func shouldPerformAutomaticCheck(
        isAutoCheckEnabled: Bool,
        appIdentity: AppIdentity,
        versionInfo: AppVersionInfo
    ) -> Bool {
        guard isAutoCheckEnabled else { return false }
        guard !appIdentity.isDevelopment else { return false }
        guard SemanticVersion(string: versionInfo.shortVersion) != nil else { return false }
        return true
    }

    /// 取得済み安定版リリースと現在環境から更新確認の最終判定を行う
    /// - Parameters:
    ///   - release: 取得した最新安定版リリース情報
    ///   - currentVersionInfo: 現在実行中アプリのバージョン情報
    ///   - appIdentity: 現在実行中アプリの識別情報
    ///   - skippedVersion: ユーザーがスキップ保存済みのバージョン文字列（未設定時は nil）
    ///   - trigger: 起動経路（自動 / 手動）
    /// - Returns: 更新確認結果の判定種別
    public static func evaluate(
        release: AppReleaseInfo,
        currentVersionInfo: AppVersionInfo,
        appIdentity: AppIdentity,
        skippedVersion: String?,
        trigger: UpdateCheckTrigger
    ) -> UpdateCheckDecision {
        // ローカル開発版または非 SemVer（"dev" 等）では自動チェックを抑止し、手動確認時は開発版案内へ留める
        guard !appIdentity.isDevelopment,
              let currentVersion = SemanticVersion(string: currentVersionInfo.shortVersion) else {
            switch trigger {
            case .automatic:
                return .suppressedDevelopmentBuild
            case .manual:
                return .developmentBuildNotice(latestRelease: release)
            }
        }

        // 現在バージョンより新しい安定版でない場合は最新版扱いとする
        guard release.version > currentVersion else {
            return .upToDate(currentVersion: currentVersion)
        }

        // 起動時自動チェック時はスキップ済みバージョンと一致するなら通知を抑止する（手動確認時は再提示する）
        if trigger == .automatic, isVersionSkipped(release.version, skippedVersion: skippedVersion) {
            return .skipped(version: release.version)
        }

        return .updateAvailable(currentVersion: currentVersion, release: release)
    }

    /// 指定バージョンが保存済みスキップ対象バージョンと一致するか判定する
    /// - Parameters:
    ///   - candidate: 判定対象の新バージョン
    ///   - skippedVersion: 保存されているスキップバージョン文字列
    /// - Returns: スキップ対象と一致する場合は true
    public static func isVersionSkipped(_ candidate: SemanticVersion, skippedVersion: String?) -> Bool {
        guard let skippedVersion else { return false }
        let trimmed = skippedVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let parsedSkipped = SemanticVersion(string: trimmed) {
            return parsedSkipped == candidate
        }
        return trimmed == candidate.normalizedString
    }
}
