# インターフェース契約定義 (Contracts): ウィンドウキャプチャ表示型スイッチャー

**Feature**: `007-window-capture-switcher`  
**Date**: 2026-11-15  
**Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/007-window-capture-switcher/spec.md)

本ドキュメントは、Wintch の MVVM + Services アーキテクチャ（[constitution.md](file:///Users/sawarame_yasushi/dev/Wintch/.specify/memory/constitution.md)）に沿って、各層間のインターフェース境界を定義する。

---

## 1. サービス層プロトコル契約（`Sources/WintchCore/Services/Protocols/`）

### 1.1 `PreferencesStoring`（拡張）
```swift
func loadNormalDisplayStyle() -> SwitcherDisplayStyle
func saveNormalDisplayStyle(_ style: SwitcherDisplayStyle)
```
- **デフォルト保証**: キー未設定または JSON/文字列デコード失敗時は必ず `.list` を返す。
- **永続化キー**: `"dev.wintch.normalDisplayStyle"`（`UserDefaults`）。

### 1.2 `ScreenRecordingPermissionServicing`（新規）
```swift
@MainActor
public protocol ScreenRecordingPermissionServicing: AnyObject {
    /// 現在の画面収録権限状態をプロンプトを出さずに確認する
    func currentStatus() -> ScreenRecordingPermissionStatus

    /// OS の画面収録権限許可プロンプトを要求する（オプトイン操作時のみ呼び出す）
    @discardableResult
    func requestPermission() -> Bool

    /// システム設定の「画面収録とシステムオーディオ録音」ペインを開く
    func openSystemSettings()
}
```
- **厳守事項**: `SwitcherDisplayStyle == .list` の間、本プロトコルのどのメソッドも呼び出してはならない（FR-003）。

### 1.3 `WindowCaptureServicing`（新規）
```swift
@MainActor
public protocol WindowCaptureServicing: AnyObject {
    /// メモリ上のキャッシュから既存のサムネイルを同期取得する（キャッシュミス時は nil）
    func cachedThumbnail(for cgWindowID: UInt32) -> NSImage?

    /// 指定ウィンドウ群の最新サムネイルを非同期で取得し、完了したものから逐次コールバックする
    /// - Parameters:
    ///   - cgWindowIDs: 取得対象の CoreGraphics ウィンドウ ID 一覧
    ///   - maxPixelSize: サムネイルの最大ピクセルサイズ（長辺基準、Retina 2x 想定）
    ///   - onCaptured: 1件取得完了ごとに呼ばれるコールバック (cgWindowID, image)
    func captureThumbnails(
        for cgWindowIDs: [UInt32],
        maxPixelSize: CGSize,
        onCaptured: @escaping @MainActor (UInt32, NSImage) -> Void
    ) async

    /// 指定ウィンドウのキャッシュを明示削除する（ウィンドウクローズ時）
    func invalidateThumbnail(for cgWindowID: UInt32)

    /// 全キャッシュを破棄する（リスト型への切り替え時等）
    func clearCache()
}
```
- **エラー・キャンセル契約**:
  - `Task.isCancelled` 検知時は残余キャプチャを中断して安全に終了する。
  - 個別ウィンドウの取得失敗・対象不在はエラーを投げずスキップし、他ウィンドウの取得を継続する。
  - 取得した画像は `NSImage` としてメモリ上の上限付き LRU キャッシュにのみ保持し、ディスク保存を行わない（FR-012）。

### 1.4 `HotKeyMonitoring`（拡張）
- `ArrowDirection` に `.left` / `.right` を追加する。
- `HotKeyMonitorService.resolveKeyDown` の `mode == .normal` において：
  - `keyCode == 123`（左矢印）→ `HotKeyKeyDownDecision(event: .arrowPressed(direction: .left), shouldConsume: true)`
  - `keyCode == 124`（右矢印）→ `HotKeyKeyDownDecision(event: .arrowPressed(direction: .right), shouldConsume: true)`
- `mode == .launcher` および `mode == .inactive` の挙動は一切変更しない。

---

## 2. ViewModel 契約（`Sources/WintchCore/ViewModels/`）

### 2.1 `SettingsViewModel`（拡張）
- **公開プロパティ**:
  - `public private(set) var normalDisplayStyle: SwitcherDisplayStyle`
  - `public private(set) var screenRecordingStatus: ScreenRecordingPermissionStatus`（`normalDisplayStyle == .capture` 時のみ最新化、`.list` 時は `.denied` 固定等でプローブしない）
  - `public var onNormalDisplayStyleChanged: ((SwitcherDisplayStyle) -> Void)?`
- **公開メソッド**:
  - `func updateNormalDisplayStyle(_ style: SwitcherDisplayStyle)`: 設定保存・通知、`.capture` 選択時のみ `screenRecordingPermissionService?.currentStatus()` を反映。
  - `func requestScreenRecordingPermission()`: `normalDisplayStyle == .capture` の場合のみ OS 権限リクエストを実行しステータス更新。
  - `func openScreenRecordingSettings()`: システム設定を開く。
  - `refreshStatus()` 呼び出し時: `normalDisplayStyle == .capture` の場合のみ画面収録権限も再確認する（`.list` 時はスキップ）。

### 2.2 `SwitcherViewModel`（拡張）
- **公開プロパティ**:
  - `public private(set) var normalDisplayStyle: SwitcherDisplayStyle`
  - `public private(set) var capturedThumbnails: [UInt32: NSImage]`（表示中または直前キャッシュを `cgWindowID` ごとに提供）
  - `public private(set) var isScreenRecordingGranted: Bool`（`.capture` モード表示中の権限バナー制御用）
  - `public var gridColumnCount: Int`（現在の通常キャプチャモードで適用中のグリッド列数、1 以上）
- **公開メソッド**:
  - `func updateNormalDisplayStyle(_ style: SwitcherDisplayStyle)`: 表示形式を更新し、`.list` へ切り替わった場合は `capturedThumbnails` と `windowCaptureService?.clearCache()` を即時リセット。
  - `func updateGridColumnCount(_ columns: Int)`: 画面幅に応じたビュー側の算出列数（`SwitcherGridLayout` 由来）を同期し、`↑` / `↓` 移動に反映する。
  - `func thumbnail(for entry: WindowEntry) -> NSImage?`: `entry.cgWindowID` に対応するサムネイルを返す（未取得なら `nil`）。
  - `func openScreenRecordingSettings()`: キャプチャ表示パネル上の未許可バナーからシステム設定へ遷移する（同時に現在のパネルを安全にキャンセル終了する）。
  - `func moveSelection(_ direction: ArrowDirection)`:
    - `mode == .normal && normalDisplayStyle == .capture`: `.left` / `.right` は前後循環、`.up` / `.down` は `SwitcherGridLayout.moveIndex(..., columns: gridColumnCount)` で行間循環移動。
    - それ以外（リスト型およびランチャー）: `.up` / `.left` は前項目、`.down` / `.right` は次項目へ移動。

---

## 3. UI / パネル契約（`Sources/WintchCore/Views/`）

### 3.1 `SwitcherPanel` とコンテンツコンテナ（`SwitcherContentView` / `SwitcherListView` / `SwitcherCaptureGridView`）
- **表示切り替え**:
  - `mode == .normal && viewModel.normalDisplayStyle == .capture`: `SwitcherCaptureGridView` を描画。
  - それ以外（`mode == .normal && .list`、または `mode == .launcher`）: 既存の `SwitcherListView` を描画（幅 `520pt` 固定・高さ動的）。
- **キャプチャグリッドのサイズ制約**:
  - アクティブディスプレイ（`NSScreen`）の `visibleFrame.width` の `85%` を最大パネル幅の上限とする。
  - ウィンドウ件数に応じた列数分の幅を自然に確保し、高さは最大高さ上限（例：`visibleFrame.height * 0.78`、目安 `560pt` 前後）を超えた場合に内部縦スクロールを有効化する。
  - カードクリック（`onTapGesture`）で `viewModel.selectAndActivate(at: index)` を呼び出す。
  - 未許可バナーの「システム設定を開く」ボタン押下で `viewModel.openScreenRecordingSettings()` を呼び出す（注：`nonactivatingPanel` 上のボタンクリック後に設定ウィンドウを最前面化するため、`AppCoordinator` 経由で `NSApp.activate()` してもよい）。
- **パネル上端・水平位置更新**:
  - 初期表示時（`show(mode:)`）に最新コンテンツの `fittingSize` で画面中央へ配置し `anchoredTopY` を記録。
  - ウィンドウクローズ等でコンテンツサイズが変化した際は `anchoredTopY` を基準に上端位置を保ちつつ幅・高さを再調整し、横幅が縮んだ場合はパネル中央 X 座標を維持する。

### 3.2 `PermissionGuideView`（FR-011 更新）
- 従来の「`※ プライバシー保護のため、「画面収録」権限は一切使用しません。`」を以下に更新する：
  - 「`※ リスト型および検索ランチャーでは「画面収録」権限を使用しません（キャプチャ表示型を選択した場合のみ任意で使用します）。`」
