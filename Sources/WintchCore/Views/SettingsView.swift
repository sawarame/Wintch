import AppKit
import SwiftUI

/// 左サイドバー付きの 4 メニュー構成（一般・スイッチャー・ランチャー・システム）を提供する設定画面
public struct SettingsView: View {
    /// 設定ウィンドウの固定横幅（AppCoordinator と共通参照）
    public static let preferredWidth: CGFloat = 640

    /// 設定ウィンドウの固定高さ（AppCoordinator と共通参照）
    public static let preferredHeight: CGFloat = 460

    /// 左サイドバーの折りたたみ不可な固定横幅
    public static let sidebarWidth: CGFloat = 170

    /// 設定画面の状態管理 ViewModel
    private let viewModel: SettingsViewModel

    /// 表示対象のアプリ識別情報（開発版・配布版名称の切り替え用）
    private let appIdentity: AppIdentity

    /// 表示対象のアプリバージョン情報
    private let versionInfo: AppVersionInfo

    /// 設定ビューを初期化する
    /// - Parameters:
    ///   - viewModel: 設定 ViewModel
    ///   - appIdentity: 表示するアプリ識別情報（既定値はメインバンドルから取得）
    ///   - versionInfo: 表示するバージョン情報（既定値はメインバンドルから取得）
    public init(
        viewModel: SettingsViewModel,
        appIdentity: AppIdentity = .current,
        versionInfo: AppVersionInfo = .current
    ) {
        self.viewModel = viewModel
        self.appIdentity = appIdentity
        self.versionInfo = versionInfo
    }

    /// サイドバーの選択メニュー用の双方向バインディング
    private var selectedTabBinding: Binding<SettingsTab> {
        Binding(
            get: { viewModel.selectedTab },
            set: { viewModel.selectTab($0) }
        )
    }

