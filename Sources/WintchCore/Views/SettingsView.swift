import SwiftUI

/// Wintch の最小限の設定項目（ショートカット・ログイン時自動起動・権限状態）を提供する設定画面
public struct SettingsView: View {
    /// 設定画面の状態管理 ViewModel
    private let viewModel: SettingsViewModel

    /// 設定ビューを初期化する
    /// - Parameter viewModel: 設定 ViewModel
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    /// 修飾キー選択用の双方向バインディング
    private var modifierBinding: Binding<ModifierKeyOption> {
        Binding(
            get: { viewModel.shortcut.modifier },
            set: { viewModel.updateModifier($0) }
        )
    }

    /// トリガーキー選択用の双方向バインディング
    private var triggerBinding: Binding<TriggerKeyOption> {
        Binding(
            get: { viewModel.shortcut.trigger },
            set: { viewModel.updateTrigger($0) }
        )
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
            Section("起動ショートカット") {
                Picker("修飾キー", selection: modifierBinding) {
                    ForEach(ModifierKeyOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }

                Picker("トリガーキー", selection: triggerBinding) {
                    ForEach(TriggerKeyOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
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
        .frame(width: 440, height: 340)
        .onAppear {
            viewModel.refreshStatus()
        }
    }
}
