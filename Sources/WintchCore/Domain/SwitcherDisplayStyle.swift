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

    /// 設定画面の選択 UI に表示するラベル（互換用：日本語既定）
    public var displayName: String {
        displayName(in: .japanese)
    }

    /// 指定言語での表示形式ラベルを返す
    /// - Parameter language: 表示対象の解決済み言語
    /// - Returns: ローカライズ済みの表示形式ラベル
    public func displayName(in language: ResolvedAppLanguage) -> String {
        let strings = AppStrings(language: language)
        switch self {
        case .list:
            return strings.text(for: .displayStyleList)
        case .icon:
            return strings.text(for: .displayStyleIcon)
        case .capture:
            return strings.text(for: .displayStyleCapture)
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