    /// ログイン時自動起動用の双方向バインディング
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isLaunchAtLoginEnabled },
            set: { viewModel.setLaunchAtLogin($0) }
        )
    }

    /// バージョンアップ自動チェック用の双方向バインディング
    private var autoCheckForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isAutoCheckForUpdatesEnabled },
            set: { viewModel.setAutoCheckForUpdates($0) }
        )
    }

    /// 通常スイッチャー表示形式用の双方向バインディング
    private var normalDisplayStyleBinding: Binding<SwitcherDisplayStyle> {
        Binding(
            get: { viewModel.normalDisplayStyle },
            set: { viewModel.updateNormalDisplayStyle($0) }
        )
    }

    /// 検索ランチャー表示形式用の双方向バインディング
    private var launcherDisplayStyleBinding: Binding<LauncherDisplayStyle> {
        Binding(
            get: { viewModel.launcherDisplayStyle },
            set: { viewModel.updateLauncherDisplayStyle($0) }
        )
    }

    /// 通常スイッチャーのアプリグルーピング用の双方向バインディング
    private var normalGroupingBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isNormalSwitcherGroupedByApp },
            set: { viewModel.updateNormalSwitcherGrouping($0) }
        )
    }

    /// 検索ランチャーのアプリグルーピング用の双方向バインディング
    private var launcherGroupingBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isLauncherGroupedByApp },
            set: { viewModel.updateLauncherGrouping($0) }
        )
    }

    /// アプリ表示言語設定用の双方向バインディング
    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { viewModel.appLanguage },
            set: { viewModel.updateAppLanguage($0) }
        )
    }

    /// 現在の解決済み言語に対応するローカライズ文言テーブル
    private var strings: AppStrings {
        viewModel.strings
    }

    /// ビューの本体構築（折りたたみ不可の固定 2 ペイン構成）
    public var body: some View {
        HStack(spacing: 0) {
            sidebarView
            Divider()
            detailContentView
        }
        .frame(width: Self.preferredWidth, height: Self.preferredHeight)
        .onAppear {
            viewModel.refreshStatus()
        }
        .onDisappear {
            viewModel.cancelAllRecordings()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            viewModel.cancelAllRecordings()
        }
    }

    /// 左ペインに固定幅で配置するサイドバーメニュー
    private var sidebarView: some View {
        List(SettingsTab.allCases, selection: selectedTabBinding) { tab in
            Label(tab.title(in: viewModel.resolvedLanguage), systemImage: tab.systemImage)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .scrollDisabled(true)
        .frame(width: Self.sidebarWidth)
        .frame(maxHeight: .infinity)
    }

    /// 右ペインに表示する選択中カテゴリの設定フォーム
    private var detailContentView: some View {
        Form {
            switch viewModel.selectedTab {
            case .general:
                generalSection
            case .switcher:
                switcherSection
            case .launcher:
                launcherSection
            case .system:
                systemPermissionsSection
                appInfoSection
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 「一般」メニューの設定セクション
    private var generalSection: some View {
        Section(SettingsTab.general.title(in: viewModel.resolvedLanguage)) {
            Toggle(strings.settingsLaunchAtLogin, isOn: launchAtLoginBinding)

            if let errorMessage = viewModel.launchAtLoginError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(strings.settingsAutoCheckForUpdates, isOn: autoCheckForUpdatesBinding)

                Text(strings.settingsAutoCheckForUpdatesCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker(strings.settingsLanguageLabel, selection: appLanguageBinding) {
                ForEach(AppLanguage.allCases) { languageOption in
                    Text(languageOption.pickerDisplayName(in: viewModel.resolvedLanguage))
                        .tag(languageOption)
                }
            }
        }
    }

    /// 「スイッチャー」メニューの設定セクション
    private var switcherSection: some View {
        Section(strings.settingsNormalSwitcherSectionTitle) {
            LabeledContent(strings.settingsShortcutLabel) {
                ShortcutRecorderView(
                    displayString: viewModel.shortcut.displayString,
                    isRecording: viewModel.isRecordingNormalShortcut,
                    recordingPrompt: strings.shortcutRecorderPrompt,
                    onBeginRecording: {
                        viewModel.beginRecordingNormalShortcut()
                    },
                    onCapture: { captured in
                        viewModel.recordNormalShortcut(captured.toNormalShortcut())
                    },
                    onCancel: {
                        viewModel.cancelRecordingNormalShortcut()
                    }
                )
            }

            LabeledContent(strings.settingsControlsLabel) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(strings.controlsNext(viewModel.shortcut.displayString))
                    Text(strings.controlsPrevious(viewModel.shortcut.reverseDisplayString))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.shortcut.conflictsWithSystemSwitcher {
                Label(
                    strings.settingsCommandTabWarning,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.shortcutValidationTarget == .normal,
               let validationError = viewModel.shortcutValidationError {
                Label(validationError, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(strings.settingsNormalShortcutHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker(strings.settingsDisplayStyleLabel, selection: normalDisplayStyleBinding) {
                ForEach(SwitcherDisplayStyle.allCases, id: \.self) { style in
                    Text(style.displayName(in: viewModel.resolvedLanguage)).tag(style)
                }
            }

            Toggle(strings.groupByAppToggle, isOn: normalGroupingBinding)

            if viewModel.normalDisplayStyle == .capture {
                if viewModel.screenRecordingStatus == .denied {
                    screenRecordingDeniedGuideView
                } else {
                    Text(strings.settingsNormalCaptureDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 「ランチャー」メニューの設定セクション
    private var launcherSection: some View {
        Section(strings.settingsLauncherSectionTitle) {
            LabeledContent(strings.settingsShortcutLabel) {
                ShortcutRecorderView(
                    displayString: viewModel.launcherShortcut.displayString,
                    isRecording: viewModel.isRecordingLauncherShortcut,
                    recordingPrompt: strings.shortcutRecorderPrompt,
                    onBeginRecording: {
                        viewModel.beginRecordingLauncherShortcut()
                    },
                    onCapture: { captured in
                        viewModel.recordLauncherShortcut(captured.toLauncherShortcut())
                    },
                    onCancel: {
                        viewModel.cancelRecordingLauncherShortcut()
                    }
                )
            }

            if viewModel.shortcutValidationTarget == .launcher,
               let validationError = viewModel.shortcutValidationError {
                Label(validationError, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(strings.settingsLauncherShortcutHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker(strings.settingsDisplayStyleLabel, selection: launcherDisplayStyleBinding) {
                ForEach(LauncherDisplayStyle.allCases, id: \.self) { style in
                    Text(style.displayName(in: viewModel.resolvedLanguage)).tag(style)
                }
            }

            Toggle(strings.groupByAppToggle, isOn: launcherGroupingBinding)

            if viewModel.launcherDisplayStyle == .capture {
                if viewModel.screenRecordingStatus == .denied {
                    screenRecordingDeniedGuideView
                } else {
                    Text(strings.settingsLauncherCaptureDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 「システム」メニュー内のシステム権限セクション
    private var systemPermissionsSection: some View {
        Section(strings.settingsSystemPermissionsSectionTitle) {
            LabeledContent(strings.settingsAccessibilityPermissionLabel) {
                if viewModel.permissionStatus == .granted {
                    Label(strings.settingsPermissionGranted, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 8) {
                        Label(strings.settingsPermissionDenied, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Button(strings.settingsOpenSettingsButton) {
                            viewModel.openAccessibilitySettings()
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            // オプトイン原則に従い、通常スイッチャーまたは検索ランチャーでキャプチャ表示型が選択されている場合のみ画面収録権限欄を表示する
            if viewModel.usesCaptureDisplayStyle {
                LabeledContent(strings.settingsScreenRecordingPermissionLabel) {
                    if viewModel.screenRecordingStatus == .granted {
                        Label(strings.settingsPermissionGranted, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 8) {
                            Label(strings.settingsPermissionDenied, systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                            Button(strings.settingsOpenSettingsButton) {
                                viewModel.openScreenRecordingSettings()
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }
        }
    }

    /// 「システム」メニュー内のアプリ情報セクション（旧「Wintchについて」から統合）
    private var appInfoSection: some View {
        Section(strings.settingsAppInfoSectionTitle) {
            LabeledContent(strings.settingsAppNameLabel) {
                Text(appIdentity.displayName)
            }

            LabeledContent(strings.settingsVersionLabel) {
                Text(versionInfo.displayVersionText(in: viewModel.resolvedLanguage))
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Button(strings.settingsCheckForUpdatesButton) {
                        viewModel.checkForUpdatesManually()
                    }
                    .disabled(viewModel.isCheckingForUpdates)

                    if viewModel.isCheckingForUpdates {
                        ProgressView()
                            .controlSize(.small)
                        Text(strings.settingsCheckingForUpdates)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let statusMessage = viewModel.manualUpdateStatusMessage {
                    manualUpdateFeedbackView(message: statusMessage)
                }
            }
        }
    }

    /// 手動アップデート確認の結果メッセージと必要に応じた GitHub Releases 導線を表示する
    /// - Parameter message: ローカライズ済み状態メッセージ
    /// - Returns: 状態に応じたフィードバックビュー
    @ViewBuilder
    private func manualUpdateFeedbackView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch viewModel.manualUpdateCheckState {
            case .upToDate:
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            case .updateAvailable:
                Label(message, systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .fixedSize(horizontal: false, vertical: true)
            case .developmentBuild:
                Label(message, systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed:
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            case .idle, .checking:
                EmptyView()
            }

            if viewModel.shouldShowOpenReleasesLink {
                Button(strings.settingsOpenGitHubReleasesButton) {
                    viewModel.openUpdateReleasePage()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    /// 画面収録権限が未許可のときに表示する共通の権限案内・リクエスト導線ビュー
    private var screenRecordingDeniedGuideView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                strings.settingsScreenRecordingRequiredMessage,
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(strings.settingsRequestPermissionButton) {
                    viewModel.requestScreenRecordingPermission()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(strings.openSystemSettingsButton) {
                    viewModel.openScreenRecordingSettings()
                }
                .buttonStyle(.link)
                .font(.caption)

                Button(strings.recheckButton) {
                    viewModel.refreshStatus()
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            Text(strings.settingsScreenRecordingRestartNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
