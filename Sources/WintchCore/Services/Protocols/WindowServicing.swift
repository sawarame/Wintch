import Foundation

/// ウィンドウ情報の収集・監視・切り替え操作を提供するサービス契約
@MainActor
public protocol WindowServicing: AnyObject {
    /// 現在の監視状態を開始する（AXObserver およびワークスペース通知の登録）
    func startObserving()

    /// 監視を停止し、保持している監視リソースを解放する
    func stopObserving()

    /// 現在の全操作スペース上のウィンドウ候補を収集して返す（フィルタリング前の生候補）
    /// - Returns: 収集されたウィンドウ候補の配列
    func fetchRawWindowCandidates() -> [RawWindowCandidate]

    /// 指定されたウィンドウを最前面にアクティブ化する（必要なら操作スペース移動・最小化解除を含む）
    /// - Parameter entry: アクティブ化対象のウィンドウ項目
    func activateWindow(_ entry: WindowEntry)

    /// 指定されたウィンドウ1枚のみを閉じる操作を実行し、実際に閉じられたかを返す
    /// - Parameter entry: クローズ対象のウィンドウ項目
    /// - Returns: ウィンドウの消滅を確認できた場合は true、非対応や確認ダイアログ等で残存した場合は false
    func closeWindow(_ entry: WindowEntry) async -> Bool

    /// 指定された PID のアプリケーションに対して通常の終了要求（強制終了ではない）を送信し、終了したかを返す
    /// - Parameter pid: 終了対象のプロセス ID
    /// - Returns: アプリケーションの終了を確認できた場合は true、保存確認ダイアログ等でキャンセル・残存した場合は false
    func terminateApplication(pid: Int32) async -> Bool
}
