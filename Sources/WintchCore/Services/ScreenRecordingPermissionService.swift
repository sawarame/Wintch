import AppKit
import CoreGraphics

/// CoreGraphics 公開 API と NSWorkspace を用いて画面収録権限の確認・要求・設定遷移を行うサービス実装
@MainActor
public final class ScreenRecordingPermissionService: ScreenRecordingPermissionServicing {
    /// システム設定の「画面収録とシステムオーディオ録音」ペインを開く URL 文字列
    private static let settingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    /// ScreenCaptureKit 呼び出し時の拒否エラー等で検知したプロセス内失効フラグ
    private var isAccessRevokedInSession = false

    /// サービスを初期化する
    public init() {}

    /// 現在の画面収録権限状態を OS プロンプトを表示せずに確認する
    /// - Returns: 許可済みなら `.granted`、未許可なら `.denied`
    public func currentStatus() -> ScreenRecordingPermissionStatus {
        // CGPreflightScreenCaptureAccess() はプロセス起動時の判定をキャッシュするため、
        // 起動後の権限失効を検知済みの場合は即座に未許可として扱う
        guard !isAccessRevokedInSession else { return .denied }
        return CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// OS 標準の画面収録権限許可プロンプトを要求する
    /// - Returns: 呼び出し時点で権限が許可されていれば true
    @discardableResult
    public func requestPermission() -> Bool {
        // 既に同一プロセス内で権限失効を検知している場合、古いキャッシュ参照による誤判定を防ぐため false を返す
        guard !isAccessRevokedInSession else { return false }
        return CGRequestScreenCaptureAccess()
    }

    /// システム設定の「プライバシーとセキュリティ ＞ 画面収録」画面を開く
    public func openSystemSettings() {
        guard let url = URL(string: Self.settingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 実行中プロセス内で画面収録アクセスが拒否・失効したことを記録する
    public func markAccessRevoked() {
        isAccessRevokedInSession = true
    }
}
