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
            Label(tab.title, systemImage: tab.systemImage)
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
        Section("一般") {
            Toggle("ログイン時に自動起動", isOn: launchAtLoginBinding)

            if let errorMessage = viewModel.launchAtLoginError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    /// 「スイッチャー」メニューの設定セクション
    private var switcherSection: some View {
        Section("通常スイッチャー（ホールド式）") {
            LabeledContent("起動ショートカット") {
                ShortcutRecorderView(
                    displayString: viewModel.shortcut.displayString,
                    isRecording: viewModel.isRecordingNormalShortcut,
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

            LabeledContent("操作方法") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("次へ: \(viewModel.shortcut.displayString)")
                    Text("前へ: \(viewModel.shortcut.reverseDisplayString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.shortcut.conflictsWithSystemSwitcher {
                Label(
                    "Command + Tab は macOS 標準のアプリスイッチャーを上書きします。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if viewModel.shortcutValidationTarget == .normal,
               let validationError = viewModel.shortcutValidationError {
                Label(validationError, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("⌘ / ⌥ / ⌃ のいずれか1つ以上を含めて入力してください（⇧ は逆順移動用）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("表示形式", selection: normalDisplayStyleBinding) {
                ForEach(SwitcherDisplayStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }

            if viewModel.normalDisplayStyle == .capture {
                if viewModel.screenRecordingStatus == .denied {
                    screenRecordingDeniedGuideView
                } else {
                    Text("ウィンドウのサムネイルをグリッド表示します（リスト型より多くのメモリを使用する場合があります）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 「ランチャー」メニューの設定セクション
    private var launcherSection: some View {
        Section("検索ランチャー（トグル式）") {
            LabeledContent("起動ショートカット") {
                ShortcutRecorderView(
                    displayString: viewModel.launcherShortcut.displayString,
                    isRecording: viewModel.isRecordingLauncherShortcut,
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
            } else {
                Text("⌘ / ⌥ / ⌃ のいずれか1つ以上を含めて入力してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("表示形式", selection: launcherDisplayStyleBinding) {
                ForEach(LauncherDisplayStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }

            if viewModel.launcherDisplayStyle == .capture {
                if viewModel.screenRecordingStatus == .denied {
                    screenRecordingDeniedGuideView
                } else {
                    Text("各ウィンドウ候補の行にサムネイルを表示します（リスト型より多くのメモリを使用する場合があります）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 「システム」メニュー内のシステム権限セクション
    private var systemPermissionsSection: some View {
        Section("システム権限") {
            LabeledContent("アクセシビリティ権限") {
                if viewModel.permissionStatus == .granted {
                    Label("許可済み", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 8) {
                        Label("未許可", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Button("設定を開く") {
                            viewModel.openAccessibilitySettings()
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            // オプトイン原則に従い、通常スイッチャーまたは検索ランチャーでキャプチャ表示型が選択されている場合のみ画面収録権限欄を表示する
            if viewModel.usesCaptureDisplayStyle {
                LabeledContent("画面収録権限") {
                    if viewModel.screenRecordingStatus == .granted {
                        Label("許可済み", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 8) {
                            Label("未許可", systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                            Button("設定を開く") {
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
        Section("アプリ情報") {
            LabeledContent("アプリ名") {
                Text(appIdentity.displayName)
            }

            LabeledContent("バージョン") {
                Text(versionInfo.displayVersionText)
                    .textSelection(.enabled)
            }
        }
    }

    /// 画面収録権限が未許可のときに表示する共通の権限案内・リクエスト導線ビュー
    private var screenRecordingDeniedGuideView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                "ウィンドウのキャプチャ表示には「画面収録」権限の許可が必要です。",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)

            HStack(spacing: 12) {
                Button("権限をリクエスト") {
                    viewModel.requestScreenRecordingPermission()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("システム設定を開く") {
                    viewModel.openScreenRecordingSettings()
                }
                .buttonStyle(.link)
                .font(.caption)

                Button("再確認") {
                    viewModel.refreshStatus()
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            Text("※ macOS の仕様上、権限を許可した後にアプリの再起動が必要になる場合があります。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
