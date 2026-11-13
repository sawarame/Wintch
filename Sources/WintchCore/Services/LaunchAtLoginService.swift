import Foundation
import ServiceManagement

/// macOS 標準の SMAppService.mainApp を用いてログイン時自動起動を管理するサービス
@MainActor
public final class LaunchAtLoginService: LaunchAtLoginServicing {
    /// LaunchAtLoginService を初期化する
    public init() {}

    /// 現在 OS のログイン項目として登録・有効化されているか
    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// ログイン時自動起動の有効・無効を切り替える
    /// - Parameter enabled: 有効にする場合は true、解除する場合は false
    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
