import Foundation

/// 長いウィンドウタイトルを表示する際の省略位置を表す設定値
public enum WindowTitleTruncationMode: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    /// 先頭と末尾を残して中央を省略する（初期値）
    case middle
    /// 末尾を省略する
    case tail

    /// 未設定時または不正値フォールバック時の既定省略位置
    public static let `default`: WindowTitleTruncationMode = .middle

    /// ForEach 等で一意識別に使用する識別子
    public var id: String { rawValue }

    /// 設定画面の選択 UI に表示するラベル（互換用：日本語既定）
    public var displayName: String {
        displayName(in: .japanese)
    }

    /// 指定言語での省略位置ラベルを返す
    /// - Parameter language: 表示対象の解決済み言語
    /// - Returns: ローカライズ済みの省略位置ラベル
    public func displayName(in language: ResolvedAppLanguage) -> String {
        let strings = AppStrings(language: language)
        switch self {
        case .middle:
            return strings.text(for: .windowTitleTruncationMiddle)
        case .tail:
            return strings.text(for: .windowTitleTruncationTail)
        }
    }
}
