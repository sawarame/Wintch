import Foundation

/// UserDefaults を利用してショートカット設定を永続化するストア実装
public final class PreferencesStore: PreferencesStoring {
    /// 通常スイッチャー設定の永続化に使用する UserDefaults キー
    private static let shortcutKey = "dev.wintch.shortcutPreference"

    /// ランチャー設定の永続化に使用する UserDefaults キー
    private static let launcherShortcutKey = "dev.wintch.launcherShortcutPreference"

    /// 通常スイッチャー表示形式の永続化に使用する UserDefaults キー
    private static let normalDisplayStyleKey = "dev.wintch.normalDisplayStyle"

    /// 検索ランチャー表示形式の永続化に使用する UserDefaults キー
    private static let launcherDisplayStyleKey = "dev.wintch.launcherDisplayStyle"

    /// 通常スイッチャーのアプリグルーピング設定の永続化に使用する UserDefaults キー
    private static let groupNormalSwitcherByAppKey = "dev.wintch.groupNormalSwitcherByApp"

    /// 検索ランチャーのアプリグルーピング設定の永続化に使用する UserDefaults キー
    private static let groupLauncherByAppKey = "dev.wintch.groupLauncherByApp"

    /// アプリの表示言語設定の永続化に使用する UserDefaults キー
    private static let appLanguageKey = "dev.wintch.appLanguage"

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

    /// 保存されている通常スイッチャーの表示形式設定を読み込む
    /// - Returns: 保存された表示形式設定（未保存または不正値の場合はデフォルトの .list）
    public func loadNormalDisplayStyle() -> SwitcherDisplayStyle {
        guard let rawValue = resolveDefaults().string(forKey: Self.normalDisplayStyleKey),
              let style = SwitcherDisplayStyle(rawValue: rawValue) else {
            return .default
        }
        return style
    }

    /// 通常スイッチャーの表示形式設定を保存する
    /// - Parameter style: 保存する表示形式設定
    public func saveNormalDisplayStyle(_ style: SwitcherDisplayStyle) {
        resolveDefaults().set(style.rawValue, forKey: Self.normalDisplayStyleKey)
    }

    /// 保存されている検索ランチャーの表示形式設定を読み込む
    /// - Returns: 保存された検索ランチャー表示形式設定（未保存または不正値の場合はデフォルトの .list）
    public func loadLauncherDisplayStyle() -> LauncherDisplayStyle {
        guard let rawValue = resolveDefaults().string(forKey: Self.launcherDisplayStyleKey),
              let style = LauncherDisplayStyle(rawValue: rawValue) else {
            return .default
        }
        return style
    }

    /// 検索ランチャーの表示形式設定を保存する
    /// - Parameter style: 保存する検索ランチャー表示形式設定
    public func saveLauncherDisplayStyle(_ style: LauncherDisplayStyle) {
        resolveDefaults().set(style.rawValue, forKey: Self.launcherDisplayStyleKey)
    }

    /// 保存されている通常スイッチャーのアプリグルーピング設定を読み込む
    /// - Returns: 保存された設定値（キー未保存時はデフォルトの true）
    public func loadGroupNormalSwitcherByApp() -> Bool {
        let defaults = resolveDefaults()
        // UserDefaults.bool(forKey:) は未保存時に false を返すため、キー存在確認でデフォルト true を保証する
        guard defaults.object(forKey: Self.groupNormalSwitcherByAppKey) != nil else {
            return true
        }
        return defaults.bool(forKey: Self.groupNormalSwitcherByAppKey)
    }

    /// 通常スイッチャーのアプリグルーピング設定を保存する
    /// - Parameter enabled: アプリごとにグルーピングする場合は true
    public func saveGroupNormalSwitcherByApp(_ enabled: Bool) {
        resolveDefaults().set(enabled, forKey: Self.groupNormalSwitcherByAppKey)
    }

    /// 保存されている検索ランチャーのアプリグルーピング設定を読み込む
    /// - Returns: 保存された設定値（キー未保存時はデフォルトの true）
    public func loadGroupLauncherByApp() -> Bool {
        let defaults = resolveDefaults()
        // UserDefaults.bool(forKey:) は未保存時に false を返すため、キー存在確認でデフォルト true を保証する
        guard defaults.object(forKey: Self.groupLauncherByAppKey) != nil else {
            return true
        }
        return defaults.bool(forKey: Self.groupLauncherByAppKey)
    }

    /// 検索ランチャーのアプリグルーピング設定を保存する
    /// - Parameter enabled: アプリごとにグルーピングする場合は true
    public func saveGroupLauncherByApp(_ enabled: Bool) {
        resolveDefaults().set(enabled, forKey: Self.groupLauncherByAppKey)
    }

    /// 保存されているアプリの表示言語設定を読み込む
    /// - Returns: 保存された言語設定（未保存または不正値時はデフォルトの .system）
    public func loadAppLanguage() -> AppLanguage {
        guard let rawValue = resolveDefaults().string(forKey: Self.appLanguageKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .default
        }
        return language
    }

    /// アプリの表示言語設定を保存する
    /// - Parameter language: 保存する言語設定
    public func saveAppLanguage(_ language: AppLanguage) {
        resolveDefaults().set(language.rawValue, forKey: Self.appLanguageKey)
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
