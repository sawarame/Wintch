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

    /// 保存されている通常スイッチャーのアプリグルーピング設定を読み込む
    /// - Returns: アプリごとにグルーピングする場合は true（未保存時はデフォルト true）
    func loadGroupNormalSwitcherByApp() -> Bool

    /// 通常スイッチャーのアプリグルーピング設定を保存する
    /// - Parameter enabled: アプリごとにグルーピングする場合は true
    func saveGroupNormalSwitcherByApp(_ enabled: Bool)

    /// 保存されている検索ランチャーのアプリグルーピング設定を読み込む
    /// - Returns: アプリごとにグルーピングする場合は true（未保存時はデフォルト true）
    func loadGroupLauncherByApp() -> Bool

    /// 検索ランチャーのアプリグルーピング設定を保存する
    /// - Parameter enabled: アプリごとにグルーピングする場合は true
    func saveGroupLauncherByApp(_ enabled: Bool)

    /// 保存されているアプリの表示言語設定を読み込む
    /// - Returns: 保存された言語設定（未保存または不正値時はデフォルトの .system）
    func loadAppLanguage() -> AppLanguage

    /// アプリの表示言語設定を保存する
    /// - Parameter language: 保存する言語設定
    func saveAppLanguage(_ language: AppLanguage)

    /// 保存されているウィンドウタイトルの省略位置設定を読み込む
    /// - Returns: 保存された省略位置設定（未保存または不正値時はデフォルトの .middle）
    func loadWindowTitleTruncationMode() -> WindowTitleTruncationMode

    /// ウィンドウタイトルの省略位置設定を保存する
    /// - Parameter mode: 保存する省略位置設定
    func saveWindowTitleTruncationMode(_ mode: WindowTitleTruncationMode)

    /// 保存されている起動時のバージョンアップ自動チェック設定を読み込む
    /// - Returns: 自動チェックを有効にする場合は true（未保存時はデフォルト false）
    func loadAutoCheckForUpdates() -> Bool

    /// 起動時のバージョンアップ自動チェック設定を保存する
    /// - Parameter enabled: 自動チェックを有効にする場合は true
    func saveAutoCheckForUpdates(_ enabled: Bool)

    /// 保存されているスキップ対象バージョン文字列を読み込む
    /// - Returns: スキップ設定されているバージョン文字列（未保存時は nil）
    func loadSkippedUpdateVersion() -> String?

    /// スキップ対象バージョン文字列を保存する（nil または空文字で解除）
    /// - Parameter version: スキップするバージョン文字列
    func saveSkippedUpdateVersion(_ version: String?)
}
