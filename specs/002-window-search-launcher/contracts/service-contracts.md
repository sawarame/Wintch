# サービスインターフェース契約 (Service Contracts): ウィンドウ検索ランチャーモード

**Feature**: `002-window-search-launcher`  
**Date**: 2026-11-13  
**Purpose**: `001-window-switcher-mvp` のサービス境界を踏襲し、ランチャーモード追加に伴う既存プロトコルの拡張点と責務を定義する。

---

## 1. `HotKeyMonitoring`（グローバルショートカット監視の拡張）

`HotKeyMonitorService` は既存の `CGEventTap` を拡張し、通常モード・ランチャーモード・設定画面ショートカット記録モードの 3 状態を同期的に切り替える。

### 1.1 イベントおよび状態の拡張

```swift
/// スイッチャーの現在の監視モード（CGEventTap コールバックが同期参照する）
public enum HotKeyMonitorMode: Equatable, Sendable {
    /// スイッチャー非表示
    case inactive
    /// 通常スイッチャー表示中（修飾キー保持式）
    case normal
    /// ランチャーモード表示中（トグル式・パネル内テキスト入力優先）
    case launcher
}

/// サービス層から通知されるグローバルキーイベント
public enum HotKeyEvent: Equatable, Sendable {
    /// 通常スイッチャーのショートカットが押された
    case triggerPressed(isShiftPressed: Bool)
    /// ランチャーの起動/トグルショートカットが押された
    case launcherTriggerPressed
    /// 通常スイッチャーの必須修飾キーが離された
    case modifierReleased
    /// Esc キーが押された（通常モードのみ）
    case escapePressed
    /// 上下矢印キーが押された（通常モードのみ）
    case arrowPressed(direction: ArrowDirection)
}
```

### 1.2 プロトコル追加メソッド・プロパティ

```swift
@MainActor
public protocol HotKeyMonitoring: AnyObject {
    var onEvent: ((HotKeyEvent) -> Void)? { get set }

    /// 現在のアクティブモードをサービスへ共有する（既存 isSwitcherActive を置換または併用）
    var activeMode: HotKeyMonitorMode { get set }

    /// 後方互換またはテスト用の簡易フラグ（activeMode != .inactive と等価）
    var isSwitcherActive: Bool { get set }

    /// 設定画面でショートカットレコーダーが入力待機中の間 true にし、グローバル横取りを一時停止する
    var isSuspendedForRecording: Bool { get set }

    /// 通常スイッチャーのショートカットを更新する
    func updateShortcut(_ preference: ShortcutPreference)

    /// ランチャーのショートカットを更新する
    func updateLauncherShortcut(_ preference: LauncherShortcutPreference)

    @discardableResult
    func startMonitoring() -> Bool

    func stopMonitoring()
}
```

### 1.3 `CGEventTap` コールバックでのイベント制御ルール

1. **`isSuspendedForRecording == true` の場合**:
   - すべての `keyDown` / `flagsChanged` を消費せず OS へそのまま通す（設定画面のレコーダーが `Option + Tab` や `Option + Space` などの既存キーも確実に受け取れるようにするため）。
2. **`activeMode == .inactive` の場合**:
   - 通常ショートカット（順・逆）に一致 → `.triggerPressed(isShiftPressed:)` を通知し、イベントを消費（`nil`）。
   - ランチャーショートカットに一致（修飾キーは完全一致を要求）→ `.launcherTriggerPressed` を通知し、イベントを消費（`nil`）。
   - それ以外 → すべて素通し。
3. **`activeMode == .normal` の場合**:
   - 必須修飾キー解放 → `.modifierReleased` を通知。
   - `Esc` (53) / `↑` (126) / `↓` (125) → 各イベントを通知し、消費（`nil`）。
   - 通常ショートカット（順・逆）→ `.triggerPressed(isShiftPressed:)` を通知し、消費（`nil`）。
   - **ランチャーショートカット** → もし通常ショートカットと無関係なキーでもランチャー遷移させないため、通知を行わない（FR-004）。
4. **`activeMode == .launcher` の場合**:
   - **ランチャーショートカット**に一致 → `.launcherTriggerPressed` を通知し、消費（`nil`：トグル終了）。
   - **通常ショートカット**（順・逆）に一致 → `.triggerPressed(isShiftPressed:)` を通知して消費（`nil`）し、モードを切り替えずにランチャー内の選択カーソルを「次へ / 前へ」に移動する（FR-004 改定 / `004-launcher-switcher-nav`）。
   - `flagsChanged` による `.modifierReleased` は通知しない。
   - **`Esc` / `↑` / `↓` / `Enter` / `Ctrl+N` / `Ctrl+P` / 文字キーは絶対に消費しない** → すべてキーウィンドウの検索入力フィールドおよび日本語 IME へ素通しさせる（FR-012）。

> [!IMPORTANT]
> ランチャーショートカットの修飾キー一致判定は、意図しない誤爆を防ぐため **`command`, `option`, `control`, `shift` の 4 修飾キー状態が設定値と完全一致すること** を条件とする（例：`⌥ + Space` 設定時に `⌥ + ⇧ + Space` で誤起動しない）。

---

## 2. `PreferencesStoring`（設定永続化の拡張）

既存の `ShortcutPreference` に加え、`LauncherShortcutPreference` の読み書きをサポートする。

```swift
public protocol PreferencesStoring: Sendable {
    func loadShortcut() -> ShortcutPreference
    func saveShortcut(_ preference: ShortcutPreference)

    /// 保存されているランチャーショートカット設定を読み込む（未保存時はデフォルトの Option + Space）
    func loadLauncherShortcut() -> LauncherShortcutPreference

    /// ランチャーショートカット設定を保存する
    func saveLauncherShortcut(_ preference: LauncherShortcutPreference)
}
```

### 実装上の保証
- 既存の `dev.wintch.shortcutPreference` キーとは独立したキー（`dev.wintch.launcherShortcutPreference`）を使用し、既存ユーザーの設定データを破壊しない。
- デコード失敗やキー未存在時は `LauncherShortcutPreference.default`（`⌥ + Space`）を返す。
- `PreferencesStore` 読み込み後に万一ロードされた設定同士が重複していた場合でも起動時にクラッシュしない（設定画面で明示・再設定可能）。

---

## 3. `WindowServicing` / `AccessibilityPermissionServicing` / `IconProviding`

- 既存契約をそのまま再利用し、変更不要。
- 画面収録権限を使用しない制約（FR-018）および非公開 API 禁止制約を引き続き厳守する。
