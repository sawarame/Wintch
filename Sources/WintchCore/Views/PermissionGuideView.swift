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
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "hand.raised.shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("アクセシビリティ権限の許可が必要です")
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("ショートカット検知とウィンドウ切り替えの操作にのみ使用します")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("1. 下の「システム設定を開く」をクリックします", systemImage: "1.circle.fill")
                    .fixedSize(horizontal: false, vertical: true)
                Label(appIdentity.accessibilitySwitchInstruction, systemImage: "2.circle.fill")
                    .fixedSize(horizontal: false, vertical: true)
                Label("3. 許可を検知すると自動的に利用可能になります", systemImage: "3.circle.fill")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // 複数行折り返し時に SwiftUI による縦方向圧縮で末尾が途切れないよう固定する
            Text("※ リスト型・アイコン型では「画面収録」権限を使用しません（スイッチャーまたは検索ランチャーでキャプチャ表示型を選択した場合のみ任意で使用します）。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
        .frame(width: Self.preferredWidth)
    }
}
