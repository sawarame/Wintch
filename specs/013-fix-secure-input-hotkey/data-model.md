# Phase 1 データモデル設計 (Data Model): セキュア入力フォーカス中のショートカット起動と安定復帰

**Feature**: `013-fix-secure-input-hotkey` | **Date**: 2026-11-17

## 1. ドメイン層（純粋値型・判定ロジック）

OS API（`Carbon` / `CoreGraphics` / `AppKit`）に依存せず、単体テスト可能な値型・純粋関数として `Sources/WintchCore/Domain/` に配置する。

### 1.1 `HotKeyTriggerSource`（起動トリガー入力元）
グローバルショートカットの起動イベントがどの監視経路から到着したかを表す列挙型。

- `cgEventTap`: 主経路の `CGEventTap` からの検知
- `carbonHotKey`: 代替経路の Carbon `RegisterEventHotKey` からの検知

### 1.2 `HotKeyTriggerKind`（重複排除対象のトリガー種別）
二重発火判定の対象となるトリガー操作種別。

- `normalForward`: 通常スイッチャー順方向
- `normalReverse`: 通常スイッチャー逆方向（`Shift` 併用）
- `launcher`: 検索ランチャー起動／トグル

### 1.3 `HotKeyTriggerDeduplicator`（二重発火防止トラッカー）
`CGEventTap` と `RegisterEventHotKey` の間で同一キー操作の二重発火を防止する値型状態トラッカー（`Sendable`）。

| フィールド / 定数 | 型 | 説明 |
|---|---|---|
| `deduplicationWindowSeconds` | `TimeInterval` | 異種経路間の同一トリガー重複とみなす最大時間窓（既定 `0.15` 秒） |
| `lastAcceptedTrigger` | `(source: HotKeyTriggerSource, kind: HotKeyTriggerKind, timestamp: TimeInterval)?` | 直前に受理したトリガーの経路・種別・単調増加時刻 |

**判定ルール（`shouldAccept(source:kind:at:)`）**:
1. 直前の受理記録が存在し、**入力元が異なり**（`last.source != source`）、かつ **種別が同じ**（`last.kind == kind`）、かつ **経過時間が `deduplicationWindowSeconds` 未満**（`timestamp - last.timestamp < deduplicationWindowSeconds`）の場合は `false`（重複として破棄）を返す。
2. 同一入力元（`last.source == source`）からの連続入力はキーリピートまたは連打として常に受理（`true`）し、`lastAcceptedTrigger` を更新する。
3. リセット（`reset()`）時は `lastAcceptedTrigger = nil` とする。

### 1.4 `CarbonHotKeySpec` / `CarbonHotKeyRegistrationPlan`（Carbon ホットキー登録計画）
`ShortcutPreference` および `LauncherShortcutPreference` から、Carbon `RegisterEventHotKey` へ登録すべき 3 つのホットキー定義（仮想キーコード、Carbon 修飾キーマスク、識別 ID、対応する `HotKeyTriggerKind`）を純粋に算出する値型。

| 識別 ID (`UInt32`) | 対象 | キーコード | 修飾キーマスク |
|---|---|---|---|
| `1` (`normalForward`) | 通常スイッチャー順方向 | `shortcut.keyCode` | `carbonModifierFlags(from: shortcut.modifiers)` |
| `2` (`normalReverse`) | 通常スイッチャー逆方向 | `shortcut.keyCode` | `carbonModifierFlags(from: shortcut.modifiers.union(.shift))` |
| `3` (`launcher`) | 検索ランチャー | `launcherShortcut.keyCode` | `carbonModifierFlags(from: launcherShortcut.modifiers)` |

**Carbon 修飾キービット変換ルール**:
- `.command` → `cmdKey` (`0x0100`)
- `.shift` → `shiftKey` (`0x0200`)
- `.option` → `optionKey` (`0x0800`)
- `.control` → `controlKey` (`0x1000`)

**登録可否バリデーション**:
- `ShortcutModifiers` に `.control` / `.option` / `.command` のいずれも含まれない場合や、`isSuspendedForRecording == true` の場合は登録リストを空とする。

---

## 2. サービス層状態モデル（`HotKeyMonitorService`）

### 2.1 フォールバック起動セッション状態
| 状態 / プロパティ | 型 | 説明 |
|---|---|---|
| `requiresAppActivationOnPresentation` | `Bool` | 通常スイッチャー起動時に `NSApplication.shared.activate()` による一時アクティブ化が必要かどうか。Carbon 代替経路からの通常起動、または `IsSecureEventInputEnabled() == true` 下での起動時に `true` となり、`.inactive` 復帰時または通常の `CGEventTap` 起動時に `false` へリセットされる |
| `carbonEventHandlerRef` | `EventHandlerRef?` | `GetApplicationEventTarget()` にインストールする `kEventHotKeyPressed` 用ハンドラ参照 |
| `registeredHotKeys` | `[UInt32: EventHotKeyRef]` | 登録 ID ごとの `EventHotKeyRef` マップ（監視停止・設定更新・記録サスペンド時に `UnregisterEventHotKey` で確実に解除） |
| `localEventMonitor` | `Any?` | フォールバック通常セッション中のみ有効化する `NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged])` ハンドル |
| `modifierWatchdogTask` | `Task<Void, Never>?` | フォールバック通常セッション中に素早い修飾キー解放を取りこぼさないための短周期確認タスク（`activeMode != .normal` または `flagsChanged` 受信で即時キャンセル） |

### 2.2 状態遷移（通常モード起動〜終了）

```text
[.inactive]
  ├─ CGEventTap (IsSecureEventInputEnabled == false)
  │    → requiresAppActivationOnPresentation = false
  │    → .normal (非アクティブパネル表示、CGEventTap のみで操作・解放監視)
  │
  └─ Carbon RegisterEventHotKey (または IsSecureEventInputEnabled == true)
       → requiresAppActivationOnPresentation = true
       → .normal (SwitcherPanel.show(..., activateApp: true) で一時アクティブ化)
       → ローカル NSEvent モニタ + 修飾キー解放ウォッチドッグ開始
       → [!IsSecureEventInputEnabled()] 確認後に修飾キー解放検知 / または localMonitor / CGEventTap で操作・確定・キャンセル
       → .inactive へ遷移時: ローカルモニタ・ウォッチドッグ停止、requiresAppActivationOnPresentation = false
```

---

## 3. ViewModel・View 層状態モデル

### 3.1 `SwitcherViewModel`
| 状態 / プロパティ | 型 | 説明 |
|---|---|---|
| `shouldActivateAppForCurrentSession` | `Bool` (`private(set)`) | 現在表示中セッションで自アプリの前面アクティブ化を行うべきか。`present(targetMode:)` で `targetMode == .launcher || hotKeyMonitor.requiresAppActivationOnPresentation` により設定し、`dismiss(reason:)` で `false` に戻す |

### 3.2 `SwitcherPanel`
| 状態 / プロパティ | 型 | 説明 |
|---|---|---|
| `didActivateAppForCurrentSession` | `Bool` | 現在の表示セッションで `NSApplication.shared.activate()` を実行したか。`show(mode:activateApp:)` で設定し、`hidePanel(restorePreviousApp:)` で `false` に戻す |
| `previousFrontmostApp` | `NSRunningApplication?` | 従来は `.launcher` のみ記録していた直前最前面アプリ参照を、`didActivateAppForCurrentSession == true` の `.normal` セッションでも同様に記録し、`hidePanel(restorePreviousApp: true)` 時にフォーカスを復元する |
