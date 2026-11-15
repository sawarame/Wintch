import Foundation

/// 画面収録権限の状態確認・許可リクエスト・システム設定誘導を行うサービス契約
@MainActor
public protocol ScreenRecordingPermissionServicing: AnyObject {
    /// 現在の画面収録権限状態を OS プロンプトを表示せずに確認する
    /// - Returns: 許可済みなら `.granted`、未許可なら `.denied`
    func currentStatus() -> ScreenRecordingPermissionStatus

    /// OS 標準の画面収録権限許可プロンプトを要求する（オプトイン操作時のみ呼び出す）
    /// - Returns: 呼び出し時点で許可されていれば true
    @discardableResult
    func requestPermission() -> Bool

    /// システム設定の「画面収録とシステムオーディオ録音」ペインを開く
    func openSystemSettings()

    /// 実行中プロセス内で画面収録アクセスが拒否・失効したことを記録し、以降の判定を未許可扱いに切り替える
    func markAccessRevoked()
}
