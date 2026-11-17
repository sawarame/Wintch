import AppKit

/// メニューバーや常駐状態から開かれる標準ウィンドウを最前面かつキーウィンドウとして表示するサービス契約
@MainActor
public protocol WindowFrontPresenting: AnyObject {
    /// 指定ウィンドウを現在の操作スペース・アクティブ画面中央へ移動し、最前面・キーウィンドウとして表示する
    /// - Parameter window: 表示対象の NSWindow
    func presentFrontmost(_ window: NSWindow)
}
