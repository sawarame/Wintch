import SwiftUI

/// スイッチャーパネル内のルートコンテナビュー
/// 通常モード時は選択中の表示形式（リスト型／アイコン型／キャプチャ表示型）に応じたビューを描画し、
/// 検索ランチャー時は縦型リストビュー（リスト型またはキャプチャサムネイル付きリスト型）を描画する
public struct SwitcherContentView: View {
    /// スイッチャーの状態管理を行う ViewModel
    private let viewModel: SwitcherViewModel

    /// コンテンツサイズ変化時にパネル側へリサイズを通知するコールバック
    private let onContentSizeChanged: ((CGSize) -> Void)?

    /// コンテンツビューを初期化する
    /// - Parameters:
    ///   - viewModel: スイッチャー ViewModel
    ///   - onContentSizeChanged: コンテンツサイズ変化時の通知クロージャ
    public init(
        viewModel: SwitcherViewModel,
        onContentSizeChanged: ((CGSize) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onContentSizeChanged = onContentSizeChanged
    }

    /// 現在のモードと表示形式に応じて表示ビューを切り替える本体構築
    public var body: some View {
        Group {
            // グルーピング ON 時は通常スイッチャーのアイコン型・キャプチャ表示型も
            // 検索ランチャーのキャプチャ表示型と同一の縦型リストビュー（ディスプレイ幅連動）で表示する
            if viewModel.usesGridLayoutForCurrentMode {
                switch viewModel.normalDisplayStyle {
                case .icon:
                    SwitcherIconGridView(
                        viewModel: viewModel,
                        onContentSizeChanged: onContentSizeChanged
                    )
                case .capture:
                    SwitcherCaptureGridView(
                        viewModel: viewModel,
                        onContentSizeChanged: onContentSizeChanged
                    )
                case .list:
                    SwitcherListView(
                        viewModel: viewModel,
                        onContentSizeChanged: onContentSizeChanged
                    )
                }
            } else {
                SwitcherListView(
                    viewModel: viewModel,
                    onContentSizeChanged: onContentSizeChanged
                )
            }
        }
    }
}
