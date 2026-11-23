import Foundation

/// 静的ローカライズ文言（引数なし）を一意に識別するキー列挙（全言語の翻訳網羅テストにも使用）
public enum AppStringKey: String, CaseIterable, Equatable, Sendable {
    /// 言語設定の「システム設定に従う」選択肢
    case languageFollowSystem
    /// 設定「一般」タブの言語ラベル
    case settingsLanguageLabel

    /// メニューバー: アクセシビリティ権限不足案内
    case menuBarAccessibilityRequired
    /// メニューバー: 表示形式サブメニュー
    case menuBarDisplayStyle
    /// メニューバー: 通常スイッチャーセクション
    case menuBarNormalSwitcher
    /// メニューバー: 検索ランチャーセクション
    case menuBarSearchLauncher
    /// メニューバー・設定共通: アプリごとにグルーピング
    case groupByAppToggle
    /// メニューバー: 設定を開く
    case menuBarOpenSettings

    /// 表示形式: リスト型
    case displayStyleList
    /// 表示形式: アイコン型
    case displayStyleIcon
    /// 表示形式: キャプチャ表示型
    case displayStyleCapture

    /// 設定サイドバー: 一般
    case settingsTabGeneral
    /// 設定サイドバー: スイッチャー
    case settingsTabSwitcher
    /// 設定サイドバー: ランチャー
    case settingsTabLauncher
    /// 設定サイドバー: システム
    case settingsTabSystem

    /// 設定一般: ログイン時に自動起動
    case settingsLaunchAtLogin
    /// 設定スイッチャー: セクション見出し
    case settingsNormalSwitcherSectionTitle
    /// 設定ランチャー: セクション見出し
    case settingsLauncherSectionTitle
    /// 設定共通: 起動ショートカット
    case settingsShortcutLabel
    /// 設定スイッチャー: 操作方法
    case settingsControlsLabel
    /// 設定スイッチャー: Command + Tab 上書き警告
    case settingsCommandTabWarning
    /// 設定スイッチャー: 修飾キー入力ヒント
    case settingsNormalShortcutHint
    /// 設定ランチャー: 修飾キー入力ヒント
    case settingsLauncherShortcutHint
    /// 設定共通: 表示形式ラベル
    case settingsDisplayStyleLabel
    /// 設定スイッチャー: キャプチャ表示説明
    case settingsNormalCaptureDescription
    /// 設定ランチャー: キャプチャ表示説明
    case settingsLauncherCaptureDescription
    /// 設定システム: システム権限セクション
    case settingsSystemPermissionsSectionTitle
    /// 設定システム: アクセシビリティ権限ラベル
    case settingsAccessibilityPermissionLabel
    /// 設定システム: 画面収録権限ラベル
    case settingsScreenRecordingPermissionLabel
    /// 設定システム: 許可済み
    case settingsPermissionGranted
    /// 設定システム: 未許可
    case settingsPermissionDenied
    /// 設定システム: 設定を開くボタン
    case settingsOpenSettingsButton
    /// 設定システム: アプリ情報セクション
    case settingsAppInfoSectionTitle
    /// 設定システム: アプリ名ラベル
    case settingsAppNameLabel
    /// 設定システム: バージョンラベル
    case settingsVersionLabel
    /// 設定キャプチャ未許可ガイド: 説明文
    case settingsScreenRecordingRequiredMessage
    /// 設定キャプチャ未許可ガイド: 権限をリクエストボタン
    case settingsRequestPermissionButton
    /// 共通ボタン: システム設定を開く
    case openSystemSettingsButton
    /// 共通ボタン: 再確認
    case recheckButton
    /// 設定キャプチャ未許可ガイド: 再起動補足
    case settingsScreenRecordingRestartNote
    /// ショートカットレコーダー: キー入力待機文言
    case shortcutRecorderPrompt

    /// ショートカット検証エラー: 必須修飾キー不足
    case shortcutValidationMissingPrimaryModifier
    /// ショートカット検証エラー: 通常スイッチャーでの Shift 禁止
    case shortcutValidationShiftReserved

    /// 権限誘導画面: 見出し
    case permissionGuideTitle
    /// 権限誘導画面: 説明文
    case permissionGuideSubtitle
    /// 権限誘導画面: 手順 1
    case permissionGuideStep1
    /// 権限誘導画面: 手順 3
    case permissionGuideStep3
    /// 権限誘導画面: 画面収録権限の注記
    case permissionGuideScreenRecordingNote

    /// 検索ランチャー: 検索欄プレースホルダー
    case launcherSearchPlaceholder
    /// 検索ランチャー空状態: ウィンドウ 0 件＋未入力
    case launcherEmptyNoOpenWindows
    /// 検索ランチャー空状態: ウィンドウ 0 件＋検索不一致
    case launcherEmptyNoMatchingApps
    /// 検索ランチャー空状態: ウィンドウ 1 件以上＋検索不一致
    case launcherEmptyNoMatchingCandidates
    /// 検索ランチャー: アプリ起動セクション見出し（ウィンドウ候補あり）
    case launcherLaunchAppSectionTitle
    /// 検索ランチャー: アプリ起動セクション見出し（ウィンドウ候補なし時のフォールバック）
    case launcherLaunchAppFallbackSectionTitle
    /// 検索ランチャー: 起動バッジ
    case launcherLaunchBadge
    /// キャプチャ表示型: 画面収録権限未許可バナー
    case screenRecordingDeniedBanner
    /// ウィンドウ表示補助: 空タイトル
    case untitledWindow
    /// ウィンドウ表示補助: 不明アプリ
    case unknownApplication

    /// トリガーキー互換表示: バッククォート
    case triggerKeyGraveDisplayName
    /// トリガーキー互換表示: バックスラッシュ
    case triggerKeyBackslashDisplayName

    /// 設定一般: バージョンアップを自動チェックトグル
    case settingsAutoCheckForUpdates
    /// 設定一般: バージョンアップを自動チェック補足キャプション
    case settingsAutoCheckForUpdatesCaption
    /// 設定システム: アップデートを確認ボタン
    case settingsCheckForUpdatesButton
    /// 設定システム: アップデート確認中インジケータ文言
    case settingsCheckingForUpdates
    /// 設定システム: 最新バージョン利用中メッセージ
    case settingsUpToDateMessage
    /// 共通ボタン: GitHub Releases を開く
    case settingsOpenGitHubReleasesButton
    /// 更新ダイアログ: 見出し
    case updateDialogTitle
    /// 更新ダイアログ: 変更内容セクション見出し
    case updateReleaseNotesSectionTitle
    /// 更新ダイアログ: リリースノート未記載時の案内
    case updateReleaseNotesEmpty
    /// 更新ダイアログ: GitHub で変更内容を見るリンク
    case updateViewOnGitHubButton
    /// 更新ダイアログ: 今すぐアップデートボタン
    case updateNowButton
    /// 更新ダイアログ: 後でボタン
    case updateLaterButton
    /// 更新ダイアログ: このバージョンをスキップボタン
    case updateSkipVersionButton
    /// 更新ダイアログ: ダウンロード中ステータス
    case updateStatusDownloading
    /// 更新ダイアログ: 展開中ステータス
    case updateStatusExtracting
    /// 更新ダイアログ: 検証中ステータス
    case updateStatusVerifying
    /// 更新ダイアログ: 適用・再起動中ステータス
    case updateStatusInstalling
}

/// 5 言語の翻訳セットを 1 項目としてまとめる内部値型（コンパイル時に翻訳漏れを検出する）
private struct LocalizedEntry: Sendable {
    /// 日本語翻訳
    let ja: String
    /// 英語翻訳
    let en: String
    /// 中国語（簡体字）翻訳
    let zhHans: String
    /// 中国語（繁体字）翻訳
    let zhHant: String
    /// 韓国語翻訳
    let ko: String

