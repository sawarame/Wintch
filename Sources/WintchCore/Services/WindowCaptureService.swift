import AppKit
import CoreGraphics
import Foundation
import os
import ScreenCaptureKit

/// ScreenCaptureKit を用いてウィンドウサムネイルを非同期取得し、上限付き LRU メモリキャッシュを管理するサービス実装
@MainActor
public final class WindowCaptureService: WindowCaptureServicing {
    /// スレッド境界を跨いで SCWindow 参照を受け渡すための Sendable ラッパー
    private struct SendableSCWindow: @unchecked Sendable {
        let value: SCWindow
    }

    /// タイムアウト付き非同期レースの状態管理構造体
    private struct TimeoutRaceState: Sendable {
        var didResume = false
        var isCancelled = false
        var operationTask: Task<Void, Never>?
        var timeoutTask: Task<Void, Never>?
    }

    /// メモリ内サムネイルキャッシュの最大保持件数（FR-012）
    private static let maxCacheCount = 50

    /// 非同期キャプチャの最大同時実行数
    private static let maxConcurrentCaptures = 4

    /// 1 ウィンドウあたりのキャプチャタイムアウト時間（秒）
    private static let captureTimeoutSeconds: TimeInterval = 1.5

    /// ウィンドウ ID ごとのサムネイル画像キャッシュ（メモリ限定・ディスク非保存）
    private var thumbnailCache: [UInt32: NSImage] = [:]

    /// LRU 順序管理配列（末尾ほど最近利用されたエントリ）
    private var cacheOrder: [UInt32] = []

    /// キャッシュ全消去の世代カウンタ（非同期取得中のクリア後に古い結果が再混入するのを防ぐ）
    private var cacheEpoch: Int = 0

    /// 進行中の非同期キャプチャセッション中に明示無効化されたウィンドウ ID 集合
    private var invalidatedWindowIDsDuringCapture: Set<UInt32> = []

    /// サービスを初期化する
    public init() {}

    /// メモリ上のキャッシュから指定ウィンドウのサムネイルを同期取得する
    /// - Parameter cgWindowID: 対象の CoreGraphics ウィンドウ ID
    /// - Returns: キャッシュ済みのサムネイル画像（未保持の場合は nil）
    public func cachedThumbnail(for cgWindowID: UInt32) -> NSImage? {
        guard let image = thumbnailCache[cgWindowID] else { return nil }
        touchCacheOrder(for: cgWindowID)
        return image
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
        // 防御的チェック: 権限未許可時は OS ダイアログを誘発する ScreenCaptureKit API を呼ばない
        guard !cgWindowIDs.isEmpty, CGPreflightScreenCaptureAccess() else {
            return
        }

        let targetIDSet = Set(cgWindowIDs)
        let shareableWindowsByID: [UInt32: SendableSCWindow]
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            )
            var mapping: [UInt32: SendableSCWindow] = [:]
            for window in content.windows where targetIDSet.contains(window.windowID) {
                mapping[window.windowID] = SendableSCWindow(value: window)
            }
            shareableWindowsByID = mapping
        } catch {
            // 権限取り消しや取得失敗時は例外を投げず安全にフォールバック継続する
            return
        }

        guard !Task.isCancelled else { return }

        // 画面表示中（isOnScreen）のウィンドウを優先し、各群内では呼び出し元指定順（MRU・未キャッシュ優先）を維持する
        let requestedTargets = cgWindowIDs.compactMap { shareableWindowsByID[$0] }
        let orderedTargets = requestedTargets.filter(\.value.isOnScreen)
            + requestedTargets.filter { !$0.value.isOnScreen }
        guard !orderedTargets.isEmpty else { return }

        let capturedEpoch = cacheEpoch
        invalidatedWindowIDsDuringCapture.removeAll()

        await withTaskGroup(of: (UInt32, CGImage)?.self) { group in
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

                if nextIndex < orderedTargets.count {
                    let target = orderedTargets[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await Self.captureSingleWindow(target, maxPixelSize: maxPixelSize)
                    }
                }

                if let (windowID, cgImage) = result,
                   !invalidatedWindowIDsDuringCapture.contains(windowID) {
                    let nsImage = NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    )
                    storeInCache(nsImage, for: windowID)
                    onCaptured(windowID, nsImage)
                }
            }
        }
    }

    /// 指定ウィンドウのキャッシュを削除する
    /// - Parameter cgWindowID: 削除対象の CoreGraphics ウィンドウ ID
    public func invalidateThumbnail(for cgWindowID: UInt32) {
        invalidatedWindowIDsDuringCapture.insert(cgWindowID)
        thumbnailCache.removeValue(forKey: cgWindowID)
        cacheOrder.removeAll { $0 == cgWindowID }
    }

    /// 保持している全サムネイルキャッシュをメモリから破棄する
    public func clearCache() {
        cacheEpoch += 1
        invalidatedWindowIDsDuringCapture.removeAll()
        thumbnailCache.removeAll()
        cacheOrder.removeAll()
    }

    /// 単一ウィンドウのサムネイル画像を ScreenCaptureKit でタイムアウト保護付き非同期キャプチャする
    /// - Parameters:
    ///   - target: 対象ウィンドウのラッパー
    ///   - maxPixelSize: 出力上限ピクセルサイズ
    /// - Returns: 取得成功時は `(windowID, CGImage)`、失敗・タイムアウト・キャンセル時は `nil`
    private nonisolated static func captureSingleWindow(
        _ target: SendableSCWindow,
        maxPixelSize: CGSize
    ) async -> (UInt32, CGImage)? {
        guard !Task.isCancelled else { return nil }

        let windowID = target.value.windowID
        let targetSize = scaledPixelSize(for: target.value.frame.size, maxPixelSize: maxPixelSize)

        let capturedImage = await runWithTimeout(seconds: captureTimeoutSeconds) {
            let filter = SCContentFilter(desktopIndependentWindow: target.value)
            let config = SCStreamConfiguration()
            config.width = targetSize.width
            config.height = targetSize.height
            config.scalesToFit = true
            config.showsCursor = false
            return try? await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        }
        guard !Task.isCancelled, let capturedImage else { return nil }
        return (windowID, capturedImage)
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

    /// 画像を LRU キャッシュへ格納し、上限件数を超えた最古エントリを破棄する
    /// - Parameters:
    ///   - image: 格納するサムネイル画像
    ///   - cgWindowID: 対象の CoreGraphics ウィンドウ ID
    private func storeInCache(_ image: NSImage, for cgWindowID: UInt32) {
        thumbnailCache[cgWindowID] = image
        touchCacheOrder(for: cgWindowID)

        while cacheOrder.count > Self.maxCacheCount {
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
