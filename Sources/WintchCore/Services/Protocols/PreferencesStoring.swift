import Foundation

/// ユーザー設定の保存と読み込みを行うストア契約
public protocol PreferencesStoring: Sendable {
    /// 保存されている通常スイッチャーのショートカット設定を読み込む
    /// - Returns: 保存されたショートカット設定（未保存時はデフォルト値）
    func loadShortcut() -> ShortcutPreference

    /// 通常スイッチャーのショートカット設定を保存する
    /// - Parameter preference: 保存するショートカット設定
    func saveShortcut(_ preference: ShortcutPreference)

    /// 保存されているランチャーのショートカット設定を読み込む
    /// - Returns: 保存されたランチャーショートカット設定（未保存時はデフォルトの Option + Space）
    func loadLauncherShortcut() -> LauncherShortcutPreference

    /// ランチャーのショートカット設定を保存する
    /// - Parameter preference: 保存するランチャーショートカット設定
    func saveLauncherShortcut(_ preference: LauncherShortcutPreference)
}
