import CoreGraphics

/// ディスプレイ全体矩形と有効表示領域の組を表す値型スナップショット
public struct ScreenFrameSnapshot: Sendable, Equatable {
    /// ディスプレイ全体の矩形領域（グローバル座標系）
    public let frame: CGRect

    /// メニューバーおよび Dock を除いた有効表示領域（グローバル座標系）
    public let visibleFrame: CGRect

    /// ディスプレイ領域スナップショットを初期化する
    /// - Parameters:
    ///   - frame: ディスプレイ全体の矩形
    ///   - visibleFrame: 有効表示領域の矩形
    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// 標準ウィンドウの表示先ディスプレイ選択および中央配置座標を計算する純粋ロジック群
public enum WindowPlacement {
    /// カーソル位置およびフォールバック情報からウィンドウ配置対象の有効表示領域を決定する
    /// - Parameters:
    ///   - cursorLocation: 現在のマウスカーソル座標
    ///   - screens: 利用可能なディスプレイ一覧
    ///   - fallbackVisibleFrame: カーソル所在ディスプレイが見つからない場合の優先フォールバック領域
    /// - Returns: 配置対象ディスプレイの有効表示領域（利用可能なディスプレイがない場合は nil）
    public static func targetVisibleFrame(
        cursorLocation: CGPoint,
        screens: [ScreenFrameSnapshot],
        fallbackVisibleFrame: CGRect?
    ) -> CGRect? {
        if let cursorScreen = screens.first(where: { $0.frame.contains(cursorLocation) }) {
            return cursorScreen.visibleFrame
        }
        return fallbackVisibleFrame ?? screens.first?.visibleFrame
    }

    /// 指定された有効表示領域の中央にウィンドウを配置するための原点座標を計算する
    /// - Parameters:
    ///   - windowSize: 配置対象ウィンドウの幅・高さ
    ///   - visibleFrame: 配置先ディスプレイの有効表示領域
    /// - Returns: タイトルバーが画面外へはみ出さないようクランプされた左下原点座標
    public static func centeredOrigin(windowSize: CGSize, in visibleFrame: CGRect) -> CGPoint {
        let idealX = visibleFrame.midX - (windowSize.width / 2.0)
        let idealY = visibleFrame.midY - (windowSize.height / 2.0)

        let clampedX: CGFloat
        if windowSize.width >= visibleFrame.width {
            clampedX = visibleFrame.minX
        } else {
            let maxX = visibleFrame.maxX - windowSize.width
            clampedX = min(max(idealX, visibleFrame.minX), maxX)
        }

        let clampedY: CGFloat
        if windowSize.height >= visibleFrame.height {
            // ウィンドウ高さが有効領域を超える場合でも上端タイトルバーがメニューバー下に収まるよう調整する
            clampedY = visibleFrame.maxY - windowSize.height
        } else {
            let maxY = visibleFrame.maxY - windowSize.height
            clampedY = min(max(idealY, visibleFrame.minY), maxY)
        }

        return CGPoint(x: clampedX, y: clampedY)
    }
}