    /// 指定言語に対応する翻訳文字列を取り出す
    /// - Parameter language: 解決済みの表示言語
    /// - Returns: 指定言語の翻訳文字列
    func value(for language: ResolvedAppLanguage) -> String {
        switch language {
        case .japanese: ja
        case .english: en
        case .simplifiedChinese: zhHans
        case .traditionalChinese: zhHant
        case .korean: ko
        }
    }
}

/// 解決済み言語（5 言語）に応じた型安全なユーザー向け UI ローカライズ文言を提供するテーブル
public struct AppStrings: Equatable, Sendable {
    /// 日本語ローカライズテーブルの共有インスタンス
    public static let japanese = AppStrings(language: .japanese)

    /// 英語ローカライズテーブルの共有インスタンス
    public static let english = AppStrings(language: .english)

    /// このテーブルが参照する解決済み言語
    public let language: ResolvedAppLanguage

    /// 指定言語用のローカライズ文言テーブルを初期化する
    /// - Parameter language: 解決済みの表示言語
    public init(language: ResolvedAppLanguage) {
        self.language = language
    }

    /// 静的キーに対応する現在言語のローカライズ文字列を返す
    /// - Parameter key: 取得対象の文言キー
    /// - Returns: 指定言語に翻訳された UI 文字列
    public func text(for key: AppStringKey) -> String {
        Self.entry(for: key).value(for: language)
    }

