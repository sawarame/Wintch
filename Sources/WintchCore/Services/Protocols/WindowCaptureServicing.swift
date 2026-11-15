import AppKit
import Foundation

/// ウィンドウのキャプチャサムネイル取得およびメモリ内一時キャッシュを管理するサービス契約
@MainActor
public protocol WindowCaptureServicing: AnyObject {
    /// メモリ上のキャッシュから指定ウィンドウのサムネイルを同期取得する
    /// - Parameter cgWindowID: 対象の CoreGraphics ウィンドウ ID
    /// - Returns: キャッシュ済みのサムネイル画像（未保持の場合は nil）
    func cachedThumbnail(for cgWindowID: UInt32) -> NSImage?

    /// 指定ウィンドウ群の最新サムネイルを非同期取得し、完了したものから順次通知する
    /// - Parameters:
    ///   - cgWindowIDs: 取得対象の CoreGraphics ウィンドウ ID 配列
    ///   - maxPixelSize: 出力サムネイルの上限ピクセルサイズ
    ///   - onCaptured: 1 件取得完了するたびに呼ばれるメインアクター上の通知クロージャ
    func captureThumbnails(
        for cgWindowIDs: [UInt32],
        maxPixelSize: CGSize,
        onCaptured: @escaping @MainActor (UInt32, NSImage) -> Void
    ) async

    /// 指定ウィンドウのキャッシュを削除する（ウィンドウクローズ時など）
    /// - Parameter cgWindowID: 削除対象の CoreGraphics ウィンドウ ID
    func invalidateThumbnail(for cgWindowID: UInt32)

    /// 保持している全サムネイルキャッシュをメモリから破棄する（リスト型への復帰時など）
    func clearCache()
}
