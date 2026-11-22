import Foundation

/// 設定画面の左サイドバーに表示するカテゴリメニューの定義
public enum SettingsTab: String, CaseIterable, Identifiable, Equatable, Sendable {
    /// 自動起動などの一般設定
    case general
    /// 通常ウィンドウスイッチャー設定
    case switcher
    /// 検索ランチャー設定
    case launcher
    /// システム権限およびアプリ情報
    case system

    /// Identifiable 準拠用の一意識別子
    public var id: String { rawValue }

    /// サイドバーに表示するメニュー名（互換用：日本語既定）
    public var title: String {
        title(in: .japanese)
    }

    /// 指定言語でのサイドバーメニュー名を返す
    /// - Parameter language: 表示対象の解決済み言語
    /// - Returns: ローカライズ済みのメニュー名
    public func title(in language: ResolvedAppLanguage) -> String {
        let strings = AppStrings(language: language)
        switch self {
        case .general:
            return strings.text(for: .settingsTabGeneral)
        case .switcher:
            return strings.text(for: .settingsTabSwitcher)
        case .launcher:
            return strings.text(for: .settingsTabLauncher)
        case .system:
            return strings.text(for: .settingsTabSystem)
        }
    }

    /// サイドバーの各メニューに添える SF Symbols アイコン名
    public var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .switcher:
            return "macwindow.on.rectangle"
        case .launcher:
            return "magnifyingglass"
        case .system:
            return "desktopcomputer"
        }
    }
}
