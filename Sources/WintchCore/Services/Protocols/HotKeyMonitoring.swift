import Foundation

/// 矢印キーの移動方向
public enum ArrowDirection: Equatable, Sendable {
    /// 上方向（前の項目へ移動）
    case up
    /// 下方向（次の項目へ移動）
    case down
}

/// スイッチャー制御のためにサービス層から通知されるグローバルキーイベント
public enum HotKeyEvent: Equatable, Sendable {
    /// 設定された修飾キー＋トリガーキーが押された
    case triggerPressed(isShiftPressed: Bool)
    /// 設定中の修飾キーが離された（選択確定トリガー）
    case modifierReleased
    /// Esc キーが押された（キャンセル）
    case escapePressed
    /// 上下矢印キーが押された（スイッチャー表示中の補助移動）
    case arrowPressed(direction: ArrowDirection)
}

/// グローバルキーボードショートカットの監視とイベント消費を行うサービス契約
@MainActor
public protocol HotKeyMonitoring: AnyObject {
    /// イベント発生時のコールバックハンドラ
    var onEvent: ((HotKeyEvent) -> Void)? { get set }

    /// スイッチャーが現在表示中かどうかをサービスに伝える（表示中のみ Esc や矢印キーを横取りする）
    var isSwitcherActive: Bool { get set }

    /// 監視対象のショートカット設定を更新する
    /// - Parameter preference: 新しいショートカット設定
    func updateShortcut(_ preference: ShortcutPreference)

    /// グローバル監視を開始する（アクセシビリティ権限が必要）
    /// - Returns: 監視の開始に成功した場合は true
    @discardableResult
    func startMonitoring() -> Bool

    /// グローバル監視を停止する
    func stopMonitoring()
}
