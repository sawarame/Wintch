import CoreGraphics

/// スイッチャー／検索ランチャーパネルのディスプレイに対する垂直配置スタイル
public enum SwitcherPanelVerticalPlacement: Equatable, Sendable {
    /// ディスプレイ上部寄りにパネル上端を配置し、下方向へ広く一覧を表示するモード
    case upperAnchored
    /// ディスプレイ有効領域の中央に配置する従来モード（グルーピング OFF のキャプチャ表示型など）
    case centered
}

/// スイッチャー／検索ランチャーパネルの垂直配置判定・座標計算・一覧最大高さ算出を行う純粋ロジック群
public enum SwitcherPanelLayout {
    /// 上寄せ配置時にディスプレイ有効高さに対して確保する上端オフセット比率
    public static let upperTopOffsetRatio: CGFloat = 0.14

    /// 上寄せ配置時に確保する上端オフセットの最小値（ポイント）
    public static let minUpperTopOffset: CGFloat = 32

    /// 上寄せ配置時にディスプレイ有効高さに対して確保する下端余白比率
    public static let upperBottomMarginRatio: CGFloat = 0.10

    /// 上寄せ配置時に確保する下端余白の最小値（ポイント）
    public static let minUpperBottomMargin: CGFloat = 24

    /// 検索ランチャーの検索入力ヘッダおよび区切り線のために予約する高さ（ポイント）
    public static let searchHeaderReservedHeight: CGFloat = 50

    /// 画面収録権限未許可バナーおよび区切り線のために予約する高さ（ポイント）
    public static let permissionBannerReservedHeight: CGFloat = 56

    /// スクロール領域として最低限確保する高さの下限（ポイント）
    public static let minScrollHeight: CGFloat = 220

    /// 従来の中央配置キャプチャ表示型グリッドにおけるディスプレイ有効高さ比率
    public static let centeredCaptureGridHeightRatio: CGFloat = 0.72

    /// 従来の中央配置キャプチャ表示型グリッドにおける最大スクロール高さ上限（ポイント）
    public static let centeredCaptureGridMaxScrollHeight: CGFloat = 560

    /// 現在の表示モード・通常スイッチャー表示形式・グルーピング設定からパネルの垂直配置スタイルを決定する
    /// - Parameters:
    ///   - mode: 現在のスイッチャー表示モード
    ///   - normalDisplayStyle: 通常スイッチャーの表示形式
    ///   - isNormalSwitcherGroupedByApp: 通常スイッチャーでアプリごとのグルーピングが有効か
    /// - Returns: 適用するパネルの垂直配置スタイル
    public static func verticalPlacement(
        mode: SwitcherMode,
        normalDisplayStyle: SwitcherDisplayStyle,
        isNormalSwitcherGroupedByApp: Bool
    ) -> SwitcherPanelVerticalPlacement {
        // 通常スイッチャーかつグルーピング OFF のキャプチャ表示型のみ従来通りディスプレイ中央に表示する
        if mode == .normal && normalDisplayStyle == .capture && !isNormalSwitcherGroupedByApp {
            return .centered
        }
        return .upperAnchored
    }

    /// 上寄せ配置時にディスプレイ有効領域の上端から空けるオフセット距離を算出する
    /// - Parameter availableScreenHeight: アクティブディスプレイの有効高さ（ポイント）
    /// - Returns: ディスプレイ上端からパネル上端までのオフセット距離（ポイント）
    public static func upperTopOffset(for availableScreenHeight: CGFloat) -> CGFloat {
        guard availableScreenHeight > 0 else { return 0 }
        let proportional = availableScreenHeight * upperTopOffsetRatio
        // 極小ディスプレイでも上端余白が画面の 1/4 を圧迫しないよう上限をクランプする
        return min(max(proportional, minUpperTopOffset), availableScreenHeight * 0.25)
    }

    /// 上寄せ配置時にディスプレイ有効領域の下端に確保する最低余白を算出する
    /// - Parameter availableScreenHeight: アクティブディスプレイの有効高さ（ポイント）
    /// - Returns: パネル下端からディスプレイ有効下端までの余白（ポイント）
    public static func upperBottomMargin(for availableScreenHeight: CGFloat) -> CGFloat {
        guard availableScreenHeight > 0 else { return 0 }
        let proportional = availableScreenHeight * upperBottomMarginRatio
        // 極小ディスプレイでも下端余白が画面の 1/5 を圧迫しないよう上限をクランプする
        return min(max(proportional, minUpperBottomMargin), availableScreenHeight * 0.20)
    }

