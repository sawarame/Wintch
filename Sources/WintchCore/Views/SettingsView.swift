import AppKit
import SwiftUI

/// Wintch の最小限の設定項目（通常/ランチャーショートカット・ログイン時自動起動・権限状態）を提供する設定画面
public struct SettingsView: View {
    /// 設定画面の状態管理 ViewModel
    private let viewModel: SettingsViewModel

    /// 設定ビューを初期化する
    /// - Parameter viewModel: 設定 ViewModel
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    /// ログイン時自動起動用の双方向バインディング
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isLaunchAtLoginEnabled },
            set: { viewModel.setLaunchAtLogin($0) }
        )
    }

    /// ビューの本体構築
    public var body: some View {
        Form {
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
            }

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
            }

            Section("一般") {
                Toggle("ログイン時に自動起動", isOn: launchAtLoginBinding)

                if let errorMessage = viewModel.launchAtLoginError {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

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
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 430)
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
}
