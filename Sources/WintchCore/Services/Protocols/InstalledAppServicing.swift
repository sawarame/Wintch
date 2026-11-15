import Foundation

/// インストール済みアプリケーションの収集・キャッシュ・起動を提供するサービス契約
@MainActor
public protocol InstalledAppServicing: AnyObject {
    /// 現在メモリ上にキャッシュされている起動可能アプリ一覧を同期で返す
    /// - Returns: キャッシュ済みの起動可能アプリ配列
    func cachedInstalledApps() -> [LaunchableApp]

    /// バックグラウンドでアプリケーションディレクトリを再走査し、キャッシュを更新して返す
    /// - Returns: 最新の起動可能アプリ配列
    @discardableResult
    func refreshInstalledApps() async -> [LaunchableApp]

    /// 指定されたアプリケーションを新規起動（すでにバックグラウンド起動中なら前面化）する
    /// - Parameter app: 起動対象のアプリケーション情報
    func launchApplication(_ app: LaunchableApp)
}
