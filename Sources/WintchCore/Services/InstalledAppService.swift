import AppKit
import Foundation

/// 標準のアプリケーションディレクトリから起動可能アプリを収集し、NSWorkspace で起動するサービス
@MainActor
public final class InstalledAppService: InstalledAppServicing {
    /// アプリ起動要求の実行に使用するハンドラ型（テスト差し替え用）
    public typealias OpenApplicationHandler = @MainActor (URL, NSWorkspace.OpenConfiguration) -> Void

    /// 走査対象とするディレクトリの最大階層深さ
    private nonisolated static let maxScanDepth = 3

    /// アプリ検索対象ルートディレクトリ一覧
    private let searchDirectories: [URL]

    /// ルート外から個別に追加するアプリバンドル URL 一覧（Finder 等）
    private let directAppURLs: [URL]

    /// 候補から除外するバンドル識別子（自分自身など）
    private let excludedBundleIdentifier: String?

    /// テスト時に NSWorkspace.openApplication 呼び出しを差し替えるための任意ハンドラ
    private let openApplicationHandler: OpenApplicationHandler?

    /// メモリ上にキャッシュされた起動可能アプリ一覧
    private var cachedApps: [LaunchableApp] = []

    /// 現在進行中の非同期スキャンタスク（多重実行抑制用）
    private var inFlightRefreshTask: Task<[LaunchableApp], Never>?

    /// 標準の macOS アプリケーションディレクトリ構成でサービスを初期化する
    public convenience init() {
        let homeApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        self.init(
            searchDirectories: [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                URL(fileURLWithPath: "/System/Applications", isDirectory: true),
                homeApps,
                URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true)
            ],
            directAppURLs: [
                URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)
            ],
            excludedBundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    /// テストやカスタマイズ用に探索先ディレクトリを指定してサービスを初期化する
    /// - Parameters:
    ///   - searchDirectories: 再帰走査するアプリケーションディレクトリ一覧
    ///   - directAppURLs: 直接候補に含める `.app` バンドル URL 一覧
    ///   - excludedBundleIdentifier: 除外対象のバンドル識別子
    ///   - openApplicationHandler: テスト時に起動処理を差し替えるための任意ハンドラ（通常は nil）
    public init(
        searchDirectories: [URL],
        directAppURLs: [URL] = [],
        excludedBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        openApplicationHandler: OpenApplicationHandler? = nil
    ) {
        self.searchDirectories = searchDirectories
        self.directAppURLs = directAppURLs
        self.excludedBundleIdentifier = excludedBundleIdentifier
        self.openApplicationHandler = openApplicationHandler
    }

    /// 現在メモリ上にキャッシュされている起動可能アプリ一覧を同期で返す
    /// - Returns: キャッシュ済みの起動可能アプリ配列
    public func cachedInstalledApps() -> [LaunchableApp] {
        cachedApps
    }

    /// バックグラウンドスレッドでアプリケーションディレクトリを走査し、キャッシュを更新して返す
    /// - Returns: 最新の起動可能アプリ配列
    @discardableResult
    public func refreshInstalledApps() async -> [LaunchableApp] {
        if let existingTask = inFlightRefreshTask {
            return await existingTask.value
        }

        let directories = searchDirectories
        let directApps = directAppURLs
        let excludedID = excludedBundleIdentifier

        let task = Task.detached(priority: .userInitiated) {
            Self.scanInstalledApps(
                in: directories,
                directAppURLs: directApps,
                excludedBundleIdentifier: excludedID
            )
        }
        inFlightRefreshTask = task
        let latestApps = await task.value
        inFlightRefreshTask = nil
        cachedApps = latestApps
        return latestApps
    }

    /// 指定されたアプリケーションを NSWorkspace 経由で起動（または前面化）する
    /// - Parameter app: 起動対象のアプリケーション情報
    public func launchApplication(_ app: LaunchableApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let openApplicationHandler {
            openApplicationHandler(app.bundleURL, configuration)
            return
        }
        // LaunchServices のバックグラウンドキュー上で @MainActor 分離クロージャが呼ばれてクラッシュするのを防ぐため completionHandler は nil を渡す
        NSWorkspace.shared.openApplication(at: app.bundleURL, configuration: configuration, completionHandler: nil)
    }

