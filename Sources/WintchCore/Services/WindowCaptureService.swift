import AppKit
import CoreGraphics
import Foundation
import os
import OSLog
@preconcurrency import ScreenCaptureKit

/// ScreenCaptureKit を用いてウィンドウサムネイルを非同期取得し、上限付き LRU メモリキャッシュを管理するサービス実装
@MainActor
public final class WindowCaptureService: WindowCaptureServicing {
    /// 診断ログ出力用ロガー（ウィンドウ ID・件数・エラーコードのみ出力し、画像内容やタイトルは出力しない）
    private static let logger = Logger(subsystem: "dev.wintch.Wintch", category: "WindowCaptureService")

    /// スレッド境界を跨いで SCWindow 参照を受け渡すための Sendable ラッパー
    private struct SendableSCWindow: @unchecked Sendable {
        let value: SCWindow
    }

    /// 単一ウィンドウの非同期キャプチャ結果を表す Sendable 列挙型
    private enum SingleCaptureResult: Sendable {
        /// サムネイル画像の取得成功
        case captured(UInt32, CGImage)
        /// 画面収録権限の拒否・不足による失敗
        case permissionDenied(windowID: UInt32, errorCode: Int)
        /// 権限以外の一時的失敗またはタイムアウト
        case failed(windowID: UInt32, isOnScreen: Bool, reason: String)
    }

    /// タイムアウト付き非同期レースの状態管理構造体
    private struct TimeoutRaceState: Sendable {
        var didResume = false
        var isCancelled = false
        var operationTask: Task<Void, Never>?
        var timeoutTask: Task<Void, Never>?
    }

    /// メモリキャッシュに格納するサムネイル画像と最終取得時刻の組
    private struct CachedThumbnailEntry {
        /// 取得済みのサムネイル画像（メモリ限定）
        let image: NSImage
        /// サムネイルを最後に取得・格納した時刻
        let capturedAt: Date
    }

    /// メモリ内サムネイルキャッシュのデフォルト最大保持件数（FR-003）
    public static let defaultMaxCacheCount = 100

    /// 非同期キャプチャの最大同時実行数
    private static let maxConcurrentCaptures = 4

    /// 1 ウィンドウあたりのキャプチャタイムアウト時間（秒）
    private static let captureTimeoutSeconds: TimeInterval = 1.5

    /// 画面収録権限状態を共有するためのサービス（省略時は内部状態と CGPreflight のみ使用）
    private let screenRecordingPermissionService: (any ScreenRecordingPermissionServicing)?

    /// メモリ内サムネイルキャッシュの最大保持件数
    private let maxCacheCount: Int

    /// キャプチャ完了時のタイムスタンプ記録に用いる現在時刻プロバイダ（テスト用に注入可能）
    private let nowProvider: @Sendable () -> Date

    /// 実行中プロセス内で ScreenCaptureKit による権限拒否エラーを検知したかどうか
    private var isAccessDeniedInSession = false

    /// ウィンドウ ID ごとのサムネイル画像および最終取得時刻キャッシュ（メモリ限定・ディスク非保存）
    private var thumbnailCache: [UInt32: CachedThumbnailEntry] = [:]

    /// LRU 順序管理配列（末尾ほど最近利用されたエントリ）
    private(set) var cacheOrder: [UInt32] = []

    /// キャッシュ全消去の世代カウンタ（非同期取得中のクリア後に古い結果が再混入するのを防ぐ）
    private var cacheEpoch: Int = 0

    /// 進行中の非同期キャプチャセッション中に明示無効化されたウィンドウ ID 集合
    private var invalidatedWindowIDsDuringCapture: Set<UInt32> = []

    /// サービスを初期化する
    /// - Parameters:
    ///   - screenRecordingPermissionService: 画面収録権限状態を共有するサービス
    ///   - maxCacheCount: メモリ内サムネイルキャッシュの最大保持件数（1 未満は 1 に正規化）
    ///   - nowProvider: 現在時刻を返すクロージャ（既定値は `Date.init`）
    public init(
        screenRecordingPermissionService: (any ScreenRecordingPermissionServicing)? = nil,
        maxCacheCount: Int = defaultMaxCacheCount,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.screenRecordingPermissionService = screenRecordingPermissionService
        self.maxCacheCount = max(maxCacheCount, 1)
        self.nowProvider = nowProvider
    }

