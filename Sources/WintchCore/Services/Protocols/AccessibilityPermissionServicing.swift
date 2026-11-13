import Foundation

/// アクセシビリティ権限の状態確認とシステム設定画面への誘導を行うサービス契約
@MainActor
public protocol AccessibilityPermissionServicing: AnyObject {
    /// 現在のアクセシビリティ権限状態を取得する
    /// - Returns: 現在の許可状態（.granted または .denied）
    func currentStatus() -> AccessibilityPermissionStatus

    /// 権限状態の定期監視を開始し、変化時にコールバックを呼び出す
    /// - Parameter onChange: 権限状態が変化した際に実行されるクロージャ
    func startMonitoring(onChange: @escaping (AccessibilityPermissionStatus) -> Void)

    /// 権限監視を停止する
    func stopMonitoring()

    /// macOS の「システム設定 > プライバシーとセキュリティ > アクセシビリティ」画面を開く
    func openAccessibilitySettings()
}
