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

    /// サイドバーに表示するメニュー名
    public var title: String {
        switch self {
        case .general:
            return "一般"
        case .switcher:
            return "スイッチャー"
        case .launcher:
            return "ランチャー"
        case .system:
            return "システム"
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
