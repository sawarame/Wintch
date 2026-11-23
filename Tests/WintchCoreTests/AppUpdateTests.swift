import Foundation
import Testing
@testable import WintchCore

/// 自動バージョンアップ機能（SemVer・GitHub API 解析・URL/署名・ポリシー・永続化・ViewModel・Coordinator）の包括テストスイート
@Suite("自動バージョンアップ機能テスト")
struct AppUpdateTests {
    // MARK: - テストヘルパー

    /// テスト用の配布版 AppIdentity を生成する
    /// - Returns: 配布版 Wintch の AppIdentity
    private static func makeReleaseIdentity() -> AppIdentity {
        AppIdentity(
            infoDictionary: [
                "CFBundleDisplayName": "Wintch",
                "CFBundleIdentifier": "dev.wintch.Wintch"
            ]
        )
    }

    /// テスト用の開発版 AppIdentity を生成する
    /// - Returns: 開発版 Wintch_dev の AppIdentity
    private static func makeDevIdentity() -> AppIdentity {
        AppIdentity(
            infoDictionary: [
                "CFBundleDisplayName": "Wintch_dev",
                "CFBundleIdentifier": "dev.wintch.Wintch.dev"
            ]
        )
    }

    /// テスト用の AppVersionInfo を生成する
    /// - Parameter shortVersion: バージョン文字列
    /// - Returns: 指定バージョンを持つ AppVersionInfo
    private static func makeVersionInfo(_ shortVersion: String) -> AppVersionInfo {
        AppVersionInfo(
            infoDictionary: [
                "CFBundleShortVersionString": shortVersion,
                "CFBundleVersion": "42"
            ]
        )
    }

    /// テスト用の AppReleaseInfo を生成する
    /// - Parameters:
    ///   - version: バージョン文字列
    ///   - notes: リリースノート本文
    /// - Returns: 安定版 AppReleaseInfo
    private static func makeRelease(
        version: String = "0.4.0",
        notes: String = "- 新機能を追加しました"
    ) -> AppReleaseInfo {
        let semver = SemanticVersion(string: version)!
        return AppReleaseInfo(
            version: semver,
            tagName: "v\(semver.normalizedString)",
            releaseURL: URL(string: "https://github.com/sawarame/Wintch/releases/tag/v\(semver.normalizedString)")!,
            downloadURL: URL(string: "https://github.com/sawarame/Wintch/releases/download/v\(semver.normalizedString)/Wintch-v\(semver.normalizedString).zip")!,
            assetName: "Wintch-v\(semver.normalizedString).zip",
            expectedSHA256: nil,
            releaseNotes: notes
        )
    }

