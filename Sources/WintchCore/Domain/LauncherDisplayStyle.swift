import Foundation

/// 検索ランチャー（トグル式）の表示形式を表す設定値
public enum LauncherDisplayStyle: String, Codable, CaseIterable, Equatable, Sendable {
    /// 従来の縦型リスト表示（初期値・画面収録権限不要）
    case list
    /// 各ウィンドウ候補行にキャプチャサムネイルを付与した縦型リスト表示（オプトインで画面収録権限を使用）
    case capture

    /// 未設定時または不正値フォールバック時の既定表示形式
    public static let `default`: LauncherDisplayStyle = .list

    /// 設定画面およびメニューバーの選択 UI に表示するラベル（互換用：日本語既定）
    public var displayName: String {
        displayName(in: .japanese)
    }

    /// 指定言語での検索ランチャー表示形式ラベルを返す
    /// - Parameter language: 表示対象の解決済み言語
    /// - Returns: ローカライズ済みの表示形式ラベル
    public func displayName(in language: ResolvedAppLanguage) -> String {
        let strings = AppStrings(language: language)
        switch self {
        case .list:
            return strings.text(for: .displayStyleList)
        case .capture:
            return strings.text(for: .displayStyleCapture)
        }
    }
}