    /// 静的キーに対応する 5 言語分の翻訳エントリを返す
    /// - Parameter key: 取得対象の文言キー
    /// - Returns: 5 言語分の翻訳を保持する LocalizedEntry
    private static func entry(for key: AppStringKey) -> LocalizedEntry {
        switch key {
        // MARK: - 言語設定
        case .languageFollowSystem:
            LocalizedEntry(
                ja: "システム設定に従う",
                en: "Follow System",
                zhHans: "跟随系统",
                zhHant: "跟隨系統",
                ko: "시스템 설정 따르기"
            )
        case .settingsLanguageLabel:
            LocalizedEntry(
                ja: "言語",
                en: "Language",
                zhHans: "语言",
                zhHant: "語言",
                ko: "언어"
            )

        // MARK: - メニューバー
        case .menuBarAccessibilityRequired:
            LocalizedEntry(
                ja: "アクセシビリティ権限が必要です...",
                en: "Accessibility Permission Required...",
                zhHans: "需要辅助功能权限...",
                zhHant: "需要輔助使用權限...",
                ko: "손쉬운 사용 권한 필요..."
            )
        case .menuBarDisplayStyle:
            LocalizedEntry(
                ja: "表示形式",
                en: "Display Style",
                zhHans: "显示方式",
                zhHant: "顯示方式",
                ko: "표시 형식"
            )
        case .menuBarNormalSwitcher:
            LocalizedEntry(
                ja: "通常スイッチャー",
                en: "Window Switcher",
                zhHans: "窗口切换器",
                zhHant: "視窗切換器",
                ko: "윈도우 전환기"
            )
        case .menuBarSearchLauncher:
            LocalizedEntry(
                ja: "検索ランチャー",
                en: "Search Launcher",
                zhHans: "搜索启动器",
                zhHant: "搜尋啟動器",
                ko: "검색 런처"
            )
        case .groupByAppToggle:
            LocalizedEntry(
                ja: "アプリごとにグルーピング",
                en: "Group by App",
                zhHans: "按应用分组",
                zhHant: "依應用程式分組",
                ko: "앱별로 그룹화"
            )
        case .menuBarOpenSettings:
            LocalizedEntry(
                ja: "設定を開く...",
                en: "Settings...",
                zhHans: "打开设置...",
                zhHant: "開啟設定...",
                ko: "설정 열기..."
            )

        // MARK: - 表示形式名
        case .displayStyleList:
            LocalizedEntry(
                ja: "リスト型",
                en: "List",
                zhHans: "列表",
                zhHant: "列表",
                ko: "목록"
            )
        case .displayStyleIcon:
            LocalizedEntry(
                ja: "アイコン型",
                en: "Icons",
                zhHans: "图标",
                zhHant: "圖示",
                ko: "아이콘"
            )
        case .displayStyleCapture:
            LocalizedEntry(
                ja: "キャプチャ表示型",
                en: "Thumbnails",
                zhHans: "缩略图",
                zhHant: "縮圖",
                ko: "미리보기"
            )

        // MARK: - 設定サイドバー
        case .settingsTabGeneral:
            LocalizedEntry(
                ja: "一般",
                en: "General",
                zhHans: "通用",
                zhHant: "一般",
                ko: "일반"
            )
        case .settingsTabSwitcher:
            LocalizedEntry(
                ja: "スイッチャー",
                en: "Switcher",
                zhHans: "切换器",
                zhHant: "切換器",
                ko: "전환기"
            )
        case .settingsTabLauncher:
            LocalizedEntry(
                ja: "ランチャー",
                en: "Launcher",
                zhHans: "启动器",
                zhHant: "啟動器",
                ko: "런처"
            )
        case .settingsTabSystem:
            LocalizedEntry(
                ja: "システム",
                en: "System",
                zhHans: "系统",
                zhHant: "系統",
                ko: "시스템"
            )

        // MARK: - 設定フォーム
        case .settingsLaunchAtLogin:
            LocalizedEntry(
                ja: "ログイン時に自動起動",
                en: "Launch at Login",
                zhHans: "登录时自动启动",
                zhHant: "登入時自動啟動",
                ko: "로그인 시 자동 실행"
            )
        case .settingsNormalSwitcherSectionTitle:
            LocalizedEntry(
                ja: "通常スイッチャー（ホールド式）",
                en: "Window Switcher (Hold)",
                zhHans: "窗口切换器（按住模式）",
                zhHant: "視窗切換器（按住模式）",
                ko: "윈도우 전환기 (홀드 방식)"
            )
        case .settingsLauncherSectionTitle:
            LocalizedEntry(
                ja: "検索ランチャー（トグル式）",
                en: "Search Launcher (Toggle)",
                zhHans: "搜索启动器（切换模式）",
                zhHant: "搜尋啟動器（切換模式）",
                ko: "검색 런처 (토글 방식)"
            )
        case .settingsShortcutLabel:
            LocalizedEntry(
                ja: "起動ショートカット",
                en: "Shortcut",
                zhHans: "快捷键",
                zhHant: "快速鍵",
                ko: "단축키"
            )
        case .settingsControlsLabel:
            LocalizedEntry(
                ja: "操作方法",
                en: "Controls",
                zhHans: "操作方式",
                zhHant: "操作方式",
                ko: "조작 방법"
            )
        case .settingsCommandTabWarning:
            LocalizedEntry(
                ja: "Command + Tab は macOS 標準のアプリスイッチャーを上書きします。",
                en: "Command + Tab overrides the default macOS application switcher.",
                zhHans: "Command + Tab 将覆盖 macOS 默认的应用切换器。",
                zhHant: "Command + Tab 將覆蓋 macOS 預設的應用程式切換器。",
                ko: "Command + Tab은 macOS 기본 앱 전환기를 덮어씁니다."
            )
        case .settingsNormalShortcutHint:
            LocalizedEntry(
                ja: "⌘ / ⌥ / ⌃ のいずれか1つ以上を含めて入力してください（⇧ は逆順移動用）。",
                en: "Include at least one of ⌘ / ⌥ / ⌃ (⇧ is reserved for reverse cycling).",
                zhHans: "请至少包含 ⌘ / ⌥ / ⌃ 中的一个修饰键（⇧ 保留用于反向切换）。",
                zhHant: "請至少包含 ⌘ / ⌥ / ⌃ 中的一個修飾鍵（⇧ 保留用於反向切換）。",
                ko: "⌘ / ⌥ / ⌃ 중 하나 이상을 포함해 입력하세요(⇧는 역순 이동용)."
            )
        case .settingsLauncherShortcutHint:
            LocalizedEntry(
                ja: "⌘ / ⌥ / ⌃ のいずれか1つ以上を含めて入力してください。",
                en: "Include at least one of ⌘ / ⌥ / ⌃.",
                zhHans: "请至少包含 ⌘ / ⌥ / ⌃ 中的一个修饰键。",
                zhHant: "請至少包含 ⌘ / ⌥ / ⌃ 中的一個修飾鍵。",
                ko: "⌘ / ⌥ / ⌃ 중 하나 이상을 포함해 입력하세요."
            )
        case .settingsDisplayStyleLabel:
            LocalizedEntry(
                ja: "表示形式",
                en: "Display Style",
                zhHans: "显示方式",
                zhHant: "顯示方式",
                ko: "표시 형식"
            )
        case .settingsNormalCaptureDescription:
            LocalizedEntry(
                ja: "ウィンドウのサムネイルをグリッド表示します（リスト型より多くのメモリを使用する場合があります）。",
                en: "Displays window thumbnails (may use more memory than List style).",
                zhHans: "以缩略图显示窗口预览（可能比列表模式占用更多内存）。",
                zhHant: "以縮圖顯示視窗預覽（可能比列表模式佔用更多記憶體）。",
                ko: "윈도우 썸네일을 표시합니다(목록 형식보다 더 많은 메모리를 사용할 수 있습니다)."
            )
        case .settingsLauncherCaptureDescription:
            LocalizedEntry(
                ja: "各ウィンドウ候補の行にサムネイルを表示します（リスト型より多くのメモリを使用する場合があります）。",
                en: "Shows a thumbnail on each window row (may use more memory than List style).",
                zhHans: "在每个窗口候选项行中显示缩略图（可能比列表模式占用更多内存）。",
                zhHant: "在每個視窗候選項列中顯示縮圖（可能比列表模式佔用更多記憶體）。",
                ko: "각 윈도우 후보 행에 썸네일을 표시합니다(목록 형식보다 더 많은 메모리를 사용할 수 있습니다)."
            )
        case .settingsSystemPermissionsSectionTitle:
            LocalizedEntry(
                ja: "システム権限",
                en: "System Permissions",
                zhHans: "系统权限",
                zhHant: "系統權限",
                ko: "시스템 권한"
            )
        case .settingsAccessibilityPermissionLabel:
            LocalizedEntry(
                ja: "アクセシビリティ権限",
                en: "Accessibility",
                zhHans: "辅助功能权限",
                zhHant: "輔助使用權限",
                ko: "손쉬운 사용 권한"
            )
        case .settingsScreenRecordingPermissionLabel:
            LocalizedEntry(
                ja: "画面収録権限",
                en: "Screen Recording",
                zhHans: "录屏权限",
                zhHant: "螢幕錄製權限",
                ko: "화면 기록 권한"
            )
        case .settingsPermissionGranted:
            LocalizedEntry(
                ja: "許可済み",
                en: "Granted",
                zhHans: "已授权",
                zhHant: "已授權",
                ko: "허용됨"
            )
        case .settingsPermissionDenied:
            LocalizedEntry(
                ja: "未許可",
                en: "Not Granted",
                zhHans: "未授权",
                zhHant: "未授權",
                ko: "허용 안 됨"
            )
        case .settingsOpenSettingsButton:
            LocalizedEntry(
                ja: "設定を開く",
                en: "Open Settings",
                zhHans: "打开设置",
                zhHant: "開啟設定",
                ko: "설정 열기"
            )
        case .settingsAppInfoSectionTitle:
            LocalizedEntry(
                ja: "アプリ情報",
                en: "About",
                zhHans: "应用信息",
                zhHant: "應用程式資訊",
                ko: "앱 정보"
            )
        case .settingsAppNameLabel:
            LocalizedEntry(
                ja: "アプリ名",
                en: "App Name",
                zhHans: "应用名称",
                zhHant: "應用程式名稱",
                ko: "앱 이름"
            )
        case .settingsVersionLabel:
            LocalizedEntry(
                ja: "バージョン",
                en: "Version",
                zhHans: "版本",
                zhHant: "版本",
                ko: "버전"
            )
        case .settingsScreenRecordingRequiredMessage:
            LocalizedEntry(
                ja: "ウィンドウのキャプチャ表示には「画面収録」権限の許可が必要です。",
                en: "Screen Recording permission is required to display window thumbnails.",
                zhHans: "显示窗口缩略图需要授予「录屏」权限。",
                zhHant: "顯示視窗縮圖需要授予「螢幕錄製」權限。",
                ko: "윈도우 썸네일을 표시하려면 「화면 기록」 권한이 필요합니다."
            )
        case .settingsRequestPermissionButton:
            LocalizedEntry(
                ja: "権限をリクエスト",
                en: "Request Permission",
                zhHans: "请求权限",
                zhHant: "請求權限",
                ko: "권한 요청"
            )
        case .openSystemSettingsButton:
            LocalizedEntry(
                ja: "システム設定を開く",
                en: "Open System Settings",
                zhHans: "打开系统设置",
                zhHant: "開啟系統設定",
                ko: "시스템 설정 열기"
            )
        case .recheckButton:
            LocalizedEntry(
                ja: "再確認",
                en: "Recheck",
                zhHans: "重新检查",
                zhHant: "重新檢查",
                ko: "다시 확인"
            )
        case .settingsScreenRecordingRestartNote:
            LocalizedEntry(
                ja: "※ macOS の仕様上、権限を許可した後にアプリの再起動が必要になる場合があります。",
                en: "* Due to macOS behavior, you may need to restart the app after granting permission.",
                zhHans: "※ 受 macOS 机制限制，授予权限后可能需要重新启动应用。",
                zhHant: "※ 受 macOS 機制限制，授予權限後可能需要重新啟動應用程式。",
                ko: "※ macOS 특성상 권한을 허용한 후 앱을 재시작해야 할 수 있습니다."
            )
        case .shortcutRecorderPrompt:
            LocalizedEntry(
                ja: "キーを入力... (Esc でキャンセル)",
                en: "Press shortcut... (Esc to cancel)",
                zhHans: "请按下快捷键... (按 Esc 取消)",
                zhHant: "請按下快速鍵... (按 Esc 取消)",
                ko: "키 입력... (Esc로 취소)"
            )

        // MARK: - ショートカット検証エラー
        case .shortcutValidationMissingPrimaryModifier:
            LocalizedEntry(
                ja: "Command / Option / Control のいずれか1つ以上の修飾キーを含めてください。",
                en: "Include at least one of Command, Option, or Control.",
                zhHans: "请至少包含 Command / Option / Control 中的一个修饰键。",
                zhHant: "請至少包含 Command / Option / Control 中的一個修飾鍵。",
                ko: "Command / Option / Control 중 하나 이상의 보조 키를 포함해 주세요."
            )
        case .shortcutValidationShiftReserved:
            LocalizedEntry(
                ja: "通常スイッチャーでは Shift は逆順移動に使用されるため、基本ショートカットに含められません。",
                en: "Shift is reserved for reverse cycling in the Window Switcher and cannot be part of its base shortcut.",
                zhHans: "窗口切换器中 Shift 保留用于反向切换，不能包含在基础快捷键中。",
                zhHant: "視窗切換器中 Shift 保留用於反向切換，不能包含在基礎快速鍵中。",
                ko: "윈도우 전환기에서는 Shift가 역순 이동에 사용되므로 기본 단축키에 포함할 수 없습니다."
            )

        // MARK: - 権限誘導画面
        case .permissionGuideTitle:
            LocalizedEntry(
                ja: "アクセシビリティ権限の許可が必要です",
                en: "Accessibility Permission Required",
                zhHans: "需要授予辅助功能权限",
                zhHant: "需要授予輔助使用權限",
                ko: "손쉬운 사용 권한이 필요합니다"
            )
        case .permissionGuideSubtitle:
            LocalizedEntry(
                ja: "ショートカット検知とウィンドウ切り替えの操作にのみ使用します",
                en: "Used only for detecting shortcuts and switching windows.",
                zhHans: "仅用于检测快捷键和切换窗口。",
                zhHant: "僅用於偵測快速鍵和切換視窗。",
                ko: "단축키 감지 및 윈도우 전환에만 사용됩니다."
            )
        case .permissionGuideStep1:
            LocalizedEntry(
                ja: "1. 下の「システム設定を開く」をクリックします",
                en: "1. Click \"Open System Settings\" below",
                zhHans: "1. 点击下方的「打开系统设置」",
                zhHant: "1. 點擊下方的「開啟系統設定」",
                ko: "1. 아래의 「시스템 설정 열기」를 클릭합니다"
            )
        case .permissionGuideStep3:
            LocalizedEntry(
                ja: "3. 許可を検知すると自動的に利用可能になります",
                en: "3. Once granted, Wintch will become ready automatically",
                zhHans: "3. 检测到权限后将自动开始使用",
                zhHant: "3. 偵測到權限後將自動開始使用",
                ko: "3. 권한이 감지되면 자동으로 사용할 수 있습니다"
            )
        case .permissionGuideScreenRecordingNote:
            LocalizedEntry(
                ja: "※ リスト型・アイコン型では「画面収録」権限を使用しません（スイッチャーまたは検索ランチャーでキャプチャ表示型を選択した場合のみ任意で使用します）。",
                en: "* List and Icons styles do not use Screen Recording permission (it is only optionally used when Thumbnails style is selected for the Switcher or Search Launcher).",
                zhHans: "※ 列表和图标模式不使用「录屏」权限（仅在窗口切换器或搜索启动器中选择缩略图模式时按需使用）。",
                zhHant: "※ 列表和圖示模式不使用「螢幕錄製」權限（僅在視窗切換器或搜尋啟動器中選擇縮圖模式時按需使用）。",
                ko: "※ 목록 및 아이콘 형식에서는 「화면 기록」 권한을 사용하지 않습니다(전환기 또는 검색 런처에서 미리보기 형식을 선택한 경우에만 선택적으로 사용합니다)."
            )

        // MARK: - スイッチャー／検索ランチャー
        case .launcherSearchPlaceholder:
            LocalizedEntry(
                ja: "ウィンドウまたはアプリを検索...",
                en: "Search windows or apps...",
                zhHans: "搜索窗口或应用...",
                zhHant: "搜尋視窗或應用程式...",
                ko: "윈도우 또는 앱 검색..."
            )
        case .launcherEmptyNoOpenWindows:
            LocalizedEntry(
                ja: "開いているウィンドウがありません（アプリ名を入力して起動）",
                en: "No open windows (type an app name to launch)",
                zhHans: "没有打开的窗口（输入应用名称以启动）",
                zhHant: "沒有開啟的視窗（輸入應用程式名稱以啟動）",
                ko: "열려 있는 윈도우가 없습니다 (앱 이름을 입력하여 실행)"
            )
        case .launcherEmptyNoMatchingApps:
            LocalizedEntry(
                ja: "一致するアプリがありません",
                en: "No matching apps",
                zhHans: "没有匹配的应用",
                zhHant: "沒有符合的應用程式",
                ko: "일치하는 앱이 없습니다"
            )
        case .launcherEmptyNoMatchingCandidates:
            LocalizedEntry(
                ja: "一致するウィンドウやアプリがありません",
                en: "No matching windows or apps",
                zhHans: "没有匹配的窗口或应用",
                zhHant: "沒有符合的視窗或應用程式",
                ko: "일치하는 윈도우나 앱이 없습니다"
            )
        case .launcherLaunchAppSectionTitle:
            LocalizedEntry(
                ja: "アプリを起動",
                en: "Launch App",
                zhHans: "启动应用",
                zhHant: "啟動應用程式",
                ko: "앱 실행"
            )
        case .launcherLaunchAppFallbackSectionTitle:
            LocalizedEntry(
                ja: "一致するウィンドウがないため、アプリを起動",
                en: "No matching windows — Launch App",
                zhHans: "没有匹配的窗口，启动应用",
                zhHant: "沒有符合的視窗，啟動應用程式",
                ko: "일치하는 윈도우가 없어 앱 실행"
            )
        case .launcherLaunchBadge:
            LocalizedEntry(
                ja: "起動",
                en: "Launch",
                zhHans: "启动",
                zhHant: "啟動",
                ko: "실행"
            )
        case .screenRecordingDeniedBanner:
            LocalizedEntry(
                ja: "画面収録権限が未許可のためプレースホルダーを表示しています",
                en: "Showing placeholders because Screen Recording permission is not granted",
                zhHans: "未授予录屏权限，当前显示占位图标",
                zhHant: "未授予螢幕錄製權限，目前顯示預留圖示",
                ko: "화면 기록 권한이 허용되지 않아 대체 아이콘을 표시하고 있습니다"
            )
        case .untitledWindow:
            LocalizedEntry(
                ja: "(タイトルなし)",
                en: "(Untitled)",
                zhHans: "(无标题)",
                zhHant: "(無標題)",
                ko: "(제목 없음)"
            )
        case .unknownApplication:
            LocalizedEntry(
                ja: "不明なアプリ",
                en: "Unknown App",
                zhHans: "未知应用",
                zhHant: "未知應用程式",
                ko: "알 수 없는 앱"
            )
        case .triggerKeyGraveDisplayName:
            LocalizedEntry(
                ja: "` (バッククォート)",
                en: "` (Backquote)",
                zhHans: "` (反引号)",
                zhHant: "` (反引號)",
                ko: "` (백틱)"
            )
        case .triggerKeyBackslashDisplayName:
            LocalizedEntry(
                ja: "\\ (バックスラッシュ)",
                en: "\\ (Backslash)",
                zhHans: "\\ (反斜杠)",
                zhHant: "\\ (反斜線)",
                ko: "\\ (백슬래시)"
            )

        // MARK: - 自動バージョンアップ・手動確認
        case .settingsAutoCheckForUpdates:
            LocalizedEntry(
                ja: "バージョンアップを自動チェック",
                en: "Automatically check for updates",
                zhHans: "自动检查更新",
                zhHant: "自動檢查更新",
                ko: "자동으로 업데이트 확인"
            )
        case .settingsAutoCheckForUpdatesCaption:
            LocalizedEntry(
                ja: "アプリ起動時に新しいバージョンがあるか自動でバックグラウンド確認します。",
                en: "Checks in the background for a new version when the app launches.",
                zhHans: "应用启动时在后台自动检查是否有新版本。",
                zhHant: "應用程式啟動時在背景自動檢查是否有新版本。",
                ko: "앱 실행 시 백그라운드에서 새 버전이 있는지 자동으로 확인합니다."
            )
        case .settingsCheckForUpdatesButton:
            LocalizedEntry(
                ja: "アップデートを確認",
                en: "Check for Updates",
                zhHans: "检查更新",
                zhHant: "檢查更新",
                ko: "업데이트 확인"
            )
        case .settingsCheckingForUpdates:
            LocalizedEntry(
                ja: "確認中...",
                en: "Checking...",
                zhHans: "正在检查...",
                zhHant: "正在檢查...",
                ko: "확인 중..."
            )
        case .settingsUpToDateMessage:
            LocalizedEntry(
                ja: "最新バージョンを使用しています。",
                en: "You're up to date.",
                zhHans: "当前已是最新版本。",
                zhHant: "目前已是最新版本。",
                ko: "최신 버전을 사용하고 있습니다."
            )
        case .settingsOpenGitHubReleasesButton:
            LocalizedEntry(
                ja: "GitHub Releases を開く",
                en: "Open GitHub Releases",
                zhHans: "打开 GitHub Releases",
                zhHant: "開啟 GitHub Releases",
                ko: "GitHub Releases 열기"
            )
        case .updateDialogTitle:
            LocalizedEntry(
                ja: "新しいバージョンが利用可能です",
                en: "A New Version Is Available",
                zhHans: "有新版本可用",
                zhHant: "有新版本可用",
                ko: "새 버전을 사용할 수 있습니다"
            )
        case .updateReleaseNotesSectionTitle:
            LocalizedEntry(
                ja: "変更内容",
                en: "Release Notes",
                zhHans: "更新内容",
                zhHant: "更新內容",
                ko: "변경 사항"
            )
        case .updateReleaseNotesEmpty:
            LocalizedEntry(
                ja: "リリースノートは記載されていません。",
                en: "No release notes provided.",
                zhHans: "未提供更新说明。",
                zhHant: "未提供更新說明。",
                ko: "릴리스 노트가 제공되지 않았습니다."
            )
        case .updateViewOnGitHubButton:
            LocalizedEntry(
                ja: "GitHub で変更内容を見る",
                en: "View Release on GitHub",
                zhHans: "在 GitHub 上查看更新内容",
                zhHant: "在 GitHub 上查看更新內容",
                ko: "GitHub에서 변경 사항 보기"
            )
        case .updateNowButton:
            LocalizedEntry(
                ja: "今すぐアップデート",
                en: "Update Now",
                zhHans: "立即更新",
                zhHant: "立即更新",
                ko: "지금 업데이트"
            )
        case .updateLaterButton:
            LocalizedEntry(
                ja: "後で",
                en: "Later",
                zhHans: "稍后",
                zhHant: "稍後",
                ko: "나중에"
            )
        case .updateSkipVersionButton:
            LocalizedEntry(
                ja: "このバージョンをスキップ",
                en: "Skip This Version",
                zhHans: "跳过此版本",
                zhHant: "略過此版本",
                ko: "이 버전 건너뛰기"
            )
        case .updateStatusDownloading:
            LocalizedEntry(
                ja: "アップデートをダウンロードしています...",
                en: "Downloading update...",
                zhHans: "正在下载更新...",
                zhHant: "正在下載更新...",
                ko: "업데이트를 다운로드하는 중..."
            )
        case .updateStatusExtracting:
            LocalizedEntry(
                ja: "アップデートを展開しています...",
                en: "Extracting update...",
                zhHans: "正在解压更新...",
                zhHant: "正在解壓縮更新...",
                ko: "업데이트 압축을 푸는 중..."
            )
        case .updateStatusVerifying:
            LocalizedEntry(
                ja: "署名と整合性を検証しています...",
                en: "Verifying signature and integrity...",
                zhHans: "正在验证签名和完整性...",
                zhHant: "正在驗證簽章與完整性...",
                ko: "서명 및 무결성을 확인하는 중..."
            )
        case .updateStatusInstalling:
            LocalizedEntry(
                ja: "アップデートを適用して再起動しています...",
                en: "Installing update and restarting...",
                zhHans: "正在应用更新并重启...",
                zhHant: "正在套用更新並重新啟動...",
                ko: "업데이트를 적용하고 재시작하는 중..."
            )
        }
    }

