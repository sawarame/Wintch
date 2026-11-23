# 技術スタックとディレクトリ構成 (Tech Stack)

Wintch プロジェクトで使用されている技術スタック、アーキテクチャ、およびリポジトリ構成の概要です。

## 1. コア技術・フレームワーク

外部サードパーティ製ライブラリは一切使用せず、Apple 標準フレームワークのみで構成されています（`Package.swift` の `dependencies: []`）。

- **言語 / パッケージ管理**: Swift 6.0（Strict Concurrency 対応） / Swift Package Manager（`Package.swift`）
- **対象 OS**: macOS 14.0 (Sonoma) 以降
- **UI フレームワーク**:
  - **SwiftUI**: 設定画面（左サイドバー付き 4 メニュー構成）、権限誘導画面、スイッチャーリスト、アイコングリッド、キャプチャグリッド、メニューバー常駐メニュー（`MenuBarExtra`）の構築
  - **AppKit**: 最前面フローティングパネル制御（`NSPanel`）、IME 対応検索入力欄（`NSTextField`）、ショートカット記録フィールド（`NSView`）、ウィンドウ最前面化およびアプリ起動（`NSWorkspace`, `NSRunningApplication`）
- **状態管理**: Swift 標準 Observation フレームワーク（`@Observable` + `@MainActor`）
- **OS 低レイヤー・システム API**:
  - **ApplicationServices (`AXUIElement`, `AXIsProcessTrustedWithOptions`)**: アクセシビリティ権限確認、ウィンドウ一覧・属性・メニュー項目取得、クローズ操作、フォーカス切り替え
  - **CoreGraphics (`CGWindowListCopyWindowInfo`, `CGEventTap`, `CGPreflightScreenCaptureAccess`)**: 全操作スペースのウィンドウメタデータ取得、グローバルショートカット監視・イベント消費
  - **Carbon (`RegisterEventHotKey`, `InstallEventHandler`)**: セキュア入力保護下での代替ホットキー検知
  - **ScreenCaptureKit (`SCShareableContent`, `SCScreenshotManager`)**: 「キャプチャ表示型」オプトイン選択時の非同期ウィンドウサムネイル取得
  - **ServiceManagement (`SMAppService`)**: ログイン時自動起動の登録・解除
  - **Security / CryptoKit / Foundation (`URLSession`, `SecStaticCode`, `SHA256`)**: GitHub Releases API からの安定版確認・配布 ZIP ダウンロード・SHA-256／コード署名／Team ID 検証・分離ヘルパーによる安全な `.app` 差し替え再起動
- **テストフレームワーク**: Swift Testing（`import Testing`）

---

## 2. アーキテクチャ（MVVM + Services）

OS 依存 API の漏洩防止とユニットテスト容易性を両立するため、4 層構造で責務を分離しています。

1. **App 層 (`Sources/Wintch/`, `Sources/WintchCore/App/`)**: アプリエントリポイント、ライフサイクル、`AppCoordinator` による依存性注入・画面遷移・権限状態統括。
2. **Domain 層 (`Sources/WintchCore/Domain/`)**: OS API に非依存な純粋ビジネスロジックおよび値型モデル。フィルタリング、ソート、ファジー検索、選択インデックス計算、グリッドレイアウト、ショートカット検証、アプリ別ウィンドウプロファイル等を配置。
3. **Services 層 (`Sources/WintchCore/Services/`)**: macOS 低レイヤー API を隔離・カプセル化する層。`Protocols/` のプロトコルを介して注入し、テスト時にモック差し替え可能。
4. **ViewModels / Views 層 (`Sources/WintchCore/ViewModels/`, `Sources/WintchCore/Views/`)**: `@Observable` / `@MainActor` な ViewModel と SwiftUI / 最小限の AppKit ラッパービュー。

---

## 3. ディレクトリ構成

