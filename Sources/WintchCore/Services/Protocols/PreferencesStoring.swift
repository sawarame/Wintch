import Foundation

/// ユーザー設定の保存と読み込みを行う永続化ストア契約
public protocol PreferencesStoring: Sendable {
    /// 保存されているショートカット設定を読み込む（未保存時はデフォルトの Option + Tab を返す）
    /// - Returns: 読み込まれたショートカット設定
    func loadShortcut() -> ShortcutPreference

    /// ショートカット設定を保存する
    /// - Parameter preference: 保存するショートカット設定
    func saveShortcut(_ preference: ShortcutPreference)
}
