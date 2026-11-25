/**
 * Wintch 紹介ページ 多言語ローカライズ辞書および言語解決ロジック
 * アプリ本体と同じ 5 言語（en / ja / zh-Hans / zh-Hant / ko）をサポートする
 */
(function (global) {
  "use strict";

  /** 対応言語の一覧とネイティブ表示名 */
  const LOCALE_LABELS = {
    en: "English",
    ja: "日本語",
    "zh-Hans": "简体中文",
    "zh-Hant": "繁體中文",
    ko: "한국어",
  };

  /** 5 言語の翻訳テーブル */
  const MESSAGES = {
    en: {
      "meta.title": "Wintch — Per-window switcher & search launcher for macOS",
      "meta.description":
        "A simple, lightweight, privacy-first per-window switcher and search launcher for macOS 14.0+. Switch individual windows across Spaces, fuzzy search windows and apps, and close windows from the panel.",
      "nav.switcher": "Window Switcher",
      "nav.capture": "Display Styles",
      "nav.launcher": "Search Launcher",
      "nav.close": "Close Windows",
      "nav.privacy": "Native Design",
      "nav.install": "Install",
      "hero.metaRest": "macOS 14.0+ · MIT License",
      "hero.titleLine1": "Switch windows,",
      "hero.titleAccent": "more intuitively.",
      "hero.subtitle":
        "Wintch (Window + Switch) is a simple, lightweight per-window switcher and search launcher for macOS—letting you jump straight to individual windows across Spaces, even when an app has several open.",
      "hero.downloadWithVersion": "Download ({version})",
      "hero.downloadFallback": "Download Latest",
      "showcase.tabSwitcher": "Window Switcher",
      "showcase.tabLauncher": "Search Launcher",
      "showcase.tabSettings": "Settings & Permissions",
      "showcase.styleList": "List",
      "showcase.styleIcon": "Icon",
      "showcase.styleCapture": "Capture View",
      "showcase.groupByApp": "Group by App",
      "showcase.prev": "Prev",
      "showcase.next": "Next",
      "showcase.close": "Close",
      "showcase.reset": "Reset",
      "showcase.emptySwitcher": "All demo windows closed. Click Reset to restore.",
      "showcase.searchPlaceholder": "Search windows or apps…",
      "showcase.sampleLabel": "Try:",
      "showcase.launchSection": "Launch App",
      "showcase.launchEmptyWindowsSection": "No matching windows — Launch App",
      "showcase.launchBadge": "Launch",
      "showcase.noMatches": "No matching windows or apps",
      "showcase.settingsGeneral": "General",
      "showcase.settingsSwitcher": "Switcher",
      "showcase.settingsLauncher": "Launcher",
      "showcase.settingsSystem": "System",
      "showcase.sLaunchAtLogin": "Launch at Login",
      "showcase.sAutoUpdate": "Check for Updates Automatically",
      "showcase.sAutoUpdateSub": "Opt-in check via GitHub Releases on launch",
      "showcase.sLanguage": "Language",
      "showcase.sLanguageValue": "Follow System (5 Languages)",
      "showcase.sOn": "ON",
      "showcase.sOff": "OFF",
      "showcase.sShortcut": "Shortcut",
      "showcase.sDisplayStyle": "Display Style",
      "showcase.sGroupByApp": "Group by App",
      "showcase.sStyleList": "List / Icon / Capture View",
      "showcase.sStyleLauncher": "List / Capture View",
      "showcase.sAccessibility": "Accessibility",
      "showcase.sGranted": "Granted",
      "showcase.sScreenRecording": "Screen Recording",
      "showcase.sOptInOnly": "Opt-in (Capture View only)",
      "showcase.sAppInfo": "Version",
      "showcase.sCheckUpdates": "Check for Updates",
      "switcher.eyebrow": "Window Switcher (⌥ + Tab)",
      "switcher.titleLine1": "Per-window switching,",
      "switcher.titleAccent": "without confusion.",
      "switcher.desc":
        "While macOS Command + Tab switches by application, Wintch lists every open window individually across all Spaces—sorted by Most Recently Used (MRU) and optionally grouped by application.",
      "switcher.bullet1":
        "Press and release Option + Tab to jump straight back to the window you were just using",
      "switcher.bullet2":
        "Group windows by app (enabled by default) or view a flat MRU list—toggleable anytime from Settings or the menu bar",
      "switcher.bullet3":
        "Choose from List, Icon, or Capture View styles and customize activation shortcuts with conflict prevention",
      "switcher.compareStandard": "Built-in Command + Tab (per app)",
      "switcher.compareWintch": "Wintch (Per-Window MRU)",
      "capture.eyebrow": "Display Styles & Capture View",
      "capture.titleLine1": "Pick your style,",
      "capture.titleAccent": "or preview windows visually.",
      "capture.desc":
        "Choose List, Icon, or opt-in Capture View for the Window Switcher—and List or Capture View independently for the Search Launcher. In Capture View, live window thumbnails make multiple windows of the same app recognizable at a glance.",
      "capture.bullet1":
        "Zero-latency display: opens immediately with cached thumbnails or placeholders and refreshes asynchronously in the background",
      "capture.bullet2":
        "Switch styles and app grouping independently for the Switcher and Search Launcher right from the menu bar",
      "capture.bullet3":
        "Screen Recording permission is strictly opt-in—List and Icon styles never request or use it",
      "capture.styleList": "List",
      "capture.styleIcon": "Icon",
      "capture.styleCapture": "Capture View (Opt-in)",
      "capture.privacyNote":
        "Thumbnails stay strictly in an in-memory temporary cache—never saved to disk or sent over the network.",
      "launcher.eyebrow": "Search Launcher (⌥ + Space)",
      "launcher.titleLine1": "Find windows and launch apps,",
      "launcher.titleAccent": "from one panel.",
      "launcher.desc":
        "Toggle the Search Launcher whenever your desktop gets busy. Narrow down windows by app name and title with space-separated AND fuzzy matching—and launch unopened apps directly from the Launch App section below.",
      "launcher.bullet1":
        "Highlights matched characters in real time, with full IME composition support for Japanese, Chinese, and Korean",
      "launcher.bullet2":
        "Works even with zero open windows, matching localized and English app aliases (e.g. メモ / Notes)",
      "launcher.bullet3":
        "Navigate seamlessly across windows and app candidates with ↑/↓, Ctrl + N/P, or ⌥ + Tab",
      "launcher.launchSection": "Launch App",
      "launcher.notesLabel": "Notes",
      "launcher.launchBadge": "Launch",
      "close.eyebrow": "Close Windows (⌥ + Q)",
      "close.titleLine1": "Clean up windows",
      "close.titleAccent": "right from the list.",
      "close.desc":
        "No need to switch to a window just to close it. Select any window in the Switcher or Launcher and press your modifier + Q (default ⌥ + Q) to close it—or gracefully quit the app when closing its last window.",
      "close.bullet1":
        "Works identically with ⌥ + Q in both the Window Switcher and Search Launcher, showing a subtle spinner while closing",
      "close.bullet2":
        "Closes a single window when multiple are open, and gracefully quits the app on its last window",
      "close.bullet3":
        "Never force-quits—always respects standard unsaved-changes confirmation dialogs",
      "close.cardTitle": "Close the selected window in place",
      "close.safeNote":
        "Standard save-confirmation dialogs are always respected for unsaved changes.",
      "privacy.eyebrow": "Native & Privacy by Design",
      "privacy.titleLine1": "Native macOS design,",
      "privacy.titleAccent": "fast and minimal.",
      "privacy.desc":
        "Built purely with Apple's standard frameworks—Swift 6.0 and SwiftUI—with zero third-party dependencies and zero private APIs. Works reliably even in Secure Input fields like password prompts.",
      "privacy.bullet1":
        "Universal Binary for Apple Silicon & Intel, living unobtrusively in your menu bar without a Dock icon",
      "privacy.bullet2":
        "No analytics or telemetry—Screen Recording and automatic update checks are strictly opt-in",
      "privacy.bullet3":
        "Instant switching across 5 languages (English, Japanese, Simplified/Traditional Chinese, Korean) plus safe in-app updates",
      "privacy.card1Desc":
        "Native Universal Binary (Apple Silicon / Intel) with zero external dependencies",
      "privacy.card2Title": "Least Privilege & Opt-In",
      "privacy.card2Desc":
        "Accessibility permission only by default; Screen Recording & update checks are opt-in",
      "privacy.card3Title": "Menu Bar Resident & 5 Languages",
      "privacy.card3Desc":
        "No Dock clutter; supports EN / JA / 简体中文 / 繁體中文 / 한국어 without restart",
      "privacy.card4Title": "Secure Input & Verified Updates",
      "privacy.card4Desc":
        "Stays responsive in password fields and verifies signatures before in-app updates",
      "shortcuts.eyebrow": "Keyboard Shortcuts",
      "shortcuts.title": "Default Shortcuts",
      "shortcuts.subtitle":
        "Default keybindings out of the box. You can customize activation shortcuts anytime in Settings (⌘ + ,).",
      "shortcuts.scopeSwitcher": "Switcher",
      "shortcuts.scopeLauncher": "Launcher",
      "shortcuts.scopeCommon": "Common",
      "shortcuts.descTab":
        "Hold to open switcher and cycle to the next window (release modifier to confirm)",
      "shortcuts.descShiftTab": "Move selection backward to the previous window",
      "shortcuts.descSpace": "Toggle the Search Launcher open or closed",
      "shortcuts.descArrows":
        "Navigate list items or icon/capture grids (⌥ + Tab also works in the Launcher)",
      "shortcuts.descClose":
        "Close the selected window (or gracefully quit if it is the app's last window)",
      "shortcuts.descEnterEsc":
        "Press Enter to switch or launch; press Esc to cancel without switching",
      "install.eyebrow": "Installation",
      "install.title": "Install & Setup",
      "install.subtitle":
        "Install quickly via Homebrew Cask or download the Developer ID-signed and Apple-notarized DMG / ZIP from GitHub Releases.",
      "install.recommendedBadge": "Recommended",
      "install.brewTitle": "Install with Homebrew",
      "install.brewDesc":
        "Run the command below in your terminal to add the tap and install Wintch in one step.",
      "install.brewUpgradeLabel": "Upgrade to the latest version",
      "install.brewUninstallLabel": "Uninstall (add --zap to remove preferences)",
      "install.manualTitle": "Manual Install from GitHub Releases",
      "install.manualDesc":
        "If you prefer not to use Homebrew, download the disk image or archive directly from GitHub Releases.",
      "install.step1":
        "Download the latest Wintch-vX.Y.Z.dmg (or .zip) from the GitHub Releases page.",
      "install.step2":
        "Open the DMG and drag Wintch.app into Applications (or extract the ZIP and move Wintch.app to /Applications), then launch it.",
      "install.step3":
        "Follow the first-launch prompt to grant Accessibility permission in System Settings > Privacy & Security > Accessibility.",
      "install.notarizedNote":
        "Distributed .app and .dmg builds are Developer ID-signed and Apple-notarized, so no Gatekeeper warnings appear on launch.",
      "install.openReleases": "Open GitHub Releases",
      "specs.osLabel": "OS / Architecture",
      "specs.osValue": "macOS 14.0 (Sonoma)+ · Apple Silicon / Intel",
      "specs.permLabel": "Permissions",
      "specs.permValue": "Accessibility (Screen Recording optional for Capture View)",
      "specs.licenseLabel": "License / Stack",
      "specs.licenseValue": "MIT License · Swift 6.0 / SwiftUI · 5 Languages",
      "bottomCta.title": "Switch windows without friction.",
      "bottomCta.desc": "Free and open-source under the MIT License.",
      "common.copied": "Copied to clipboard",
      "common.copyCommand": "Copy command",
      "common.themeSystem": "Theme: System",
      "common.themeLight": "Theme: Light",
      "common.themeDark": "Theme: Dark",
    },

    ja: {
      "meta.title": "Wintch — macOS 向けシンプルウィンドウ単位スイッチャー＆ランチャー",
      "meta.description":
        "完全ローカル動作・最小権限・軽量な macOS 14.0+ 向けウィンドウ単位スイッチャー＆検索ランチャー「Wintch」の紹介とインストール方法。",
      "nav.switcher": "通常スイッチャー",
      "nav.capture": "表示形式・キャプチャ",
      "nav.launcher": "検索ランチャー",
      "nav.close": "ウィンドウ終了",
      "nav.privacy": "ネイティブ設計",
      "nav.install": "インストール",
      "hero.metaRest": "macOS 14.0+ · MIT License",
      "hero.titleLine1": "ウィンドウの切り替えを、",
      "hero.titleAccent": "もっと直感的に。",
      "hero.subtitle":
        "Wintch（Window + Switch）は、macOS 標準の Command + Tab では届かない「同じアプリの複数ウィンドウ」へ操作スペースを横断して瞬時に切り替えられる、シンプルで軽量なウィンドウ単位スイッチャー＆検索ランチャーです。",
      "hero.downloadWithVersion": "ダウンロード ({version})",
      "hero.downloadFallback": "最新版をダウンロード",
      "showcase.tabSwitcher": "通常スイッチャー",
      "showcase.tabLauncher": "検索ランチャー",
      "showcase.tabSettings": "設定・権限",
      "showcase.styleList": "リスト型",
      "showcase.styleIcon": "アイコン型",
      "showcase.styleCapture": "キャプチャ表示型",
      "showcase.groupByApp": "アプリごとにグルーピング",
      "showcase.prev": "前へ",
      "showcase.next": "次へ",
      "showcase.close": "閉じる",
      "showcase.reset": "リセット",
      "showcase.emptySwitcher": "デモ用ウィンドウをすべて閉じました。「リセット」で元に戻せます。",
      "showcase.searchPlaceholder": "ウィンドウやアプリを検索…",
      "showcase.sampleLabel": "試す:",
      "showcase.launchSection": "アプリを起動",
      "showcase.launchEmptyWindowsSection": "一致するウィンドウがないため、アプリを起動",
      "showcase.launchBadge": "起動",
      "showcase.noMatches": "一致するウィンドウやアプリがありません",
      "showcase.settingsGeneral": "一般",
      "showcase.settingsSwitcher": "スイッチャー",
      "showcase.settingsLauncher": "ランチャー",
      "showcase.settingsSystem": "システム",
      "showcase.sLaunchAtLogin": "ログイン時に自動起動",
      "showcase.sAutoUpdate": "バージョンアップを自動チェック",
      "showcase.sAutoUpdateSub": "起動時に GitHub Releases の最新安定版を確認（オプトイン）",
      "showcase.sLanguage": "言語",
      "showcase.sLanguageValue": "システム設定に従う（5 言語対応）",
      "showcase.sOn": "ON",
      "showcase.sOff": "OFF",
      "showcase.sShortcut": "ショートカット",
      "showcase.sDisplayStyle": "表示形式",
      "showcase.sGroupByApp": "アプリごとにグルーピング",
      "showcase.sStyleList": "リスト型 / アイコン型 / キャプチャ表示型",
      "showcase.sStyleLauncher": "リスト型 / キャプチャ表示型",
      "showcase.sAccessibility": "アクセシビリティ権限",
      "showcase.sGranted": "許可済み",
      "showcase.sScreenRecording": "画面収録権限",
      "showcase.sOptInOnly": "任意（キャプチャ表示型のみ）",
      "showcase.sAppInfo": "バージョン",
      "showcase.sCheckUpdates": "アップデートを確認",
      "switcher.eyebrow": "通常スイッチャー (⌥ + Tab)",
      "switcher.titleLine1": "ウィンドウ単位で、",
      "switcher.titleAccent": "迷わず切り替え。",
      "switcher.desc":
        "macOS 標準の Command + Tab がアプリケーション単位の切り替えであるのに対し、Wintch は操作スペースを横断して開いているウィンドウを 1 枚ずつ直近アクティブ順（MRU）で一覧表示。アプリごとのグルーピングにも対応し、複数ウィンドウ間を迷わず行き来できます。",
      "switcher.bullet1":
        "Option + Tab を押してすぐ離すだけで、直前まで使っていたウィンドウへすばやく切り替え",
      "switcher.bullet2":
        "アプリごとのグルーピング表示（デフォルト ON）とフラット表示をメニューバーや設定からいつでも切替可能",
      "switcher.bullet3":
        "リスト型・アイコン型・キャプチャ表示型の 3 形式から選べ、競合防止付きでショートカットを自由にカスタマイズ",
      "switcher.compareStandard": "標準の Command + Tab（アプリ単位）",
      "switcher.compareWintch": "Wintch (ウィンドウ単位 MRU)",
      "capture.eyebrow": "表示形式・キャプチャ表示型",
      "capture.titleLine1": "好みのスタイルで、",
      "capture.titleAccent": "見た目からも直感的に選ぶ。",
      "capture.desc":
        "通常スイッチャーは「リスト型」「アイコン型」「キャプチャ表示型」の 3 種類、検索ランチャーも「リスト型」「キャプチャ表示型」を独立して選択可能。キャプチャ表示型では各ウィンドウの実際の見た目をプレビュー表示し、同じアプリの複数ウィンドウも一目で判別できます。",
      "capture.bullet1":
        "ショートカット押下でキャッシュまたはプレースホルダーを即座に表示し、バックグラウンドで最新キャプチャへ滑らかに差し替え",
      "capture.bullet2":
        "メニューバーから通常スイッチャー・検索ランチャーそれぞれの表示形式とグルーピングを個別に切替可能",
      "capture.bullet3":
        "画面収録権限はキャプチャ表示型を選んだ場合のみ任意で使用（リスト型・アイコン型では一切不要）",
      "capture.styleList": "リスト型",
      "capture.styleIcon": "アイコン型",
      "capture.styleCapture": "キャプチャ表示型（任意）",
      "capture.privacyNote":
        "画像はメモリ上の一時キャッシュのみで保持し、ディスク保存や外部送信は一切行いません。",
      "launcher.eyebrow": "検索ランチャー (⌥ + Space)",
      "launcher.titleLine1": "検索もアプリ起動も、",
      "launcher.titleAccent": "ひとつのパネルで。",
      "launcher.desc":
        "ウィンドウが増えてきたら検索ランチャーをトグル起動。アプリ名やウィンドウタイトルをスペース区切り AND のファジー検索で絞り込み、まだ開いていないアプリも下の「アプリを起動」欄からそのまま立ち上げられます。",
      "launcher.bullet1":
        "一致した文字位置をリアルタイムにハイライト表示し、日本語 IME の変換操作も妨げない設計",
      "launcher.bullet2":
        "開いているウィンドウが 0 件でもランチャーを起動でき、「メモ / Notes」のように日英どちらの名称でもアプリを検索・起動可能",
      "launcher.bullet3":
        "↑ / ↓・Ctrl + N / P に加え、ランチャー表示中でも ⌥ + Tab でウィンドウ候補とアプリ候補を貫通移動",
      "launcher.launchSection": "アプリを起動",
      "launcher.notesLabel": "メモ",
      "launcher.launchBadge": "起動",
      "close.eyebrow": "ウィンドウ／アプリ終了 (⌥ + Q)",
      "close.titleLine1": "一覧のまま、",
      "close.titleAccent": "不要なウィンドウを閉じる。",
      "close.desc":
        "わざわざ対象ウィンドウへ切り替えてから閉じる必要はありません。スイッチャーやランチャーの一覧から選んで修飾キー + Q（デフォルト ⌥ + Q）を押すだけで、その場から素早く閉じられます。",
      "close.bullet1":
        "スイッチャーでも検索ランチャーでも同じ ⌥ + Q で操作でき、終了処理中は対象項目にスピナーを表示",
      "close.bullet2":
        "複数ウィンドウがある場合は選択中の 1 枚のみを閉じ、最後の 1 枚の場合はアプリ本体を通常終了",
      "close.bullet3":
        "未保存変更のあるウィンドウでは強制終了せず、アプリ標準の保存確認ダイアログを尊重",
      "close.cardTitle": "選択中のウィンドウをその場で閉じる",
      "close.safeNote":
        "未保存の変更がある場合は、アプリ標準の確認ダイアログを尊重します。",
      "privacy.eyebrow": "Native & Privacy by Design",
      "privacy.titleLine1": "ネイティブ実装で、",
      "privacy.titleAccent": "軽快に、シンプルに。",
      "privacy.desc":
        "Swift 6.0 と SwiftUI を中心とした Apple 標準フレームワークのみで構成。外部依存や非公開 API を一切使わず、パスワード入力欄などのセキュア入力保護下でも安定して動作します。",
      "privacy.bullet1":
        "Apple Silicon / Intel 両対応の Universal Binary で、Dock を専有しないメニューバー常駐スタイル",
      "privacy.bullet2":
        "トラッキングや不要な通信はゼロ。画面収録権限も自動バージョン確認も明示的なオプトイン方式",
      "privacy.bullet3":
        "再起動不要の 5 言語切替（日本語・英語・簡体字／繁体字中国語・韓国語）と署名検証付きアプリ内アップデートに対応",
      "privacy.card1Desc":
        "外部依存ゼロ・Apple Silicon / Intel 両対応のネイティブ実装",
      "privacy.card2Title": "最小権限＆オプトイン原則",
      "privacy.card2Desc":
        "標準ではアクセシビリティ権限のみ。画面収録・自動更新確認は任意選択",
      "privacy.card3Title": "メニューバー常駐＆ 5 言語対応",
      "privacy.card3Desc":
        "Dock に表示せず軽快待機。日本語 / EN / 简体中文 / 繁體中文 / 한국어 を即時切替",
      "privacy.card4Title": "セキュア入力対応＆安全な更新",
      "privacy.card4Desc":
        "パスワード欄でも反応し、アプリ内アップデート時は署名・SHA-256 を検証",
      "shortcuts.eyebrow": "キーボード操作",
      "shortcuts.title": "基本ショートカット一覧",
      "shortcuts.subtitle":
        "デフォルト設定のキーバインドです。起動ショートカットは設定画面（⌘ + ,）から自由にカスタマイズできます。",
      "shortcuts.scopeSwitcher": "通常スイッチャー",
      "shortcuts.scopeLauncher": "検索ランチャー",
      "shortcuts.scopeCommon": "共通",
      "shortcuts.descTab":
        "ホールド式でスイッチャーを開き、次のウィンドウへ移動（修飾キーを離して確定）",
      "shortcuts.descShiftTab": "逆方向（前のウィンドウ）へ選択を移動",
      "shortcuts.descSpace": "トグル式で検索ランチャーを開く / 閉じる（再押下でキャンセル）",
      "shortcuts.descArrows":
        "リストの上下およびアイコン／キャプチャグリッドの上下左右を循環移動（ランチャー中は ⌥ + Tab も可）",
      "shortcuts.descClose":
        "選択中のウィンドウを閉じる（同アプリ最後の 1 枚の場合はアプリを通常終了）",
      "shortcuts.descEnterEsc":
        "Enter で切り替え・アプリ起動を確定、Esc で切り替えずにキャンセル",
      "install.eyebrow": "インストール",
      "install.title": "インストール方法とセットアップ",
      "install.subtitle":
        "Homebrew Cask または GitHub Releases の配布 DMG / ZIP からすぐに導入できます。Developer ID 署名・Apple 公証済みです。",
      "install.recommendedBadge": "推奨",
      "install.brewTitle": "Homebrew でインストール",
      "install.brewDesc":
        "ターミナルから以下のコマンドを実行すると、Tap の追加とインストールが一度に完了します。",
      "install.brewUpgradeLabel": "最新版へアップデート",
      "install.brewUninstallLabel": "アンインストール（設定削除は --zap を付与）",
      "install.manualTitle": "GitHub Releases から手動インストール",
      "install.manualDesc":
        "Homebrew を利用しない場合は、リリースページから DMG または ZIP を直接ダウンロードして導入できます。",
      "install.step1":
        "GitHub Releases ページから最新の Wintch-vX.Y.Z.dmg（または .zip）をダウンロードします。",
      "install.step2":
        "DMG を開いて Wintch.app を Applications フォルダへドラッグ＆ドロップし起動します（ZIP の場合は展開後 /Applications へ移動）。",
      "install.step3":
        "初回起動時に表示される案内に従って「システム設定 ＞ プライバシーとセキュリティ ＞ アクセシビリティ」で Wintch を許可します。",
      "install.notarizedNote":
        "配布版（.app・.dmg）は Developer ID 署名および Apple 公証済みのため、通常の起動で Gatekeeper 警告は表示されません。",
      "install.openReleases": "GitHub Releases を開く",
      "specs.osLabel": "対応 OS / アーキテクチャ",
      "specs.osValue": "macOS 14.0 (Sonoma) 以降 · Apple Silicon / Intel",
      "specs.permLabel": "必要権限",
      "specs.permValue": "アクセシビリティ（画面収録はキャプチャ表示型のみ任意）",
      "specs.licenseLabel": "ライセンス / 技術",
      "specs.licenseValue": "MIT License · Swift 6.0 / SwiftUI · 5 言語対応",
      "bottomCta.title": "ウィンドウ切り替えのストレスを、ゼロに。",
      "bottomCta.desc": "無料・オープンソース（MIT ライセンス）で公開しています。",
      "common.copied": "コピーしました",
      "common.copyCommand": "コマンドをコピー",
      "common.themeSystem": "テーマ: システム連動",
      "common.themeLight": "テーマ: ライト",
      "common.themeDark": "テーマ: ダーク",
    },

    "zh-Hans": {
      "meta.title": "Wintch — 面向 macOS 的简洁轻量窗口级切换器与搜索启动器",
      "meta.description":
        "完全本地运行、最小权限且轻量的 macOS 14.0+ 窗口级切换器与搜索启动器 Wintch 的功能介绍与安装指南。",
      "nav.switcher": "窗口切换器",
      "nav.capture": "显示样式",
      "nav.launcher": "搜索启动器",
      "nav.close": "关闭窗口",
      "nav.privacy": "原生设计",
      "nav.install": "安装",
      "hero.metaRest": "macOS 14.0+ · MIT License",
      "hero.titleLine1": "让窗口切换，",
      "hero.titleAccent": "更加直观。",
      "hero.subtitle":
        "Wintch（Window + Switch）是一款简洁轻量的 macOS 窗口级切换器与搜索启动器，支持跨调度空间（Spaces）瞬间切换到同一应用的任意窗口。",
      "hero.downloadWithVersion": "下载 ({version})",
      "hero.downloadFallback": "下载最新版本",
      "showcase.tabSwitcher": "窗口切换器",
      "showcase.tabLauncher": "搜索启动器",
      "showcase.tabSettings": "设置与权限",
      "showcase.styleList": "列表",
      "showcase.styleIcon": "图标",
      "showcase.styleCapture": "截图视图",
      "showcase.groupByApp": "按应用分组",
      "showcase.prev": "上一个",
      "showcase.next": "下一个",
      "showcase.close": "关闭",
      "showcase.reset": "重置",
      "showcase.emptySwitcher": "演示窗口已全部关闭，点击“重置”可恢复。",
      "showcase.searchPlaceholder": "搜索窗口或应用…",
      "showcase.sampleLabel": "示例:",
      "showcase.launchSection": "启动应用",
      "showcase.launchEmptyWindowsSection": "无匹配窗口 — 启动应用",
      "showcase.launchBadge": "启动",
      "showcase.noMatches": "没有匹配的窗口或应用",
      "showcase.settingsGeneral": "通用",
      "showcase.settingsSwitcher": "切换器",
      "showcase.settingsLauncher": "启动器",
      "showcase.settingsSystem": "系统",
      "showcase.sLaunchAtLogin": "登录时自动启动",
      "showcase.sAutoUpdate": "自动检查更新",
      "showcase.sAutoUpdateSub": "启动时通过 GitHub Releases 检查稳定版（可选）",
      "showcase.sLanguage": "语言",
      "showcase.sLanguageValue": "跟随系统（支持 5 种语言）",
      "showcase.sOn": "开",
      "showcase.sOff": "关",
      "showcase.sShortcut": "快捷键",
      "showcase.sDisplayStyle": "显示样式",
      "showcase.sGroupByApp": "按应用分组",
      "showcase.sStyleList": "列表 / 图标 / 截图视图",
      "showcase.sStyleLauncher": "列表 / 截图视图",
      "showcase.sAccessibility": "辅助功能权限",
      "showcase.sGranted": "已授权",
      "showcase.sScreenRecording": "屏幕录制权限",
      "showcase.sOptInOnly": "可选（仅截图视图需要）",
      "showcase.sAppInfo": "版本",
      "showcase.sCheckUpdates": "检查更新",
      "switcher.eyebrow": "窗口切换器 (⌥ + Tab)",
      "switcher.titleLine1": "按窗口切换，",
      "switcher.titleAccent": "不再迷失。",
      "switcher.desc":
        "macOS 原生的 Command + Tab 按应用切换，而 Wintch 可跨空间单独列出每个打开的窗口，按最近使用顺序 (MRU) 排列，并支持按应用分组。",
      "switcher.bullet1": "只需按下并松开 Option + Tab，即可直接跳回上一个使用中的窗口",
      "switcher.bullet2": "默认开启按应用分组，也可随时在设置或菜单栏切换为平铺 MRU 列表",
      "switcher.bullet3": "提供列表、图标、截图视图三种样式，并支持带冲突检测的快捷键自定义",
      "switcher.compareStandard": "系统默认的 Command + Tab（按应用切换）",
      "switcher.compareWintch": "Wintch（按窗口 MRU）",
      "capture.eyebrow": "显示样式与截图视图",
      "capture.titleLine1": "自由选择视图，",
      "capture.titleAccent": "凭画面一眼识别。",
      "capture.desc":
        "窗口切换器支持列表、图标与可选截图视图，搜索启动器也独立支持列表与截图缩略图视图。开启截图视图后，即使同一应用有多个窗口也能一目了然。",
      "capture.bullet1": "零延迟弹出：优先展示缓存或占位图标，并在后台异步刷新最新窗口截图",
      "capture.bullet2": "可直接通过菜单栏为切换器和启动器独立切换样式与按应用分组",
      "capture.bullet3": "屏幕录制权限严格遵循可选原则：列表与图标样式完全无需该权限",
      "capture.styleList": "列表",
      "capture.styleIcon": "图标",
      "capture.styleCapture": "截图视图（可选）",
      "capture.privacyNote": "截图仅暂存于内存中，绝不写入磁盘或发送至网络。",
      "launcher.eyebrow": "搜索启动器 (⌥ + Space)",
      "launcher.titleLine1": "搜索窗口与启动应用，",
      "launcher.titleAccent": "一个面板搞定。",
      "launcher.desc":
        "窗口较多时可一键呼出搜索启动器，使用空格分隔的 AND 模糊匹配筛选应用名与窗口标题，并可直接从下方“启动应用”区域启动尚未打开的应用。",
      "launcher.bullet1": "实时高亮匹配字符，并完整兼容中文、日文、韩文输入法组合输入",
      "launcher.bullet2": "即使当前打开的窗口数为 0 也能启动，支持中英文等多语言别名搜索",
      "launcher.bullet3": "支持 ↑ / ↓、Ctrl + N / P 及 ⌥ + Tab 在窗口与应用候选间无缝移动",
      "launcher.launchSection": "启动应用",
      "launcher.notesLabel": "备忘录",
      "launcher.launchBadge": "启动",
      "close.eyebrow": "关闭窗口 (⌥ + Q)",
      "close.titleLine1": "在列表中，",
      "close.titleAccent": "直接整理冗余窗口。",
      "close.desc":
        "无需先切换到窗口再关闭。在切换器或启动器中选中目标后按下修饰键 + Q（默认 ⌥ + Q）即可关闭窗口；若是该应用的最后一个窗口，则会正常退出应用。",
      "close.bullet1": "在切换器与搜索启动器中均使用 ⌥ + Q 关闭，处理期间显示加载指示器",
      "close.bullet2": "多窗口时仅关闭当前选中窗口，最后一个窗口时自动温和退出应用",
      "close.bullet3": "绝不强制终止进程，完整尊重应用原生的未保存更改确认对话框",
      "close.cardTitle": "就地关闭当前选中的窗口",
      "close.safeNote": "如存在未保存的更改，将始终尊重应用标准的保存确认提示。",
      "privacy.eyebrow": "原生与隐私优先",
      "privacy.titleLine1": "纯原生构建，",
      "privacy.titleAccent": "轻快且纯粹。",
      "privacy.desc":
        "完全基于 Swift 6.0 与 SwiftUI 等 Apple 标准框架打造，零第三方依赖、零私有 API。即使在密码输入框等安全输入保护状态下也能稳定响应。",
      "privacy.bullet1": "支持 Apple Silicon 与 Intel 的通用二进制，常驻菜单栏不占程序坞图标",
      "privacy.bullet2": "无任何统计与追踪；屏幕录制权限与自动更新检查均为用户主动开启",
      "privacy.bullet3": "内置 5 种语言即时切换（无需重启），并提供签名验证的应用内安全更新",
      "privacy.card1Desc": "零外部依赖的 Apple Silicon / Intel 原生通用二进制",
      "privacy.card2Title": "最小权限与可选授权",
      "privacy.card2Desc": "默认仅需辅助功能权限；屏幕录制与自动更新检查均按需启用",
      "privacy.card3Title": "菜单栏常驻与 5 种语言",
      "privacy.card3Desc": "不占程序坞空间，支持中 / 英 / 日 / 韩即时切换",
      "privacy.card4Title": "安全输入支持与可信更新",
      "privacy.card4Desc": "密码输入场景同样响应，应用内更新前校验签名与 SHA-256",
      "shortcuts.eyebrow": "键盘快捷键",
      "shortcuts.title": "默认快捷键一览",
      "shortcuts.subtitle": "以下为默认键位配置，您可随时在设置界面（⌘ + ,）中自由自定义触发快捷键。",
      "shortcuts.scopeSwitcher": "切换器",
      "shortcuts.scopeLauncher": "启动器",
      "shortcuts.scopeCommon": "通用",
      "shortcuts.descTab": "按住以打开切换器并切换至下一个窗口（松开修饰键确认）",
      "shortcuts.descShiftTab": "反向选择上一个窗口",
      "shortcuts.descSpace": "打开或关闭搜索启动器",
      "shortcuts.descArrows": "在列表项或图标/截图网格中移动（启动器中也可使用 ⌥ + Tab）",
      "shortcuts.descClose": "关闭当前选中的窗口（若为最后 1 个窗口则正常退出应用）",
      "shortcuts.descEnterEsc": "按 Enter 确认切换或启动，按 Esc 取消且不切换",
      "install.eyebrow": "安装",
      "install.title": "安装与配置",
      "install.subtitle":
        "可通过 Homebrew Cask 或 GitHub Releases 提供的 DMG / ZIP 安装包快速安装，均已完成 Developer ID 签名与 Apple 公证。",
      "install.recommendedBadge": "推荐",
      "install.brewTitle": "使用 Homebrew 安装",
      "install.brewDesc": "在终端运行以下命令即可一步完成添加 Tap 与安装 Wintch。",
      "install.brewUpgradeLabel": "升级到最新版本",
      "install.brewUninstallLabel": "卸载（附加 --zap 可一并清除配置）",
      "install.manualTitle": "从 GitHub Releases 手动安装",
      "install.manualDesc": "如不使用 Homebrew，可直接从发布页下载 DMG 或 ZIP 安装。",
      "install.step1": "从 GitHub Releases 页面下载最新的 Wintch-vX.Y.Z.dmg（或 .zip）。",
      "install.step2":
        "打开 DMG 并将 Wintch.app 拖入 Applications 文件夹后启动（或解压 ZIP 后移至 /Applications）。",
      "install.step3":
        "按照首次启动引导，在“系统设置 > 隐私与安全性 > 辅助功能”中允许 Wintch。",
      "install.notarizedNote":
        "官方发布的 .app 与 .dmg 均经过 Developer ID 签名与 Apple 公证，启动时不会出现 Gatekeeper 拦截警告。",
      "install.openReleases": "打开 GitHub Releases",
      "specs.osLabel": "系统要求 / 架构",
      "specs.osValue": "macOS 14.0 (Sonoma)+ · Apple Silicon / Intel",
      "specs.permLabel": "所需权限",
      "specs.permValue": "辅助功能（屏幕录制仅在截图视图下可选）",
      "specs.licenseLabel": "许可证 / 技术栈",
      "specs.licenseValue": "MIT License · Swift 6.0 / SwiftUI · 5 种语言",
      "bottomCta.title": "告别窗口切换的繁琐与干扰。",
      "bottomCta.desc": "免费且以 MIT 协议开源发布。",
      "common.copied": "已复制到剪贴板",
      "common.copyCommand": "复制命令",
      "common.themeSystem": "主题：跟随系统",
      "common.themeLight": "主题：浅色",
      "common.themeDark": "主题：深色",
    },

    "zh-Hant": {
      "meta.title": "Wintch — 專為 macOS 打造的簡潔輕量視窗級切換器與搜尋啟動器",
      "meta.description":
        "完全本機執行、最小權限且輕量的 macOS 14.0+ 視窗級切換器與搜尋啟動器 Wintch 功能介紹與安裝指南。",
      "nav.switcher": "視窗切換器",
      "nav.capture": "顯示樣式",
      "nav.launcher": "搜尋啟動器",
      "nav.close": "關閉視窗",
      "nav.privacy": "原生設計",
      "nav.install": "安裝",
      "hero.metaRest": "macOS 14.0+ · MIT License",
      "hero.titleLine1": "讓視窗切換，",
      "hero.titleAccent": "更加直覺。",
      "hero.subtitle":
        "Wintch（Window + Switch）是一款簡潔輕量的 macOS 視窗級切換器與搜尋啟動器，支援跨桌面空間瞬間切換至同一應用程式的任意視窗。",
      "hero.downloadWithVersion": "下載 ({version})",
      "hero.downloadFallback": "下載最新版本",
      "showcase.tabSwitcher": "視窗切換器",
      "showcase.tabLauncher": "搜尋啟動器",
      "showcase.tabSettings": "設定與權限",
      "showcase.styleList": "清單",
      "showcase.styleIcon": "圖示",
      "showcase.styleCapture": "擷取檢視",
      "showcase.groupByApp": "依應用程式分組",
      "showcase.prev": "上一個",
      "showcase.next": "下一個",
      "showcase.close": "關閉",
      "showcase.reset": "重設",
      "showcase.emptySwitcher": "示範視窗已全部關閉，點擊「重設」即可還原。",
      "showcase.searchPlaceholder": "搜尋視窗或應用程式…",
      "showcase.sampleLabel": "試試:",
      "showcase.launchSection": "啟動應用程式",
      "showcase.launchEmptyWindowsSection": "沒有符合的視窗 — 啟動應用程式",
      "showcase.launchBadge": "啟動",
      "showcase.noMatches": "找不到符合的視窗或應用程式",
      "showcase.settingsGeneral": "一般",
      "showcase.settingsSwitcher": "切換器",
      "showcase.settingsLauncher": "啟動器",
      "showcase.settingsSystem": "系統",
      "showcase.sLaunchAtLogin": "登入時自動啟動",
      "showcase.sAutoUpdate": "自動檢查更新",
      "showcase.sAutoUpdateSub": "啟動時透過 GitHub Releases 檢查穩定版（可選）",
      "showcase.sLanguage": "語言",
      "showcase.sLanguageValue": "跟隨系統（支援 5 種語言）",
      "showcase.sOn": "開",
      "showcase.sOff": "關",
      "showcase.sShortcut": "快捷鍵",
      "showcase.sDisplayStyle": "顯示樣式",
      "showcase.sGroupByApp": "依應用程式分組",
      "showcase.sStyleList": "清單 / 圖示 / 擷取檢視",
      "showcase.sStyleLauncher": "清單 / 擷取檢視",
      "showcase.sAccessibility": "輔助使用權限",
      "showcase.sGranted": "已授權",
      "showcase.sScreenRecording": "螢幕錄製權限",
      "showcase.sOptInOnly": "可選（僅擷取檢視使用）",
      "showcase.sAppInfo": "版本",
      "showcase.sCheckUpdates": "檢查更新",
      "switcher.eyebrow": "視窗切換器 (⌥ + Tab)",
      "switcher.titleLine1": "以視窗為單位，",
      "switcher.titleAccent": "切換不再混亂。",
      "switcher.desc":
        "macOS 內建的 Command + Tab 僅以應用程式為單位切換，而 Wintch 可跨空間列出每個開啟的視窗，依最近使用順序 (MRU) 排列並支援依應用程式分組。",
      "switcher.bullet1": "輕按並放開 Option + Tab，即可立刻回到剛才使用的視窗",
      "switcher.bullet2": "預設啟用依應用程式分組，亦可隨時於設定或選單列切換為扁平 MRU 清單",
      "switcher.bullet3": "提供清單、圖示與擷取檢視三種樣式，並支援附衝突檢查的自訂快捷鍵",
      "switcher.compareStandard": "系統預設的 Command + Tab（依應用程式）",
      "switcher.compareWintch": "Wintch（依視窗 MRU）",
      "capture.eyebrow": "顯示樣式與擷取檢視",
      "capture.titleLine1": "自由切換檢視樣式，",
      "capture.titleAccent": "憑畫面一眼辨識。",
      "capture.desc":
        "視窗切換器支援清單、圖示與可選擷取檢視，搜尋啟動器亦可獨立選擇清單或縮圖擷取檢視，讓同一應用程式的多個視窗一目了然。",
      "capture.bullet1": "零延遲開啟：立即顯示快取縮圖或預留圖示，並於背景非同步更新最新畫面",
      "capture.bullet2": "可由選單列獨立調整切換器與搜尋啟動器的顯示樣式及分組狀態",
      "capture.bullet3": "螢幕錄製權限嚴格採自願啟用制：清單與圖示模式完全無需該權限",
      "capture.styleList": "清單",
      "capture.styleIcon": "圖示",
      "capture.styleCapture": "擷取檢視（可選）",
      "capture.privacyNote": "擷取影像僅暫存於記憶體快取中，絕不寫入磁碟或傳送至外部。",
      "launcher.eyebrow": "搜尋啟動器 (⌥ + Space)",
      "launcher.titleLine1": "搜尋視窗與啟動 App，",
      "launcher.titleAccent": "一個面板完成。",
      "launcher.desc":
        "視窗繁多時可隨時呼出搜尋啟動器，以空白分隔 AND 模糊搜尋快速篩選應用程式名稱與視窗標題，並從下方「啟動應用程式」區塊直接開啟尚未執行的 App。",
      "launcher.bullet1": "即時醒目標示符合字元，並完整相容中文、日文、韓文輸入法組字操作",
      "launcher.bullet2": "即使目前開啟的視窗數為 0 仍可啟動，支援中英文別名搜尋",
      "launcher.bullet3": "可使用 ↑ / ↓、Ctrl + N / P 與 ⌥ + Tab 連續瀏覽視窗與啟動候選",
      "launcher.launchSection": "啟動應用程式",
      "launcher.notesLabel": "備忘錄",
      "launcher.launchBadge": "啟動",
      "close.eyebrow": "關閉視窗 (⌥ + Q)",
      "close.titleLine1": "就在清單中，",
      "close.titleAccent": "隨手關閉不需要的視窗。",
      "close.desc":
        "無需先切換過去再關閉。於切換器或搜尋啟動器選取目標後按下修飾鍵 + Q（預設 ⌥ + Q）即可立即關閉，若為最後一個視窗則正常結束該應用程式。",
      "close.bullet1": "切換器與搜尋啟動器皆可用 ⌥ + Q 操作，關閉處理期間顯示旋轉進度指示",
      "close.bullet2": "多個視窗時僅關閉選取的單一視窗，最後一個視窗時自動溫和結束應用程式",
      "close.bullet3": "絕不強制終止，完整尊重應用程式標準的未儲存變更確認對話框",
      "close.cardTitle": "就地關閉目前選取的視窗",
      "close.safeNote": "若有未儲存的變更，將始終尊重應用程式標準的儲存確認提示。",
      "privacy.eyebrow": "原生與隱私優先",
      "privacy.titleLine1": "純原生實作，",
      "privacy.titleAccent": "輕快又純粹。",
      "privacy.desc":
        "完全採用 Swift 6.0 與 SwiftUI 等 Apple 標準框架開發，零外部套件相依、零私有 API，在密碼輸入欄等安全輸入保護下依然穩定運作。",
      "privacy.bullet1": "支援 Apple Silicon 與 Intel 的 Universal Binary，常駐選單列不佔 Dock 空間",
      "privacy.bullet2": "無遙測與追蹤；螢幕錄製權限與自動更新檢查均採明確自願啟用",
      "privacy.bullet3": "支援 5 種語言免重啟即時切換，並提供簽章驗證的應用程式內安全更新",
      "privacy.card1Desc": "零外部相依的 Apple Silicon / Intel 原生通用二進位檔",
      "privacy.card2Title": "最小權限與自願啟用",
      "privacy.card2Desc": "預設僅需輔助使用權限；螢幕錄製與自動更新檢查皆為可選",
      "privacy.card3Title": "選單列常駐與 5 種語言",
      "privacy.card3Desc": "不佔用 Dock 圖示，支援繁中 / 簡中 / 英 / 日 / 韓即時切換",
      "privacy.card4Title": "安全輸入相容與簽章驗證更新",
      "privacy.card4Desc": "密碼輸入環境下仍可操作，更新前自動驗證程式碼簽章與 SHA-256",
      "shortcuts.eyebrow": "鍵盤操作",
      "shortcuts.title": "預設快捷鍵一覽",
      "shortcuts.subtitle": "以下為預設按鍵配置，隨時可在設定畫面（⌘ + ,）自由自訂啟動快捷鍵。",
      "shortcuts.scopeSwitcher": "切換器",
      "shortcuts.scopeLauncher": "啟動器",
      "shortcuts.scopeCommon": "共用",
      "shortcuts.descTab": "按住開啟切換器並切換至下一個視窗（放開修飾鍵即可確認）",
      "shortcuts.descShiftTab": "反向選取上一個視窗",
      "shortcuts.descSpace": "開啟或關閉搜尋啟動器",
      "shortcuts.descArrows": "於清單或圖示／擷取格狀中移動（搜尋啟動器中也可使用 ⌥ + Tab）",
      "shortcuts.descClose": "關閉選取的視窗（若為最後 1 個視窗則正常結束應用程式）",
      "shortcuts.descEnterEsc": "按 Enter 確認切換或啟動；按 Esc 取消且不切換",
      "install.eyebrow": "安裝",
      "install.title": "安裝與初始設定",
      "install.subtitle":
        "可透過 Homebrew Cask 或 GitHub Releases 的 DMG / ZIP 檔快速安裝，均已通過 Developer ID 簽章與 Apple 公證。",
      "install.recommendedBadge": "推薦",
      "install.brewTitle": "透過 Homebrew 安裝",
      "install.brewDesc": "在終端機執行以下指令，即可一次完成新增 Tap 與安裝 Wintch。",
      "install.brewUpgradeLabel": "更新至最新版本",
      "install.brewUninstallLabel": "解除安裝（加上 --zap 可一併刪除設定）",
      "install.manualTitle": "從 GitHub Releases 手動安裝",
      "install.manualDesc": "若不使用 Homebrew，可直接從發布頁面下載 DMG 或 ZIP 檔案安裝。",
      "install.step1": "從 GitHub Releases 頁面下載最新的 Wintch-vX.Y.Z.dmg（或 .zip）。",
      "install.step2":
        "開啟 DMG 並將 Wintch.app 拖放至 Applications 資料夾後啟動（或解壓縮 ZIP 後移至 /Applications）。",
      "install.step3":
        "依照首次啟動提示，於「系統設定 ＞ 隱私權與安全性 ＞ 輔助使用」中允許 Wintch。",
      "install.notarizedNote":
        "發行版（.app 與 .dmg）均已完成 Developer ID 簽章與 Apple 公證，啟動時不會出現 Gatekeeper 警告。",
      "install.openReleases": "開啟 GitHub Releases",
      "specs.osLabel": "支援系統 / 架構",
      "specs.osValue": "macOS 14.0 (Sonoma)+ · Apple Silicon / Intel",
      "specs.permLabel": "所需權限",
      "specs.permValue": "輔助使用（螢幕錄製僅於擷取檢視時可選）",
      "specs.licenseLabel": "授權條款 / 技術",
      "specs.licenseValue": "MIT License · Swift 6.0 / SwiftUI · 5 種語言",
      "bottomCta.title": "讓視窗切換的煩躁感歸零。",
      "bottomCta.desc": "免費且以 MIT License 開源釋出。",
      "common.copied": "已複製到剪貼簿",
      "common.copyCommand": "複製指令",
      "common.themeSystem": "主題：跟隨系統",
      "common.themeLight": "主題：淺色",
      "common.themeDark": "主題：深色",
    },

    ko: {
      "meta.title": "Wintch — macOS를 위한 심플하고 가벼운 창 단위 전환기 & 검색 런처",
      "meta.description":
        "완전 로컬 동작, 최소 권한, 가벼운 macOS 14.0+용 창 단위 전환기 및 검색 런처 Wintch 소개와 설치 방법.",
      "nav.switcher": "창 전환기",
      "nav.capture": "표시 스타일",
      "nav.launcher": "검색 런처",
      "nav.close": "창 닫기",
      "nav.privacy": "네이티브 설계",
      "nav.install": "설치",
      "hero.metaRest": "macOS 14.0+ · MIT License",
      "hero.titleLine1": "창 전환을,",
      "hero.titleAccent": "더 직관적으로.",
      "hero.subtitle":
        "Wintch(Window + Switch)는 macOS 기본 Command + Tab으로는 닿기 어려운 '같은 앱의 여러 창' 사이를 가상 데스크톱(Spaces)을 넘나들며 즉시 전환할 수 있는 심플하고 가벼운 창 단위 전환기 & 검색 런처입니다.",
      "hero.downloadWithVersion": "다운로드 ({version})",
      "hero.downloadFallback": "최신 버전 다운로드",
      "showcase.tabSwitcher": "일반 전환기",
      "showcase.tabLauncher": "검색 런처",
      "showcase.tabSettings": "설정 및 권한",
      "showcase.styleList": "목록형",
      "showcase.styleIcon": "아이콘형",
      "showcase.styleCapture": "캡처 보기",
      "showcase.groupByApp": "앱별로 그룹화",
      "showcase.prev": "이전",
      "showcase.next": "다음",
      "showcase.close": "닫기",
      "showcase.reset": "초기화",
      "showcase.emptySwitcher": "데모 창을 모두 닫았습니다. '초기화'로 복원할 수 있습니다.",
      "showcase.searchPlaceholder": "창 또는 앱 검색…",
      "showcase.sampleLabel": "예시:",
      "showcase.launchSection": "앱 실행",
      "showcase.launchEmptyWindowsSection": "일치하는 창이 없어 앱을 실행합니다",
      "showcase.launchBadge": "실행",
      "showcase.noMatches": "일치하는 창이나 앱이 없습니다",
      "showcase.settingsGeneral": "일반",
      "showcase.settingsSwitcher": "전환기",
      "showcase.settingsLauncher": "런처",
      "showcase.settingsSystem": "시스템",
      "showcase.sLaunchAtLogin": "로그인 시 자동 실행",
      "showcase.sAutoUpdate": "업데이트 자동 확인",
      "showcase.sAutoUpdateSub": "실행 시 GitHub Releases에서 최신 안정 버전 확인(선택)",
      "showcase.sLanguage": "언어",
      "showcase.sLanguageValue": "시스템 설정 따르기(5개 언어)",
      "showcase.sOn": "켬",
      "showcase.sOff": "끔",
      "showcase.sShortcut": "단축키",
      "showcase.sDisplayStyle": "표시 스타일",
      "showcase.sGroupByApp": "앱별로 그룹화",
      "showcase.sStyleList": "목록형 / 아이콘형 / 캡처 보기",
      "showcase.sStyleLauncher": "목록형 / 캡처 보기",
      "showcase.sAccessibility": "손쉬운 사용 권한",
      "showcase.sGranted": "허용됨",
      "showcase.sScreenRecording": "화면 기록 권한",
      "showcase.sOptInOnly": "선택(캡처 보기 사용 시만)",
      "showcase.sAppInfo": "버전",
      "showcase.sCheckUpdates": "업데이트 확인",
      "switcher.eyebrow": "창 전환기 (⌥ + Tab)",
      "switcher.titleLine1": "창 단위 전환을",
      "switcher.titleAccent": "헷갈림 없이.",
      "switcher.desc":
        "macOS 기본 Command + Tab은 앱 단위로 전환하지만, Wintch는 모든 Space에 열려 있는 창을 최근 사용 순(MRU)으로 개별 표시하며 앱별 그룹화도 지원합니다.",
      "switcher.bullet1": "Option + Tab을 눌렀다 떼기만 하면 직전에 쓰던 창으로 바로 돌아갑니다",
      "switcher.bullet2": "앱별 그룹화(기본 켜짐)와 평면 MRU 목록을 설정이나 메뉴 막대에서 언제든 전환",
      "switcher.bullet3": "목록형, 아이콘형, 캡처 보기 3가지 스타일과 충돌 방지 단축키 사용자 지정 지원",
      "switcher.compareStandard": "기본 Command + Tab (앱 단위)",
      "switcher.compareWintch": "Wintch (창 단위 MRU)",
      "capture.eyebrow": "표시 스타일 & 캡처 보기",
      "capture.titleLine1": "원하는 스타일로,",
      "capture.titleAccent": "화면 미리보기로 한눈에.",
      "capture.desc":
        "일반 전환기는 목록형·아이콘형·캡처 보기 3가지를, 검색 런처도 목록형·캡처 보기를 독립적으로 선택할 수 있습니다. 캡처 보기에서는 실제 창 썸네일로 같은 앱의 여러 창도 바로 구분할 수 있습니다.",
      "capture.bullet1": "지연 없는 표시: 캐시된 썸네일이나 플레이스홀더를 먼저 띄우고 백그라운드에서 최신 캡처로 갱신",
      "capture.bullet2": "메뉴 막대에서 일반 전환기와 검색 런처의 스타일·그룹화를 각각 즉시 변경",
      "capture.bullet3": "화면 기록 권한은 캡처 보기를 선택한 경우에만 선택적으로 사용(목록형·아이콘형에서는 불필요)",
      "capture.styleList": "목록형",
      "capture.styleIcon": "아이콘형",
      "capture.styleCapture": "캡처 보기 (선택)",
      "capture.privacyNote": "캡처 이미지는 메모리 임시 캐시에만 보관되며 디스크 저장이나 외부 전송을 하지 않습니다.",
      "launcher.eyebrow": "검색 런처 (⌥ + Space)",
      "launcher.titleLine1": "창 검색도 앱 실행도,",
      "launcher.titleAccent": "하나의 패널에서.",
      "launcher.desc":
        "창이 많아지면 검색 런처를 토글로 열어 앱 이름과 창 제목을 공백 구분 AND 퍼지 검색으로 좁혀 보세요. 아직 열리지 않은 앱도 하단의 '앱 실행' 영역에서 바로 띄울 수 있습니다.",
      "launcher.bullet1": "일치하는 글자를 실시간 강조 표시하며 한국어·일본어·중국어 IME 입력 조합을 방해하지 않음",
      "launcher.bullet2": "열린 창이 0개여도 런처를 실행할 수 있으며 현지화 이름과 영문 별칭 모두 검색 가능",
      "launcher.bullet3": "↑/↓, Ctrl + N/P는 물론 런처에서도 ⌥ + Tab으로 창과 앱 후보를 연속 탐색",
      "launcher.launchSection": "앱 실행",
      "launcher.notesLabel": "메모",
      "launcher.launchBadge": "실행",
      "close.eyebrow": "창 닫기 / 앱 종료 (⌥ + Q)",
      "close.titleLine1": "목록에서 바로,",
      "close.titleAccent": "필요 없는 창 정리.",
      "close.desc":
        "창을 닫으려고 굳이 해당 창으로 전환할 필요가 없습니다. 전환기나 런처 목록에서 선택하고 보조 키 + Q(기본 ⌥ + Q)를 누르면 즉시 닫히며, 앱의 마지막 창이면 앱을 안전하게 종료합니다.",
      "close.bullet1": "전환기와 검색 런처 모두 동일한 ⌥ + Q로 동작하며 닫는 동안 스피너 표시",
      "close.bullet2": "여러 창이 있으면 선택한 1개만 닫고, 마지막 1개 창일 때는 앱을 정상 종료",
      "close.bullet3": "강제 종료하지 않고 저장되지 않은 변경 사항 확인 대화 상자를 항상 존중",
      "close.cardTitle": "선택한 창을 그 자리에서 닫기",
      "close.safeNote": "저장되지 않은 변경 사항이 있을 경우 앱의 기본 저장 확인 창을 존중합니다.",
      "privacy.eyebrow": "네이티브 & 프라이버시 우선",
      "privacy.titleLine1": "네이티브 구현으로,",
      "privacy.titleAccent": "가볍고 단순하게.",
      "privacy.desc":
        "외부 라이브러리와 비공개 API 없이 Swift 6.0과 SwiftUI 등 Apple 표준 프레임워크만으로 제작되었습니다. 비밀번호 입력창 같은 보안 입력 환경에서도 안정적으로 작동합니다.",
      "privacy.bullet1": "Apple Silicon / Intel 범용 바이너리, Dock을 차지하지 않는 메뉴 막대 상주 방식",
      "privacy.bullet2": "분석·추적 통신 제로. 화면 기록 권한과 자동 업데이트 확인 모두 명시적 옵트인",
      "privacy.bullet3": "재시작 없는 5개 언어 즉시 전환과 코드 서명 검증 기반 인앱 업데이트 지원",
      "privacy.card1Desc": "외부 의존성 제로, Apple Silicon / Intel 네이티브 유니버설 바이너리",
      "privacy.card2Title": "최소 권한 & 옵트인 원칙",
      "privacy.card2Desc": "기본은 손쉬운 사용 권한만 필요, 화면 기록 및 자동 업데이트는 선택 사항",
      "privacy.card3Title": "메뉴 막대 상주 & 5개 언어",
      "privacy.card3Desc": "Dock을 비워 두고 한국어 / EN / 日本語 / 简体中文 / 繁體中文 즉시 전환",
      "privacy.card4Title": "보안 입력 지원 & 서명 검증 업데이트",
      "privacy.card4Desc": "비밀번호 입력 중에도 응답하며 업데이트 전 서명과 SHA-256을 검증",
      "shortcuts.eyebrow": "키보드 단축키",
      "shortcuts.title": "기본 단축키 목록",
      "shortcuts.subtitle": "기본 키 바인딩입니다. 실행 단축키는 설정(⌘ + ,)에서 언제든 자유롭게 변경할 수 있습니다.",
      "shortcuts.scopeSwitcher": "전환기",
      "shortcuts.scopeLauncher": "런처",
      "shortcuts.scopeCommon": "공통",
      "shortcuts.descTab": "누른 상태로 전환기를 열고 다음 창으로 이동 (보조 키를 떼면 확정)",
      "shortcuts.descShiftTab": "선택을 이전 창으로 역순 이동",
      "shortcuts.descSpace": "검색 런처 열기 / 닫기 전환",
      "shortcuts.descArrows": "목록 또는 아이콘/캡처 그리드 이동 (런처에서도 ⌥ + Tab 지원)",
      "shortcuts.descClose": "선택한 창 닫기 (앱의 마지막 창이면 앱을 정상 종료)",
      "shortcuts.descEnterEsc": "Enter로 전환 또는 실행 확정, Esc로 전환하지 않고 취소",
      "install.eyebrow": "설치",
      "install.title": "설치 및 초기 설정",
      "install.subtitle":
        "Homebrew Cask 또는 GitHub Releases의 DMG / ZIP 파일로 간편하게 설치할 수 있습니다. Developer ID 서명 및 Apple 공증이 완료되어 있습니다.",
      "install.recommendedBadge": "추천",
      "install.brewTitle": "Homebrew로 설치",
      "install.brewDesc": "터미널에서 아래 명령어를 실행하면 Tap 추가와 설치가 한 번에 완료됩니다.",
      "install.brewUpgradeLabel": "최신 버전으로 업데이트",
      "install.brewUninstallLabel": "제거 (설정까지 삭제하려면 --zap 추가)",
      "install.manualTitle": "GitHub Releases에서 수동 설치",
      "install.manualDesc": "Homebrew를 사용하지 않는다면 릴리스 페이지에서 DMG 또는 ZIP을 직접 내려받으세요.",
      "install.step1": "GitHub Releases 페이지에서 최신 Wintch-vX.Y.Z.dmg(또는 .zip)을 다운로드합니다.",
      "install.step2":
        "DMG를 열어 Wintch.app을 Applications 폴더로 드래그한 뒤 실행합니다(ZIP은 압축 해제 후 /Applications로 이동).",
      "install.step3":
        "첫 실행 안내에 따라 '시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용'에서 Wintch를 허용합니다.",
      "install.notarizedNote":
        "배포용 .app 및 .dmg는 Developer ID 서명과 Apple 공증을 마쳐 Gatekeeper 경고 없이 실행됩니다.",
      "install.openReleases": "GitHub Releases 열기",
      "specs.osLabel": "지원 OS / 아키텍처",
      "specs.osValue": "macOS 14.0 (Sonoma)+ · Apple Silicon / Intel",
      "specs.permLabel": "필요 권한",
      "specs.permValue": "손쉬운 사용 (화면 기록은 캡처 보기 시에만 선택)",
      "specs.licenseLabel": "라이선스 / 기술",
      "specs.licenseValue": "MIT License · Swift 6.0 / SwiftUI · 5개 언어",
      "bottomCta.title": "창 전환의 스트레스를 제로로.",
      "bottomCta.desc": "무료 오픈소스(MIT License)로 공개되어 있습니다.",
      "common.copied": "클립보드에 복사되었습니다",
      "common.copyCommand": "명령어 복사",
      "common.themeSystem": "테마: 시스템",
      "common.themeLight": "테마: 라이트",
      "common.themeDark": "테마: 다크",
    },
  };

  /**
   * 任意の言語タグを対応する 5 言語コードへ正規化する
   * @param {string | null | undefined} rawTag 判定対象の言語タグ
   * @returns {string | null} 対応する言語コード（非対応時は null）
   */
  function normalizeLocale(rawTag) {
    if (!rawTag || typeof rawTag !== "string") return null;
    const normalized = rawTag.trim().toLowerCase().replace(/_/g, "-");
    if (!normalized) return null;

    if (normalized === "en" || normalized.startsWith("en-")) return "en";
    if (normalized === "ja" || normalized.startsWith("ja-")) return "ja";
    if (normalized === "ko" || normalized.startsWith("ko-")) return "ko";
    if (normalized === "zh" || normalized.startsWith("zh-")) {
      if (
        normalized.includes("hant") ||
        normalized.includes("-tw") ||
        normalized.includes("-hk") ||
        normalized.includes("-mo")
      ) {
        return "zh-Hant";
      }
      return "zh-Hans";
    }
    return null;
  }

  /**
   * URL パラメータ → 保存済み設定 → ブラウザ言語 → 英語フォールバックの順で初期言語を決定する
   * @returns {string} 選択された言語コード
   */
  function resolveInitialLocale() {
    try {
      const params = new URLSearchParams(global.location ? global.location.search : "");
      const fromQuery = normalizeLocale(params.get("lang"));
      if (fromQuery) return fromQuery;
    } catch (_err) {
      // クエリ解析不可時は次へ進む
    }

    try {
      const saved = global.localStorage ? global.localStorage.getItem("wintch-docs-locale") : null;
      const fromStorage = normalizeLocale(saved);
      if (fromStorage) return fromStorage;
    } catch (_err) {
      // localStorage 無効環境では次へ進む
    }

    const candidates = [];
    if (global.navigator) {
      if (Array.isArray(global.navigator.languages)) {
        candidates.push.apply(candidates, global.navigator.languages);
      }
      if (global.navigator.language) {
        candidates.push(global.navigator.language);
      }
    }
    for (let i = 0; i < candidates.length; i += 1) {
      const matched = normalizeLocale(candidates[i]);
      if (matched) return matched;
    }

    return "en";
  }

  global.WintchI18n = {
    LOCALE_LABELS: LOCALE_LABELS,
    MESSAGES: MESSAGES,
    normalizeLocale: normalizeLocale,
    resolveInitialLocale: resolveInitialLocale,
  };
})(typeof window !== "undefined" ? window : globalThis);
