import CoreGraphics

/// スイッチャー／検索ランチャーパネルのディスプレイに対する垂直配置スタイル
public enum SwitcherPanelVerticalPlacement: Equatable, Sendable {
    /// ディスプレイ上部寄りにパネル上端を配置し、下方向へ広く一覧を表示するモード
    case upperAnchored
    /// ディスプレイ有効領域の中央に配置する従来モード（グルーピング OFF のキャプチャ表示型など）
    case centered
}

/// スイッチャー／検索ランチャーパネルの垂直配置判定・座標計算・パネル横幅／一覧最大高さ算出を行う純粋ロジック群
public enum SwitcherPanelLayout {
    /// リスト表示パネルの基準とするディスプレイ有効幅比率
    public static let listWidthScreenRatio: CGFloat = 0.50

    /// リスト表示パネルの標準的な最小目標横幅（ポイント）
    public static let minListPanelWidth: CGFloat = 680

    /// リスト表示パネルの最大横幅上限（ポイント）
    public static let maxListPanelWidth: CGFloat = 800

    /// リスト表示パネルがディスプレイ有効幅に対して占有可能な最大比率（狭い画面での画面外はみ出し防止）
    public static let maxListScreenWidthRatio: CGFloat = 0.85

    /// 極小ディスプレイ時でもリスト表示が破綻しないように保護する絶対最小横幅（ポイント）
    public static let absoluteMinListPanelWidth: CGFloat = 320

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

    /// リスト表示パネル（通常スイッチャー縦型リストおよび検索ランチャー）の横幅をディスプレイ有効幅に応じて算出する
    /// - Parameter availableScreenWidth: アクティブディスプレイの有効横幅（ポイント）
    /// - Returns: 画面幅比率と上下限に基づき安全にクランプされたパネル横幅（整数ポイント）
    public static func listPanelWidth(availableScreenWidth: CGFloat) -> CGFloat {
        guard availableScreenWidth > 0 else { return minListPanelWidth }
        let proportional = availableScreenWidth * listWidthScreenRatio
        let preferredWidth = min(max(proportional, minListPanelWidth), maxListPanelWidth)
        let screenCap = availableScreenWidth * maxListScreenWidthRatio
        let safeFloor = min(absoluteMinListPanelWidth, availableScreenWidth)
        return max(min(preferredWidth, screenCap), safeFloor).rounded()
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

    /// リスト行配列の描画に必要な保守的な最小コンテンツ高さを算出する
    /// 実際の描画高さを決して上回らない下界を返すため、結果が `maxScrollHeight` 以上であれば確実にスクロールが発生する
    /// - Parameters:
    ///   - rows: 表示対象の統合リスト行配列
    ///   - isGrouped: アプリグルーピング表示が有効かどうか
    ///   - usesTallWindowRow: ウィンドウ行に大型アイコン行またはキャプチャサムネイル行を使用しているかどうか
    /// - Returns: 上下余白と行間スペーシングを含む最小保証高さ（ポイント）
    public static func minimumListContentHeight(
        rows: [SwitcherListRow],
        isGrouped: Bool,
        usesTallWindowRow: Bool
    ) -> CGFloat {
        // 上部アンカー余白（10pt）と下部余白（10pt）
        let verticalPadding: CGFloat = 20
        guard !rows.isEmpty else { return verticalPadding }

        let rowSpacing: CGFloat = 4
        var totalHeight = verticalPadding + CGFloat(max(rows.count - 1, 0)) * rowSpacing

        for row in rows {
            switch row {
            case let .appGroupHeader(_, _, _, _, isFirstGroup):
                totalHeight += isFirstGroup ? 20 : 28
            case .window:
                if usesTallWindowRow {
                    totalHeight += 60
                } else if isGrouped {
                    totalHeight += 26
                } else {
                    totalHeight += 38
                }
            case let .launchSectionHeader(_, hasPrecedingWindows):
                totalHeight += hasPrecedingWindows ? 24 : 16
            case .appLaunch:
                totalHeight += 38
            }
        }

        return totalHeight
    }

    /// リスト表示で `ScrollView` を固定最大高さ（`LazyVStack` 併用・`.fixedSize` なし）にすべきか判定する
    /// 最小保証高さが `maxScrollHeight` 以上の場合は必ず上限に達するため固定高さへ切り替え、
    /// `LazyVStack` の遅延推定高さと `NSWindow` リサイズの循環依存を構造的に遮断する
    /// - Parameters:
    ///   - rows: 表示対象の統合リスト行配列
    ///   - isGrouped: アプリグルーピング表示が有効かどうか
    ///   - usesTallWindowRow: ウィンドウ行に大型アイコン行またはキャプチャサムネイル行を使用しているかどうか
    ///   - maxScrollHeight: リストの最大スクロール高さ（ポイント）
    /// - Returns: 固定最大高さモードで描画すべき場合は true
    public static func shouldUseFixedMaxScrollHeight(
        rows: [SwitcherListRow],
        isGrouped: Bool,
        usesTallWindowRow: Bool,
        maxScrollHeight: CGFloat
    ) -> Bool {
        guard maxScrollHeight > 0 else { return false }
        return minimumListContentHeight(
            rows: rows,
            isGrouped: isGrouped,
            usesTallWindowRow: usesTallWindowRow
        ) >= maxScrollHeight
    }
}

/// パネルリサイズ要求を整数ポイントへ正規化し、往復振動や過剰な連続更新を遮断して有限回数で収束させる純粋ロジック
public struct SwitcherPanelResizeStabilizer: Equatable, Sendable {
    /// 整数ポイント正規化後のサイズを一意に識別するハッシュキー
    private struct SizeKey: Hashable, Sendable {
        /// 整数ポイント幅
        let width: Int
        /// 整数ポイント高さ
        let height: Int