    /// 指定されたディレクトリ群および個別 URL から起動可能なアプリ一覧を同期スキャンする
    /// - Parameters:
    ///   - directories: 走査対象ディレクトリ配列
    ///   - directAppURLs: 個別確認するアプリバンドル URL 配列
    ///   - excludedBundleIdentifier: 除外するバンドル識別子
    /// - Returns: 重複排除および名前順ソート済みの起動可能アプリ配列
    nonisolated static func scanInstalledApps(
        in directories: [URL],
        directAppURLs: [URL],
        excludedBundleIdentifier: String?
    ) -> [LaunchableApp] {
        var collectedApps: [LaunchableApp] = []
        var seenKeys: Set<String> = []
        var visitedDirectories: Set<String> = []

        for directory in directories {
            collectApps(
                in: directory,
                depth: 0,
                excludedBundleIdentifier: excludedBundleIdentifier,
                visitedDirectories: &visitedDirectories,
                seenKeys: &seenKeys,
                into: &collectedApps
            )
        }

        for appURL in directAppURLs {
            appendIfValidApp(
                at: appURL,
                excludedBundleIdentifier: excludedBundleIdentifier,
                seenKeys: &seenKeys,
                into: &collectedApps
            )
        }

        return collectedApps.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    /// 単一ディレクトリ内を再帰的に走査して `.app` バンドルを収集する
    /// - Parameters:
    ///   - directory: 走査対象ディレクトリ URL
    ///   - depth: 現在の探索深度
    ///   - excludedBundleIdentifier: 除外対象のバンドル識別子
    ///   - visitedDirectories: 循環シンボリックリンク防止用の訪問済みパス集合
    ///   - seenKeys: 重複登録防止用のアプリ識別キー集合
    ///   - apps: 収集結果の格納先配列
    private nonisolated static func collectApps(
        in directory: URL,
        depth: Int,
        excludedBundleIdentifier: String?,
        visitedDirectories: inout Set<String>,
        seenKeys: inout Set<String>,
        into apps: inout [LaunchableApp]
    ) {
        let resolvedDir = directory.resolvingSymlinksInPath().standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedDir.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        // 同じ実体ディレクトリの重複走査および循環リンクを防ぐ
        guard visitedDirectories.insert(resolvedDir.path).inserted else {
            return
        }

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for childURL in children {
            if childURL.pathExtension.lowercased() == "app" {
                appendIfValidApp(
                    at: childURL,
                    excludedBundleIdentifier: excludedBundleIdentifier,
                    seenKeys: &seenKeys,
                    into: &apps
                )
                continue
            }

            guard depth < maxScanDepth else { continue }
            let resolvedChild = childURL.resolvingSymlinksInPath().standardizedFileURL
            var childIsDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: resolvedChild.path, isDirectory: &childIsDir),
               childIsDir.boolValue {
                collectApps(
                    in: childURL,
                    depth: depth + 1,
                    excludedBundleIdentifier: excludedBundleIdentifier,
                    visitedDirectories: &visitedDirectories,
                    seenKeys: &seenKeys,
                    into: &apps
                )
            }
        }
    }

    /// 指定 URL が起動可能なアプリバンドルであれば情報を抽出し、未登録の場合のみ結果配列へ追加する
    /// - Parameters:
    ///   - appURL: 検査対象の `.app` URL（シンボリックリンク可）
    ///   - excludedBundleIdentifier: 除外するバンドル識別子
    ///   - seenKeys: 重複チェック用の識別キー集合
    ///   - apps: 格納先配列
    private nonisolated static func appendIfValidApp(
        at appURL: URL,
        excludedBundleIdentifier: String?,
        seenKeys: inout Set<String>,
        into apps: inout [LaunchableApp]
    ) {
        guard appURL.pathExtension.lowercased() == "app" else { return }

        let resolvedURL = appURL.resolvingSymlinksInPath().standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        guard let bundle = Bundle(url: resolvedURL),
              let info = bundle.infoDictionary else {
            return
        }

        // 実行バイナリを持たないダミーバンドルやバックグラウンド専用プロセスは除外する
        guard let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty else {
            return
        }
        if isTruthyFlag(info["LSBackgroundOnly"]) {
            return
        }

        let bundleIdentifier = bundle.bundleIdentifier
        if let excludedBundleIdentifier,
           let bundleIdentifier,
           bundleIdentifier == excludedBundleIdentifier {
            return
        }

        let dedupKey = bundleIdentifier ?? resolvedURL.path
        guard seenKeys.insert(dedupKey).inserted else {
            return
        }

        let rawFileName = appURL.deletingPathExtension().lastPathComponent
        let localizedDisplay = stripAppExtension(from: FileManager.default.displayName(atPath: appURL.path))
        let displayName = localizedDisplay.isEmpty ? rawFileName : localizedDisplay
        let alternateName = rawFileName.caseInsensitiveCompare(displayName) == .orderedSame ? "" : rawFileName

        apps.append(
            LaunchableApp(
                id: resolvedURL.path,
                displayName: displayName,
                alternateName: alternateName,
                bundleIdentifier: bundleIdentifier,
                bundleURL: resolvedURL
            )
        )
    }

    /// Info.plist 内の真偽フラグ値（Bool / NSNumber / String）を判定する
    /// - Parameter value: Info.plist から取得した任意の値
    /// - Returns: 真とみなせる場合は true
    private nonisolated static func isTruthyFlag(_ value: Any?) -> Bool {
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }
        if let stringValue = value as? String {
            let lowered = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lowered == "1" || lowered == "true" || lowered == "yes"
        }
        return false
    }

    /// 表示名末尾に付与された ".app" 拡張子を大文字小文字を区別せず取り除く
    /// - Parameter name: FileManager から取得した表示名
    /// - Returns: 拡張子を除去した表示名
    private nonisolated static func stripAppExtension(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasSuffix(".app") {
            return String(trimmed.dropLast(4))
        }
        return trimmed
    }
}