    /// メモリ上のキャッシュから指定ウィンドウのサムネイルを同期取得する
    /// - Parameter cgWindowID: 対象の CoreGraphics ウィンドウ ID
    /// - Returns: キャッシュ済みのサムネイル画像（未保持の場合は nil）
    public func cachedThumbnail(for cgWindowID: UInt32) -> NSImage? {
        guard let entry = thumbnailCache[cgWindowID] else { return nil }
        touchCacheOrder(for: cgWindowID)
        return entry.image
    }

    /// 指定ウィンドウのサムネイルがメモリキャッシュに存在するかを確認する（LRU 順序は変更しない）
    /// - Parameter cgWindowID: 確認対象の CoreGraphics ウィンドウ ID
    /// - Returns: キャッシュに保持されていれば true
    public func hasCachedThumbnail(for cgWindowID: UInt32) -> Bool {
        thumbnailCache[cgWindowID] != nil
    }

    /// 指定ウィンドウのサムネイルがメモリキャッシュへ最後に格納された時刻を返す（LRU 順序は変更しない）
    /// - Parameter cgWindowID: 確認対象の CoreGraphics ウィンドウ ID
    /// - Returns: キャッシュに保持されていれば最終取得時刻、未保持の場合は nil
    public func lastCapturedAt(for cgWindowID: UInt32) -> Date? {
        thumbnailCache[cgWindowID]?.capturedAt
    }

    /// 指定ウィンドウ群の最新サムネイルを非同期取得し、完了したものから順次通知する
    /// - Parameters:
    ///   - cgWindowIDs: 取得対象の CoreGraphics ウィンドウ ID 配列
    ///   - maxPixelSize: 出力サムネイルの上限ピクセルサイズ
    ///   - onCaptured: 1 件取得完了するたびに呼ばれるメインアクター上の通知クロージャ
    public func captureThumbnails(
        for cgWindowIDs: [UInt32],
        maxPixelSize: CGSize,
        onCaptured: @escaping @MainActor (UInt32, NSImage) -> Void
    ) async {
        // 防御的チェック: 権限未許可・セッション内失効時は OS ダイアログを誘発する ScreenCaptureKit API を呼ばない
        guard !cgWindowIDs.isEmpty, hasScreenRecordingPermission() else {
            return
        }

        let targetIDSet = Set(cgWindowIDs)
        let shareableWindowsByID: [UInt32: SendableSCWindow]
        do {
            shareableWindowsByID = try await Self.fetchShareableWindows(for: targetIDSet)
        } catch {
            let nsError = error as NSError
            let isDenied = Self.isPermissionDeniedError(error)
            Self.logger.info(
                "SCShareableContent 取得失敗: domain=\(nsError.domain, privacy: .public) code=\(nsError.code) permissionDenied=\(isDenied)"
            )
            // 再ビルドや権限変更で TCC が拒否を返した場合はセッション内失効として記録し、次回以降の OS ダイアログ再発を防ぐ
            if isDenied {
                handlePermissionDenied()
            }
            return
        }

        guard !Task.isCancelled else { return }

        // 画面表示中（isOnScreen）のウィンドウを優先し、各群内では呼び出し元指定順（MRU・未キャッシュ優先）を維持する
        let requestedTargets = cgWindowIDs.compactMap { shareableWindowsByID[$0] }
        let onScreenTargets = requestedTargets.filter(\.value.isOnScreen)
        let offScreenTargets = requestedTargets.filter { !$0.value.isOnScreen }
        let orderedTargets = onScreenTargets + offScreenTargets
        let missingCount = cgWindowIDs.count - requestedTargets.count
        Self.logger.debug(
            "キャプチャ開始: requested=\(cgWindowIDs.count) matched=\(orderedTargets.count) onScreen=\(onScreenTargets.count) offScreen=\(offScreenTargets.count) missing=\(missingCount)"
        )
        guard !orderedTargets.isEmpty else { return }

        let capturedEpoch = cacheEpoch
        invalidatedWindowIDsDuringCapture.removeAll()
        var succeededCount = 0
        var failedOnScreenCount = 0
        var failedOffScreenCount = 0

        await withTaskGroup(of: SingleCaptureResult.self) { group in
            var nextIndex = 0
            let initialBatch = min(Self.maxConcurrentCaptures, orderedTargets.count)

            for _ in 0..<initialBatch {
                let target = orderedTargets[nextIndex]
                nextIndex += 1
                group.addTask {
                    await Self.captureSingleWindow(target, maxPixelSize: maxPixelSize)
                }
            }

            while let result = await group.next() {
                if Task.isCancelled || cacheEpoch != capturedEpoch {
                    group.cancelAll()
                    break
                }

                if case let .permissionDenied(windowID, errorCode) = result {
                    Self.logger.info(
                        "キャプチャ中に画面収録権限拒否を検知: windowID=\(windowID) code=\(errorCode)"
                    )
                    // 実行中の権限取り消しを検知した時点で残りのキャプチャを中断する
                    handlePermissionDenied()
                    group.cancelAll()
                    return
                }

                if nextIndex < orderedTargets.count {
                    let target = orderedTargets[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await Self.captureSingleWindow(target, maxPixelSize: maxPixelSize)
                    }
                }

                switch result {
                case let .captured(windowID, cgImage):
                    if !invalidatedWindowIDsDuringCapture.contains(windowID) {
                        let nsImage = NSImage(
                            cgImage: cgImage,
                            size: NSSize(width: cgImage.width, height: cgImage.height)
                        )
                        storeInCache(nsImage, for: windowID)
                        succeededCount += 1
                        onCaptured(windowID, nsImage)
                    }
                case let .failed(windowID, isOnScreen, reason):
                    if isOnScreen {
                        failedOnScreenCount += 1
                    } else {
                        failedOffScreenCount += 1
                    }
                    Self.logger.debug(
                        "単一キャプチャ失敗: windowID=\(windowID) isOnScreen=\(isOnScreen) reason=\(reason, privacy: .public)"
                    )
                case .permissionDenied:
                    break
                }
            }
        }

        Self.logger.debug(
            "キャプチャ完了: succeeded=\(succeededCount) failedOnScreen=\(failedOnScreenCount) failedOffScreen=\(failedOffScreenCount) cacheCount=\(self.thumbnailCache.count)"
        )
    }

