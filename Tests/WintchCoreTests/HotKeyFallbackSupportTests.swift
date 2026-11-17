import Foundation
import Testing
@testable import WintchCore

/// セキュア入力フォールバック支援ロジック（重複排除・Carbon登録計画・解放ガード）を検証するテストスイート
@Suite("HotKeyFallbackSupport テスト")
struct HotKeyFallbackSupportTests {
    /// 異種経路（CGEventTap ⇄ Carbon）間で 0.15 秒以内の同一トリガーが重複排除されることを検証する
    @Test("HotKeyTriggerDeduplicator は異種経路間の時間窓内重複を破棄し同一経路連打と窓外は受理する")
    func deduplicatorRejectsCrossSourceDuplicateAndAllowsSameSourceOrExpiredWindow() {
        var deduplicator = HotKeyTriggerDeduplicator(deduplicationWindowSeconds: 0.15)

        // 主経路 CGEventTap での通常順方向起動を受理
        #expect(deduplicator.shouldAccept(source: .cgEventTap, kind: .normalForward, at: 10.0) == true)
        // 直後（0.05秒後）の Carbon からの同一トリガーは二重発火として破棄
        #expect(deduplicator.shouldAccept(source: .carbonHotKey, kind: .normalForward, at: 10.05) == false)
        // 同一経路 CGEventTap での高速連打（0.08秒後）は受理
        #expect(deduplicator.shouldAccept(source: .cgEventTap, kind: .normalForward, at: 10.08) == true)
        // 0.15秒境界以降（10.08 + 0.15 = 10.23）は受理
        #expect(deduplicator.shouldAccept(source: .carbonHotKey, kind: .normalForward, at: 10.23) == true)

        // 別種別（逆順やランチャー）は直後でも別操作として受理
        #expect(deduplicator.shouldAccept(source: .cgEventTap, kind: .normalReverse, at: 10.25) == true)
        #expect(deduplicator.shouldAccept(source: .carbonHotKey, kind: .launcher, at: 10.26) == true)

        // reset 後は同一時刻帯の異種経路でも受理される
        deduplicator.reset()
        #expect(deduplicator.shouldAccept(source: .cgEventTap, kind: .launcher, at: 10.27) == true)
    }

    /// Carbon 先着後に CGEventTap が遅れて到着した場合も重複排除されることを検証する
    @Test("Carbon 先着直後の CGEventTap 到着も重複排除される")
    func deduplicatorRejectsTapFollowingCarbonWithinWindow() {
        var deduplicator = HotKeyTriggerDeduplicator(deduplicationWindowSeconds: 0.15)

        #expect(deduplicator.shouldAccept(source: .carbonHotKey, kind: .launcher, at: 20.0) == true)
        #expect(deduplicator.shouldAccept(source: .cgEventTap, kind: .launcher, at: 20.02) == false)
    }

