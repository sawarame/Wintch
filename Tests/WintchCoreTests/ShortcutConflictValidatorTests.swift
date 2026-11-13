import Foundation
import Testing
@testable import WintchCore

/// ShortcutConflictValidator の修飾キー必須チェックおよび双方向競合判定を検証するテストスイート
@Suite("ShortcutConflictValidator テスト")
struct ShortcutConflictValidatorTests {
    /// 修飾キーなし、または Shift のみのランチャーショートカットが拒否されることを検証する
    @Test("修飾キーなしや Shift のみの組み合わせを拒否する")
    func rejectsMissingPrimaryModifier() {
        let normal = ShortcutPreference.default

        let noMod = LauncherShortcutPreference(keyCode: 40, modifiers: [], keyLabel: "K")
        let shiftOnly = LauncherShortcutPreference(keyCode: 40, modifiers: [.shift], keyLabel: "K")

        if case .invalidModifier = ShortcutConflictValidator.validateLauncherShortcut(noMod, against: normal) {
            // 期待通り
        } else {
            Issue.record("修飾キーなしが許可されてしまいました")
        }

        if case .invalidModifier = ShortcutConflictValidator.validateLauncherShortcut(shiftOnly, against: normal) {
            // 期待通り
        } else {
            Issue.record("Shift のみの組み合わせが許可されてしまいました")
        }
    }

    /// 通常スイッチャーの順方向および逆方向（Shift 併用）との重複がブロックされることを検証する
    @Test("通常スイッチャーの順方向および逆方向と重複するランチャーショートカットを拒否する")
    func rejectsConflictWithNormalForwardAndReverse() {
        let normal = ShortcutPreference(modifier: .option, trigger: .tab)

        // 順方向 Option + Tab と重複
        let sameAsForward = LauncherShortcutPreference(keyCode: 48, modifiers: [.option], keyLabel: "⇥")
        // 逆方向 Option + Shift + Tab と重複
        let sameAsReverse = LauncherShortcutPreference(keyCode: 48, modifiers: [.option, .shift], keyLabel: "⇥")
        // 別キー Option + Space は有効
        let validLauncher = LauncherShortcutPreference.default

        if case .conflictWithNormalSwitcher = ShortcutConflictValidator.validateLauncherShortcut(sameAsForward, against: normal) {
            // 期待通り
        } else {
            Issue.record("通常順方向との重複が検知されませんでした")
        }

        if case .conflictWithNormalSwitcher = ShortcutConflictValidator.validateLauncherShortcut(sameAsReverse, against: normal) {
            // 期待通り
        } else {
            Issue.record("通常逆方向との重複が検知されませんでした")
        }

        #expect(ShortcutConflictValidator.validateLauncherShortcut(validLauncher, against: normal) == .valid)
    }

    /// 通常スイッチャー側をランチャーと重複する設定へ変更しようとした際も拒否されることを検証する
    @Test("通常スイッチャー側でランチャーと重複する組み合わせを拒否する")
    func rejectsNormalShortcutConflictingWithLauncher() {
        let launcher = LauncherShortcutPreference.default // Option + Space
        let conflictingNormal = ShortcutPreference(modifier: .option, trigger: .space)
        let nonConflictingNormal = ShortcutPreference(modifier: .control, trigger: .space)

        if case .conflictWithLauncher = ShortcutConflictValidator.validateNormalShortcut(conflictingNormal, against: launcher) {
            // 期待通り
        } else {
            Issue.record("通常設定側の重複が検知されませんでした")
        }

        #expect(ShortcutConflictValidator.validateNormalShortcut(nonConflictingNormal, against: launcher) == .valid)
    }

    /// 通常スイッチャーのキャプチャ入力で Shift 含み・修飾キーなしが拒否されることを検証する
    @Test("通常スイッチャー側で Shift を含む入力や修飾キーなしを拒否する")
    func rejectsShiftOrMissingPrimaryInNormalShortcut() {
        let launcher = LauncherShortcutPreference.default

        let withShift = ShortcutPreference(keyCode: 40, modifiers: [.option, .shift], keyLabel: "K")
        let noPrimary = ShortcutPreference(keyCode: 40, modifiers: [], keyLabel: "K")

        if case .invalidModifier = ShortcutConflictValidator.validateNormalShortcut(withShift, against: launcher) {
            // 期待通り
        } else {
            Issue.record("通常スイッチャーで Shift 含みが許可されてしまいました")
        }

        if case .invalidModifier = ShortcutConflictValidator.validateNormalShortcut(noPrimary, against: launcher) {
            // 期待通り
        } else {
            Issue.record("通常スイッチャーで修飾キーなしが許可されてしまいました")
        }
    }
}