    /// 指定ウィンドウのキャッシュを削除する
    /// - Parameter cgWindowID: 削除対象の CoreGraphics ウィンドウ ID
    public func invalidateThumbnail(for cgWindowID: UInt32) {
        invalidatedWindowIDsDuringCapture.insert(cgWindowID)
        let hadEntry = thumbnailCache.removeValue(forKey: cgWindowID) != nil
        cacheOrder.removeAll { $0 == cgWindowID }
        if hadEntry {
            Self.logger.debug("単一キャッシュ無効化: windowID=\(cgWindowID) remaining=\(self.thumbnailCache.count)")
        }
    }

    /// 現在開いている有効ウィンドウ ID 集合に含まれない閉じ済みウィンドウのキャッシュを破棄する
    /// - Parameter activeCGWindowIDs: 現在生存しているウィンドウの CoreGraphics ウィンドウ ID 集合
    public func pruneCache(keeping activeCGWindowIDs: Set<UInt32>) {
        let staleIDs = thumbnailCache.keys.filter { !activeCGWindowIDs.contains($0) }
        guard !staleIDs.isEmpty else { return }
        for windowID in staleIDs {
            thumbnailCache.removeValue(forKey: windowID)
            invalidatedWindowIDsDuringCapture.insert(windowID)
        }
        cacheOrder.removeAll { !activeCGWindowIDs.contains($0) }
        Self.logger.info(
            "キャッシュ整理で破棄: pruned=\(staleIDs.count) keepingSetCount=\(activeCGWindowIDs.count) remaining=\(self.thumbnailCache.count)"
        )
    }

    /// 保持している全サムネイルキャッシュをメモリから破棄する
    public func clearCache() {
        let previousCount = thumbnailCache.count
        cacheEpoch += 1
        invalidatedWindowIDsDuringCapture.removeAll()
        thumbnailCache.removeAll()
        cacheOrder.removeAll()
        if previousCount > 0 {
            Self.logger.info("キャッシュ全破棄: cleared=\(previousCount)")
        }
    }

