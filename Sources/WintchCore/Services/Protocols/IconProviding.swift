import AppKit

/// プロセス ID やアプリ URL からアプリケーションアイコンを取得するサービス契約
@MainActor
public protocol IconProviding: AnyObject {
    /// 指定されたプロセス ID に対応するアプリアイコンを取得する
    /// - Parameter pid: アプリケーションのプロセス ID
    /// - Returns: アプリアイコン画像（取得できない場合は nil）
    func icon(for pid: Int32) -> NSImage?

    /// 指定されたアプリケーションバンドル URL に対応するアプリアイコンを取得する
    /// - Parameter url: アプリケーションバンドルの URL
    /// - Returns: アプリアイコン画像（取得できない場合は nil）
    func icon(forAppURL url: URL) -> NSImage?
}
