import Observation

/// アクセシビリティ権限誘導画面の状態とアクションを管理する ViewModel
@MainActor
@Observable
public final class PermissionGuideViewModel {
    /// 現在のアクセシビリティ権限状態
    public private(set) var status: AccessibilityPermissionStatus

    /// 権限が許可された際に呼び出される通知ハンドラ
    public var onPermissionGranted: (() -> Void)?

    /// 権限管理サービス
    private let permissionService: any AccessibilityPermissionServicing

    /// 権限誘導 ViewModel を初期化する
    /// - Parameter permissionService: アクセシビリティ権限管理サービス
    public init(permissionService: any AccessibilityPermissionServicing) {
        self.permissionService = permissionService
        self.status = permissionService.currentStatus()
    }

    /// システム設定のアクセシビリティ項目を開く
    public func openSystemSettings() {
        permissionService.openAccessibilitySettings()
    }

    /// 現在の権限状態を再確認し、許可済みに変化していればコールバックを通知する
    public func refreshStatus() {
        let latest = permissionService.currentStatus()
        status = latest
        if latest == .granted {
            onPermissionGranted?()
        }
    }
}
