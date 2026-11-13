import Foundation

/// ログイン時自動起動の状態管理を行うサービス契約
@MainActor
public protocol LaunchAtLoginServicing: AnyObject {
    /// 現在ログイン時自動起動が有効になっているか
    var isEnabled: Bool { get }

    /// ログイン時自動起動の有効・無効を切り替える
    /// - Parameter enabled: 有効にする場合は true、解除する場合は false
    func setEnabled(_ enabled: Bool) throws
}