        /// 正規化済みサイズからハッシュキーを生成する
        /// - Parameter size: 整数ポイントへ丸められたサイズ
        init(_ size: CGSize) {
            self.width = Int(size.width.rounded())
            self.height = Int(size.height.rounded())
        }
    }

    /// リサイズ時に保証する最小パネル横幅（ポイント）
    public static let minimumWidth: CGFloat = 200

    /// リサイズ時に保証する最小パネル高さ（ポイント）
    public static let minimumHeight: CGFloat = 48

    /// 正規化後の現在サイズと要求サイズで更新を発火させる最小差分（ポイント）
    public static let minimumDeltaThreshold: CGFloat = 1.0

    /// 1 回のコンテンツ更新サイクル内で許容する連続リサイズ回数の既定上限
    public static let defaultMaxUpdatesPerCycle: Int = 6

    /// 1 サイクルあたりの最大許容リサイズ回数
    public let maxUpdatesPerCycle: Int

    /// 現在のサイクルで既に経由したパネルサイズ集合（往復振動検出用）
    private var visitedSizes: Set<SizeKey> = []

    /// 現在のサイクルで適用したリサイズ回数
    public private(set) var appliedCountInCycle: Int = 0

    /// リサイズ安定化器を初期化する
    /// - Parameter maxUpdatesPerCycle: 1 コンテンツ更新サイクル内で許可する最大リサイズ回数
    public init(maxUpdatesPerCycle: Int = defaultMaxUpdatesPerCycle) {
        self.maxUpdatesPerCycle = max(maxUpdatesPerCycle, 1)
    }

    /// 要求サイズを非 Retina 環境（`backingScale = 1.0`）でも端数ズレしない安全な整数ポイントサイズへ正規化する
    /// - Parameter rawSize: ビューから通知された生の要求サイズ
    /// - Returns: 下限クランプおよび整数ポイント丸めを適用したサイズ
    public static func normalizedSize(from rawSize: CGSize) -> CGSize {
        let safeWidth = rawSize.width.isFinite ? rawSize.width : minimumWidth
        let safeHeight = rawSize.height.isFinite ? rawSize.height : minimumHeight
        return CGSize(
            width: max(safeWidth.rounded(), minimumWidth),
            height: max(safeHeight.rounded(), minimumHeight)
        )
    }

    /// 要求サイズを評価し、実際にパネルへ適用すべき正規化済みサイズを返す（不要・振動・上限超過時は nil）
    /// - Parameters:
    ///   - requestedSize: コンテンツ側から通知された要求サイズ
    ///   - currentFrameSize: 現在のパネルウィンドウのフレームサイズ
    /// - Returns: リサイズを実行すべき場合は正規化済みサイズ、抑止すべき場合は nil
    public mutating func resolveTargetSize(
        requestedSize: CGSize,
        currentFrameSize: CGSize
    ) -> CGSize? {
        let target = Self.normalizedSize(from: requestedSize)
        let current = CGSize(
            width: currentFrameSize.width.isFinite ? currentFrameSize.width.rounded() : 0,
            height: currentFrameSize.height.isFinite ? currentFrameSize.height.rounded() : 0
        )

        // 整数ポイント丸め後に 1pt 未満の差であればリサイズ不要
        guard abs(current.width - target.width) >= Self.minimumDeltaThreshold
            || abs(current.height - target.height) >= Self.minimumDeltaThreshold else {
            return nil
        }

        // 同一サイクル内の連続リサイズ上限に達した場合は暴走を防ぐため打ち切る
        guard appliedCountInCycle < maxUpdatesPerCycle else {
            return nil
        }

        // 初回判定時は開始時の現在サイズも訪問済みへ記録し、A → B → A の往復振動を即座に検知できるようにする
        if visitedSizes.isEmpty {
            visitedSizes.insert(SizeKey(current))
        }

        let targetKey = SizeKey(target)
        guard !visitedSizes.contains(targetKey) else {
            return nil
        }

        visitedSizes.insert(targetKey)
        appliedCountInCycle += 1
        return target
    }

    /// 新しい検索結果・表示形式変更・パネル再表示などの正当なコンテンツ更新開始時にサイクル状態を初期化する
    public mutating func resetCycle() {
        visitedSizes.removeAll()
        appliedCountInCycle = 0
    }
}
