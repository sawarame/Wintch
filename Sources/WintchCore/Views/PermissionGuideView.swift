import SwiftUI

/// アクセシビリティ権限が未許可の際に手順を案内しシステム設定へ誘導するビュー
public struct PermissionGuideView: View {
    /// 誘導画面の状態管理 ViewModel
    private let viewModel: PermissionGuideViewModel

    /// 権限誘導ビューを初期化する
    /// - Parameter viewModel: 権限誘導 ViewModel
    public init(viewModel: PermissionGuideViewModel) {
        self.viewModel = viewModel
    }

    /// ビューの本体構築
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "hand.raised.shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("アクセシビリティ権限の許可が必要です")
                        .font(.title3.bold())
                    Text("ショートカット検知とウィンドウ切り替えの操作にのみ使用します")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("1. 下の「システム設定を開く」をクリックします", systemImage: "1.circle.fill")
                Label("2. 一覧の「Wintch」のスイッチをオンにします", systemImage: "2.circle.fill")
                Label("3. 許可を検知すると自動的に利用可能になります", systemImage: "3.circle.fill")
            }
            .font(.callout)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("※ プライバシー保護のため、「画面収録」権限は一切使用しません。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("再確認") {
                    viewModel.refreshStatus()
                }

                Spacer()

                Button("システム設定を開く") {
                    viewModel.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
