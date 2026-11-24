import SwiftUI

/// ウィンドウ／アプリ終了処理の待機中に表示する円形スピナーインジケータービュー
struct SwitcherClosingIndicatorView: View {
    /// 現在の環境カラースキーム
    @Environment(\.colorScheme) private var colorScheme

    /// 暗い背景・選択ハイライト上で明るいスピナー描画を強制するかどうか
    let usesLightAppearance: Bool

    /// インジケーターのコントロールサイズ
    let controlSize: ControlSize

    /// クローズ処理中スピナービューを初期化する
    /// - Parameters:
    ///   - usesLightAppearance: アクセントカラーや暗色オーバーレイ上で白系描画を強制する場合は true
    ///   - controlSize: SwiftUI のコントロールサイズ（既定値は `.small`）
    init(
        usesLightAppearance: Bool,
        controlSize: ControlSize = .small
    ) {
        self.usesLightAppearance = usesLightAppearance
        self.controlSize = controlSize
    }

    /// コントロールサイズに対応する固定の一辺サイズ（レイアウト揺れ防止用）
    private var dimension: CGFloat {
        switch controlSize {
        case .mini:
            12
        case .small:
            16
        case .regular:
            32
        default:
            32
        }
    }

    /// ビューの本体構築
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(controlSize)
            .frame(width: dimension, height: dimension)
            // macOS の NSProgressIndicator は effectiveAppearance に連動するため、
            // 選択行（アクセント背景）や暗色オーバーレイ上では .dark を指定して視認性を確保する
            .environment(\.colorScheme, usesLightAppearance ? .dark : colorScheme)
    }
}
