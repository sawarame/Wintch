# サービス・UI 契約仕様 (Contracts): セキュア入力フォーカス中のショートカット起動と安定復帰

**Feature**: `013-fix-secure-input-hotkey` | **Date**: 2026-11-17

## 1. `HotKeyMonitoring` プロトコル契約 (`Sources/WintchCore/Services/Protocols/HotKeyMonitoring.swift`)

既存の `HotKeyEvent` ケース定義は維持し、通常スイッチャー表示時に一時アクティブ化が必要かを通知するための読み取りプロパティを追加する。

```swift
@MainActor
public protocol HotKeyMonitoring: AnyObject {
    // ... 既存プロパティ・メソッドを維持 ...

    /// 直近の起動トリガーにより通常スイッチャー表示時の一時アプリアクティブ化が必要かどうか
    var requiresAppActivationOnPresentation: Bool { get }
}
```

- デフォルト拡張または `MockHotKeyMonitor` 実装では `false` を既定値とし、既存モック・既存テストの互換性を維持する。

---

## 2. ドメイン契約 (`Sources/WintchCore/Domain/HotKeyFallbackSupport.swift`)

OS API 非依存の純粋ロジック契約：

1. **`HotKeyTriggerDeduplicator.shouldAccept(source:kind:at:) -> Bool`**
   - 異なる `source`（`.cgEventTap` ⇄ `.carbonHotKey`）で同一 `kind` が `deduplicationWindowSeconds`（既定 `0.15` 秒）以内に連続到着した場合、`false` を返す。
   - 同一 `source` の連打・リピート、またはウィンドウ外の到着は常に `true` を返し、最終受理状態を更新する。

2. **`CarbonHotKeyRegistrationPlan.build(shortcut:launcherShortcut:isSuspendedForRecording:) -> [CarbonHotKeySpec]`**
   - `isSuspendedForRecording == true` の場合は空配列 `[]` を返す（記録中の誤起動防止）。
   - `false` の場合は `normalForward` / `normalReverse`（`.shift` 合成） / `launcher` の最大 3 件を返す。
   - 各要素は `id`、`keyCode`、`carbonModifiers`（`cmdKey` / `shiftKey` / `optionKey` / `controlKey` のビット和）、`triggerKind` を持つ。

3. **`HotKeyMonitorService` 用安全解放判定ヘルパー（純粋関数）**
   - `shouldTreatModifiersAsReleased(requiredModifiers:observedModifiers:isSecureInputEnabled:isAppActive:elapsedSincePresentation:)`
   - **重要制約**: `isSecureInputEnabled == true` かつ `!isAppActive` の段階（他アプリが Secure Input を保持したままのフォーカス移行途中）では、OS からゼロ化された修飾キー状態が返る恐れがあるため `false`（解放と誤認しない）を返す。
   - `!isSecureInputEnabled` または `isAppActive` 成立かつ猶予時間経過後に `!requiredModifiers.isSubset(of: observedModifiers)` となった場合のみ `true` を返す。

---

## 3. `HotKeyMonitorService` 契約 (`Sources/WintchCore/Services/HotKeyMonitorService.swift`)

1. **起動・停止契約 (`startMonitoring()` / `stopMonitoring()`)**:
   - `startMonitoring()` は `CGEventTap` 開始と合わせて Carbon イベントハンドラ（`InstallEventHandler`）およびホットキー（`RegisterEventHotKey`）を登録する。
   - ただし `RegisterEventHotKey` が一部またはすべて失敗した場合（例：`Command + Tab` 等の OS 予約キー衝突）でも、`CGEventTap` 監視自体は失敗扱いにせずログ出力のみで継続する（`startMonitoring()` は `CGEventTap` の成否で決まる既存契約を維持）。
   - `stopMonitoring()` および `deinit` は Carbon ホットキー・イベントハンドラ・ローカル `NSEvent` モニタ・ウォッチドッグを確実に破棄・解放する。

2. **設定更新・記録サスペンド契約 (`updateShortcut` / `updateLauncherShortcut` / `isSuspendedForRecording`)**:
   - いずれの変更時も Carbon ホットキー登録計画を再評価し、既存登録を `UnregisterEventHotKey` してから最新設定で再登録する。
   - `isSuspendedForRecording == true` の間は全 Carbon ホットキーが未登録状態になることを保証する。

3. **イベント処理契約**:
   - `CGEventTap` でトリガーを消費した場合も `HotKeyTriggerDeduplicator` を通じて受理記録を残す。
   - Carbon `kEventHotKeyPressed` 受信時：
     - `isSuspendedForRecording == true` の場合は無視する。
     - `HotKeyTriggerDeduplicator.shouldAccept(source: .carbonHotKey, ...)` が `false` なら重複として無視する。
     - `.inactive` 状態からの通常スイッチャー起動（または `IsSecureEventInputEnabled() == true` 状態での起動）の場合は `requiresAppActivationOnPresentation = true` をセットしてから `onEvent?(.triggerPressed(...))` を通知する。
     - `.launcher` モードからの通常ショートカットや、`.normal` モード中の追加入力にも `resolveKeyDown` と整合する同一の `HotKeyEvent` を通知する。
   - フォールバック通常セッション（`activeMode == .normal && requiresAppActivationOnPresentation`）開始時：
     - ローカル `NSEvent` モニタ（`keyDown`, `flagsChanged`）で自アプリ宛ての `Esc`・矢印・`Q`・通常/逆順トリガー・修飾キー解放を処理し、`shouldConsume == true` のキーは `nil` 返却で消費してシステム警告音を抑止する。
     - 短周期ウォッチドッグにより、高速な修飾キー解放の取りこぼしを検知して `.modifierReleased` を発火する。
     - `activeMode` が `.inactive` に戻った時点でローカルモニタ・ウォッチドッグ・`requiresAppActivationOnPresentation` を即座にクリアする。

---

## 4. `SwitcherViewModel`・`AppCoordinator`・`SwitcherPanel` 契約

1. **`SwitcherViewModel`**
   - `present(targetMode:)` で `shouldActivateAppForCurrentSession = (targetMode == .launcher || hotKeyMonitor.requiresAppActivationOnPresentation)` を記録し、`dismiss(reason:)` で `false` に戻す。
   - `onModePresentationChanged` の既存シグネチャ `(SwitcherMode, SwitcherDismissReason?) -> Void` を維持し、既存呼び出し元・テストへの破壊的変更を避ける。

2. **`AppCoordinator`**
   - `onModePresentationChanged` 受信時、`.normal` / `.launcher` に対して `ensureSwitcherPanel().show(mode: mode, activateApp: self.switcherViewModel.shouldActivateAppForCurrentSession)` を呼び出す。

3. **`SwitcherPanel`**
   - `show(mode: SwitcherMode, activateApp: Bool? = nil)` を提供（`activateApp == nil` の場合は `mode == .launcher` と同等で後方互換）。
   - `activateApp == true` の場合は `mode` に関わらず `previousFrontmostApp` を記録して `NSApplication.shared.activate()` を実行し、`didActivateAppForCurrentSession = true` を保持する。
   - `restoreFocusIfNeeded(mode:)` は `mode == .launcher || didActivateAppForCurrentSession` の場合に再アクティブ化する。
   - `hidePanel(restorePreviousApp:)` は `restorePreviousApp == true` の場合に記録済み `previousFrontmostApp` を再アクティブ化し、`didActivateAppForCurrentSession = false` にリセットする。
