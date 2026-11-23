import AppKit
import CryptoKit
import Foundation
import OSLog
import Security

/// リダイレクト先のホスト検証と進捗通知を行うダウンロード専用 URLSession デリゲート
private final class SecureDownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    /// ダウンロード進捗通知コールバック
    private let onProgress: @Sendable (Double?) -> Void
    /// ダウンロード完了時の継続オブジェクト保護用ロック
    private let lock = NSLock()
    /// 完了待機用の継続オブジェクト
    private var continuation: CheckedContinuation<URL, Error>?
    /// 一時保存先ファイル URL
    private let destinationURL: URL

    /// デリゲートを初期化する
    /// - Parameters:
    ///   - destinationURL: ダウンロード完了後の保存先一時ファイル URL
    ///   - onProgress: 進捗率通知コールバック
    init(destinationURL: URL, onProgress: @escaping @Sendable (Double?) -> Void) {
        self.destinationURL = destinationURL
        self.onProgress = onProgress
    }

    /// 完了待機用の継続オブジェクトを登録する
    /// - Parameter continuation: ダウンロード完了結果を返す継続
    func setContinuation(_ continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    /// 継続オブジェクトを 1 度だけ解決する
    /// - Parameter result: 成功ファイル URL またはエラー
    private func finish(with result: Result<URL, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    /// HTTP リダイレクト発生時に遷移先 URL のスキームとホストを厳密検証する
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let nextURL = request.url, UpdateURLValidator.isAllowedDownloadURL(nextURL) else {
            completionHandler(nil)
            finish(with: .failure(AppUpdateError.untrustedDownloadURL))
            task.cancel()
            return
        }
        completionHandler(request)
    }

    /// ダウンロード進捗更新を通知する
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            let fraction = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1)
            onProgress(fraction)
        } else {
            onProgress(nil)
        }
    }

    /// ダウンロード完了時に一時ファイルを指定の作業ディレクトリへ移動する
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            finish(with: .failure(AppUpdateError.invalidHTTPStatus(httpResponse.statusCode)))
            return
        }

        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: location, to: destinationURL)
            onProgress(1.0)
            finish(with: .success(destinationURL))
        } catch {
            finish(with: .failure(AppUpdateError.networkError(error.localizedDescription)))
        }
    }

    /// 通信エラー発生時に継続を失敗解決する
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        if let updateError = error as? AppUpdateError {
            finish(with: .failure(updateError))
        } else {
            finish(with: .failure(AppUpdateError.networkError(error.localizedDescription)))
        }
    }
}

/// GitHub Releases API を用いたバージョン確認・署名検証・安全な `.app` 差し替えおよび再起動を担うサービス実装
public final class AppUpdateService: AppUpdateServicing, @unchecked Sendable {
    /// 診断ログ出力用ロガー
    private static let logger = Logger(subsystem: "dev.wintch.Wintch", category: "AppUpdate")

    /// リリース確認に使用する API エンドポイント URL
    private let latestReleaseAPIURL: URL

    /// 実行中アプリバンドルの URL（テスト時に任意パスを注入可能）
    private let currentBundleURLProvider: @Sendable () -> URL

    /// データ取得に使用する URLSession
    private let session: URLSession

    /// ユーザーエージェント表記用のアプリバージョン文字列
    private let userAgentVersion: String

    /// AppUpdateService を初期化する
    /// - Parameters:
    ///   - latestReleaseAPIURL: GitHub Releases API のエンドポイント URL
    ///   - currentBundleURLProvider: 現在実行中アプリのバンドル URL 提供クロージャ
    ///   - session: 通信に使用する URLSession
    ///   - userAgentVersion: User-Agent ヘッダに付与するバージョン文字列
    public init(
        latestReleaseAPIURL: URL = GitHubReleaseParser.latestReleaseAPIURL,
        currentBundleURLProvider: @escaping @Sendable () -> URL = { Bundle.main.bundleURL },
        session: URLSession = .shared,
        userAgentVersion: String = AppVersionInfo.current.shortVersion
    ) {
        self.latestReleaseAPIURL = latestReleaseAPIURL
        self.currentBundleURLProvider = currentBundleURLProvider
        self.session = session
        self.userAgentVersion = userAgentVersion
    }

