# 技術調査レポート (Research): Wintch MVP

**Feature**: `001-window-switcher-mvp`  
**Created**: 2026-11-13  
**Status**: Complete

本ドキュメントは、[plan.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/001-window-switcher-mvp/plan.md) の「Technical Context」およびアーキテクチャ設計における不確実性を解消するための調査・技術選定結果をまとめたものです。

---

## 1. プロジェクト構成とビルド・配布方式（SwiftPM + `.app` バンドル生成）

- **Decision**:
  Apple標準の Swift Package Manager（`Package.swift`、macOS 14.0以降、`executableTarget` + テストターゲット）をプロジェクト定義の基盤とし、外部サードパーティ依存は一切持たない（`dependencies: []`）。実機でメニューバーアプリ（`LSUIElement = true`）およびアクセシビリティ権限／`SMAppService` の検証を行うための `.app` バンドル組み立てスクリプト（`scripts/build-app.sh`）を併用する。
- **Rationale**:
  - 開発環境に Xcode.app が存在しない場合でも Command Line Tools（Swift 6.4.2 / macOS SDK）のみで `swift build` や `swift test` を高速に実行できる。
  - Xcode がインストールされた環境では `Package.swift` をそのまま開いてビルド・デバッグ・アーカイブが可能。
  - `SMAppService.mainApp`（ログイン時自動起動）および macOS のアクセシビリティ権限管理（TCC）は単体バイナリではなく有効な `.app` バンドル（`Info.plist`・バンドルID付き）を要求するため、ビルド成果物を `.app` バンドル化する軽量シェルスクリプトを組み合わせることで、ローカル検証から Homebrew / Mac App Store 配布への橋渡しが確実になる。
- **Alternatives considered**:
  - **Xcodeプロジェクト（`.xcodeproj`）単独構成**: CLI環境（Command Line Toolsのみ）でビルド・テストが実行できないリスクがあり、今回は不採用。将来的に App Store 提出用アーカイブを作成する際は `Package.swift` から生成・ラップが可能。

---

## 2. 画面収録権限なし・非公開APIなしでの全操作スペース横断ウィンドウ取得とフォーカス制御

- **Decision**:
  `CGWindowListCopyWindowInfo`（メタデータ・全スペース把握・Zオーダー取得）と `AXUIElement` / `AXObserver`（タイトル取得・操作実行・MRU/キャッシュ維持）を組み合わせた **ハイブリッドウィンドウ管理方式** を採用する。非公開API（`CGS*` や `_AXUIElementGetWindow` 等）および画面収録権限（`ScreenCaptureKit` 等）は一切使用しない。
- **Rationale**:
  - **macOS の制約**:
    1. `CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)` は全操作スペースのウィンドウ情報（PID、ウィンドウ番号、レイヤー、座標・サイズ、Zオーダー）を返すが、画面収録権限がない場合は他アプリの `kCGWindowName`（ウィンドウタイトル）がOSによって隠蔽される。
    2. 一方、`AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute)` はアクセシビリティ権限のみでタイトルや `AXUIElement` 参照を取得できるが、非アクティブな操作スペースにのみ存在するウィンドウを返却しない場合がある。
  - **ハイブリッド戦略による解決**:
    1. **現在スペース＆最小化ウィンドウ**: `NSWorkspace.shared.runningApplications`（`activationPolicy == .regular`）の `AXUIElement` から `kAXWindowsAttribute` を走査し、`kAXTitleAttribute`、`kAXSubroleAttribute`（`kAXStandardWindowSubrole` 等）、`kAXMinimizedAttribute`、`kAXPositionAttribute`、`kAXSizeAttribute` を取得する。
    2. **MRU追跡・別スペースキャッシュ**: `AXObserver`（`kAXWindowCreatedNotification`, `kAXFocusedWindowChangedNotification`, `kAXTitleChangedNotification`, `kAXUIElementDestroyedNotification`）および `NSWorkspace.didActivateApplicationNotification` / `activeSpaceDidChangeNotification` を常時購読し、一度でも認識したウィンドウのタイトル・属性・`AXUIElement` 参照とアクティブ日時（MRU順位）をメモリ上にキャッシュする。
    3. **未訪問の別スペースウィンドウの補完**: Wintch起動前から別の操作スペースに存在し、まだ一度もそのスペースを訪れていないウィンドウは `CGWindowListCopyWindowInfo` の `layer == 0` かつ有効サイズを持つエントリとして検知し、`NSRunningApplication` からアプリアイコン・アプリ名を補完して一覧に表示する。
    4. **別スペースを含む切り替え実行**: 確定時はまず `NSRunningApplication.activate()` を呼び出し（macOS標準のスペース切り替えを誘発）、保持している `AXUIElement`（または移動後に再取得・照合した `AXUIElement`）に対して最小化解除（必要に応じて `kAXMinimizedAttribute = false`）、`kAXMainAttribute = true`、`kAXRaiseAction` を順次実行して対象ウィンドウを最前面化する。
- **Alternatives considered**:
  - **非公開API（`_AXUIElementGetWindow`, `CGS*`）の使用**: 全スペースの完全な制御が可能だが、プロジェクト憲章「非公開APIの禁止」および App Store 審査ガイドラインに違反するため即却下。
  - **`CGWindowListCopyWindowInfo` のみでタイトル取得**: 画面収録権限の許可が必須となり、憲章「最小権限の原則（画面収録権限不使用）」に違反するため却下。

---

## 3. macOS 14+ におけるアプリおよびウィンドウのアクティブ化 API

