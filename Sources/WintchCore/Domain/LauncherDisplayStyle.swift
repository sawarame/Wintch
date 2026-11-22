import Foundation

/// 検索ランチャー（トグル式）の表示形式を表す設定値
public enum LauncherDisplayStyle: String, Codable, CaseIterable, Equatable, Sendable {
    /// 従来の縦型リスト表示（初期値・画面収録権限不要）
    case list
    /// 各ウィンドウ候補行にキャプチャサムネイルを付与した縦型リスト表示（オプトインで画面収録権限を使用）
    case capture

    /// 未設定時または不正値フォールバック時の既定表示形式
    public static let `default`: LauncherDisplayStyle = .list

    /// 設定画面およびメニューバーの選択 UI に表示する日本語ラベル
    public var displayName: String {
        switch self {
        case .list:
            "リスト型"
        case .capture:
            "キャプチャ表示型"
        }
    }
}
