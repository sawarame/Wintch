import SwiftUI

/// スイッチャーパネル内のルートコンテナビュー
/// 通常モードかつ表示形式がキャプチャ表示型のときのみグリッドビューを描画し、それ以外は既存のリストビューを描画する
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
            if viewModel.mode == .normal && viewModel.normalDisplayStyle == .capture {
                SwitcherCaptureGridView(
                    viewModel: viewModel,
                    onContentSizeChanged: onContentSizeChanged
                )
            } else {
                SwitcherListView(
                    viewModel: viewModel,
                    onContentHeightChanged: { newHeight in
                        onContentSizeChanged?(CGSize(width: 520, height: newHeight))
                    }
                )
            }
        }
    }
}