    /// GitHub Releases API から最新の安定版リリース情報を取得して検証する
    /// - Returns: 検証済みの安定版リリース情報
    public func fetchLatestStableRelease() async throws -> AppReleaseInfo {
        var request = URLRequest(url: latestReleaseAPIURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Wintch/\(userAgentVersion)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.logger.error("アップデート確認の通信に失敗しました: \(error.localizedDescription, privacy: .public)")
            throw AppUpdateError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }

        if httpResponse.statusCode == 429 ||
            (httpResponse.statusCode == 403 && httpResponse.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0") {
            Self.logger.warning("GitHub Releases API のレート制限に到達しました (HTTP \(httpResponse.statusCode))")
            throw AppUpdateError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            Self.logger.error("GitHub Releases API が異常ステータスを返しました: \(httpResponse.statusCode)")
            throw AppUpdateError.invalidHTTPStatus(httpResponse.statusCode)
        }

        return try GitHubReleaseParser.parseStableRelease(from: data)
    }

    /// 現在の実行環境でアプリ内自動差し替えが可能か事前判定する
    /// - Parameters:
    ///   - appIdentity: 実行中アプリの識別情報
    ///   - versionInfo: 実行中アプリのバージョン情報
    /// - Returns: 差し替え可否判定結果
    public func evaluateInstallEligibility(
        appIdentity: AppIdentity,
        versionInfo: AppVersionInfo
    ) -> UpdateInstallEligibility {
        let bundleURL = currentBundleURLProvider()
        let fileManager = FileManager.default
        let resourceValues = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        let isVolumeReadOnly = resourceValues?.volumeIsReadOnly ?? false
        let isBundleWritable = fileManager.isWritableFile(atPath: bundleURL.path)
        let isParentWritable = fileManager.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path)

