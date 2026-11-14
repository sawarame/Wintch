import Testing
@testable import WintchCore

/// HotKeyMonitorService のモード別キー判定および消費ルールを検証するテストスイート
@Suite("HotKeyMonitorService 判定テスト")
struct HotKeyMonitorDecisionTests {
    /// デフォルト設定（通常: Option + Tab、ランチャー: Option + Space）でのランチャー中キー判定を検証する
    @Test("ランチャー表示中に通常スイッチャー順方向ショートカットで次移動イベントを通知し消費する")
    func launcherModeNormalForwardShortcutNotifiesAndConsumes() {
        let decision = HotKeyMonitorService.resolveKeyDown(
            mode: .launcher,
            keyCode: TriggerKeyOption.tab.keyCode,
            modifiers: [.option],
            shortcut: .default,
            launcherShortcut: .default
        )

        #expect(decision == HotKeyKeyDownDecision(
            event: .triggerPressed(isShiftPressed: false),
            shouldConsume: true
        ))
    }

    /// ランチャー表示中に通常スイッチャー逆方向ショートカット（Shift 併用）が押された場合の判定を検証する
    @Test("ランチャー表示中に通常スイッチャー逆方向ショートカットで前移動イベントを通知し消費する")
    func launcherModeNormalReverseShortcutNotifiesAndConsumes() {
        let decision = HotKeyMonitorService.resolveKeyDown(
            mode: .launcher,
            keyCode: TriggerKeyOption.tab.keyCode,
            modifiers: [.option, .shift],
            shortcut: .default,
            launcherShortcut: .default
        )

        #expect(decision == HotKeyKeyDownDecision(
            event: .triggerPressed(isShiftPressed: true),
            shouldConsume: true
        ))
    }

    /// ランチャー表示中にランチャーショートカット再押下と Esc・矢印・文字キーの通過が維持されることを検証する
    @Test("ランチャー表示中は再押下をトグル消費し Esc・矢印・文字入力は通過させる")
    func launcherModePreservesToggleAndPassThroughKeys() {
        let toggleDecision = HotKeyMonitorService.resolveKeyDown(
            mode: .launcher,
            keyCode: LauncherShortcutPreference.default.keyCode,
            modifiers: LauncherShortcutPreference.default.modifiers,
            shortcut: .default,
            launcherShortcut: .default
        )
        #expect(toggleDecision == HotKeyKeyDownDecision(
            event: .launcherTriggerPressed,
            shouldConsume: true
        ))

        // Esc (53), 上矢印 (126), 下矢印 (125), A キー (0) はすべてキーウィンドウ側へ通過する
        for keyCode in [UInt16(53), 126, 125, 0] {
            let passThroughDecision = HotKeyMonitorService.resolveKeyDown(
                mode: .launcher,
                keyCode: keyCode,
                modifiers: [],
                shortcut: .default,
                launcherShortcut: .default
            )
            #expect(passThroughDecision == HotKeyKeyDownDecision(
                event: nil,
                shouldConsume: false
            ))
        }
    }

    /// トリガーキー長押しによる連続キーリピート相当入力でも毎回通知・消費されることを検証する
    @Test("ランチャー表示中の通常ショートカット連続入力で毎回通知および消費が行われる")
    func launcherModeRepeatedNormalShortcutEventsAreConsumed() {
        for _ in 0..<3 {
            let decision = HotKeyMonitorService.resolveKeyDown(
                mode: .launcher,
                keyCode: TriggerKeyOption.tab.keyCode,
                modifiers: [.option],
                shortcut: .default,
                launcherShortcut: .default
            )
            #expect(decision.event == .triggerPressed(isShiftPressed: false))
            #expect(decision.shouldConsume == true)
        }
    }

    /// カスタマイズされた通常ショートカット設定（単一修飾・複数修飾）にもランチャー内の順逆判定が追従することを検証する
    @Test("カスタマイズ済み通常ショートカットでもランチャー表示中の次/前移動が正しく判定される")
    func launcherModeFollowsCustomizedNormalShortcuts() {
        let customSingle = ShortcutPreference(modifier: .control, trigger: .grave)
        let customMulti = ShortcutPreference(keyCode: 45, modifiers: [.control, .option], keyLabel: "N")

        let forwardSingle = HotKeyMonitorService.resolveKeyDown(
            mode: .launcher,
            keyCode: TriggerKeyOption.grave.keyCode,
            modifiers: [.control],
            shortcut: customSingle,
            launcherShortcut: .default
        )
        #expect(forwardSingle == HotKeyKeyDownDecision(
            event: .triggerPressed(isShiftPressed: false),
            shouldConsume: true
        ))

        let reverseSingle = HotKeyMonitorService.resolveKeyDown(
            mode: .launcher,
            keyCode: TriggerKeyOption.grave.keyCode,
            modifiers: [.control, .shift],
            shortcut: customSingle,
            launcherShortcut: .default
        )
        #expect(reverseSingle == HotKeyKeyDownDecision(
            event: .triggerPressed(isShiftPressed: true),
            shouldConsume: true
        ))

        let forwardMulti = HotKeyMonitorService.resolveKeyDown(
            mode: .launcher,
            keyCode: 45,
            modifiers: [.control, .option],
            shortcut: customMulti,
            launcherShortcut: .default
        )
        #expect(forwardMulti == HotKeyKeyDownDecision(
            event: .triggerPressed(isShiftPressed: false),
            shouldConsume: true
        ))

        // デフォルトの Option + Tab は設定変更後は無視されない（通常通り通過）
        let oldDefaultPassThrough = HotKeyMonitorService.resolveKeyDown(
            mode: .launcher,
            keyCode: TriggerKeyOption.tab.keyCode,
            modifiers: [.option],
            shortcut: customSingle,
            launcherShortcut: .default
        )
        #expect(oldDefaultPassThrough == HotKeyKeyDownDecision(
            event: nil,
            shouldConsume: false
        ))
    }

    /// 通常モード表示中のランチャーショートカット無視、および万一の設定重複時のランチャー優先を検証する
    @Test("通常モード中のランチャーショートカットは無視消費され重複設定時はランチャーが優先される")
    func normalModeIgnoresLauncherAndDuplicatePrefersLauncher() {
        let normalIgnoringLauncher = HotKeyMonitorService.resolveKeyDown(
            mode: .normal,
            keyCode: LauncherShortcutPreference.default.keyCode,
            modifiers: LauncherShortcutPreference.default.modifiers,
            shortcut: .default,
            launcherShortcut: .default
        )
        #expect(normalIgnoringLauncher == HotKeyKeyDownDecision(
            event: nil,
            shouldConsume: true
        ))

        // 外部編集などで同一キーになっていた場合もランチャー中の再押下はトグル終了が優先される
        let overlappingShortcut = ShortcutPreference(modifier: .option, trigger: .space)
        let duplicateDecision = HotKeyMonitorService.resolveKeyDown(
            mode: .launcher,
            keyCode: LauncherShortcutPreference.default.keyCode,
            modifiers: LauncherShortcutPreference.default.modifiers,
            shortcut: overlappingShortcut,
            launcherShortcut: .default
        )
        #expect(duplicateDecision == HotKeyKeyDownDecision(
            event: .launcherTriggerPressed,
            shouldConsume: true
        ))
    }
}