    /// ショートカット設定から順方向・逆順・ランチャーの Carbon 登録仕様が生成され、記録中は空になることを検証する
    @Test("CarbonHotKeyRegistrationPlan は通常順逆とランチャーの3件を生成し記録サスペンド中は空を返す")
    func registrationPlanBuildsExpectedSpecsAndRespectsSuspension() {
        let normal = ShortcutPreference(modifier: .option, trigger: .tab)
        let launcher = LauncherShortcutPreference.default

        let activeSpecs = CarbonHotKeyRegistrationPlan.build(
            shortcut: normal,
            launcherShortcut: launcher,
            isSuspendedForRecording: false
        )

        #expect(activeSpecs == [
            CarbonHotKeySpec(
                id: CarbonHotKeyRegistrationPlan.normalForwardID,
                keyCode: UInt32(TriggerKeyOption.tab.keyCode),
                carbonModifiers: CarbonHotKeyRegistrationPlan.optionKeyMask,
                triggerKind: .normalForward
            ),
            CarbonHotKeySpec(
                id: CarbonHotKeyRegistrationPlan.normalReverseID,
                keyCode: UInt32(TriggerKeyOption.tab.keyCode),
                carbonModifiers: CarbonHotKeyRegistrationPlan.optionKeyMask | CarbonHotKeyRegistrationPlan.shiftKeyMask,
                triggerKind: .normalReverse
            ),
            CarbonHotKeySpec(
                id: CarbonHotKeyRegistrationPlan.launcherID,
                keyCode: UInt32(LauncherShortcutPreference.default.keyCode),
                carbonModifiers: CarbonHotKeyRegistrationPlan.optionKeyMask,
                triggerKind: .launcher
            )
        ])

        // 記録サスペンド中は全登録を解除するため空配列になる
        let suspendedSpecs = CarbonHotKeyRegistrationPlan.build(
            shortcut: normal,
            launcherShortcut: launcher,
            isSuspendedForRecording: true
        )
        #expect(suspendedSpecs.isEmpty)
    }

    /// カスタマイズされた複数修飾キーショートカットでも Carbon 修飾ビットマスクが正しく変換されることを検証する
    @Test("複数修飾キー設定でも Carbon 修飾マスクへ正確に変換される")
    func registrationPlanConvertsCombinedModifiers() {
        let customNormal = ShortcutPreference(keyCode: 45, modifiers: [.control, .option], keyLabel: "N")
        let customLauncher = LauncherShortcutPreference(keyCode: 49, modifiers: [.command, .shift], keyLabel: "Space")

        let specs = CarbonHotKeyRegistrationPlan.build(
            shortcut: customNormal,
            launcherShortcut: customLauncher,
            isSuspendedForRecording: false
        )

        #expect(specs.count == 3)
        #expect(specs[0].carbonModifiers == (
            CarbonHotKeyRegistrationPlan.controlKeyMask | CarbonHotKeyRegistrationPlan.optionKeyMask
        ))
        #expect(specs[1].carbonModifiers == (
            CarbonHotKeyRegistrationPlan.controlKeyMask
            | CarbonHotKeyRegistrationPlan.optionKeyMask
            | CarbonHotKeyRegistrationPlan.shiftKeyMask
        ))
        #expect(specs[2].carbonModifiers == (
            CarbonHotKeyRegistrationPlan.cmdKeyMask | CarbonHotKeyRegistrationPlan.shiftKeyMask
        ))
    }

    /// 必須修飾キーが欠落した不正設定は登録計画から除外されることを検証する
    @Test("主要修飾キーを含まない設定は Carbon 登録対象から除外される")
    func registrationPlanSkipsInvalidModifierPreferences() {
        let invalidNormal = ShortcutPreference(keyCode: 48, modifiers: [], keyLabel: "Tab")
        let validLauncher = LauncherShortcutPreference.default

        let specs = CarbonHotKeyRegistrationPlan.build(
            shortcut: invalidNormal,
            launcherShortcut: validLauncher,
            isSuspendedForRecording: false
        )

        #expect(specs.count == 1)
        #expect(specs[0].id == CarbonHotKeyRegistrationPlan.launcherID)
    }

    /// セキュア入力保護中の解放誤検知ガードと解除後／アクティブ猶予後の解放検知を検証する
    @Test("HotKeySecureInputGuard はセキュア入力中のゼロ化誤検知を防ぎ解除後または猶予後に解放確定する")
    func secureInputGuardPreventsFalseReleaseWhileProtected() {
        // セキュア入力が有効かつ未アクティブ状態では、見かけ上フラグが 0 でも解放扱いしない
        #expect(HotKeySecureInputGuard.shouldTreatModifiersAsReleased(
            requiredModifiers: [.option],
            observedModifiers: [],
            isSecureInputEnabled: true,
            isAppActive: false,
            elapsedSincePresentation: 0.01
        ) == false)

        // セキュア入力が有効かつアクティブ直後（猶予 0.05秒未満）は待機する
        #expect(HotKeySecureInputGuard.shouldTreatModifiersAsReleased(
            requiredModifiers: [.option],
            observedModifiers: [],
            isSecureInputEnabled: true,
            isAppActive: true,
            elapsedSincePresentation: 0.02
        ) == false)

        // セキュア入力が解除されていれば即座に解放扱いとする
        #expect(HotKeySecureInputGuard.shouldTreatModifiersAsReleased(
            requiredModifiers: [.option],
            observedModifiers: [],
            isSecureInputEnabled: false,
            isAppActive: false,
            elapsedSincePresentation: 0.01
        ) == true)

        // セキュア入力が他アプリに残っていても自アプリ前面化後の猶予経過後は解放扱いとする
        #expect(HotKeySecureInputGuard.shouldTreatModifiersAsReleased(
            requiredModifiers: [.option],
            observedModifiers: [],
            isSecureInputEnabled: true,
            isAppActive: true,
            elapsedSincePresentation: 0.05
        ) == true)

        // 必須修飾キーがまだ押下されている場合は常に false
        #expect(HotKeySecureInputGuard.shouldTreatModifiersAsReleased(
            requiredModifiers: [.option],
            observedModifiers: [.option, .shift],
            isSecureInputEnabled: false,
            isAppActive: true,
            elapsedSincePresentation: 0.2
        ) == false)
    }

    /// ランチャートリガー（id=3）の重複排除と各モードでのイベント変換整合性を検証する (US2)
    @Test("ランチャートリガーの異種経路重複排除とイベント変換整合性が保たれる")
    func launcherTriggerDeduplicationAndEventMapping() {
        var deduplicator = HotKeyTriggerDeduplicator(deduplicationWindowSeconds: 0.15)

        // セキュア入力中の Carbon 経由ランチャー起動が受理され、直後の CGEventTap 重複は破棄される
        #expect(deduplicator.shouldAccept(source: .carbonHotKey, kind: .launcher, at: 30.0) == true)
        #expect(deduplicator.shouldAccept(source: .cgEventTap, kind: .launcher, at: 30.04) == false)

        // 時間窓経過後の再押下（トグル終了）は受理される
        #expect(deduplicator.shouldAccept(source: .cgEventTap, kind: .launcher, at: 30.25) == true)

        // TriggerKind と HotKeyEvent の双方向変換が一致する
        #expect(HotKeyTriggerKind.normalForward.hotKeyEvent == .triggerPressed(isShiftPressed: false))
        #expect(HotKeyTriggerKind.normalReverse.hotKeyEvent == .triggerPressed(isShiftPressed: true))
        #expect(HotKeyTriggerKind.launcher.hotKeyEvent == .launcherTriggerPressed)
        #expect(HotKeyTriggerKind.from(event: .triggerPressed(isShiftPressed: false)) == .normalForward)
        #expect(HotKeyTriggerKind.from(event: .triggerPressed(isShiftPressed: true)) == .normalReverse)
        #expect(HotKeyTriggerKind.from(event: .launcherTriggerPressed) == .launcher)
        #expect(HotKeyTriggerKind.from(event: .escapePressed) == nil)
        #expect(HotKeyTriggerKind.from(event: .modifierReleased) == nil)
    }

    /// セキュア入力残留や頻繁なフォーカス往復後も経路切替が固着せず連続利用できることを検証する (US3)
    @Test("セキュア入力残留中の連続 Carbon 起動および保護解除後の経路往復帰で固着しない")
    func repeatedFallbackAndRecoveryRoundTripsDoNotStall() {
        var deduplicator = HotKeyTriggerDeduplicator(deduplicationWindowSeconds: 0.15)

        // セキュア入力残留中に Carbon だけで連続操作（Tab 連打相当）しても毎回受理される
        #expect(deduplicator.shouldAccept(source: .carbonHotKey, kind: .normalForward, at: 40.0) == true)
        #expect(deduplicator.shouldAccept(source: .carbonHotKey, kind: .normalForward, at: 40.06) == true)
        #expect(deduplicator.shouldAccept(source: .carbonHotKey, kind: .normalReverse, at: 40.10) == true)

        // フォーカス解除後に通常 CGEventTap 経路へ戻った際も、十分な間隔があれば即座に通常経路が受理される
        #expect(deduplicator.shouldAccept(source: .cgEventTap, kind: .normalForward, at: 40.30) == true)
        // 再びパスワード欄に戻り別タイミング（0.2秒後）で Carbon が動いても問題なく受理される
        #expect(deduplicator.shouldAccept(source: .carbonHotKey, kind: .normalForward, at: 40.50) == true)
    }

    /// ショートカット変更時の Carbon 登録計画の差し替えと、記録サスペンド時の全解除を検証する (US4)
    @Test("ショートカット変更で旧登録が置き換わり記録サスペンド時は空リストになる")
    func registrationPlanReplacesOldShortcutsAndClearsWhenSuspended() {
        let initialNormal = ShortcutPreference(modifier: .option, trigger: .tab)
        let updatedNormal = ShortcutPreference(modifier: .control, trigger: .grave)
        let initialLauncher = LauncherShortcutPreference.default
        let updatedLauncher = LauncherShortcutPreference(keyCode: 49, modifiers: [.control, .option], keyLabel: "Space")

        let beforeSpecs = CarbonHotKeyRegistrationPlan.build(
            shortcut: initialNormal,
            launcherShortcut: initialLauncher,
            isSuspendedForRecording: false
        )
        let afterSpecs = CarbonHotKeyRegistrationPlan.build(
            shortcut: updatedNormal,
            launcherShortcut: updatedLauncher,
            isSuspendedForRecording: false
        )

        #expect(beforeSpecs != afterSpecs)
        // 変更後の順方向・逆方向・ランチャーがすべて新設定に切り替わっている
        #expect(afterSpecs[0].keyCode == UInt32(TriggerKeyOption.grave.keyCode))
        #expect(afterSpecs[0].carbonModifiers == CarbonHotKeyRegistrationPlan.controlKeyMask)
        #expect(afterSpecs[1].carbonModifiers == (
            CarbonHotKeyRegistrationPlan.controlKeyMask | CarbonHotKeyRegistrationPlan.shiftKeyMask
        ))
        #expect(afterSpecs[2].carbonModifiers == (
            CarbonHotKeyRegistrationPlan.controlKeyMask | CarbonHotKeyRegistrationPlan.optionKeyMask
        ))

        // 記録サスペンド中はすべて解除対象となる
        #expect(CarbonHotKeyRegistrationPlan.build(
            shortcut: updatedNormal,
            launcherShortcut: updatedLauncher,
            isSuspendedForRecording: true
        ).isEmpty)
    }
}
