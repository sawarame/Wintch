import SwiftUI

/// アクセシビリティ権限が未許可の際に手順を案内しシステム設定へ誘導するビュー
public struct PermissionGuideView: View {
    /// 権限誘導ダイアログの基準横幅
    public static let preferredWidth: CGFloat = 460

    /// 権限誘導ウィンドウの最小高さ下限
    public static let minimumHeight: CGFloat = 280

    /// 誘導画面の状態管理 ViewModel
    private let viewModel: PermissionGuideViewModel

    /// 手順案内文に表示するアプリ識別情報
    private let appIdentity: AppIdentity

    /// 権限誘導ビューを初期化する
    /// - Parameters:
    ///   - viewModel: 権限誘導 ViewModel
    ///   - appIdentity: アプリ識別情報（既定値はメインバンドルから取得）
    public init(
        viewModel: PermissionGuideViewModel,
        appIdentity: AppIdentity = .current
    ) {
        self.viewModel = viewModel
        self.appIdentity = appIdentity
    }

    /// ビューの本体構築
    public var body: some View {
        let strings = viewModel.strings

        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "hand.raised.shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.permissionGuideTitle)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(strings.permissionGuideSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label(strings.permissionGuideStep1, systemImage: "1.circle.fill")
                    .fixedSize(horizontal: false, vertical: true)
                Label(
                    appIdentity.accessibilitySwitchInstruction(in: viewModel.resolvedLanguage),
                    systemImage: "2.circle.fill"
                )
                    .fixedSize(horizontal: false, vertical: true)
                Label(strings.permissionGuideStep3, systemImage: "3.circle.fill")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // 複数行折り返し時に SwiftUI による縦方向圧縮で末尾が途切れないよう固定する
            Text(strings.permissionGuideScreenRecordingNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(strings.recheckButton) {
                    viewModel.refreshStatus()
                }

                Spacer()

                Button(strings.openSystemSettingsButton) {
                    viewModel.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: Self.preferredWidth)
    }
}
