import Foundation

/// UserDefaults を利用してショートカット設定を永続化するストア実装
public final class PreferencesStore: PreferencesStoring {
    /// 通常スイッチャー設定の永続化に使用する UserDefaults キー
    private static let shortcutKey = "dev.wintch.shortcutPreference"

    /// ランチャー設定の永続化に使用する UserDefaults キー
    private static let launcherShortcutKey = "dev.wintch.launcherShortcutPreference"

    /// 使用する UserDefaults スイート名（nil の場合は standard）
    private let suiteName: String?

    /// PreferencesStore を初期化する
    /// - Parameter suiteName: テストや分離用の UserDefaults スイート名（通常は nil）
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// 保存されている通常スイッチャーのショートカット設定を読み込む
    /// - Returns: 保存された設定（未保存または不正データの場合はデフォルトの Option + Tab）
    public func loadShortcut() -> ShortcutPreference {
        let defaults = resolveDefaults()
        guard let data = defaults.data(forKey: Self.shortcutKey),
              let decoded = try? JSONDecoder().decode(ShortcutPreference.self, from: data) else {
            return .default
        }
        return decoded
    }

    /// 通常スイッチャーのショートカット設定を保存する
    /// - Parameter preference: 保存するショートカット設定
    public func saveShortcut(_ preference: ShortcutPreference) {
        guard let data = try? JSONEncoder().encode(preference) else { return }
        resolveDefaults().set(data, forKey: Self.shortcutKey)
    }

    /// 保存されているランチャーのショートカット設定を読み込む
    /// - Returns: 保存されたランチャー設定（未保存または不正データの場合はデフォルトの Option + Space）
    public func loadLauncherShortcut() -> LauncherShortcutPreference {
        let defaults = resolveDefaults()
        guard let data = defaults.data(forKey: Self.launcherShortcutKey),
              let decoded = try? JSONDecoder().decode(LauncherShortcutPreference.self, from: data) else {
            return .default
        }
        return decoded
    }

    /// ランチャーのショートカット設定を保存する
    /// - Parameter preference: 保存するランチャーショートカット設定
    public func saveLauncherShortcut(_ preference: LauncherShortcutPreference) {
        guard let data = try? JSONEncoder().encode(preference) else { return }
        resolveDefaults().set(data, forKey: Self.launcherShortcutKey)
    }

    /// 設定用の UserDefaults インスタンスを解決する
    /// - Returns: 対象の UserDefaults
    private func resolveDefaults() -> UserDefaults {
        if let suiteName {
            return UserDefaults(suiteName: suiteName) ?? .standard
        }
        return .standard
    }
}