        return UpdateInstallEligibility.evaluate(
            appIdentity: appIdentity,
            versionInfo: versionInfo,
            bundleURL: bundleURL,
            isVolumeReadOnly: isVolumeReadOnly,
            isBundleWritable: isBundleWritable,
            isParentDirectoryWritable: isParentWritable
        )
    }

    /// 指定リリースの配布 ZIP をダウンロード・展開・署名検証し、分離ヘルパープロセスで安全な差し替えと再起動を予約する
    /// - Parameters:
    ///   - release: 適用対象の安定版リリース情報
    ///   - appIdentity: 実行中アプリの識別情報
    ///   - versionInfo: 実行中アプリのバージョン情報
    ///   - onProgress: 進捗フェーズ通知コールバック
    public func downloadVerifyAndScheduleInstall(
        release: AppReleaseInfo,
        appIdentity: AppIdentity,
        versionInfo: AppVersionInfo,
        onProgress: @escaping @Sendable (UpdateProgressPhase) -> Void
    ) async throws {
        // 1. 事前環境チェック（開発版・App Translocation・書き込み不可環境では即時拒否）
        let eligibility = evaluateInstallEligibility(appIdentity: appIdentity, versionInfo: versionInfo)
        guard eligibility.canInstallInPlace else {
            throw AppUpdateError.installNotEligible(eligibility)
        }

        guard UpdateURLValidator.isAllowedDownloadURL(release.downloadURL) else {
            throw AppUpdateError.untrustedDownloadURL
        }

        let currentBundleURL = currentBundleURLProvider()

        // 2. 現在の署名済みアプリから Team ID を取得（未署名やアドホック署名時は安全のため拒否）
        guard let currentTeamID = Self.extractTeamIdentifier(for: currentBundleURL), !currentTeamID.isEmpty else {
            Self.logger.error("現在実行中アプリの Team ID を取得できないため自動更新を中止します")
            throw AppUpdateError.teamIdentifierMismatch
        }

        // 3. 一時作業ディレクトリを作成（エラー時は必ず削除する）
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("wintch-update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        var shouldCleanupWorkDirectory = true
        defer {
            if shouldCleanupWorkDirectory {
                try? fileManager.removeItem(at: workDirectory)
            }
        }

        // 4. ZIP ダウンロード（リダイレクト先 URL 検証＋進捗通知）
        let downloadedZipURL = workDirectory.appendingPathComponent(release.assetName)
        onProgress(.downloading(fractionCompleted: 0))
        try await downloadZip(from: release.downloadURL, to: downloadedZipURL) { fraction in
            onProgress(.downloading(fractionCompleted: fraction))
        }

        // 5. SHA-256 ダイジェスト検証（API レスポンスに digest が含まれる場合）
        onProgress(.verifying)
        if let expectedSHA256 = release.expectedSHA256 {
            let actualSHA256 = try Self.computeSHA256Hex(fileURL: downloadedZipURL)
            guard actualSHA256 == expectedSHA256.lowercased() else {
                Self.logger.error("ダウンロード ZIP の SHA-256 が一致しません")
                throw AppUpdateError.checksumMismatch
            }
        }

        // 6. ditto -x -k で一時ディレクトリへ展開し、Wintch.app の存在を確認
        onProgress(.extracting)
        let extractDirectory = workDirectory.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        try Self.extractZipWithDitto(zipURL: downloadedZipURL, destinationDirectory: extractDirectory)

        let extractedAppURL = extractDirectory.appendingPathComponent("Wintch.app", isDirectory: true)
        guard fileManager.fileExists(atPath: extractedAppURL.path) else {
            throw AppUpdateError.extractionFailed("Wintch.app が見つかりませんでした。")
        }

        // 7. 展開された Wintch.app の Info.plist・コード署名・Team ID を検証
        onProgress(.verifying)
        try Self.validateExtractedAppBundleInfo(
            appBundleURL: extractedAppURL,
            expectedBundleIdentifier: AppIdentity.releaseBundleIdentifier,
            expectedVersion: release.version
        )
        try Self.verifyCodeSignature(of: extractedAppURL)

        guard let newTeamID = Self.extractTeamIdentifier(for: extractedAppURL),
              !newTeamID.isEmpty,
              newTeamID == currentTeamID else {
            Self.logger.error("ダウンロード済みアプリの Team ID が現在アプリと一致しないため更新を中止します")
            throw AppUpdateError.teamIdentifierMismatch
        }

        // 8. 分離ヘルパープロセスを起動して安全な差し替え・再起動を予約
        onProgress(.installing)
        try Self.launchReplacementHelper(
            currentPID: ProcessInfo.processInfo.processIdentifier,
            destinationAppURL: currentBundleURL,
            newAppURL: extractedAppURL,
            workDirectoryURL: workDirectory
        )

        // ヘルパープロセスが作業ディレクトリを利用し終了後に削除するため、ここでは削除しない
        shouldCleanupWorkDirectory = false
    }

    /// 指定された GitHub Release 関連 URL を既定ブラウザで開く
    /// - Parameter url: 開く対象の URL（安全でない場合は Releases 一覧へフォールバック）
    public func openReleasePage(url: URL) {
        let safeURL = UpdateURLValidator.isAllowedReleasePageURL(url) ? url : GitHubReleaseParser.releasesPageURL
        DispatchQueue.main.async {
            NSWorkspace.shared.open(safeURL)
        }
    }

    // MARK: - ダウンロード・検証・差し替えヘルパー（単体テスト可能）

    /// 指定ファイルの SHA-256 ダイジェストをストリーム読み込みで計算し小文字 64 桁 hex 文字列で返す
    /// - Parameter fileURL: 計算対象ファイルの URL
    /// - Returns: 小文字 64 桁の SHA-256 hex 文字列
    public static func computeSHA256Hex(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 65_536) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 展開された `.app` バンドルの `Info.plist` が期待する Bundle ID およびバージョンと一致するか検証する
    /// - Parameters:
    ///   - appBundleURL: 展開済み `.app` バンドル URL
    ///   - expectedBundleIdentifier: 期待する `CFBundleIdentifier`
    ///   - expectedVersion: 期待するリリースバージョン
    public static func validateExtractedAppBundleInfo(
        appBundleURL: URL,
        expectedBundleIdentifier: String,
        expectedVersion: SemanticVersion
    ) throws {
        let infoPlistURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw AppUpdateError.invalidBundleMetadata("Info.plist を読み込めませんでした。")
        }

        let bundleID = (plist["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard bundleID == expectedBundleIdentifier else {
            throw AppUpdateError.invalidBundleMetadata("Bundle ID mismatch (\(bundleID))")
        }

        let shortVersionRaw = (plist["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let shortVersion = SemanticVersion(string: shortVersionRaw), shortVersion == expectedVersion else {
            throw AppUpdateError.invalidBundleMetadata("Version mismatch (\(shortVersionRaw))")
        }
    }

    /// 差し替え・ロールバック・再起動を実行する分離ヘルパー用 POSIX シェルスクリプトを生成する
    /// - Returns: 位置引数（`$1`: PID, `$2`: 置換先 `.app`, `$3`: 新 `.app`, `$4`: 一時作業ディレクトリ）を受け取るシェルスクリプト
    public static func buildInstallHelperScript() -> String {
        """
        #!/bin/sh
        set -eu

        OLD_PID="$1"
        DEST_APP="$2"
        NEW_APP="$3"
        WORK_DIR="$4"

        cleanup_work_dir() {
            rm -rf "$WORK_DIR" >/dev/null 2>&1 || true
        }

        # 1. 現アプリの終了を最大 30 秒待機する（終了しなければ置換を中止して安全終了）
        ATTEMPTS=0
        while kill -0 "$OLD_PID" >/dev/null 2>&1; do
            ATTEMPTS=$((ATTEMPTS + 1))
            if [ "$ATTEMPTS" -ge 150 ]; then
                cleanup_work_dir
                exit 1
            fi
            sleep 0.2
        done

        # 2. 既存 .app を同一ディレクトリ（同一ボリューム上）の退避パスへ一時リネームする
        PARENT_DIR="$(dirname "$DEST_APP")"
        APP_NAME="$(basename "$DEST_APP")"
        BACKUP_APP="${PARENT_DIR}/.${APP_NAME}.wintch-backup-$$"

        if [ -e "$BACKUP_APP" ]; then
            rm -rf "$BACKUP_APP" >/dev/null 2>&1 || true
        fi

        mv "$DEST_APP" "$BACKUP_APP"

        # 3. 検証済み新 .app を元の配置パスへ移動（ボリューム跨ぎにも対応し、失敗時はロールバック復元）
        replace_app() {
            if mv "$NEW_APP" "$DEST_APP" >/dev/null 2>&1; then
                return 0
            fi
            rm -rf "$DEST_APP" >/dev/null 2>&1 || true
            if /usr/bin/ditto "$NEW_APP" "$DEST_APP" >/dev/null 2>&1; then
                return 0
            fi
            return 1
        }

        if ! replace_app; then
            rm -rf "$DEST_APP" >/dev/null 2>&1 || true
            mv "$BACKUP_APP" "$DEST_APP" >/dev/null 2>&1 || true
            cleanup_work_dir
            exit 1
        fi

        # 4. ダウンロード起因の検疫属性があれば除去し、新バージョンを起動する
        /usr/bin/xattr -dr com.apple.quarantine "$DEST_APP" >/dev/null 2>&1 || true
        /usr/bin/open -n "$DEST_APP" >/dev/null 2>&1 || true

        # 5. 退避済み旧 .app および一時作業ディレクトリを削除する
        rm -rf "$BACKUP_APP" >/dev/null 2>&1 || true
        cleanup_work_dir
        exit 0
        """
    }

    /// ダウンロード専用 URLSession でリダイレクト検証と進捗報告を行いながら ZIP を保存する
    /// - Parameters:
    ///   - url: ダウンロード元 URL
    ///   - destinationURL: 保存先一時ファイル URL
    ///   - onProgress: ダウンロード進捗コールバック
    private func downloadZip(
        from url: URL,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        let delegate = SecureDownloadSessionDelegate(
            destinationURL: destinationURL,
            onProgress: onProgress
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        let downloadSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer {
            downloadSession.finishTasksAndInvalidate()
        }

        var request = URLRequest(url: url)
        request.setValue("Wintch/\(userAgentVersion)", forHTTPHeaderField: "User-Agent")

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            delegate.setContinuation(continuation)
            let task = downloadSession.downloadTask(with: request)
            task.resume()
        }
    }

    /// `/usr/bin/ditto -x -k` を用いて ZIP を一時ディレクトリへ展開する
    /// - Parameters:
    ///   - zipURL: 展開元 ZIP ファイル URL
    ///   - destinationDirectory: 展開先ディレクトリ URL
    private static func extractZipWithDitto(zipURL: URL, destinationDirectory: URL) throws {
        let result = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", zipURL.path, destinationDirectory.path]
        )
        guard result.exitCode == 0 else {
            throw AppUpdateError.extractionFailed(result.stderr.isEmpty ? "ditto exit \(result.exitCode)" : result.stderr)
        }
    }

    /// macOS 標準のコード署名検証（Security フレームワークおよび `codesign --verify --deep --strict`）を実行する
    /// - Parameter appBundleURL: 検証対象の `.app` バンドル URL
    private static func verifyCodeSignature(of appBundleURL: URL) throws {
        // Security フレームワークによる静的コード署名検証
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(appBundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            throw AppUpdateError.codeSignatureInvalid("SecStaticCodeCreateWithPath failed (\(createStatus))")
        }
        let checkFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        let validityStatus = SecStaticCodeCheckValidity(staticCode, checkFlags, nil)
        guard validityStatus == errSecSuccess else {
            throw AppUpdateError.codeSignatureInvalid("SecStaticCodeCheckValidity failed (\(validityStatus))")
        }

        // codesign --verify --deep --strict による追加検証
        let result = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--verify", "--deep", "--strict", appBundleURL.path]
        )
        guard result.exitCode == 0 else {
            throw AppUpdateError.codeSignatureInvalid(result.stderr.isEmpty ? "codesign exit \(result.exitCode)" : result.stderr)
        }
    }

    /// 指定されたアプリバンドルの署名情報から Developer ID の Team ID を抽出する
    /// - Parameter appBundleURL: 対象の `.app` バンドル URL
    /// - Returns: 取得できた Team ID（未署名・アドホック署名・取得失敗時は nil）
    public static func extractTeamIdentifier(for appBundleURL: URL) -> String? {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(appBundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return nil
        }

        var signingInfoCF: CFDictionary?
        let infoFlags = SecCSFlags(rawValue: kSecCSSigningInformation)
        let copyStatus = SecCodeCopySigningInformation(staticCode, infoFlags, &signingInfoCF)
        guard copyStatus == errSecSuccess,
              let signingInfo = signingInfoCF as? [String: Any],
              let teamID = signingInfo[kSecCodeInfoTeamIdentifier as String] as? String else {
            return nil
        }

        let trimmed = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 差し替え・ロールバック・再起動を行う分離ヘルパープロセスを起動する
    /// - Parameters:
    ///   - currentPID: 終了待機対象の現アプリ PID
    ///   - destinationAppURL: 差し替え先となる現在アプリの `.app` URL
    ///   - newAppURL: 検証済みの新しい `.app` URL
    ///   - workDirectoryURL: 後片付け対象の一時作業ディレクトリ URL
    private static func launchReplacementHelper(
        currentPID: Int32,
        destinationAppURL: URL,
        newAppURL: URL,
        workDirectoryURL: URL
    ) throws {
        let scriptURL = workDirectoryURL.appendingPathComponent("apply-update.sh")
        let scriptContent = buildInstallHelperScript()
        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        } catch {
            throw AppUpdateError.helperLaunchFailed(error.localizedDescription)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            scriptURL.path,
            String(currentPID),
            destinationAppURL.path,
            newAppURL.path,
            workDirectoryURL.path
        ]
        // 親プロセス終了後にパイプ破断で中断されないよう標準入出力を /dev/null へ接続する
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw AppUpdateError.helperLaunchFailed(error.localizedDescription)
        }
    }

    /// 外部システムコマンドを同期実行し終了コードと標準エラー出力を返す
    /// - Parameters:
    ///   - executableURL: 実行ファイルパス
    ///   - arguments: 引数配列
    /// - Returns: 終了コードおよびトリミング済み標準エラー出力
    private static func runProcess(
        executableURL: URL,
        arguments: [String]
    ) throws -> (exitCode: Int32, stderr: String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, errorText)
    }
}