    /// 非同期条件が満たされるまで短時間ポーリング待機するテストヘルパー
    /// 並列実行される他テストの `@MainActor` 占有で 1 回の待機中に実経過時間が伸びても誤タイムアウトしないよう、
    /// 最低試行回数と十分なタイムアウト時間を併用する
    /// - Parameters:
    ///   - timeoutNanoseconds: 最大待機ナノ秒（既定 15 秒）
    ///   - minimumAttempts: 実時間に関わらず最低限保証する再試行回数（既定 50 回）
    ///   - condition: 終了条件クロージャ
    @MainActor
    private static func waitUntil(
        timeoutNanoseconds: UInt64 = 15_000_000_000,
        minimumAttempts: Int = 50,
        condition: @MainActor () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        var attempts = 0
        while !condition() {
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            if attempts >= minimumAttempts && elapsed >= timeoutNanoseconds {
                break
            }
            attempts += 1
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - SemanticVersion テスト

    /// `v` プレフィックス除去・ビルドメタデータ無視・不正形式の拒否を検証する
    @Test("SemanticVersion のパース・正規化・不正形式拒否が仕様通り動作する")
    func semanticVersionParsingAndValidation() {
        let v1 = SemanticVersion(string: "v0.3.0")
        #expect(v1 == SemanticVersion(major: 0, minor: 3, patch: 0))
        #expect(v1?.normalizedString == "0.3.0")
        #expect(v1?.isPrerelease == false)

        let v2 = SemanticVersion(string: " V1.2.3-beta.1+build.99 ")
        #expect(v2 == SemanticVersion(major: 1, minor: 2, patch: 3, prereleaseIdentifiers: ["beta", "1"]))
        #expect(v2?.normalizedString == "1.2.3-beta.1")
        #expect(v2?.isPrerelease == true)

        // 不正形式は nil を返す
        #expect(SemanticVersion(string: "") == nil)
        #expect(SemanticVersion(string: "dev") == nil)
        #expect(SemanticVersion(string: "v") == nil)
        #expect(SemanticVersion(string: "1.2") == nil)
        #expect(SemanticVersion(string: "1.2.3.4") == nil)
        #expect(SemanticVersion(string: "01.2.3") == nil)
        #expect(SemanticVersion(string: "1.02.3") == nil)
        #expect(SemanticVersion(string: "1.2.3-") == nil)
        #expect(SemanticVersion(string: "1.2.3-01") == nil)
        #expect(SemanticVersion(string: "1.2.3+") == nil)
    }

    /// SemVer 2.0 規則に従ったコアバージョンおよびプレリリース識別子の大小比較を検証する
    @Test("SemanticVersion の大小比較が SemVer 2.0 優先順位に準拠する")
    func semanticVersionComparison() {
        let ordered = [
            "0.2.6",
            "0.3.0-alpha",
            "0.3.0-alpha.1",
            "0.3.0-alpha.beta",
            "0.3.0-beta",
            "0.3.0-beta.2",
            "0.3.0-beta.11",
            "0.3.0-rc.1",
            "0.3.0",
            "0.3.1",
            "0.10.0",
            "1.0.0"
        ].compactMap { SemanticVersion(string: $0) }

        #expect(ordered.count == 12)
        for idx in 0..<(ordered.count - 1) {
            #expect(ordered[idx] < ordered[idx + 1])
            #expect(!(ordered[idx + 1] < ordered[idx]))
        }
        #expect(SemanticVersion(string: "v0.3.0") == SemanticVersion(string: "0.3.0+20261123"))
    }

    // MARK: - GitHubReleaseParser & UpdateURLValidator テスト

    /// 正常な GitHub Release JSON から ZIP アセット・SHA-256 ダイジェスト・リリースノートを抽出できることを検証する
    @Test("GitHub Releases API JSON から安定版リリースと ZIP アセットおよび digest を正しく抽出する")
    func parsesValidStableReleasePayload() throws {
        let sha = String(repeating: "a", count: 64)
        let json = """
        {
          "tag_name": "v0.4.0",
          "html_url": "https://github.com/sawarame/Wintch/releases/tag/v0.4.0",
          "body": "## 変更点\\n- 自動アップデート対応",
          "draft": false,
          "prerelease": false,
          "published_at": "2026-11-23T00:00:00Z",
          "assets": [
            {
              "name": "Wintch-v0.4.0.dmg",
              "browser_download_url": "https://github.com/sawarame/Wintch/releases/download/v0.4.0/Wintch-v0.4.0.dmg"
            },
            {
              "name": "Wintch-v0.4.0.zip",
              "browser_download_url": "https://github.com/sawarame/Wintch/releases/download/v0.4.0/Wintch-v0.4.0.zip",
              "digest": "sha256:\(sha.uppercased())"
            }
          ]
        }
        """

        let release = try GitHubReleaseParser.parseStableRelease(from: Data(json.utf8))
        #expect(release.version == SemanticVersion(major: 0, minor: 4, patch: 0))
        #expect(release.tagName == "v0.4.0")
        #expect(release.assetName == "Wintch-v0.4.0.zip")
        #expect(release.expectedSHA256 == sha)
        #expect(release.releaseNotes.contains("自動アップデート対応"))
        #expect(release.publishedAt != nil)
    }

    /// ドラフト・プレリリース・アセット欠如・非信頼 URL・不正ダイジェストを適切に拒否することを検証する
    @Test("ドラフト・プレリリース・アセット欠如・不正 URL・不正 digest を確実に拒否する")
    func rejectsInvalidOrUntrustedReleasePayloads() {
        // ドラフト除外
        let draftJSON = """
        {"tag_name":"v0.4.0","html_url":"https://github.com/sawarame/Wintch/releases/tag/v0.4.0","draft":true,"prerelease":false,"assets":[]}
        """
        #expect(throws: AppUpdateError.noStableRelease) {
            try GitHubReleaseParser.parseStableRelease(from: Data(draftJSON.utf8))
        }

        // プレリリース除外
        let prereleaseJSON = """
        {"tag_name":"v0.4.0-rc.1","html_url":"https://github.com/sawarame/Wintch/releases/tag/v0.4.0-rc.1","draft":false,"prerelease":true,"assets":[]}
        """
        #expect(throws: AppUpdateError.noStableRelease) {
            try GitHubReleaseParser.parseStableRelease(from: Data(prereleaseJSON.utf8))
        }

        // 期待アセット欠如
        let missingAssetJSON = """
        {"tag_name":"v0.4.0","html_url":"https://github.com/sawarame/Wintch/releases/tag/v0.4.0","draft":false,"prerelease":false,"assets":[{"name":"Wintch-v0.4.0.dmg","browser_download_url":"https://github.com/sawarame/Wintch/releases/download/v0.4.0/Wintch-v0.4.0.dmg"}]}
        """
        #expect(throws: AppUpdateError.missingReleaseAsset(expectedName: "Wintch-v0.4.0.zip")) {
            try GitHubReleaseParser.parseStableRelease(from: Data(missingAssetJSON.utf8))
        }

