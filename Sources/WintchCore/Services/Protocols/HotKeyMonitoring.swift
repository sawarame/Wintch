import Foundation

/// 矢印キーの移動方向
public enum ArrowDirection: Equatable, Sendable {
    /// 上方向（前の項目へ移動）
    case up
    /// 下方向（次の項目へ移動）
    case down
}

/// ホットキー監視サービスが認識する現在のアクティブモード
public enum HotKeyMonitorMode: Equatable, Sendable {
    /// スイッチャー非表示（起動ショートカットのみ待機）
    case inactive
    /// 通常スイッチャー表示中（修飾キー保持式・Esc/上下矢印をグローバル横取り）
    case normal
    /// ランチャーモード表示中（トグル式・検索入力および IME を優先し、再押下トグルのみ監視）
    case launcher
}

/// スイッチャー制御のためにサービス層から通知されるグローバルキーイベント
public enum HotKeyEvent: Equatable, Sendable {
    /// 設定された修飾キー＋トリガーキーが押された（通常モード）
    case triggerPressed(isShiftPressed: Bool)
    /// ランチャー起動／トグル終了のショートカットが押された
    case launcherTriggerPressed
    /// 設定中の修飾キーが離された（通常モードの確定トリガー）
    case modifierReleased
    /// Esc キーが押された（通常モードのキャンセル）
    case escapePressed
    /// 上下矢印キーが押された（通常モード表示中の補助移動）
    case arrowPressed(direction: ArrowDirection)
}

/// グローバルキーボードショートカットの監視とイベント消費を行うサービス契約
@MainActor
public protocol HotKeyMonitoring: AnyObject {
    /// イベント発生時のコールバックハンドラ
    var onEvent: ((HotKeyEvent) -> Void)? { get set }

    /// 現在のスイッチャー監視モード
    var activeMode: HotKeyMonitorMode { get set }

    /// スイッチャーが現在表示中かどうかをサービスに伝える（activeMode != .inactive と連動）
    var isSwitcherActive: Bool { get set }

    /// 設定画面でショートカットレコーダーが入力待機中の間 true にし、グローバル横取りを一時停止する
    var isSuspendedForRecording: Bool { get set }

    /// 通常スイッチャーの監視対象ショートカット設定を更新する
    /// - Parameter preference: 新しいショートカット設定
    func updateShortcut(_ preference: ShortcutPreference)

    /// ランチャーモードの監視対象ショートカット設定を更新する
    /// - Parameter preference: 新しいランチャーショートカット設定
    func updateLauncherShortcut(_ preference: LauncherShortcutPreference)

    /// グローバル監視を開始する（アクセシビリティ権限が必要）
    /// - Returns: 監視の開始に成功した場合は true
    @discardableResult
    func startMonitoring() -> Bool

    /// グローバル監視を停止する
    func stopMonitoring()
}
