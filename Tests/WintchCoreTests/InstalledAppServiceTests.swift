import Foundation
import Testing
@testable import WintchCore

/// InstalledAppService のバンドル走査・シンボリックリンク解決・重複排除・除外フィルタを検証するテストスイート
@Suite("InstalledAppService テスト")
struct InstalledAppServiceTests {
    /// 一時ディレクトリ上の模擬アプリ構造を走査し、有効な起動対象のみを収集・重複排除できることを検証する
    @Test("通常アプリ・サブディレクトリ・シンボリックリンクを収集し重複とバックグラウンド専用を除外する")
    @MainActor
    func scansValidAppsAndExcludesDuplicatesAndHelpers() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("WintchInstalledAppTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let primaryAppsDir = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        let utilitiesDir = primaryAppsDir.appendingPathComponent("Utilities", isDirectory: true)
        let cryptexAppsDir = tempRoot.appendingPathComponent("CryptexApps", isDirectory: true)
        let coreServicesDir = tempRoot.appendingPathComponent("CoreServices", isDirectory: true)
        try fileManager.createDirectory(at: utilitiesDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cryptexAppsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: coreServicesDir, withIntermediateDirectories: true)

        // 1. 通常のアプリ
        try createMockApp(
            at: primaryAppsDir.appendingPathComponent("Alpha.app"),
            bundleID: "com.example.alpha",
            executable: "Alpha"
        )
        // 2. サブディレクトリ内のアプリ
        try createMockApp(
            at: utilitiesDir.appendingPathComponent("Beta Tool.app"),
            bundleID: "com.example.beta",
            executable: "BetaTool"
        )
        // 3. シンボリックリンク先のアプリ（macOS の Safari.app と同様の構成）
        let realGamma = cryptexAppsDir.appendingPathComponent("Gamma.app")
        try createMockApp(
            at: realGamma,
            bundleID: "com.example.gamma",
            executable: "Gamma"
        )
        let linkGamma = primaryAppsDir.appendingPathComponent("Gamma.app")
        try fileManager.createSymbolicLink(at: linkGamma, withDestinationURL: realGamma)

        // 4. 同じ bundleIdentifier を持つ重複アプリ（別パス）は最初の1件のみ残る
        let duplicateAlphaDir = tempRoot.appendingPathComponent("UserApplications", isDirectory: true)
        try fileManager.createDirectory(at: duplicateAlphaDir, withIntermediateDirectories: true)
        try createMockApp(
            at: duplicateAlphaDir.appendingPathComponent("Alpha Duplicate.app"),
            bundleID: "com.example.alpha",
            executable: "Alpha"
        )

        // 5. LSBackgroundOnly = true のバックグラウンド専用ヘルパーは除外される
        try createMockApp(
            at: primaryAppsDir.appendingPathComponent("BackgroundAgent.app"),
            bundleID: "com.example.agent",
            executable: "Agent",
            extraPlist: ["LSBackgroundOnly": true]
        )

        // 6. 除外指定されたバンドル ID（自分自身）は除外される
        try createMockApp(
            at: primaryAppsDir.appendingPathComponent("Wintch.app"),
            bundleID: "dev.wintch.app",
            executable: "Wintch"
        )

        // 7. CFBundleExecutable の無い不完全バンドルは除外される
        let brokenApp = primaryAppsDir.appendingPathComponent("Broken.app/Contents", isDirectory: true)
        try fileManager.createDirectory(at: brokenApp, withIntermediateDirectories: true)
        let brokenPlist: [String: Any] = ["CFBundleIdentifier": "com.example.broken"]
        let brokenData = try PropertyListSerialization.data(fromPropertyList: brokenPlist, format: .xml, options: 0)
        try brokenData.write(to: brokenApp.appendingPathComponent("Info.plist"))

        // 8. directAppURLs で個別指定する Finder 相当アプリ
        let finderApp = coreServicesDir.appendingPathComponent("Finder.app")
        try createMockApp(
            at: finderApp,
            bundleID: "com.apple.finder",
            executable: "Finder"
        )

        let service = InstalledAppService(
            searchDirectories: [primaryAppsDir, duplicateAlphaDir],
            directAppURLs: [finderApp],
            excludedBundleIdentifier: "dev.wintch.app"
        )

        #expect(service.cachedInstalledApps().isEmpty)
        let discovered = await service.refreshInstalledApps()
        #expect(service.cachedInstalledApps() == discovered)

        let names = discovered.map(\.displayName)
        #expect(names == ["Alpha", "Beta Tool", "Finder", "Gamma"])
        #expect(discovered.first(where: { $0.displayName == "Gamma" })?.bundleURL == realGamma.standardizedFileURL)
    }

    /// テスト用のダミー `.app` バンドルと Info.plist を生成するヘルパー
    /// - Parameters:
    ///   - appURL: 生成先の `.app` URL
    ///   - bundleID: CFBundleIdentifier に書き込む識別子
    ///   - executable: CFBundleExecutable に書き込む実行ファイル名
    ///   - extraPlist: 追加で Info.plist に含めるキーと値
    private func createMockApp(
        at appURL: URL,
        bundleID: String,
        executable: String,
        extraPlist: [String: Any] = [:]
    ) throws {
        let contentsDir = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)

        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": executable,
            "CFBundlePackageType": "APPL"
        ]
        for (key, value) in extraPlist {
            plist[key] = value
        }

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsDir.appendingPathComponent("Info.plist"))
    }
}
