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

    /// 通常スイッチャー表示中に修飾キー + Q が押された場合のクローズイベント通知と優先順位を検証する
    @Test("通常モード表示中に修飾キー＋Qでクローズイベントを通知し消費する")
    func normalModeCloseWindowShortcutNotifiesAndConsumes() {
        let qKeyCode: UInt16 = 12

        // デフォルト設定（Option + Q）
        let closeDecision = HotKeyMonitorService.resolveKeyDown(
            mode: .normal,
            keyCode: qKeyCode,
            modifiers: [.option],
            shortcut: .default,
            launcherShortcut: .default
        )
        #expect(closeDecision == HotKeyKeyDownDecision(
            event: .closeSelectedWindowPressed,
            shouldConsume: true
        ))

        // 逆順移動直後などで Shift が残った状態（Option + Shift + Q）でも反応して消費する
        let shiftCloseDecision = HotKeyMonitorService.resolveKeyDown(
            mode: .normal,
            keyCode: qKeyCode,
            modifiers: [.option, .shift],
            shortcut: .default,
            launcherShortcut: .default
        )
        #expect(shiftCloseDecision == HotKeyKeyDownDecision(
            event: .closeSelectedWindowPressed,
            shouldConsume: true
        ))

        // 必須修飾キーなし単体 Q は通常モードでもクローズに一致しない
        let plainQDecision = HotKeyMonitorService.resolveKeyDown(
            mode: .normal,
            keyCode: qKeyCode,
            modifiers: [],
            shortcut: .default,
            launcherShortcut: .default
        )
        #expect(plainQDecision == HotKeyKeyDownDecision(
            event: nil,
            shouldConsume: false
        ))

        // 通常モード中の Esc・矢印・通常移動は従来通り優先される
        #expect(HotKeyMonitorService.resolveKeyDown(
            mode: .normal,
            keyCode: 53,
            modifiers: [.option],
            shortcut: .default,
            launcherShortcut: .default
        ) == HotKeyKeyDownDecision(event: .escapePressed, shouldConsume: true))
    }

    /// ランチャー表示中に修飾キー + Q が消費され、単体 Q / Shift + Q は検索入力として通過することを検証する
    @Test("ランチャー表示中は修飾キー＋Qのみを閉操作として消費し単体QとShift+Qは文字入力へ通過させる")
    func launcherModeCloseWindowConsumesModifiedQAndPassesPlainQ() {
        let qKeyCode = HotKeyMonitorService.closeWindowKeyCode

        // デフォルト設定（Option + Q）はクローズイベントとして通知・消費される
        #expect(HotKeyMonitorService.resolveKeyDown(
            mode: .launcher,
            keyCode: qKeyCode,
            modifiers: [.option],
            shortcut: .default,
            launcherShortcut: .default
        ) == HotKeyKeyDownDecision(event: .closeSelectedWindowPressed, shouldConsume: true))

        // 単体 Q および Shift + Q は検索入力欄への文字入力として通過させる
        for modifiers: ShortcutModifiers in [[], [.shift]] {
            #expect(HotKeyMonitorService.resolveKeyDown(
                mode: .launcher,
                keyCode: qKeyCode,
                modifiers: modifiers,
                shortcut: .default,
                launcherShortcut: .default
            ) == HotKeyKeyDownDecision(event: nil, shouldConsume: false))
        }

        // カスタム修飾キー（Control / 複数修飾キー）にも追従し、旧修飾キー Option + Q は通過する
        let customControl = ShortcutPreference(modifier: .control, trigger: .tab)
        #expect(HotKeyMonitorService.resolveKeyDown(
            mode: .launcher,
            keyCode: qKeyCode,
            modifiers: [.control],
            shortcut: customControl,
            launcherShortcut: .default
        ) == HotKeyKeyDownDecision(event: .closeSelectedWindowPressed, shouldConsume: true))
        #expect(HotKeyMonitorService.resolveKeyDown(
            mode: .launcher,
            keyCode: qKeyCode,
            modifiers: [.option],
            shortcut: customControl,
            launcherShortcut: .default
        ) == HotKeyKeyDownDecision(event: nil, shouldConsume: false))

        let customMulti = ShortcutPreference(keyCode: 45, modifiers: [.control, .option], keyLabel: "N")
        #expect(HotKeyMonitorService.resolveKeyDown(
            mode: .launcher,
            keyCode: qKeyCode,
            modifiers: [.control, .option],
            shortcut: customMulti,
            launcherShortcut: .default
        ) == HotKeyKeyDownDecision(event: .closeSelectedWindowPressed, shouldConsume: true))

        // ランチャーショートカットや通常スイッチャーショートカットが万一 Q と一致する場合は既存操作が優先される
        let launcherUsingOptionQ = LauncherShortcutPreference(keyCode: qKeyCode, modifiers: [.option], keyLabel: "Q")
        #expect(HotKeyMonitorService.resolveKeyDown(
            mode: .launcher,
            keyCode: qKeyCode,
            modifiers: [.option],
            shortcut: .default,
            launcherShortcut: launcherUsingOptionQ
        ) == HotKeyKeyDownDecision(event: .launcherTriggerPressed, shouldConsume: true))
    }

    /// 通常スイッチャー修飾キーが Command に設定されている場合、Command + Q がアプリ終了に漏れず消費されることを検証する
    @Test("Command修飾キー設定時のCommand+Qは通常・ランチャー双方で消費され誤終了を防ぐ")
    func commandModifierCloseWindowConsumesCommandQ() {
        let qKeyCode = HotKeyMonitorService.closeWindowKeyCode
        let commandTab = ShortcutPreference(modifier: .command, trigger: .tab)

        for mode: HotKeyMonitorMode in [.normal, .launcher] {
            let decision = HotKeyMonitorService.resolveKeyDown(
                mode: mode,
                keyCode: qKeyCode,
                modifiers: [.command],
                shortcut: commandTab,
                launcherShortcut: .default
            )
            #expect(decision == HotKeyKeyDownDecision(
                event: .closeSelectedWindowPressed,
                shouldConsume: true
            ))
        }

        // 非表示状態 (.inactive) では Command + Q を横取りせず OS 標準の終了操作へ通す
        #expect(HotKeyMonitorService.resolveKeyDown(
            mode: .inactive,
            keyCode: qKeyCode,
            modifiers: [.command],
            shortcut: commandTab,
            launcherShortcut: .default
        ) == HotKeyKeyDownDecision(event: nil, shouldConsume: false))
    }

    /// タイムアウト無効化がバースト上限を超えた場合にクールダウンおよび自動再有効化停止へ段階遷移することを検証する
    @Test("TapTimeoutRecoveryTracker はバースト時にクールダウン・上限超過時に自動停止を返す")
    func tapTimeoutRecoveryEscalatesToCooldownAndCircuitBreaker() {
        var tracker = TapTimeoutRecoveryTracker(
            burstWindowSeconds: 10.0,
            maxImmediateRetriesInWindow: 3,
            cooldownSeconds: 5.0,
            longWindowSeconds: 60.0,
            maxTotalRetriesInLongWindow: 6
        )

        // 1〜3回目はバースト上限内のため即時再有効化
        #expect(tracker.recordDisableEvent(at: 100.0) == .reenableImmediately)
        #expect(tracker.recordDisableEvent(at: 101.0) == .reenableImmediately)
        #expect(tracker.recordDisableEvent(at: 102.0) == .reenableImmediately)

        // 4〜6回目はバースト上限超過のためクールダウン待機へ移行
        #expect(tracker.recordDisableEvent(at: 103.0) == .reenableAfterCooldown(seconds: 5.0))
        #expect(tracker.recordDisableEvent(at: 104.0) == .reenableAfterCooldown(seconds: 5.0))
        #expect(tracker.recordDisableEvent(at: 105.0) == .reenableAfterCooldown(seconds: 5.0))

        // 7回目以降は長期ウィンドウの上限超過によりサーキットブレーカー発動
        #expect(tracker.recordDisableEvent(at: 106.0) == .stopAutoReenable)
        #expect(tracker.recordDisableEvent(at: 120.0) == .stopAutoReenable)

        // 長期ウィンドウ (60秒) を十分に過ぎると履歴が失効して再び即時再有効化へ戻る
        #expect(tracker.recordDisableEvent(at: 200.0) == .reenableImmediately)
    }

    /// リセット呼び出しによってタイムアウト履歴がクリアされ、再度即時再有効化から再開できることを検証する
    @Test("TapTimeoutRecoveryTracker は reset により履歴を初期化する")
    func tapTimeoutRecoveryResetRestoresImmediateReenable() {
        var tracker = TapTimeoutRecoveryTracker(
            burstWindowSeconds: 10.0,
            maxImmediateRetriesInWindow: 2,
            cooldownSeconds: 4.0,
            longWindowSeconds: 60.0,
            maxTotalRetriesInLongWindow: 3
        )

        #expect(tracker.recordDisableEvent(at: 10.0) == .reenableImmediately)
        #expect(tracker.recordDisableEvent(at: 11.0) == .reenableImmediately)
        #expect(tracker.recordDisableEvent(at: 12.0) == .reenableAfterCooldown(seconds: 4.0))
        #expect(tracker.recordDisableEvent(at: 13.0) == .stopAutoReenable)

        tracker.reset()
        #expect(tracker.recordDisableEvent(at: 14.0) == .reenableImmediately)
    }

    /// HotKeyMonitorService と WindowService の保護設定値および停止時状態リセットを検証する
    @Test("HotKeyMonitorService の停止処理と WindowService のタイムアウト／デバウンス設定が安全に構成されている")
    @MainActor
    func serviceProtectionSettingsAndLifecycle() {
        let monitor = HotKeyMonitorService()
        monitor.activeMode = .normal
        #expect(monitor.isSwitcherActive == true)

        monitor.stopMonitoring()
        #expect(monitor.activeMode == .inactive)
        #expect(monitor.isSwitcherActive == false)

        // WindowService は短時間の AX IPC タイムアウトとデバウンス間隔を備え、開始・停止を安全に繰り返せる
        #expect(WindowService.axMessagingTimeoutSeconds > 0 && WindowService.axMessagingTimeoutSeconds <= 0.5)
        #expect(WindowService.titleChangeDebounceDuration > .zero)
        #expect(WindowService.spaceChangeDebounceDuration > .zero)

        let windowService = WindowService()
        windowService.stopObserving()
        windowService.startObserving()
        windowService.stopObserving()
    }
}