    // MARK: - 静的文言アクセサ

    /// 「システム設定に従う」選択肢ラベル
    public var languageFollowSystem: String { text(for: .languageFollowSystem) }
    /// 設定「一般」タブの言語ピッカーラベル
    public var settingsLanguageLabel: String { text(for: .settingsLanguageLabel) }
    /// メニューバー: アクセシビリティ権限不足案内
    public var menuBarAccessibilityRequired: String { text(for: .menuBarAccessibilityRequired) }
    /// メニューバー: 表示形式サブメニュー
    public var menuBarDisplayStyle: String { text(for: .menuBarDisplayStyle) }
    /// メニューバー: 通常スイッチャーセクション
    public var menuBarNormalSwitcher: String { text(for: .menuBarNormalSwitcher) }
    /// メニューバー: 検索ランチャーセクション
    public var menuBarSearchLauncher: String { text(for: .menuBarSearchLauncher) }
    /// 共通: アプリごとにグルーピングトグル
    public var groupByAppToggle: String { text(for: .groupByAppToggle) }
    /// メニューバー: 設定を開く
    public var menuBarOpenSettings: String { text(for: .menuBarOpenSettings) }
    /// 設定一般: ログイン時に自動起動
    public var settingsLaunchAtLogin: String { text(for: .settingsLaunchAtLogin) }
    /// 設定スイッチャー: セクション見出し
    public var settingsNormalSwitcherSectionTitle: String { text(for: .settingsNormalSwitcherSectionTitle) }
    /// 設定ランチャー: セクション見出し
    public var settingsLauncherSectionTitle: String { text(for: .settingsLauncherSectionTitle) }
    /// 設定共通: 起動ショートカット
    public var settingsShortcutLabel: String { text(for: .settingsShortcutLabel) }
    /// 設定スイッチャー: 操作方法
    public var settingsControlsLabel: String { text(for: .settingsControlsLabel) }
    /// 設定スイッチャー: Command + Tab 上書き警告
    public var settingsCommandTabWarning: String { text(for: .settingsCommandTabWarning) }
    /// 設定スイッチャー: 修飾キー入力ヒント
    public var settingsNormalShortcutHint: String { text(for: .settingsNormalShortcutHint) }
    /// 設定ランチャー: 修飾キー入力ヒント
    public var settingsLauncherShortcutHint: String { text(for: .settingsLauncherShortcutHint) }
    /// 設定共通: 表示形式ラベル
    public var settingsDisplayStyleLabel: String { text(for: .settingsDisplayStyleLabel) }
    /// 設定スイッチャー: キャプチャ表示説明
    public var settingsNormalCaptureDescription: String { text(for: .settingsNormalCaptureDescription) }
    /// 設定ランチャー: キャプチャ表示説明
    public var settingsLauncherCaptureDescription: String { text(for: .settingsLauncherCaptureDescription) }
    /// 設定システム: システム権限セクション見出し
    public var settingsSystemPermissionsSectionTitle: String { text(for: .settingsSystemPermissionsSectionTitle) }
    /// 設定システム: アクセシビリティ権限ラベル
    public var settingsAccessibilityPermissionLabel: String { text(for: .settingsAccessibilityPermissionLabel) }
    /// 設定システム: 画面収録権限ラベル
    public var settingsScreenRecordingPermissionLabel: String { text(for: .settingsScreenRecordingPermissionLabel) }
    /// 設定システム: 許可済み
    public var settingsPermissionGranted: String { text(for: .settingsPermissionGranted) }
    /// 設定システム: 未許可
    public var settingsPermissionDenied: String { text(for: .settingsPermissionDenied) }
    /// 設定システム: 設定を開くボタン
    public var settingsOpenSettingsButton: String { text(for: .settingsOpenSettingsButton) }
    /// 設定システム: アプリ情報セクション見出し
    public var settingsAppInfoSectionTitle: String { text(for: .settingsAppInfoSectionTitle) }
    /// 設定システム: アプリ名ラベル
    public var settingsAppNameLabel: String { text(for: .settingsAppNameLabel) }
    /// 設定システム: バージョンラベル
    public var settingsVersionLabel: String { text(for: .settingsVersionLabel) }
    /// 設定キャプチャ未許可ガイド: 説明文
    public var settingsScreenRecordingRequiredMessage: String { text(for: .settingsScreenRecordingRequiredMessage) }
    /// 設定キャプチャ未許可ガイド: 権限をリクエストボタン
    public var settingsRequestPermissionButton: String { text(for: .settingsRequestPermissionButton) }
    /// 共通ボタン: システム設定を開く
    public var openSystemSettingsButton: String { text(for: .openSystemSettingsButton) }
    /// 共通ボタン: 再確認
    public var recheckButton: String { text(for: .recheckButton) }
    /// 設定キャプチャ未許可ガイド: 再起動補足
    public var settingsScreenRecordingRestartNote: String { text(for: .settingsScreenRecordingRestartNote) }
    /// ショートカットレコーダー: キー入力待機文言
    public var shortcutRecorderPrompt: String { text(for: .shortcutRecorderPrompt) }
    /// 権限誘導画面: 見出し
    public var permissionGuideTitle: String { text(for: .permissionGuideTitle) }
    /// 権限誘導画面: サブ見出し
    public var permissionGuideSubtitle: String { text(for: .permissionGuideSubtitle) }
    /// 権限誘導画面: 手順 1
    public var permissionGuideStep1: String { text(for: .permissionGuideStep1) }
    /// 権限誘導画面: 手順 3
    public var permissionGuideStep3: String { text(for: .permissionGuideStep3) }
    /// 権限誘導画面: 画面収録権限の注記
    public var permissionGuideScreenRecordingNote: String { text(for: .permissionGuideScreenRecordingNote) }
    /// 検索ランチャー: 検索欄プレースホルダー
    public var launcherSearchPlaceholder: String { text(for: .launcherSearchPlaceholder) }
    /// 検索ランチャー: アプリ起動セクション見出し（ウィンドウ候補あり）
    public var launcherLaunchAppSectionTitle: String { text(for: .launcherLaunchAppSectionTitle) }
    /// 検索ランチャー: アプリ起動セクション見出し（ウィンドウ候補なし時）
    public var launcherLaunchAppFallbackSectionTitle: String { text(for: .launcherLaunchAppFallbackSectionTitle) }
    /// 検索ランチャー: 起動バッジ
    public var launcherLaunchBadge: String { text(for: .launcherLaunchBadge) }
    /// キャプチャ表示型: 画面収録権限未許可バナー
    public var screenRecordingDeniedBanner: String { text(for: .screenRecordingDeniedBanner) }
    /// ウィンドウ表示補助: 空タイトル
    public var untitledWindow: String { text(for: .untitledWindow) }
    /// ウィンドウ表示補助: 不明アプリ
    public var unknownApplication: String { text(for: .unknownApplication) }
    /// 設定一般: バージョンアップを自動チェック
    public var settingsAutoCheckForUpdates: String { text(for: .settingsAutoCheckForUpdates) }
    /// 設定一般: バージョンアップを自動チェック補足
    public var settingsAutoCheckForUpdatesCaption: String { text(for: .settingsAutoCheckForUpdatesCaption) }
    /// 設定システム: アップデートを確認ボタン
    public var settingsCheckForUpdatesButton: String { text(for: .settingsCheckForUpdatesButton) }
    /// 設定システム: アップデート確認中
    public var settingsCheckingForUpdates: String { text(for: .settingsCheckingForUpdates) }
    /// 設定システム: 最新バージョン利用中メッセージ
    public var settingsUpToDateMessage: String { text(for: .settingsUpToDateMessage) }
    /// 共通ボタン: GitHub Releases を開く
    public var settingsOpenGitHubReleasesButton: String { text(for: .settingsOpenGitHubReleasesButton) }
    /// 更新ダイアログ: 見出し
    public var updateDialogTitle: String { text(for: .updateDialogTitle) }
    /// 更新ダイアログ: 変更内容見出し
    public var updateReleaseNotesSectionTitle: String { text(for: .updateReleaseNotesSectionTitle) }
    /// 更新ダイアログ: リリースノート未記載時案内
    public var updateReleaseNotesEmpty: String { text(for: .updateReleaseNotesEmpty) }
    /// 更新ダイアログ: GitHub で変更内容を見る
    public var updateViewOnGitHubButton: String { text(for: .updateViewOnGitHubButton) }
    /// 更新ダイアログ: 今すぐアップデート
    public var updateNowButton: String { text(for: .updateNowButton) }
    /// 更新ダイアログ: 後で
    public var updateLaterButton: String { text(for: .updateLaterButton) }
    /// 更新ダイアログ: このバージョンをスキップ
    public var updateSkipVersionButton: String { text(for: .updateSkipVersionButton) }
    /// 更新ダイアログ: ダウンロード中
    public var updateStatusDownloading: String { text(for: .updateStatusDownloading) }
    /// 更新ダイアログ: 展開中
    public var updateStatusExtracting: String { text(for: .updateStatusExtracting) }
    /// 更新ダイアログ: 検証中
    public var updateStatusVerifying: String { text(for: .updateStatusVerifying) }
    /// 更新ダイアログ: 適用・再起動中
    public var updateStatusInstalling: String { text(for: .updateStatusInstalling) }

