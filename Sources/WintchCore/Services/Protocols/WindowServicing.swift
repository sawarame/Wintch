import Foundation

/// ウィンドウまたはアプリケーションの終了要求送出結果
public enum WindowCloseRequestResult: Equatable, Sendable {
    /// 終了要求の送出に成功し、実際の消滅完了待ちへ移行する
    /// - Parameter didSwitchSpace: 対象解決のために別スペースへの一時遷移を行った場合は true
    case requested(didSwitchSpace: Bool = false)
    /// 要求時点または要求直後にすでにウィンドウ消滅済み・アプリ終了済みだった
    /// - Parameter didSwitchSpace: 対象解決のために別スペースへの一時遷移を行った場合は true
    case alreadyClosed(didSwitchSpace: Bool = false)
    /// クローズボタン不在・無効化や terminate() 失敗など、終了要求の送出自体に失敗した
    /// - Parameter didSwitchSpace: 対象解決のために別スペースへの一時遷移を行った場合は true
    case failed(didSwitchSpace: Bool = false)

    /// 要求送出の過程で別スペースへの一時遷移が発生したかどうか
    public var didSwitchSpace: Bool {
        switch self {
        case let .requested(didSwitchSpace),
             let .alreadyClosed(didSwitchSpace),
             let .failed(didSwitchSpace):
            return didSwitchSpace
        }
    }
}

/// WindowService が OS 通知等から検知したリアルタイムのウィンドウ／アプリ終了イベント
public enum WindowLifecycleEvent: Equatable, Sendable {
    /// 個別ウィンドウの破棄・消滅を検知した
    /// - Parameters:
    ///   - windowID: 対象ウィンドウの識別子（`WindowEntry.id` 相当）
    ///   - cgWindowID: 紐付いていた CoreGraphics ウィンドウ ID（不明時は nil）
    ///   - pid: 所有アプリケーションのプロセス ID
    case windowClosed(windowID: String, cgWindowID: UInt32?, pid: Int32)
    /// アプリケーションプロセスの終了を検知した
    /// - Parameter pid: 終了したアプリケーションのプロセス ID
    case applicationTerminated(pid: Int32)
}

/// ウィンドウ情報の収集・監視・切り替え操作を提供するサービス契約
@MainActor
public protocol WindowServicing: AnyObject {
    /// OS 通知等でウィンドウ破棄またはアプリ終了を検知した際に呼ばれるリアルタイム通知ハンドラ
    var onWindowLifecycleEvent: ((WindowLifecycleEvent) -> Void)? { get set }

    /// 現在の監視状態を開始する（AXObserver およびワークスペース通知の登録）
    func startObserving()

    /// 監視を停止し、保持している監視リソースを解放する
    func stopObserving()

    /// 現在の全操作スペース上のウィンドウ候補を収集して返す（フィルタリング前の生候補）
    /// - Returns: 収集されたウィンドウ候補の配列
    func fetchRawWindowCandidates() -> [RawWindowCandidate]

    /// 現在の全ディスプレイの矩形一覧（CoreGraphics 座標系）を返す
    /// - Returns: ディスプレイ矩形配列
    func currentDisplayBounds() -> [WindowBounds]

    /// キャッシュ整理用に OS（WindowServer）上で現在生存している全 CGWindow ID 集合を返す
    /// - Returns: 生存中の CGWindow ID 集合（未対応または一時取得失敗時は nil）
    func survivingCGWindowIDsForCachePruning() -> Set<UInt32>?

    /// 指定されたウィンドウを最前面にアクティブ化する（必要なら操作スペース移動・最小化解除を含む）
    /// - Parameter entry: アクティブ化対象のウィンドウ項目
    func activateWindow(_ entry: WindowEntry)

    /// 指定されたウィンドウ 1 枚に対してクローズ要求を送出し、要求フェーズの結果を返す
    /// - Parameter entry: クローズ対象のウィンドウ項目
    /// - Returns: 要求送出成功・すでに消滅済み・送出失敗のいずれかを表す結果
    func requestCloseWindow(_ entry: WindowEntry) async -> WindowCloseRequestResult

    /// 指定された PID のアプリケーションに対して通常の終了要求（強制終了ではない）を送出し、要求フェーズの結果を返す
    /// - Parameter pid: 終了対象のプロセス ID
    /// - Returns: 要求送出成功・すでに終了済み・送出失敗のいずれかを表す結果
    func requestTerminateApplication(pid: Int32) async -> WindowCloseRequestResult

    /// 指定されたウィンドウが現在も生存しているかを非同期で確認する（フォールバック生存確認用）
    /// - Parameter entry: 確認対象のウィンドウ項目
    /// - Returns: まだ生存している場合は true、閉じられて消滅している場合は false
    func isWindowAlive(_ entry: WindowEntry) async -> Bool

    /// 指定された PID のアプリケーションが現在も稼働中かを確認する（フォールバック生存確認用）
    /// - Parameter pid: 確認対象のプロセス ID
    /// - Returns: 稼働中の場合は true、終了済みの場合は false
    func isApplicationRunning(pid: Int32) async -> Bool
}

public extension WindowServicing {
    /// デフォルト実装として空配列を返す（テストモック互換用）
    /// - Returns: ディスプレイ矩形配列
    func currentDisplayBounds() -> [WindowBounds] {
        []
    }

    /// デフォルト実装として nil を返す（テストモック互換用）
    /// - Returns: 既定では nil（呼び出し元で候補ベースへフォールバック）
    func survivingCGWindowIDsForCachePruning() -> Set<UInt32>? {
        nil
    }
}