- **Decision**:
  `NSRunningApplication.activate(options: [])`（`activateIgnoringOtherApps` は非推奨かつmacOS 14以降で実質無効のため使用しない）と `AXUIElementPerformAction(windowElement, kAXRaiseAction)` の組み合わせを使用する。
- **Rationale**:
  - macOS 14 (Sonoma) で `.activateIgnoringOtherApps` が非推奨（Deprecated）となったため、警告ゼロのモダンな `activate()` 系APIに準拠する。
  - Wintch のフローティングパネル自体を `.nonactivatingPanel` にすることで、スイッチャー表示中も元のアプリからアクティブ状態を奪いすぎず、切り替え確定時に目的アプリ・ウィンドウへスムーズにフォーカスを移せる。
- **Alternatives considered**:
  - レガシーな `activate(options: [.activateIgnoringOtherApps])`: macOS 14+ で非推奨警告が出るため不採用。

---

## 4. 非アクティブ化しないフローティングパネル（`NSPanel`）と SwiftUI 統合

- **Decision**:
  AppKit の `NSPanel` を継承した軽量パネル（`styleMask: [.nonactivatingPanel, .borderless]` または `.fullSizeContentView`、レベル `.floating` または `.popUpMenu` 相当の前面表示、`collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`）に `NSHostingView` を組み込み、リスト描画・スタイルはすべて SwiftUI（`@Observable` な ViewModel とバインド）で実装する。
- **Rationale**:
  - SwiftUI 標準の `Window` / `WindowGroup` では「他アプリのフォーカスを奪わずに最前面表示する」「すべてのスペースやフルスクリーンアプリ上に重ねて表示する」制御が困難。
  - 憲章に従い、`NSPanel` 制御は最小限のラッパーに留め、UI本体を SwiftUI で構築することで可読性と保守性を両立できる。
- **Alternatives considered**:
  - SwiftUI のみ（`MenuBarExtra` の `.window` スタイル等）: 画面中央へのフローティング表示やショートカットによる即時開閉制御ができず不採用。

---

## 5. グローバルキーボード監視とショートカット横取り（`CGEventTap`）

- **Decision**:
  `CGEvent.tapCreate`（`.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap`）を用いて `keyDown` および `flagsChanged` イベントを監視する。イベントタップのコールバックは最小限の判定のみを行い、状態変更やUI操作はメインアクター（`MainActor`）へディスパッチする。OSによるタイムアウト無効化イベント（`tapDisabledByTimeout` / `tapDisabledByUserInput`）を受信した際は即座に `CGEvent.tapEnable` で自己復旧する。
- **Rationale**:
  - `NSEvent.addGlobalMonitorForEvents` はイベントを「監視」するだけで「消費（横取り）」できないため、`Option + Tab` による文字入力（特殊文字挿入）や `Command + Tab` による標準スイッチャー起動を抑止できない。
  - `.defaultTap` の `CGEventTap` であれば、Wintch のショートカット合致時およびスイッチャー表示中の `Tab` / `Shift + Tab` / `Esc` / トリガーキーのイベントに対して `nil` を返却し、他アプリへの誤入力を完全に遮断できる。
  - 修飾キーを離した瞬間の確定処理は、`flagsChanged` イベントから現在の修飾キーフラグを確認することでミリ秒単位の即時判定が可能。
- **Alternatives considered**:
  - Carbon `RegisterEventHotKey`: 修飾キーを「離した瞬間（Key Up / FlagsChanged）」の検知や、スイッチャー表示中の柔軟な `Shift` 逆順・`Esc` 横取りが難しく、レガシーAPIでもあるため不採用。
  - `NSEvent.addGlobalMonitorForEvents`: イベントを消費できず他アプリへキー入力が漏れるため不採用。

---

## 6. ログイン時自動起動（Launch at Login）

- **Decision**:
  macOS 13+ 標準の `ServiceManagement` フレームワーク `SMAppService.mainApp` を使用する。
- **Rationale**:
  - 外部ライブラリ（`LaunchAtLogin` 等）や旧式の Login Item ヘルパーアプリを不要とし、OSの「システム設定 > 一般 > ログイン項目」とリアルタイムに状態を同期できる。
  - `SMAppService.mainApp.status == .enabled` を都度評価することで、ユーザーがシステム設定側からOFFにした場合も設定画面の表示が常に正確になる。
- **Alternatives considered**:
  - 旧 `SMLoginItemSetEnabled` + ヘルパーバンドル: 非推奨かつ構成が冗長なため不採用。

---

## 7. 状態管理・設定永続化・テスタビリティ設計

- **Decision**:
  - **状態管理**: 憲章に基づき Swift 標準の `@Observable` マクロ（Observation フレームワーク）を使用する。
  - **設定永続化**: `UserDefaults` をプロトコル抽象化した設定ストアを通じて、`ShortcutPreference`（修飾キー・トリガーキー）を保存・復元する。
  - **テストフレームワーク**: Swift 標準の **Swift Testing**（`import Testing`, `@Test`, `#expect`）を採用し（Xcode / Swift 6 環境で標準サポート）、OS低レイヤーAPIから切り離した純粋ロジック（ノイズウィンドウ除外、MRUソート・初期選択インデックス算出、ショートカット判定、設定シリアライズ）をユニットテストで網羅する。
- **Rationale**:
  - `CGWindow` 辞書や `AXUIElement` をそのままテスト対象にすると権限やGUI環境に依存してしまうため、サービスの出力前に純粋な値型（`RawWindowCandidate` 等）へ変換し、フィルタリング・ソート・選択計算のドメインロジックを100%決定論的にユニットテスト可能にする。
- **Alternatives considered**:
  - `ObservableObject` / `@Published`: プロジェクト憲章で明示的に禁止されているため不採用。