    // MARK: - 動的パラメータ付き文言

    /// メニューバーの終了ボタン文言を生成する
    /// - Parameter appName: アプリケーション表示名（例: `"Wintch"` / `"Wintch_dev"`）
    /// - Returns: ローカライズ済み終了メニュー文言
    public func quitMenuTitle(appName: String) -> String {
        switch language {
        case .japanese: "\(appName) を終了"
        case .english: "Quit \(appName)"
        case .simplifiedChinese: "退出 \(appName)"
        case .traditionalChinese: "結束 \(appName)"
        case .korean: "\(appName) 종료"
        }
    }

    /// 設定ウィンドウのタイトルバー文言を生成する
    /// - Parameter appName: アプリケーション表示名
    /// - Returns: ローカライズ済み設定ウィンドウタイトル
    public func settingsWindowTitle(appName: String) -> String {
        switch language {
        case .japanese: "\(appName) 設定"
        case .english: "\(appName) Settings"
        case .simplifiedChinese: "\(appName) 设置"
        case .traditionalChinese: "\(appName) 設定"
        case .korean: "\(appName) 설정"
        }
    }

    /// 権限誘導ウィンドウのタイトルバー文言を生成する
    /// - Parameter appName: アプリケーション表示名
    /// - Returns: ローカライズ済み権限誘導ウィンドウタイトル
    public func permissionGuideWindowTitle(appName: String) -> String {
        switch language {
        case .japanese: "\(appName) - 権限の確認"
        case .english: "\(appName) - Permission Required"
        case .simplifiedChinese: "\(appName) - 权限确认"
        case .traditionalChinese: "\(appName) - 權限確認"
        case .korean: "\(appName) - 권한 확인"
        }
    }

