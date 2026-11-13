# サービスインターフェース契約 (Service Contracts): Wintch MVP

**Feature**: `001-window-switcher-mvp`  
**Created**: 2026-11-13  
**Purpose**: プロジェクト憲章の「MVVM + Services（低レイヤーAPIの隔離）」に基づき、`ViewModels/`・`Domain/` と `Services/` 層の境界となるプロトコルおよび入出力仕様を定義します。

---

## 1. `WindowServicing`（ウィンドウ取得・アクティブ化・MRU追跡）

macOS のウィンドウサーバー（`CGWindowListCopyWindowInfo`）およびアクセシビリティAPI（`AXUIElement` / `AXObserver`）をすべて内部に隠蔽する。

```swift
/// ウィンドウ情報の収集・監視・切り替え操作を提供するサービス契約
@MainActor
protocol WindowServicing: AnyObject {
    /// 現在の監視状態を開始する（AXObserver、Workspace通知の登録）
    func startObserving()

    /// 監視を停止し、リソースを解放する
    func stopObserving()

    /// 現在の全操作スペース上のウィンドウ候補を収集して返す（フィルタリング前の生候補）
    /// - Returns: 収集されたウィンドウ候補の配列
    func fetchRawWindowCandidates() -> [RawWindowCandidate]

    /// 指定されたウィンドウを最前面にアクティブ化する（必要なら操作スペース移動・最小化解除を含む）
    /// - Parameter entry: アクティブ化対象のウィンドウ項目
    func activateWindow(_ entry: WindowEntry)
}
```

### 実装上の保証・制約
- `fetchRawWindowCandidates()` は画面収録権限を要求してはならない（`ScreenCaptureKit` 等不使用）。
- `activateWindow(_:)` は `NSRunningApplication.activate(options: [])` と `AXUIElementPerformAction(..., kAXRaiseAction)` を組み合わせ、別スペースのウィンドウであっても確実にフォーカスを移動させる。
- 非公開API（`CGS*`、`_AXUIElementGetWindow` 等）は使用してはならない。

---

## 2. `HotKeyMonitoring`（グローバルショートカット監視）

`CGEventTap` を用いた低レイヤーキーボードイベント監視およびイベント消費（横取り）を隠蔽する。

### 入力イベント列挙型 (`HotKeyEvent`)
```swift
/// スイッチャー制御のためにサービス層から通知されるキーイベント
enum HotKeyEvent: Equatable, Sendable {
    /// 設定された修飾キー＋トリガーキーが押された（順方向）
    case triggerPressed(isShiftPressed: Bool)
    /// 設定中の修飾キーが離された（確定トリガー）
    case modifierReleased
    /// Esc キーが押された（キャンセル）
    case escapePressed
    /// 上下矢印キーが押された（スイッチャー表示中の補助操作）
    case arrowPressed(direction: ArrowDirection)
}

/// 矢印キーの方向
enum ArrowDirection: Equatable, Sendable {
    case up
    case down
}
```

### プロトコル定義
```swift
/// グローバルキーボードショートカットの監視と横取りを行うサービス契約
@MainActor
protocol HotKeyMonitoring: AnyObject {
    /// イベント発生時のハンドラ
    var onEvent: ((HotKeyEvent) -> Void)? { get set }

    /// スイッチャーが現在表示中かどうかをサービスに伝える（表示中のみ Esc / 矢印キー等を横取りするため）
    var isSwitcherActive: Bool { get set }

    /// 監視対象のショートカット設定を更新する
    /// - Parameter preference: 新しいショートカット設定
    func updateShortcut(_ preference: ShortcutPreference)

    /// グローバル監視を開始する（アクセシビリティ権限が必要）
    /// - Returns: 開始に成功したかどうか
    @discardableResult
    func startMonitoring() -> Bool

    /// グローバル監視を停止する
    func stopMonitoring()
}
```

### 実装上の保証・制約
- スイッチャー非表示時（`isSwitcherActive == false`）は、`shortcut` に一致する `keyDown` のみを消費（swallow）し、他のすべてのキーイベントはOSへ素通しさせる。
- スイッチャー表示中（`isSwitcherActive == true`）は、`trigger`、`Shift + trigger`、`Esc`、および上下矢印キーを消費し、裏側のアプリへ入力が漏れないようにする。
- イベントタップが OS のタイムアウトで無効化された場合は即座に再有効化する。

---

## 3. `AccessibilityPermissionServicing`（権限監視・設定誘導）

`AXIsProcessTrusted` およびシステム設定へのディープリンク誘導を隠蔽する。

```swift
/// アクセシビリティ権限の状態確認と設定画面への誘導を行うサービス契約
@MainActor
protocol AccessibilityPermissionServicing: AnyObject {
    /// 現在のアクセシビリティ権限状態を取得する
    /// - Returns: 許可状態（.granted または .denied）
    func currentStatus() -> AccessibilityPermissionStatus

    /// 権限の定期監視または変更検知を開始し、変化時にコールバックを呼ぶ
    /// - Parameter onChange: 権限状態が変化した際に呼ばれるクロージャ
    func startMonitoring(onChange: @escaping (AccessibilityPermissionStatus) -> Void)

    /// 権限監視を停止する
    func stopMonitoring()

    /// macOSの「システム設定 > プライバシーとセキュリティ > アクセシビリティ」画面を開く
    func openAccessibilitySettings()
}
```

---

## 4. `PreferencesStoring` & `LaunchAtLoginServicing`（設定永続化・自動起動）

```swift
/// ユーザー設定の保存と読み込みを行うストア契約
protocol PreferencesStoring: Sendable {
    /// 保存されているショートカット設定を読み込む（未保存時はデフォルトの Option + Tab を返す）
    func loadShortcut() -> ShortcutPreference

    /// ショートカット設定を保存する
    func saveShortcut(_ preference: ShortcutPreference)
}

/// ログイン時自動起動の状態管理を行うサービス契約
@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    /// 現在ログイン時自動起動が有効になっているか
    var isEnabled: Bool { get }

    /// ログイン時自動起動の有効・無効を切り替える
    /// - Parameter enabled: 有効にする場合は true
    /// - Throws: OSへの登録・解除に失敗した場合のエラー
    func setEnabled(_ enabled: Bool) throws
}
```

---

## 5. `IconProviding`（アプリアイコン取得）

```swift
/// プロセスIDからアプリケーションアイコンを取得するサービス契約
@MainActor
protocol IconProviding: AnyObject {
    /// 指定されたPIDのアプリアイコンを取得する（キャッシュ活用）
    /// - Parameter pid: アプリケーションのプロセスID
    /// - Returns: アプリアイコン（取得できない場合は nil）
    func icon(for pid: Int32) -> NSImage?
}
```
