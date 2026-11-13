import Foundation
import Testing
@testable import WintchCore

/// ShortcutPreference のデフォルト値・永続化互換・競合判定を検証するテストスイート
@Suite("ShortcutPreference テスト")
struct ShortcutPreferenceTests {
    /// デフォルト値が Option + Tab であることを検証する
    @Test("デフォルトショートカットは Option + Tab")
    func defaultShortcutIsOptionTab() {
        let pref = ShortcutPreference.default
        #expect(pref.modifier == .option)
        #expect(pref.trigger == .tab)
        #expect(pref.displayString == "⌥ + ⇥")
        #expect(pref.reverseDisplayString == "⌥ + ⇧ + ⇥")
        #expect(pref.conflictsWithSystemSwitcher == false)
    }

    /// Command + Tab のときのみシステム競合フラグが立つことを検証する
    @Test("Command + Tab 選択時のみシステム競合警告フラグが有効になる")
    func commandTabFlagsConflict() {
        let cmdTab = ShortcutPreference(modifier: .command, trigger: .tab)
        let cmdSpace = ShortcutPreference(modifier: .command, trigger: .space)
        let ctrlTab = ShortcutPreference(modifier: .control, trigger: .tab)

        #expect(cmdTab.conflictsWithSystemSwitcher == true)
        #expect(cmdSpace.conflictsWithSystemSwitcher == false)
        #expect(ctrlTab.conflictsWithSystemSwitcher == false)
    }

    /// Codable によるエンコードとデコードが可逆であることを検証する
    @Test("Codable のエンコード・デコードで値が保持される")
    func codableRoundTrip() throws {
        let original = ShortcutPreference(modifier: .control, trigger: .grave)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShortcutPreference.self, from: data)
        #expect(decoded == original)
    }
}