    /// 権限誘導画面のステップ 2（アプリ名埋め込み）文言を生成する
    /// - Parameter appName: アプリケーション表示名
    /// - Returns: ローカライズ済み手順 2 文言
    public func permissionGuideStep2(appName: String) -> String {
        switch language {
        case .japanese: "2. 一覧の「\(appName)」のスイッチをオンにします"
        case .english: "2. Turn on the switch for \"\(appName)\" in the list"
        case .simplifiedChinese: "2. 在列表中打开「\(appName)」的开关"
        case .traditionalChinese: "2. 在列表中開啟「\(appName)」的開關"
        case .korean: "2. 목록에서 「\(appName)」 스위치를 켭니다"
        }
    }

    /// アプリ情報に表示する整形済みバージョン文言を生成する
    /// - Parameters:
    ///   - shortVersion: セマンティックバージョン文字列
    ///   - buildNumber: ビルド番号文字列
    /// - Returns: ローカライズ済みバージョン表記
    public func versionText(shortVersion: String, buildNumber: String) -> String {
        switch language {
        case .japanese: "バージョン \(shortVersion) (\(buildNumber))"
        case .english: "Version \(shortVersion) (\(buildNumber))"
        case .simplifiedChinese: "版本 \(shortVersion) (\(buildNumber))"
        case .traditionalChinese: "版本 \(shortVersion) (\(buildNumber))"
        case .korean: "버전 \(shortVersion) (\(buildNumber))"
        }
    }

    /// 通常スイッチャーの順方向操作ガイド行を生成する
    /// - Parameter shortcut: 順方向ショートカット表記
    /// - Returns: ローカライズ済み「次へ」表記
    public func controlsNext(_ shortcut: String) -> String {
        switch language {
        case .japanese: "次へ: \(shortcut)"
        case .english: "Next: \(shortcut)"
        case .simplifiedChinese: "下一个: \(shortcut)"
        case .traditionalChinese: "下一個: \(shortcut)"
        case .korean: "다음: \(shortcut)"
        }
    }