    /// 指定されたウィンドウ ID 集合に該当する SCWindow を非同期で取得し、Sendable ラッパー辞書として返す
    /// - Parameter targetIDSet: 取得対象の CoreGraphics ウィンドウ ID 集合
    /// - Returns: ウィンドウ ID をキーとした SendableSCWindow の辞書
    private nonisolated static func fetchShareableWindows(
        for targetIDSet: Set<UInt32>
    ) async throws -> [UInt32: SendableSCWindow] {
        // Xcode 16.4 (macOS 15.5 SDK) では SCShareableContent が非 Sendable のため、
        // async 境界を跨がずにコールバック内で Sendable な辞書へ変換する
        try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            ) { content, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var mapping: [UInt32: SendableSCWindow] = [:]
                if let content {
                    for window in content.windows where targetIDSet.contains(window.windowID) {
                        mapping[window.windowID] = SendableSCWindow(value: window)
                    }
                }
                continuation.resume(returning: mapping)
            }
        }
    }

    /// 単一ウィンドウのサムネイル画像を ScreenCaptureKit でタイムアウト保護付き非同期キャプチャする
    /// - Parameters:
    ///   - target: 対象ウィンドウのラッパー
    ///   - maxPixelSize: 出力上限ピクセルサイズ
    /// - Returns: 取得結果（成功時は `.captured`、権限拒否時は `.permissionDenied`、失敗・タイムアウト時は `.failed`）
    private nonisolated static func captureSingleWindow(
        _ target: SendableSCWindow,
        maxPixelSize: CGSize
    ) async -> SingleCaptureResult {
        let windowID = target.value.windowID
        let isOnScreen = target.value.isOnScreen
        guard !Task.isCancelled else {
            return .failed(windowID: windowID, isOnScreen: isOnScreen, reason: "cancelled")
        }

        let targetSize = scaledPixelSize(for: target.value.frame.size, maxPixelSize: maxPixelSize)

        let captureResult = await runWithTimeout(seconds: captureTimeoutSeconds) {
            let filter = SCContentFilter(desktopIndependentWindow: target.value)
            let config = SCStreamConfiguration()
            config.width = targetSize.width
            config.height = targetSize.height
            config.scalesToFit = true
            config.showsCursor = false
            do {
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
                guard Self.isValidCapturedImageSize(CGSize(width: image.width, height: image.height)) else {
                    return SingleCaptureResult.failed(
                        windowID: windowID,
                        isOnScreen: isOnScreen,
                        reason: "emptyImageSize"
                    )
                }
                return SingleCaptureResult.captured(windowID, image)
            } catch {
                let nsError = error as NSError
                if Self.isPermissionDeniedError(error) {
                    return .permissionDenied(windowID: windowID, errorCode: nsError.code)
                }
                return .failed(
                    windowID: windowID,
                    isOnScreen: isOnScreen,
                    reason: "\(nsError.domain):\(nsError.code)"
                )
            }
        }
        guard !Task.isCancelled else {
            return .failed(windowID: windowID, isOnScreen: isOnScreen, reason: "cancelled")
        }
        guard let captureResult else {
            return .failed(windowID: windowID, isOnScreen: isOnScreen, reason: "timeout")
        }
        return captureResult
    }

    /// 現在のセッションで ScreenCaptureKit を安全に呼び出せる権限状態かどうかを確認する
    /// - Returns: 許可されており未失効であれば true
    private func hasScreenRecordingPermission() -> Bool {
        guard !isAccessDeniedInSession else { return false }
        if let screenRecordingPermissionService {
            return screenRecordingPermissionService.currentStatus() == .granted
        }
        return CGPreflightScreenCaptureAccess()
    }

    /// ScreenCaptureKit 呼び出しによる権限拒否を検知した際、セッション内失効の記録とキャッシュ破棄を行う
    func handlePermissionDenied() {
        isAccessDeniedInSession = true
        clearCache()
        screenRecordingPermissionService?.markAccessRevoked()
    }

    /// 渡されたエラーが ScreenCaptureKit の画面収録権限拒否・不足に起因するものか判定する
    /// - Parameter error: ScreenCaptureKit から返されたエラー
    /// - Returns: 権限拒否（`userDeclined`）またはエンタイトルメント不足（`missingEntitlements`）であれば true
    nonisolated static func isPermissionDeniedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SCStreamError.errorDomain else { return false }
        return nsError.code == SCStreamError.userDeclined.rawValue
            || nsError.code == SCStreamError.missingEntitlements.rawValue
    }

    /// キャプチャ結果画像のピクセルサイズが有効（幅・高さともに 1px 以上）かを判定する
    /// - Parameter size: 検証対象の画像ピクセルサイズ
    /// - Returns: 有効なサイズであれば true
    nonisolated static func isValidCapturedImageSize(_ size: CGSize) -> Bool {
        size.width > 0 && size.height > 0
    }

    /// キャンセル非対応になり得る非同期 I/O を指定秒数のタイムアウトおよび親キャンセルから隔離して実行する
    /// - Parameters:
    ///   - seconds: タイムアウト時間（秒）
    ///   - operation: 実行する非同期処理
    /// - Returns: 期限内に完了した場合は結果、タイムアウトまたはキャンセル時は `nil`
    nonisolated static func runWithTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        guard !Task.isCancelled else { return nil }
        let state = OSAllocatedUnfairLock<TimeoutRaceState>(initialState: TimeoutRaceState())

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let finish: @Sendable (T?) -> Void = { value in
                    let tasksToCancel: (Task<Void, Never>?, Task<Void, Never>?)? = state.withLock { current in
                        guard !current.didResume else { return nil }
                        current.didResume = true
                        let pair = (current.operationTask, current.timeoutTask)
                        current.operationTask = nil
                        current.timeoutTask = nil
                        return pair
                    }
                    guard let tasksToCancel else { return }
                    tasksToCancel.0?.cancel()
                    tasksToCancel.1?.cancel()
                    continuation.resume(returning: value)
                }

                let opTask = Task {
                    let value = await operation()
                    finish(value)
                }
                let sleepTask = Task {
                    try? await Task.sleep(for: .seconds(seconds))
                    finish(nil)
                }

                let shouldAbortImmediately: Bool = state.withLock { current in
                    if current.isCancelled || current.didResume || Task.isCancelled {
                        return true
                    }
                    current.operationTask = opTask
                    current.timeoutTask = sleepTask
                    return false
                }

                if shouldAbortImmediately {
                    opTask.cancel()
                    sleepTask.cancel()
                    finish(nil)
                }
            }
        } onCancel: {
            let tasksToCancel: (Task<Void, Never>?, Task<Void, Never>?) = state.withLock { current in
                current.isCancelled = true
                return (current.operationTask, current.timeoutTask)
            }
            tasksToCancel.0?.cancel()
            tasksToCancel.1?.cancel()
        }
    }

    /// 元のウィンドウアスペクト比を維持したまま上限ピクセル枠内に収まる出力サイズを算出する
    /// - Parameters:
    ///   - sourceSize: 元ウィンドウのサイズ（ポイント）
    ///   - maxPixelSize: 上限ピクセルサイズ
    /// - Returns: 2px 以上の偶数丸め済みピクセル幅・高さ
    nonisolated static func scaledPixelSize(
        for sourceSize: CGSize,
        maxPixelSize: CGSize
    ) -> (width: Int, height: Int) {
        let safeMaxW = max(maxPixelSize.width, 64)
        let safeMaxH = max(maxPixelSize.height, 64)
        guard sourceSize.width > 1, sourceSize.height > 1 else {
            return (Int(safeMaxW), Int(safeMaxH))
        }

        let scale = min(safeMaxW / sourceSize.width, safeMaxH / sourceSize.height, 2.0)
        let rawW = max(Int(round(sourceSize.width * scale)), 2)
        let rawH = max(Int(round(sourceSize.height * scale)), 2)
        // CoreVideo/ScreenCaptureKit での不要なパディングを避けるため偶数に丸める
        let evenW = rawW % 2 == 0 ? rawW : rawW + 1
        let evenH = rawH % 2 == 0 ? rawH : rawH + 1
        return (evenW, evenH)
    }

    /// 画像を現在時刻とともに LRU キャッシュへ格納し、上限件数を超えた最古エントリを破棄する
    /// - Parameters:
    ///   - image: 格納するサムネイル画像
    ///   - cgWindowID: 対象の CoreGraphics ウィンドウ ID
    func storeInCache(_ image: NSImage, for cgWindowID: UInt32) {
        thumbnailCache[cgWindowID] = CachedThumbnailEntry(
            image: image,
            capturedAt: nowProvider()
        )
        touchCacheOrder(for: cgWindowID)

        while cacheOrder.count > maxCacheCount {
            let evictedID = cacheOrder.removeFirst()
            thumbnailCache.removeValue(forKey: evictedID)
        }
    }

    /// 指定ウィンドウ ID のアクセス順を最新（末尾）へ更新する
    /// - Parameter cgWindowID: 対象の CoreGraphics ウィンドウ ID
    private func touchCacheOrder(for cgWindowID: UInt32) {
        cacheOrder.removeAll { $0 == cgWindowID }
        cacheOrder.append(cgWindowID)
    }
}
