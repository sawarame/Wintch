import Observation

/// アクセシビリティ権限誘導画面の状態とアクションを管理する ViewModel
@MainActor
@Observable
public final class PermissionGuideViewModel {
    /// 現在のアクセシビリティ権限状態
    public private(set) var status: AccessibilityPermissionStatus

    /// 画面表示に使用する解決済み言語
    public private(set) var resolvedLanguage: ResolvedAppLanguage

    /// 現在の表示言語に対応するローカライズ文言テーブル
    public var strings: AppStrings {
        AppStrings(language: resolvedLanguage)
    }

    /// 権限が許可された際に呼び出される通知ハンドラ
    public var onPermissionGranted: (() -> Void)?

    /// 権限管理サービス
    private let permissionService: any AccessibilityPermissionServicing

    /// 権限誘導 ViewModel を初期化する
    /// - Parameters:
    ///   - permissionService: アクセシビリティ権限管理サービス
    ///   - resolvedLanguage: 初期表示に使用する解決済み言語（既定値は日本語）
    public init(
        permissionService: any AccessibilityPermissionServicing,
        resolvedLanguage: ResolvedAppLanguage = .japanese
    ) {
        self.permissionService = permissionService
        self.status = permissionService.currentStatus()
        self.resolvedLanguage = resolvedLanguage
    }

    /// 表示言語を即時更新する
    /// - Parameter language: 新しい解決済み言語
    public func updateLanguage(_ language: ResolvedAppLanguage) {
        guard resolvedLanguage != language else { return }
        resolvedLanguage = language
    }

    /// システム設定のアクセシビリティ項目を開く
    public func openSystemSettings() {
        permissionService.openAccessibilitySettings()
    }

    /// 外部の権限状態変化（または監視強制停止）をコールバック再発火なしで UI 状態へ同期する
    /// - Parameter newStatus: 反映する最新の権限状態
    public func syncStatus(_ newStatus: AccessibilityPermissionStatus) {
        status = newStatus
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