    /// 通常スイッチャーの逆方向操作ガイド行を生成する
    /// - Parameter shortcut: 逆方向ショートカット表記
    /// - Returns: ローカライズ済み「前へ」表記
    public func controlsPrevious(_ shortcut: String) -> String {
        switch language {
        case .japanese: "前へ: \(shortcut)"
        case .english: "Previous: \(shortcut)"
        case .simplifiedChinese: "上一个: \(shortcut)"
        case .traditionalChinese: "上一個: \(shortcut)"
        case .korean: "이전: \(shortcut)"
        }
    }

    /// ログイン時自動起動設定の変更失敗エラー文言を生成する
    /// - Parameter detail: OS から返されたエラー詳細文字列
    /// - Returns: ローカライズ済みエラーメッセージ
    public func launchAtLoginError(detail: String) -> String {
        switch language {
        case .japanese:
            "自動起動の設定変更に失敗しました（.app バンドルとして起動しているか確認してください）: \(detail)"
        case .english:
            "Failed to update Launch at Login (make sure the app is running from a .app bundle): \(detail)"
        case .simplifiedChinese:
            "更改登录时自动启动设置失败（请确认是否从 .app 应用包启动）: \(detail)"
        case .traditionalChinese:
            "變更登入時自動啟動設定失敗（請確認是否從 .app 應用程式套件啟動）: \(detail)"
        case .korean:
            "로그인 시 자동 실행 설정 변경에 실패했습니다(.app 번들로 실행 중인지 확인해 주세요): \(detail)"
        }
    }

    /// 通常スイッチャーとショートカットが競合した場合の検証エラー文言を生成する
    /// - Parameters:
    ///   - forward: 通常スイッチャーの順方向ショートカット表記
    ///   - reverse: 通常スイッチャーの逆方向ショートカット表記
    /// - Returns: ローカライズ済みエラーメッセージ
    public func shortcutConflictWithNormalSwitcher(forward: String, reverse: String) -> String {
        switch language {
        case .japanese:
            "通常スイッチャー（\(forward) / \(reverse)）と重複するため登録できません。"
        case .english:
            "Conflicts with the Window Switcher shortcut (\(forward) / \(reverse))."
        case .simplifiedChinese:
            "与窗口切换器快捷键（\(forward) / \(reverse)）冲突，无法设置。"
        case .traditionalChinese:
            "與視窗切換器快速鍵（\(forward) / \(reverse)）衝突，無法設定。"
        case .korean:
            "윈도우 전환기 단축키(\(forward) / \(reverse))와 중복되어 등록할 수 없습니다."
        }
    }

    /// 検索ランチャーとショートカットが競合した場合の検証エラー文言を生成する
    /// - Parameter shortcut: 検索ランチャーのショートカット表記
    /// - Returns: ローカライズ済みエラーメッセージ
    public func shortcutConflictWithLauncher(shortcut: String) -> String {
        switch language {
        case .japanese:
            "検索ランチャー（\(shortcut)）と重複するため設定できません。"
        case .english:
            "Conflicts with the Search Launcher shortcut (\(shortcut))."
        case .simplifiedChinese:
            "与搜索启动器快捷键（\(shortcut)）冲突，无法设置。"
        case .traditionalChinese:
            "與搜尋啟動器快速鍵（\(shortcut)）衝突，無法設定。"
        case .korean:
            "검색 런처 단축키(\(shortcut))와 중복되어 설정할 수 없습니다."
        }
    }

    /// アップデート確認ウィンドウのタイトルバー文言を生成する
    /// - Parameter appName: アプリケーション表示名
    /// - Returns: ローカライズ済みアップデートウィンドウタイトル
    public func updateWindowTitle(appName: String) -> String {
        switch language {
        case .japanese: "\(appName) のアップデート"
        case .english: "Update \(appName)"
        case .simplifiedChinese: "更新 \(appName)"
        case .traditionalChinese: "更新 \(appName)"
        case .korean: "\(appName) 업데이트"
        }
    }

    /// 新バージョン検出時の設定画面通知文言を生成する
    /// - Parameter version: 検出された新バージョン文字列
    /// - Returns: ローカライズ済み通知文言
    public func settingsUpdateAvailableMessage(version: String) -> String {
        switch language {
        case .japanese: "新しいバージョン（v\(version)）が利用可能です。"
        case .english: "A new version (v\(version)) is available."
        case .simplifiedChinese: "有新版本（v\(version)）可用。"
        case .traditionalChinese: "有新版本（v\(version)）可用。"
        case .korean: "새 버전(v\(version))을 사용할 수 있습니다."
        }
    }

    /// ローカル開発版での手動アップデート確認時に表示する案内文言を生成する
    /// - Parameter latestVersion: 取得できた最新安定版バージョン文字列（未取得時は nil）
    /// - Returns: ローカライズ済み開発版案内文言
    public func updateDevelopmentBuildNotice(latestVersion: String?) -> String {
        if let latestVersion {
            switch language {
            case .japanese:
                "開発版を実行中のためアプリ内自動アップデートは無効です（最新安定版: v\(latestVersion)）。"
            case .english:
                "In-app updates are disabled in development builds (latest stable: v\(latestVersion))."
            case .simplifiedChinese:
                "开发版本已禁用应用内自动更新（最新稳定版：v\(latestVersion)）。"
            case .traditionalChinese:
                "開發版本已停用應用程式內自動更新（最新穩定版：v\(latestVersion)）。"
            case .korean:
                "개발 빌드에서는 앱 내 자동 업데이트가 비활성화되어 있습니다(최신 안정 버전: v\(latestVersion))."
            }
        } else {
            switch language {
            case .japanese:
                "開発版を実行中のためアプリ内自動アップデートは無効です。"
            case .english:
                "In-app updates are disabled in development builds."
            case .simplifiedChinese:
                "开发版本已禁用应用内自动更新。"
            case .traditionalChinese:
                "開發版本已停用應用程式內自動更新。"
            case .korean:
                "개발 빌드에서는 앱 내 자동 업데이트가 비활성화되어 있습니다."
            }
        }
    }

    /// アプリ内自動差し替えが利用できない環境における理由説明文言を生成する
    /// - Parameter eligibility: 差し替え可否判定結果
    /// - Returns: ローカライズ済み理由説明（`.eligible` 時は nil）
    public func updateInstallEligibilityReason(for eligibility: UpdateInstallEligibility) -> String? {
        switch eligibility {
        case .eligible:
            return nil
        case .developmentBuild:
            return updateDevelopmentBuildNotice(latestVersion: nil)
        case .appTranslocated:
            return switch language {
            case .japanese:
                "アプリが隔離環境（App Translocation）から起動されているため自動差し替えできません。アプリケーションフォルダへ移動するか、GitHub Releases から手動で更新してください。"
            case .english:
                "Automatic replacement is unavailable while running from App Translocation. Move the app to Applications or update manually from GitHub Releases."
            case .simplifiedChinese:
                "应用正在隔离环境（App Translocation）中运行，无法自动替换。请将应用移至“应用程序”文件夹，或从 GitHub Releases 手动更新。"
            case .traditionalChinese:
                "應用程式正在隔離環境（App Translocation）中執行，無法自動取代。請將應用程式移至「應用程式」資料夾，或從 GitHub Releases 手動更新。"
            case .korean:
                "앱이 App Translocation 격리 환경에서 실행 중이어서 자동 교체를 수행할 수 없습니다. 응용 프로그램 폴더로 이동하거나 GitHub Releases에서 수동으로 업데이트해 주세요."
            }
        case .notAppBundle:
            return switch language {
            case .japanese:
                ".app バンドルとして実行されていないため自動差し替えできません。GitHub Releases から手動で更新してください。"
            case .english:
                "Automatic replacement requires running from a .app bundle. Please update manually from GitHub Releases."
            case .simplifiedChinese:
                "当前未作为 .app 应用包运行，无法自动替换。请从 GitHub Releases 手动更新。"
            case .traditionalChinese:
                "目前未作為 .app 應用程式套件執行，無法自動取代。請從 GitHub Releases 手動更新。"
            case .korean:
                ".app 번들로 실행 중이 아니어서 자동 교체를 수행할 수 없습니다. GitHub Releases에서 수동으로 업데이트해 주세요."
            }
        case .readOnlyOrUnwritable:
            return switch language {
            case .japanese:
                "現在の配置先に書き込み権限がないか読み取り専用ボリューム上のため、自動差し替えできません。GitHub Releases から手動で更新してください。"
            case .english:
                "Automatic replacement is unavailable because the app location is read-only or not writable. Please update manually from GitHub Releases."
            case .simplifiedChinese:
                "当前位置位于只读卷或缺少写入权限，无法自动替换。请从 GitHub Releases 手动更新。"
            case .traditionalChinese:
                "目前位置位於唯讀磁碟區或缺少寫入權限，無法自動取代。請從 GitHub Releases 手動更新。"
            case .korean:
                "현재 위치가 읽기 전용 볼륨이거나 쓰기 권한이 없어 자동 교체를 수행할 수 없습니다. GitHub Releases에서 수동으로 업데이트해 주세요."
            }
        }
    }

