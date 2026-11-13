import AppKit

/// プロセス ID ごとのアプリアイコンを取得・キャッシュするサービス
@MainActor
public final class IconProviderService: IconProviding {
    /// プロセス ID ごとのアイコンキャッシュ
    private var cache: [Int32: NSImage] = [:]

    /// アプリ終了通知の監視トークン
    private var terminationObserver: NSObjectProtocol?

    /// アイコン取得サービスを初期化する
    public init() {
        // アプリ終了時に不要なキャッシュを解放してメモリ消費を抑える
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let pid = app.processIdentifier
            Task { @MainActor [weak self] in
                self?.cache.removeValue(forKey: pid)
            }
        }
    }

    /// プロセス ID に対応するアプリアイコンを取得する
    /// - Parameter pid: 対象アプリケーションのプロセス ID
    /// - Returns: アプリアイコン画像（取得できない場合は nil）
    public func icon(for pid: Int32) -> NSImage? {
        if let cached = cache[pid] {
            return cached
        }
        guard let app = NSRunningApplication(processIdentifier: pid),
              let icon = app.icon else {
            return nil
        }
        cache[pid] = icon
        return icon
    }
}
