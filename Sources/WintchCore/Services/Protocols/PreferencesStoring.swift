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

    /// 保存されている通常スイッチャーの表示形式設定を読み込む
    /// - Returns: 保存された表示形式設定（未保存時はデフォルトのリスト型）
    func loadNormalDisplayStyle() -> SwitcherDisplayStyle

    /// 通常スイッチャーの表示形式設定を保存する
    /// - Parameter style: 保存する表示形式設定
    func saveNormalDisplayStyle(_ style: SwitcherDisplayStyle)

    /// 保存されている検索ランチャーの表示形式設定を読み込む
    /// - Returns: 保存された検索ランチャー表示形式設定（未保存または不正値時はデフォルトのリスト型）
    func loadLauncherDisplayStyle() -> LauncherDisplayStyle

    /// 検索ランチャーの表示形式設定を保存する
    /// - Parameter style: 保存する検索ランチャー表示形式設定
    func saveLauncherDisplayStyle(_ style: LauncherDisplayStyle)
}