    /// アップデート処理エラーに対応するユーザー向けメッセージを生成する
    /// - Parameter error: 発生したアップデートエラー
    /// - Returns: ローカライズ済みエラーメッセージ
    public func updateErrorMessage(for error: AppUpdateError) -> String {
        switch error {
        case .rateLimited:
            switch language {
            case .japanese:
                "GitHub API のアクセス上限に達しました。しばらく時間をおいてから再試行してください。"
            case .english:
                "GitHub API rate limit reached. Please try again later."
            case .simplifiedChinese:
                "已达到 GitHub API 访问限制，请稍后再试。"
            case .traditionalChinese:
                "已達到 GitHub API 存取上限，請稍後再試。"
            case .korean:
                "GitHub API 요청 한도에 도달했습니다. 잠시 후 다시 시도해 주세요."
            }
        case let .invalidHTTPStatus(code):
            switch language {
            case .japanese:
                "アップデートの確認に失敗しました（HTTP \(code)）。"
            case .english:
                "Failed to check for updates (HTTP \(code))."
            case .simplifiedChinese:
                "检查更新失败（HTTP \(code)）。"
            case .traditionalChinese:
                "檢查更新失敗（HTTP \(code)）。"
            case .korean:
                "업데이트 확인에 실패했습니다(HTTP \(code))."
            }
        case let .networkError(detail):
            switch language {
            case .japanese:
                "通信エラーが発生しました: \(detail)"
            case .english:
                "Network error: \(detail)"
            case .simplifiedChinese:
                "发生网络错误：\(detail)"
            case .traditionalChinese:
                "發生網路錯誤：\(detail)"
            case .korean:
                "네트워크 오류가 발생했습니다: \(detail)"
            }
        case .invalidResponse:
            switch language {
            case .japanese:
                "リリース情報の解析に失敗しました。"
            case .english:
                "Failed to parse release information."
            case .simplifiedChinese:
                "解析发布信息失败。"
            case .traditionalChinese:
                "解析發佈資訊失敗。"
            case .korean:
                "릴리스 정보를 해석하지 못했습니다."
            }
        case .noStableRelease:
            switch language {
            case .japanese:
                "利用可能な安定版リリースが見つかりませんでした。"
            case .english:
                "No stable release was found."
            case .simplifiedChinese:
                "未找到可用的稳定版本。"
            case .traditionalChinese:
                "找不到可用的穩定版本。"
            case .korean:
                "사용 가능한 안정 버전을 찾을 수 없습니다."
            }
        case let .missingReleaseAsset(expectedName):
            switch language {
            case .japanese:
                "配布用ファイル（\(expectedName)）がリリースに見つかりませんでした。"
            case .english:
                "Release asset (\(expectedName)) was not found."
            case .simplifiedChinese:
                "在发布中未找到分发文件（\(expectedName)）。"
            case .traditionalChinese:
                "在發佈中找不到發佈檔案（\(expectedName)）。"
            case .korean:
                "릴리스에서 배포 파일(\(expectedName))을 찾을 수 없습니다."
            }
        case .untrustedDownloadURL:
            switch language {
            case .japanese:
                "信頼できないダウンロード URL が検出されたため処理を中止しました。"
            case .english:
                "Update aborted because an untrusted download URL was detected."
            case .simplifiedChinese:
                "检测到不受信任的下载链接，已中止更新。"
            case .traditionalChinese:
                "偵測到不受信任的下載網址，已中止更新。"
            case .korean:
                "신뢰할 수 없는 다운로드 URL이 감지되어 업데이트를 중단했습니다."
            }
        case .checksumMismatch:
            switch language {
            case .japanese:
                "ダウンロードファイルのチェックサム検証に失敗したため更新を中止しました。"
            case .english:
                "Update aborted because the downloaded file checksum did not match."
            case .simplifiedChinese:
                "下载文件校验和验证失败，已中止更新。"
            case .traditionalChinese:
                "下載檔案雜湊值驗證失敗，已中止更新。"
            case .korean:
                "다운로드한 파일의 체크섬 검증에 실패하여 업데이트를 중단했습니다."
            }
        case let .extractionFailed(detail):
            switch language {
            case .japanese:
                "アップデートファイルの展開に失敗しました: \(detail)"
            case .english:
                "Failed to extract the update archive: \(detail)"
            case .simplifiedChinese:
                "解压更新文件失败：\(detail)"
            case .traditionalChinese:
                "解壓縮更新檔案失敗：\(detail)"
            case .korean:
                "업데이트 파일 압축 해제에 실패했습니다: \(detail)"
            }
        case let .invalidBundleMetadata(detail):
            switch language {
            case .japanese:
                "ダウンロードされたアプリのバンドル情報検証に失敗しました（\(detail)）。"
            case .english:
                "Downloaded app bundle metadata verification failed (\(detail))."
            case .simplifiedChinese:
                "已下载应用的包信息验证失败（\(detail)）。"
            case .traditionalChinese:
                "已下載應用程式的套件資訊驗證失敗（\(detail)）。"
            case .korean:
                "다운로드한 앱 번들 메타데이터 검증에 실패했습니다(\(detail))."
            }
        case let .codeSignatureInvalid(detail):
            switch language {
            case .japanese:
                "コード署名の検証に失敗したため更新を中止しました（\(detail)）。"
            case .english:
                "Update aborted because code signature verification failed (\(detail))."
            case .simplifiedChinese:
                "代码签名验证失败，已中止更新（\(detail)）。"
            case .traditionalChinese:
                "程式碼簽章驗證失敗，已中止更新（\(detail)）。"
            case .korean:
                "코드 서명 검증에 실패하여 업데이트를 중단했습니다(\(detail))."
            }
        case .teamIdentifierMismatch:
            switch language {
            case .japanese:
                "署名者（Developer ID）の一致を確認できなかったため更新を中止しました。"
            case .english:
                "Update aborted because the Developer ID Team Identifier could not be matched."
            case .simplifiedChinese:
                "无法确认签名者（Developer ID）一致，已中止更新。"
            case .traditionalChinese:
                "無法確認簽署者（Developer ID）一致，已中止更新。"
            case .korean:
                "서명자(Developer ID) 일치를 확인할 수 없어 업데이트를 중단했습니다."
            }
        case let .installNotEligible(eligibility):
            updateInstallEligibilityReason(for: eligibility) ?? updateDevelopmentBuildNotice(latestVersion: nil)
        case let .helperLaunchFailed(detail):
            switch language {
            case .japanese:
                "アップデート適用プロセスの起動に失敗しました: \(detail)"
            case .english:
                "Failed to launch the update installer helper: \(detail)"
            case .simplifiedChinese:
                "启动更新安装助手失败：\(detail)"
            case .traditionalChinese:
                "啟動更新安裝輔助程式失敗：\(detail)"
            case .korean:
                "업데이트 적용 프로세스 시작에 실패했습니다: \(detail)"
            }
        }
    }
}