```text
.
├── Package.swift                        # SwiftPM 定義（Swift 6.0 / macOS 14.0+ / 外部依存なし）
├── VERSION                              # アプリバージョン定義（SemVer 単一情報源）
├── AGENTS.md                            # AI エージェントおよび開発者向けプロジェクトガイド
├── README.md                            # プロジェクト概要・インストール・ローカル開発手順（英語）
├── README.ja.md                         # プロジェクト概要・インストール・ローカル開発手順（日本語）
├── .context/                            # プロジェクト基礎ドキュメント・仕様書正本
│   ├── constitution.md                  # 設計・実装の絶対原則（Wintch 憲章 v2.0.0）
│   ├── spec.md                          # 全機能の仕様書正本
│   ├── tech_stack.md                    # 技術スタック・アーキテクチャ・ディレクトリ構成
│   ├── development.md                   # 開発・テスト・ビルド・リリースワークフロー
│   └── swift.md                         # Swift 6.0 コーディング・並行性・ドキュメント規約
├── .github/workflows/
│   └── release.yml                      # テスト・Universal Build・署名・公証・ZIP/DMG Release・Homebrew Tap 自動更新
├── Resources/
│   ├── Info.plist                       # バンドル情報ベース（LSUIElement / アイコン指定等）
│   └── Icons/
│       ├── AppIcon.svg                  # アプリアイコン原画（1024x1024）
│       └── MenuBarIcon.svg              # メニューバー用テンプレートアイコン（18x18）
├── scripts/
│   ├── build-app.sh                     # .app 組み立て・Info.plist 反映・.icns 生成・署名スクリプト
│   └── build-dmg.sh                     # .app と /Applications リンクを格納した DMG 生成・署名スクリプト
├── Sources/
│   ├── Wintch/
│   │   └── WintchApp.swift              # エントリポイント・AppDelegate・MenuBarExtra
│   └── WintchCore/
│       ├── App/
│       │   └── AppCoordinator.swift     # DI・権限監視・ホットキー連携・パネル/ウィンドウ管理
│       ├── Domain/
│       │   ├── AccessibilityStatus.swift        # アクセシビリティ権限状態
│       │   ├── AppIdentity.swift                # 配布版(Wintch) / 開発版(Wintch_dev) 識別情報解決
│       │   ├── AppLanguage.swift                # 対応言語定義（5言語 + system）・システム優先言語解決ロジック
│       │   ├── AppSearchEngine.swift            # アプリ起動候補のファジー検索・スコア順ソート
│       │   ├── AppSearchResult.swift            # アプリ検索結果・ハイライト範囲モデル
│       │   ├── AppStrings.swift                 # 型安全な 5 言語 UI ローカライズテーブル
│       │   ├── AppUpdateModels.swift            # リリースモデル・GitHub API 解析・URL検証・更新/差し替え可否判定
│       │   ├── AppVersionInfo.swift             # バンドル情報からのバージョン・著作権抽出
│       │   ├── AppWindowProfile.swift           # バックキングウィンドウ除外・アプリ別ウィンドウプロファイル
│       │   ├── FuzzySearchMatcher.swift         # スペース区切り AND ファジー検索・ハイライト範囲算出
│       │   ├── HotKeyFallbackSupport.swift      # Carbon 代替ホットキー計画・重複発火防止・解放ウォッチドッグ判定
│       │   ├── LaunchableApp.swift              # 起動可能アプリケーションモデル（別名含む）
│       │   ├── LauncherDisplayStyle.swift       # 検索ランチャー表示形式（リスト型 / キャプチャ表示型）
│       │   ├── LauncherEmptyState.swift         # ランチャー 0 件時の空状態種別と文言判定
│       │   ├── LauncherShortcutPreference.swift # 検索ランチャーショートカット設定・キーラベル解決
│       │   ├── RawWindowCandidate.swift         # フィルタリング前の生ウィンドウ候補モデル
│       │   ├── ScreenRecordingPermissionStatus.swift # 画面収録権限状態
│       │   ├── SemanticVersion.swift            # SemVer 2.0 解析・優先順位比較ロジック
│       │   ├── SettingsTab.swift                # 設定画面左サイドバーの4メニュー定義
│       │   ├── ShortcutConflictValidator.swift  # 通常スイッチャー・ランチャー間の双方向競合検証
│       │   ├── ShortcutPreference.swift         # 通常スイッチャーショートカット設定（旧形式マイグレーション含む）
│       │   ├── SwitcherDisplayStyle.swift       # 表示形式（リスト型 / アイコン型 / キャプチャ表示型）
│       │   ├── SwitcherGridLayout.swift         # アイコン型・キャプチャグリッド列数算出・4 方向循環カーソル計算
│       │   ├── SwitcherListRow.swift            # リスト表示用の統合行識別・構築ロジック
│       │   ├── SwitcherSelection.swift          # スイッチャー／ランチャーの選択インデックス・循環計算
│       │   ├── WindowAppGrouping.swift          # アプリ単位の安定グルーピング・MRU 2 番目初期選択解決
│       │   ├── WindowEntry.swift                # 表示対象ウィンドウドメインモデル
│       │   ├── WindowFilter.swift               # ノイズ除外・重複統合・画面占有判定・WindowEntry 変換
│       │   ├── WindowMenuPairing.swift          # アプリ「ウィンドウ」メニュー項目との省略記号対応照合・補完
│       │   ├── WindowPlacement.swift            # パネル上端固定のウィンドウフレーム配置・クランプ計算
│       │   ├── WindowSearchEngine.swift         # ウィンドウ候補のファジー検索・スコア/MRU ソート
│       │   ├── WindowSearchResult.swift         # ウィンドウ検索結果・ハイライト範囲モデル
│       │   └── WindowSorter.swift               # MRU 記録・Z オーダー併用ソートロジック
│       ├── Services/
│       │   ├── Protocols/                       # テスト用モック差し替えのためのプロトコル群
│       │   ├── AccessibilityPermissionService.swift
│       │   ├── AppUpdateService.swift           # GitHub Releases 確認・ZIP ダウンロード・署名検証・安全差し替え再起動
│       │   ├── HotKeyMonitorService.swift
│       │   ├── IconProviderService.swift
│       │   ├── InstalledAppService.swift
│       │   ├── LaunchAtLoginService.swift
│       │   ├── PreferencesStore.swift
│       │   ├── ScreenRecordingPermissionService.swift
│       │   ├── WindowCaptureService.swift
│       │   ├── WindowFrontPresenter.swift
│       │   └── WindowService.swift
│       ├── ViewModels/
│       │   ├── PermissionGuideViewModel.swift   # 権限誘導画面の状態・アクション管理
│       │   ├── SettingsViewModel.swift          # 設定画面の選択メニュー・ショートカット記録・検証・権限・手動更新管理
│       │   ├── SwitcherViewModel.swift          # スイッチャー／ランチャー表示・検索・終了操作・キャプチャ統括
│       │   └── UpdateViewModel.swift            # 更新確認・進捗・スキップ・差し替えフォールバック制御
│       └── Views/
│           ├── LauncherSearchField.swift        # IME 優先 NSTextField ラッパー検索入力欄
│           ├── PermissionGuideView.swift        # アクセシビリティ権限誘導画面
│           ├── SettingsView.swift               # 左サイドバー付き設定画面（バージョン情報・手動更新統合）
│           ├── ShortcutRecorderView.swift       # ショートカットキー入力キャプチャビュー
│           ├── SwitcherCaptureGridView.swift    # キャプチャ表示型グリッドビュー
│           ├── SwitcherContentView.swift        # モード・表示形式に応じたコンテナ分岐ビュー
│           ├── SwitcherIconGridView.swift       # アイコン型グリッドビュー
│           ├── SwitcherListView.swift           # リスト型スイッチャー＆検索ランチャー統合ビュー
│           ├── SwitcherPanel.swift              # 非アクティブ表示対応フローティング NSPanel ラッパー
│           └── UpdatePromptView.swift           # 新バージョン更新確認・進捗・フォールバックダイアログ
└── Tests/
    └── WintchCoreTests/                         # Swift Testing ユニットテストおよび Mocks/
```
