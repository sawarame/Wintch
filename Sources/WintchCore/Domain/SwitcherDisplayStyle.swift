import Foundation

/// 通常スイッチャー（ホールド式）の表示形式を表す設定値
public enum SwitcherDisplayStyle: String, Codable, CaseIterable, Equatable, Sendable {
    /// 従来の縦型リスト表示（初期値・画面収録権限不要）
    case list
    /// アプリアイコンとアプリ名・ウィンドウタイトルを並べたタイルグリッド表示（画面収録権限不要）
    case icon
    /// ウィンドウのキャプチャサムネイルを並べたカードグリッド表示（オプトインで画面収録権限を使用）
    case capture

    /// 未設定時または不正値フォールバック時の既定表示形式
    public static let `default`: SwitcherDisplayStyle = .list

    /// 設定画面の選択 UI に表示する日本語ラベル
    public var displayName: String {
        switch self {
        case .list:
            "リスト型"
        case .icon:
            "アイコン型"
        case .capture:
            "キャプチャ表示型"
        }
    }

    /// 複数列グリッドレイアウトおよび上下左右 4 方向移動を使用する表示形式かどうか
    public var usesGridLayout: Bool {
        switch self {
        case .list:
            false
        case .icon, .capture:
            true
        }
    }
}
