import SwiftUI

/// 新バージョン検出時に表示する更新確認・進捗ダイアログビュー
public struct UpdatePromptView: View {
    /// 更新ダイアログの推奨横幅（AppCoordinator と共通参照）
    public static let preferredWidth: CGFloat = 480

    /// 更新ダイアログの推奨高さ（AppCoordinator と共通参照）
    public static let preferredHeight: CGFloat = 380

    /// 更新確認ダイアログの状態管理 ViewModel
    private let viewModel: UpdateViewModel

    /// 表示対象のアプリ識別情報
    private let appIdentity: AppIdentity

    /// 現在の解決済み言語に対応するローカライズ文言テーブル
    private var strings: AppStrings {
        viewModel.strings
    }

    /// UpdatePromptView を初期化する
    /// - Parameters:
    ///   - viewModel: 更新ダイアログ ViewModel
    ///   - appIdentity: アプリ識別情報
    public init(viewModel: UpdateViewModel, appIdentity: AppIdentity = .current) {
        self.viewModel = viewModel
        self.appIdentity = appIdentity
    }

    /// ビューの本体構築
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            releaseNotesSection
            statusSection
            Spacer(minLength: 0)
            footerButtons
        }
        .padding(20)
        .frame(width: Self.preferredWidth, height: Self.preferredHeight)
    }

    /// ヘッダー（アイコン・見出し・バージョン遷移表示）
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(strings.updateDialogTitle)
                    .font(.headline)

                if let release = viewModel.release {
                    Text("\(appIdentity.displayName): \(viewModel.currentVersionText) → \(release.version.normalizedString)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// スクロール可能なリリースノート概要と GitHub リンク
    private var releaseNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(strings.updateReleaseNotesSectionTitle)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button(strings.updateViewOnGitHubButton) {
                    viewModel.openReleasePage()
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            ScrollView {
                let notes = viewModel.release?.releaseNotes ?? ""
                Text(notes.isEmpty ? strings.updateReleaseNotesEmpty : notes)
                    .font(.callout)
                    .foregroundStyle(notes.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 170)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    /// 進捗表示・差し替え不可理由・エラーメッセージ領域
    @ViewBuilder
    private var statusSection: some View {
        if let progressMessage = viewModel.progressMessage {
            VStack(alignment: .leading, spacing: 6) {
                if let fraction = viewModel.downloadFractionCompleted {
                    ProgressView(value: fraction, total: 1.0)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
                Text(progressMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let errorMessage = viewModel.errorMessage {
            VStack(alignment: .leading, spacing: 6) {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)

                Button(strings.settingsOpenGitHubReleasesButton) {
                    viewModel.openReleasePage()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        } else if let eligibilityReason = viewModel.eligibilityNoticeMessage {
            Label(eligibilityReason, systemImage: "info.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 下部のアクションボタン群
    private var footerButtons: some View {
        HStack(spacing: 10) {
            Button(strings.updateSkipVersionButton) {
                viewModel.skipThisVersion()
            }
            .disabled(viewModel.isUpdating)

            Spacer()

            Button(strings.updateLaterButton) {
                viewModel.deferUpdate()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(viewModel.isUpdating)

            if viewModel.canInstallInPlace {
                Button(strings.updateNowButton) {
                    viewModel.startUpdate()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isUpdating)
            } else {
                Button(strings.settingsOpenGitHubReleasesButton) {
                    viewModel.openReleasePage()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isUpdating)
            }
        }
    }
}
