import Foundation

/// 画面収録権限の現在の許可状態を表すドメイン値
public enum ScreenRecordingPermissionStatus: Equatable, Sendable {
    /// 画面収録権限が許可されている状態
    case granted
    /// 画面収録権限が未許可または取り消されている状態
    case denied
}