        // 外部ドメインダウンロード URL の拒否
        let evilURLJSON = """
        {"tag_name":"v0.4.0","html_url":"https://github.com/sawarame/Wintch/releases/tag/v0.4.0","draft":false,"prerelease":false,"assets":[{"name":"Wintch-v0.4.0.zip","browser_download_url":"https://evil.example.com/Wintch-v0.4.0.zip"}]}
        """
        #expect(throws: AppUpdateError.untrustedDownloadURL) {
            try GitHubReleaseParser.parseStableRelease(from: Data(evilURLJSON.utf8))
        }

        // 不正な sha256 digest 形式の拒否
        let badDigestJSON = """
        {"tag_name":"v0.4.0","html_url":"https://github.com/sawarame/Wintch/releases/tag/v0.4.0","draft":false,"prerelease":false,"assets":[{"name":"Wintch-v0.4.0.zip","browser_download_url":"https://github.com/sawarame/Wintch/releases/download/v0.4.0/Wintch-v0.4.0.zip","digest":"sha256:not-a-valid-hex"}]}
        """
        #expect(throws: AppUpdateError.invalidResponse) {
            try GitHubReleaseParser.parseStableRelease(from: Data(badDigestJSON.utf8))
        }
    }

    /// URL 検証器が HTTPS と GitHub 公式ホストのみ許可することを検証する
    @Test("UpdateURLValidator が HTTPS および GitHub 許可ホストのみを許可する")
    func urlValidatorChecksSchemeAndHost() {
        #expect(UpdateURLValidator.isAllowedDownloadURL(URL(string: "https://github.com/sawarame/Wintch/releases/download/v0.4.0/Wintch-v0.4.0.zip")!) == true)
        #expect(UpdateURLValidator.isAllowedDownloadURL(URL(string: "https://objects.githubusercontent.com/github-production-release-asset/foo")!) == true)
        #expect(UpdateURLValidator.isAllowedDownloadURL(URL(string: "https://release-assets.githubusercontent.com/bar")!) == true)

        #expect(UpdateURLValidator.isAllowedDownloadURL(URL(string: "http://github.com/sawarame/Wintch/releases/download/v0.4.0/Wintch-v0.4.0.zip")!) == false)
        #expect(UpdateURLValidator.isAllowedDownloadURL(URL(string: "https://evil.com/Wintch.zip")!) == false)
        #expect(UpdateURLValidator.isAllowedDownloadURL(URL(string: "https://githubusercontent.com.evil.com/Wintch.zip")!) == false)

        #expect(UpdateURLValidator.isAllowedReleasePageURL(URL(string: "https://github.com/sawarame/Wintch/releases/tag/v0.4.0")!) == true)
        #expect(UpdateURLValidator.isAllowedReleasePageURL(URL(string: "https://github.com/other/repo/releases")!) == false)
        #expect(UpdateURLValidator.isAllowedReleasePageURL(URL(string: "http://github.com/sawarame/Wintch/releases")!) == false)
    }

    // MARK: - UpdateCheckPolicy & UpdateInstallEligibility テスト

    /// 自動チェック実行判定・更新要否判定・スキップ判定・開発版抑止を網羅検証する
    @Test("UpdateCheckPolicy が自動チェック可否・更新要否・スキップ・開発版抑止を正しく判定する")
    func updateCheckPolicyDecisions() {
        let releaseIdentity = Self.makeReleaseIdentity()
        let devIdentity = Self.makeDevIdentity()
        let v030 = Self.makeVersionInfo("0.3.0")
        let vDev = Self.makeVersionInfo("dev")
        let rel030 = Self.makeRelease(version: "0.3.0")
        let rel040 = Self.makeRelease(version: "0.4.0")
        let rel050 = Self.makeRelease(version: "0.5.0")

        // 起動時自動チェック可否
        #expect(UpdateCheckPolicy.shouldPerformAutomaticCheck(isAutoCheckEnabled: false, appIdentity: releaseIdentity, versionInfo: v030) == false)
        #expect(UpdateCheckPolicy.shouldPerformAutomaticCheck(isAutoCheckEnabled: true, appIdentity: releaseIdentity, versionInfo: v030) == true)
        #expect(UpdateCheckPolicy.shouldPerformAutomaticCheck(isAutoCheckEnabled: true, appIdentity: devIdentity, versionInfo: v030) == false)
        #expect(UpdateCheckPolicy.shouldPerformAutomaticCheck(isAutoCheckEnabled: true, appIdentity: releaseIdentity, versionInfo: vDev) == false)

        // 最新版と同一 → upToDate
        #expect(
            UpdateCheckPolicy.evaluate(
                release: rel030,
                currentVersionInfo: v030,
                appIdentity: releaseIdentity,
                skippedVersion: nil,
                trigger: .automatic
            ) == .upToDate(currentVersion: SemanticVersion(major: 0, minor: 3, patch: 0))
        )

        // 新バージョンあり（未スキップ）→ updateAvailable
        #expect(
            UpdateCheckPolicy.evaluate(
                release: rel040,
                currentVersionInfo: v030,
                appIdentity: releaseIdentity,
                skippedVersion: nil,
                trigger: .automatic
            ) == .updateAvailable(currentVersion: SemanticVersion(major: 0, minor: 3, patch: 0), release: rel040)
        )

        // スキップ済み同一バージョン: 自動チェック時は skipped、手動確認時は updateAvailable
        #expect(
            UpdateCheckPolicy.evaluate(
                release: rel040,
                currentVersionInfo: v030,
                appIdentity: releaseIdentity,
                skippedVersion: "v0.4.0",
                trigger: .automatic
            ) == .skipped(version: SemanticVersion(major: 0, minor: 4, patch: 0))
        )
        #expect(
            UpdateCheckPolicy.evaluate(
                release: rel040,
                currentVersionInfo: v030,
                appIdentity: releaseIdentity,
                skippedVersion: "0.4.0",
                trigger: .manual
            ) == .updateAvailable(currentVersion: SemanticVersion(major: 0, minor: 3, patch: 0), release: rel040)
        )

        // スキップしたバージョンよりさらに新しいバージョン（0.5.0）は自動チェックでも通知対象
        #expect(
            UpdateCheckPolicy.evaluate(
                release: rel050,
                currentVersionInfo: v030,
                appIdentity: releaseIdentity,
                skippedVersion: "0.4.0",
                trigger: .automatic
            ) == .updateAvailable(currentVersion: SemanticVersion(major: 0, minor: 3, patch: 0), release: rel050)
        )

        // 開発版: 自動は抑止、手動は案内
        #expect(
            UpdateCheckPolicy.evaluate(
                release: rel040,
                currentVersionInfo: v030,
                appIdentity: devIdentity,
                skippedVersion: nil,
                trigger: .automatic
            ) == .suppressedDevelopmentBuild
        )
        #expect(
            UpdateCheckPolicy.evaluate(
                release: rel040,
                currentVersionInfo: v030,
                appIdentity: devIdentity,
                skippedVersion: nil,
                trigger: .manual
            ) == .developmentBuildNotice(latestRelease: rel040)
        )
    }

    /// 差し替え可否判定が開発版・App Translocation・書き込み不可・読み取り専用・通常環境を正確に区別することを検証する
    @Test("UpdateInstallEligibility が差し替え可能環境とフォールバック環境を正確に判定する")
    func installEligibilityEvaluation() {
        let releaseIdentity = Self.makeReleaseIdentity()
        let devIdentity = Self.makeDevIdentity()
        let v030 = Self.makeVersionInfo("0.3.0")
        let vDev = Self.makeVersionInfo("dev")
        let appsURL = URL(fileURLWithPath: "/Applications/Wintch.app")

        #expect(
            UpdateInstallEligibility.evaluate(
                appIdentity: releaseIdentity,
                versionInfo: v030,
                bundleURL: appsURL,
                isVolumeReadOnly: false,
                isBundleWritable: true,
                isParentDirectoryWritable: true
            ) == .eligible
        )
        #expect(
            UpdateInstallEligibility.evaluate(
                appIdentity: devIdentity,
                versionInfo: v030,
                bundleURL: appsURL,
                isVolumeReadOnly: false,
                isBundleWritable: true,
                isParentDirectoryWritable: true
            ) == .developmentBuild
        )
        #expect(
            UpdateInstallEligibility.evaluate(
                appIdentity: releaseIdentity,
                versionInfo: vDev,
                bundleURL: appsURL,
                isVolumeReadOnly: false,
                isBundleWritable: true,
                isParentDirectoryWritable: true
            ) == .developmentBuild
        )
        #expect(
            UpdateInstallEligibility.evaluate(
                appIdentity: releaseIdentity,
                versionInfo: v030,
                bundleURL: URL(fileURLWithPath: "/private/var/folders/xx/AppTranslocation/UUID/d/Wintch.app"),
                isVolumeReadOnly: false,
                isBundleWritable: true,
                isParentDirectoryWritable: true
            ) == .appTranslocated
        )
        #expect(
            UpdateInstallEligibility.evaluate(
                appIdentity: releaseIdentity,
                versionInfo: v030,
                bundleURL: URL(fileURLWithPath: "/usr/local/bin/Wintch"),
                isVolumeReadOnly: false,
                isBundleWritable: true,
                isParentDirectoryWritable: true
            ) == .notAppBundle
        )
        #expect(
            UpdateInstallEligibility.evaluate(
                appIdentity: releaseIdentity,
                versionInfo: v030,
                bundleURL: URL(fileURLWithPath: "/Volumes/Wintch/Wintch.app"),
                isVolumeReadOnly: true,
                isBundleWritable: false,
                isParentDirectoryWritable: false
            ) == .readOnlyOrUnwritable
        )
        #expect(
            UpdateInstallEligibility.evaluate(
                appIdentity: releaseIdentity,
                versionInfo: v030,
                bundleURL: appsURL,
                isVolumeReadOnly: false,
                isBundleWritable: true,
                isParentDirectoryWritable: false
            ) == .readOnlyOrUnwritable
        )
    }

    // MARK: - SHA-256・Info.plist 検証・差し替えスクリプトテスト

    /// SHA-256 算出と Info.plist 検証（一致・Bundle ID 不一致・バージョン不一致）を検証する
    @Test("AppUpdateService の SHA-256 算出と Info.plist 検証および差し替えスクリプトが正しく機能する")
    func sha256AndBundleMetadataValidation() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wintch-update-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // "abc" の標準 SHA-256 ハッシュ検証
        let sampleFile = tempDir.appendingPathComponent("sample.txt")
        try Data("abc".utf8).write(to: sampleFile)
        let digest = try AppUpdateService.computeSHA256Hex(fileURL: sampleFile)
        #expect(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

        // 正常な Info.plist 検証
        let fakeApp = tempDir.appendingPathComponent("Wintch.app", isDirectory: true)
        let contentsDir = fakeApp.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        let infoPlistURL = contentsDir.appendingPathComponent("Info.plist")

        let validPlist: [String: Any] = [
            "CFBundleIdentifier": "dev.wintch.Wintch",
            "CFBundleShortVersionString": "0.4.0"
        ]
        try PropertyListSerialization.data(fromPropertyList: validPlist, format: .xml, options: 0).write(to: infoPlistURL)
        try AppUpdateService.validateExtractedAppBundleInfo(
            appBundleURL: fakeApp,
            expectedBundleIdentifier: "dev.wintch.Wintch",
            expectedVersion: SemanticVersion(major: 0, minor: 4, patch: 0)
        )

        // Bundle ID 不一致を拒否
        let wrongIDPlist: [String: Any] = [
            "CFBundleIdentifier": "com.evil.Fake",
            "CFBundleShortVersionString": "0.4.0"
        ]
        try PropertyListSerialization.data(fromPropertyList: wrongIDPlist, format: .xml, options: 0).write(to: infoPlistURL)
        #expect(throws: AppUpdateError.invalidBundleMetadata("Bundle ID mismatch (com.evil.Fake)")) {
            try AppUpdateService.validateExtractedAppBundleInfo(
                appBundleURL: fakeApp,
                expectedBundleIdentifier: "dev.wintch.Wintch",
                expectedVersion: SemanticVersion(major: 0, minor: 4, patch: 0)
            )
        }

        // バージョン不一致を拒否
        let wrongVersionPlist: [String: Any] = [
            "CFBundleIdentifier": "dev.wintch.Wintch",
            "CFBundleShortVersionString": "0.3.9"
        ]
        try PropertyListSerialization.data(fromPropertyList: wrongVersionPlist, format: .xml, options: 0).write(to: infoPlistURL)
        #expect(throws: AppUpdateError.invalidBundleMetadata("Version mismatch (0.3.9)")) {
            try AppUpdateService.validateExtractedAppBundleInfo(
                appBundleURL: fakeApp,
                expectedBundleIdentifier: "dev.wintch.Wintch",
                expectedVersion: SemanticVersion(major: 0, minor: 4, patch: 0)
            )
        }

        // 差し替えスクリプトに退避・ロールバック・再起動手順が含まれること
        let script = AppUpdateService.buildInstallHelperScript()
        #expect(script.contains("OLD_PID=\"$1\""))
        #expect(script.contains("DEST_APP=\"$2\""))
        #expect(script.contains("BACKUP_APP="))
        #expect(script.contains("/usr/bin/open -n \"$DEST_APP\""))
    }

    // MARK: - PreferencesStore 永続化テスト

    /// `dev.wintch.autoCheckForUpdates` と `dev.wintch.skippedUpdateVersion` の初期値および永続化を検証する
    @Test("PreferencesStore が自動チェック設定（初期値 OFF）とスキップバージョンを永続化する")
    func preferencesStorePersistsUpdateSettings() {
        let suiteName = "dev.wintch.tests.update.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(suiteName: suiteName)

        // デフォルト値（オプトイン原則に従い OFF / nil）
        #expect(store.loadAutoCheckForUpdates() == false)
        #expect(store.loadSkippedUpdateVersion() == nil)

        // 保存・再読み込み
        store.saveAutoCheckForUpdates(true)
        store.saveSkippedUpdateVersion("0.4.0")
        #expect(store.loadAutoCheckForUpdates() == true)
        #expect(store.loadSkippedUpdateVersion() == "0.4.0")
        #expect(defaults.bool(forKey: "dev.wintch.autoCheckForUpdates") == true)
        #expect(defaults.string(forKey: "dev.wintch.skippedUpdateVersion") == "0.4.0")

        // 解除（OFF / nil）
        store.saveAutoCheckForUpdates(false)
        store.saveSkippedUpdateVersion(nil)
        #expect(store.loadAutoCheckForUpdates() == false)
        #expect(store.loadSkippedUpdateVersion() == nil)
    }

    // MARK: - SettingsViewModel 手動確認・設定トグルテスト

    /// 設定画面の自動チェックトグル初期値・永続化と手動確認の全状態遷移を検証する
    @Test("SettingsViewModel の自動チェック設定と手動確認（最新・新バージョン・スキップ再提示・開発版・エラー・重複防止）")
    @MainActor
    func settingsViewModelManualUpdateCheckFlows() async {
        let store = MockPreferencesStore()
        store.storedSkippedUpdateVersion = "0.4.0"
        let updateService = MockAppUpdateService()
        let release040 = Self.makeRelease(version: "0.4.0")
        let release030 = Self.makeRelease(version: "0.3.0")

        let viewModel = SettingsViewModel(
            preferencesStore: store,
            hotKeyMonitor: MockHotKeyMonitor(),
            launchAtLoginService: MockLaunchAtLoginService(),
            permissionService: MockAccessibilityPermissionService(),
            updateService: updateService,
            appIdentity: Self.makeReleaseIdentity(),
            versionInfo: Self.makeVersionInfo("0.3.0")
        )

        // 初期値は OFF
        #expect(viewModel.isAutoCheckForUpdatesEnabled == false)
        viewModel.setAutoCheckForUpdates(true)
        #expect(viewModel.isAutoCheckForUpdatesEnabled == true)
        #expect(store.storedAutoCheckForUpdates == true)

        // 1. 最新版ケース
        updateService.stubbedReleaseResult = .success(release030)
        viewModel.checkForUpdatesManually()
        await Self.waitUntil { !viewModel.isCheckingForUpdates }
        #expect(viewModel.manualUpdateCheckState == .upToDate)
        #expect(viewModel.manualUpdateStatusMessage == AppStrings.japanese.settingsUpToDateMessage)

        // 2. 新バージョンあり（過去スキップ済みでも手動確認ならコールバック発火して再提示される）
        var promptedRelease: AppReleaseInfo?
        viewModel.onUpdateAvailable = { release, _ in
            promptedRelease = release
        }
        updateService.stubbedReleaseResult = .success(release040)
        viewModel.checkForUpdatesManually()
        await Self.waitUntil { !viewModel.isCheckingForUpdates }
        #expect(viewModel.manualUpdateCheckState == .updateAvailable(release040.version))
        #expect(promptedRelease == release040)

        // 3. エラーケース
        updateService.stubbedReleaseResult = .failure(AppUpdateError.rateLimited)
        viewModel.checkForUpdatesManually()
        await Self.waitUntil { !viewModel.isCheckingForUpdates }
        #expect(viewModel.manualUpdateCheckState == .failed(.rateLimited))
        #expect(viewModel.shouldShowOpenReleasesLink == true)
        viewModel.openUpdateReleasePage()
        #expect(updateService.openedURLs.last == GitHubReleaseParser.releasesPageURL)

        // 4. 確認中の重複実行防止
        let countBefore = updateService.fetchCallCount
        updateService.fetchHandler = {
            try? await Task.sleep(nanoseconds: 80_000_000)
            return release030
        }
        viewModel.checkForUpdatesManually()
        viewModel.checkForUpdatesManually()
        #expect(viewModel.isCheckingForUpdates == true)
        await Self.waitUntil { !viewModel.isCheckingForUpdates }
        #expect(updateService.fetchCallCount == countBefore + 1)

        // 5. ローカル開発版の手動確認は開発版案内＋リリースページ誘導になる
        let devUpdateService = MockAppUpdateService()
        devUpdateService.stubbedReleaseResult = .success(release040)
        let devViewModel = SettingsViewModel(
            preferencesStore: MockPreferencesStore(),
            hotKeyMonitor: MockHotKeyMonitor(),
            launchAtLoginService: MockLaunchAtLoginService(),
            permissionService: MockAccessibilityPermissionService(),
            updateService: devUpdateService,
            appIdentity: Self.makeDevIdentity(),
            versionInfo: Self.makeVersionInfo("0.3.0")
        )
        devViewModel.checkForUpdatesManually()
        await Self.waitUntil { !devViewModel.isCheckingForUpdates }
        #expect(devViewModel.manualUpdateCheckState == .developmentBuild(latestRelease: release040))
        #expect(devViewModel.shouldShowOpenReleasesLink == true)
        #expect(devViewModel.manualUpdateReleaseURL == release040.releaseURL)
    }

    // MARK: - UpdateViewModel 状態遷移テスト

    /// 更新確認ダイアログの「後で」「スキップ」「今すぐアップデート」「署名エラー」「差し替え不可フォールバック」を検証する
    @Test("UpdateViewModel の各アクション・進捗遷移・エラー・フォールバックが仕様通り動作する")
    @MainActor
    func updateViewModelActionsAndTransitions() async {
        let store = MockPreferencesStore()
        let updateService = MockAppUpdateService()
        let release = Self.makeRelease(version: "0.4.0")
        let current = SemanticVersion(major: 0, minor: 3, patch: 0)

        let viewModel = UpdateViewModel(
            updateService: updateService,
            preferencesStore: store,
            appIdentity: Self.makeReleaseIdentity(),
            versionInfo: Self.makeVersionInfo("0.3.0")
        )

        var closeCount = 0
        var quitCount = 0
        viewModel.onCloseRequested = { closeCount += 1 }
        viewModel.onQuitForRestartRequested = { quitCount += 1 }

        viewModel.present(release: release, currentVersion: current)
        #expect(viewModel.canInstallInPlace == true)
        #expect(viewModel.phase == .ready)

        // 「後で」はスキップ保存せずダイアログ閉鎖のみ
        viewModel.deferUpdate()
        #expect(closeCount == 1)
        #expect(store.storedSkippedUpdateVersion == nil)

        // 「このバージョンをスキップ」は永続化＋閉鎖
        viewModel.skipThisVersion()
        #expect(closeCount == 2)
        #expect(store.storedSkippedUpdateVersion == "0.4.0")

        // 「GitHub で変更内容を見る」
        viewModel.openReleasePage()
        #expect(updateService.openedURLs.last == release.releaseURL)

        // 「今すぐアップデート」成功フロー
        viewModel.startUpdate()
        await Self.waitUntil { quitCount == 1 }
        #expect(updateService.installCallCount == 1)
        #expect(quitCount == 1)

        // 署名／Team ID 検証エラー時は終了せずエラー表示へ遷移
        let failingService = MockAppUpdateService()
        failingService.installHandler = { _, _ in
            throw AppUpdateError.teamIdentifierMismatch
        }
        let failingVM = UpdateViewModel(
            updateService: failingService,
            preferencesStore: MockPreferencesStore(),
            appIdentity: Self.makeReleaseIdentity(),
            versionInfo: Self.makeVersionInfo("0.3.0")
        )
        var failQuitCount = 0
        failingVM.onQuitForRestartRequested = { failQuitCount += 1 }
        failingVM.present(release: release, currentVersion: current)
        failingVM.startUpdate()
        await Self.waitUntil { !failingVM.isUpdating }
        #expect(failingVM.phase == .failed(.teamIdentifierMismatch))
        #expect(failingVM.errorMessage != nil)
        #expect(failQuitCount == 0)

        // App Translocation 等の差し替え不可環境ではフォールバック表示となり自動差し替えを実行しない
        let translocatedService = MockAppUpdateService()
        translocatedService.stubbedEligibility = .appTranslocated
        let translocatedVM = UpdateViewModel(
            updateService: translocatedService,
            preferencesStore: MockPreferencesStore(),
            appIdentity: Self.makeReleaseIdentity(),
            versionInfo: Self.makeVersionInfo("0.3.0")
        )
        translocatedVM.present(release: release, currentVersion: current)
        #expect(translocatedVM.canInstallInPlace == false)
        #expect(translocatedVM.eligibilityNoticeMessage != nil)
        translocatedVM.startUpdate()
        #expect(translocatedService.installCallCount == 0)
        #expect(translocatedVM.phase == .failed(.installNotEligible(.appTranslocated)))
    }

    // MARK: - AppCoordinator 起動時自動チェック統合テスト

    /// 自動チェック OFF または開発版では起動時に一切ネットワーク通信を行わないことを検証する
    @Test("AppCoordinator は自動チェック OFF 時および開発版起動時にバージョン確認通信を一切行わない")
    @MainActor
    func coordinatorDoesNotCheckWhenDisabledOrDevelopment() async {
        let release = Self.makeRelease(version: "0.4.0")

        // 1. デフォルト OFF（配布版）
        let offService = MockAppUpdateService()
        offService.stubbedReleaseResult = .success(release)
        let offCoordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            preferencesStore: MockPreferencesStore(),
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            windowFrontPresenter: MockWindowFrontPresenter(),
            updateService: offService,
            appIdentity: Self.makeReleaseIdentity(),
            versionInfo: Self.makeVersionInfo("0.3.0")
        )
        offCoordinator.start()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(offService.fetchCallCount == 0)
        #expect(offCoordinator.isUpdatePromptPresented == false)

        // 2. ON だが開発版（Wintch_dev）
        let devStore = MockPreferencesStore()
        devStore.storedAutoCheckForUpdates = true
        let devService = MockAppUpdateService()
        devService.stubbedReleaseResult = .success(release)
        let devCoordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            preferencesStore: devStore,
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            windowFrontPresenter: MockWindowFrontPresenter(),
            updateService: devService,
            appIdentity: Self.makeDevIdentity(),
            versionInfo: Self.makeVersionInfo("0.3.0")
        )
        devCoordinator.start()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(devService.fetchCallCount == 0)
        #expect(devCoordinator.isUpdatePromptPresented == false)
    }

    /// 自動チェック ON・新バージョンありでダイアログ表示、スキップ時・通信エラー時はサイレント抑止されることを検証する
    @Test("AppCoordinator の起動時自動チェック（新バージョン提示・スキップ抑止・エラー時サイレント）")
    @MainActor
    func coordinatorAutomaticCheckSuccessSkipAndSilentError() async {
        let release = Self.makeRelease(version: "0.4.0")

        // 1. 新バージョン検出 → 更新確認ダイアログを最前面表示
        let store = MockPreferencesStore()
        store.storedAutoCheckForUpdates = true
        let service = MockAppUpdateService()
        service.stubbedReleaseResult = .success(release)
        let presenter = MockWindowFrontPresenter()
        let coordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            preferencesStore: store,
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            windowFrontPresenter: presenter,
            updateService: service,
            appIdentity: Self.makeReleaseIdentity(),
            versionInfo: Self.makeVersionInfo("0.3.0")
        )

        coordinator.start()
        await Self.waitUntil { !coordinator.isAutomaticUpdateCheckRunning }
        #expect(service.fetchCallCount == 1)
        #expect(coordinator.isUpdatePromptPresented == true)
        #expect(coordinator.updateViewModel.release == release)
        #expect(presenter.presentedWindows.count == 1)

        // 2. スキップ済み同一バージョン → ダイアログ非表示
        let skippedStore = MockPreferencesStore()
        skippedStore.storedAutoCheckForUpdates = true
        skippedStore.storedSkippedUpdateVersion = "0.4.0"
        let skippedService = MockAppUpdateService()
        skippedService.stubbedReleaseResult = .success(release)
        let skippedCoordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            preferencesStore: skippedStore,
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            windowFrontPresenter: MockWindowFrontPresenter(),
            updateService: skippedService,
            appIdentity: Self.makeReleaseIdentity(),
            versionInfo: Self.makeVersionInfo("0.3.0")
        )
        skippedCoordinator.start()
        await Self.waitUntil { !skippedCoordinator.isAutomaticUpdateCheckRunning }
        #expect(skippedService.fetchCallCount == 1)
        #expect(skippedCoordinator.isUpdatePromptPresented == false)

        // 3. 通信エラー → サイレント終了（ダイアログ非表示）
        let errorStore = MockPreferencesStore()
        errorStore.storedAutoCheckForUpdates = true
        let errorService = MockAppUpdateService()
        errorService.stubbedReleaseResult = .failure(AppUpdateError.networkError("offline"))
        let errorCoordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            preferencesStore: errorStore,
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            windowFrontPresenter: MockWindowFrontPresenter(),
            updateService: errorService,
            appIdentity: Self.makeReleaseIdentity(),
            versionInfo: Self.makeVersionInfo("0.3.0")
        )
        errorCoordinator.start()
        await Self.waitUntil { !errorCoordinator.isAutomaticUpdateCheckRunning }
        #expect(errorService.fetchCallCount == 1)
        #expect(errorCoordinator.isUpdatePromptPresented == false)
    }

    /// アクセシビリティ権限誘導画面の表示中は更新ダイアログを保留し、権限許可後に提示されることを検証する
    @Test("権限誘導画面表示中の自動アップデート検出は保留され、権限許可後に更新ダイアログが表示される")
    @MainActor
    func coordinatorDefersUpdatePromptWhilePermissionGuideIsPresented() async {
        let release = Self.makeRelease(version: "0.4.0")
        let store = MockPreferencesStore()
        store.storedAutoCheckForUpdates = true
        let service = MockAppUpdateService()
        service.stubbedReleaseResult = .success(release)
        let permissionService = MockAccessibilityPermissionService()
        permissionService.stubbedStatus = .denied
        let presenter = MockWindowFrontPresenter()

        let coordinator = AppCoordinator(
            windowService: MockWindowService(),
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: permissionService,
            preferencesStore: store,
            launchAtLoginService: MockLaunchAtLoginService(),
            iconProvider: MockIconProvider(),
            installedAppService: MockInstalledAppService(),
            windowFrontPresenter: presenter,
            updateService: service,
            appIdentity: Self.makeReleaseIdentity(),
            versionInfo: Self.makeVersionInfo("0.3.0")
        )

        coordinator.start()
        await Self.waitUntil { !coordinator.isAutomaticUpdateCheckRunning }
        #expect(service.fetchCallCount == 1)

        // 権限誘導画面表示中は更新確認ダイアログを重複表示しない
        #expect(coordinator.isPermissionGuidePresented == true)
        #expect(coordinator.isUpdatePromptPresented == false)

        // アクセシビリティ権限が許可されると誘導画面が閉じ、保留していた更新確認ダイアログが提示される
        permissionService.simulateStatusChange(.granted)
        #expect(coordinator.isPermissionGuidePresented == false)
        #expect(coordinator.isUpdatePromptPresented == true)
        #expect(coordinator.updateViewModel.release == release)
    }
}
