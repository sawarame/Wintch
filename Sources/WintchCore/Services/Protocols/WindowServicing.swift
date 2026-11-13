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
}
