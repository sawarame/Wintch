import Foundation
import Testing
@testable import WintchCore

/// LauncherShortcutPreference のデフォルト値・表示書式・Codable 永続化を検証するテストスイート
@Suite("LauncherShortcutPreference テスト")
struct LauncherShortcutPreferenceTests {
    /// デフォルト設定が Option + Space であることを検証する
    @Test("デフォルトのランチャーショートカットは Option + Space")
    func defaultLauncherShortcutIsOptionSpace() {
        let pref = LauncherShortcutPreference.default
        #expect(pref.keyCode == 49)
        #expect(pref.modifiers == [.option])
        #expect(pref.keyLabel == "Space")
        #expect(pref.displayString == "⌥ + Space")
    }

    /// 修飾キー記号の並び順（⌃ → ⌥ → ⇧ → ⌘）と表示文字列を検証する
    @Test("複数修飾キーの表示順が macOS 標準順になる")
    func displayStringFollowsMacOSOrder() {
        let pref = LauncherShortcutPreference(
            keyCode: 40,
            modifiers: [.command, .shift, .control],
            keyLabel: "K"
        )
        #expect(pref.displayString == "⌃ + ⇧ + ⌘ + K")
    }

    /// JSON エンコード・デコードの往復で値が保持されることを検証する
    @Test("Codable のエンコード・デコードで値が保持される")
    func codableRoundTrip() throws {
        let original = LauncherShortcutPreference(
            keyCode: 3,
            modifiers: [.control, .option],
            keyLabel: "F"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LauncherShortcutPreference.self, from: data)
        #expect(decoded == original)
    }

    /// PreferencesStore を介してランチャーショートカットを保存・復元できることを検証する
    @Test("PreferencesStore でランチャーショートカットの保存と読み込みができる")
    func preferencesStorePersistsLauncherShortcut() {
        let suiteName = "dev.wintch.tests.launcher.\(UUID().uuidString)"
        let store = PreferencesStore(suiteName: suiteName)
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        // 未保存時はデフォルト値（Option + Space）が返る
        #expect(store.loadLauncherShortcut() == .default)

        let custom = LauncherShortcutPreference(keyCode: 40, modifiers: [.command, .shift], keyLabel: "K")
        store.saveLauncherShortcut(custom)
        #expect(store.loadLauncherShortcut() == custom)
    }
}