    /// 上寄せ配置時にパネル全体として使用可能な最大高さを算出する
    /// - Parameter availableScreenHeight: アクティブディスプレイの有効高さ（ポイント）
    /// - Returns: 上端オフセットと下端余白を除いたパネル最大高さ（ポイント）
    public static func maxUpperAnchoredPanelHeight(availableScreenHeight: CGFloat) -> CGFloat {
        let usableHeight = availableScreenHeight
            - upperTopOffset(for: availableScreenHeight)
            - upperBottomMargin(for: availableScreenHeight)
        let floorHeight = min(minScrollHeight, max(availableScreenHeight, 48))
        return max(usableHeight, floorHeight)
    }

    /// リスト表示パネル（通常スイッチャー縦型リストおよび検索ランチャー）のスクロール領域最大高さを算出する
    /// - Parameters:
    ///   - availableScreenHeight: アクティブディスプレイの有効高さ（ポイント）
    ///   - hasSearchHeader: 検索入力ヘッダを表示中かどうか
    ///   - hasPermissionBanner: 画面収録権限未許可バナーを表示中かどうか
    /// - Returns: リストの ScrollView に適用する最大高さ（ポイント）
    public static func maxListScrollHeight(
        availableScreenHeight: CGFloat,
        hasSearchHeader: Bool,
        hasPermissionBanner: Bool
    ) -> CGFloat {
        let maxPanelHeight = maxUpperAnchoredPanelHeight(availableScreenHeight: availableScreenHeight)
        let reservedHeaderHeight = (hasSearchHeader ? searchHeaderReservedHeight : 0)
            + (hasPermissionBanner ? permissionBannerReservedHeight : 0)
        let floorHeight = min(minScrollHeight, max(availableScreenHeight - reservedHeaderHeight, 48))
        return max(maxPanelHeight - reservedHeaderHeight, floorHeight)
    }

    /// 上寄せ配置のアイコン型グリッド（グルーピング OFF）におけるスクロール領域最大高さを算出する
    /// - Parameter availableScreenHeight: アクティブディスプレイの有効高さ（ポイント）
    /// - Returns: アイコングリッドの ScrollView に適用する最大高さ（ポイント）
    public static func maxIconGridScrollHeight(availableScreenHeight: CGFloat) -> CGFloat {
        maxUpperAnchoredPanelHeight(availableScreenHeight: availableScreenHeight)
    }

    /// 中央配置のキャプチャ表示型グリッド（グルーピング OFF）におけるスクロール領域最大高さを算出する
    /// - Parameter availableScreenHeight: アクティブディスプレイの有効高さ（ポイント）
    /// - Returns: キャプチャグリッドの ScrollView に適用する最大高さ（ポイント）
    public static func maxCenteredCaptureGridScrollHeight(availableScreenHeight: CGFloat) -> CGFloat {
        min(
            max(availableScreenHeight * centeredCaptureGridHeightRatio, minScrollHeight),
            centeredCaptureGridMaxScrollHeight
        )
    }

    /// パネルサイズ・配置先ディスプレイ有効領域・垂直配置スタイルからパネルの左下原点座標を算出する
    /// - Parameters:
    ///   - panelSize: 配置対象パネルの幅・高さ
    ///   - visibleFrame: 配置先ディスプレイの有効表示領域（AppKit グローバル座標系）
    ///   - placement: 適用する垂直配置スタイル
    /// - Returns: 画面外へのはみ出しを防いでクランプされた左下原点座標
    public static func panelOrigin(
        panelSize: CGSize,
        in visibleFrame: CGRect,
        placement: SwitcherPanelVerticalPlacement
    ) -> CGPoint {
        let centered = WindowPlacement.centeredOrigin(windowSize: panelSize, in: visibleFrame)
        switch placement {
        case .centered:
            return centered
        case .upperAnchored:
            let topOffset = upperTopOffset(for: visibleFrame.height)
            let idealTopY = visibleFrame.maxY - topOffset
            let idealOriginY = idealTopY - panelSize.height

            let clampedY: CGFloat
            if panelSize.height >= visibleFrame.height {
                // パネル高さが有効領域を超える場合でも上端がメニューバー下に収まるよう調整する
                clampedY = visibleFrame.maxY - panelSize.height
            } else {
                let maxY = visibleFrame.maxY - panelSize.height
                clampedY = min(max(idealOriginY, visibleFrame.minY), maxY)
            }

            return CGPoint(x: centered.x, y: clampedY)
        }
    }
}
