import Foundation

/// アクセシビリティ権限の現在の許可状態
public enum AccessibilityPermissionStatus: Equatable, Sendable {
    /// 権限が許可されている状態（全機能利用可能）
    case granted
    /// 権限が未許可の状態（誘導画面を表示して安全に待機）
    case denied
}
