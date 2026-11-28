import SwiftUI

/// 固定グリッドの 1 行内に並べる個別アイテムのスナップショットモデル（候補数変動時の範囲外参照を防ぐ）
internal struct SwitcherGridRowItem: Identifiable {
    /// 全体表示配列上のインデックス
    let index: Int

    /// 表示対象のウィンドウ検索結果
    let result: WindowSearchResult

    /// ウィンドウ固有 ID（削除・並び替え時の SwiftUI 差分識別に使用）
    var id: String {
        result.id
    }
}

/// 固定グリッドの 1 行分のスナップショットモデル（行内アイテム列＋複数ウィンドウグループ背面枠セグメント）
internal struct SwitcherGridRowModel: Identifiable {
    /// 行インデックス（0 始まり）
    let rowIndex: Int

    /// この行に配置するアイテム一覧
    let items: [SwitcherGridRowItem]

    /// この行に描画する複数ウィンドウグループの背面枠セグメント一覧
    let segments: [SwitcherGridGroupSegment]

    /// 行の一意識別子
    var id: Int {
        rowIndex
    }

    /// 表示結果一覧と行別セグメント辞書から、安全な行スナップショット配列を構築する
    /// - Parameters:
    ///   - results: 表示中の全ウィンドウ検索結果配列
    ///   - columns: 1 行あたりの列数（1 以上）
    ///   - segmentsByRow: 行インデックスごとのグループ背面枠セグメント辞書
    /// - Returns: 0 行目から順に構築された行スナップショット配列
    static func buildRows(
        from results: [WindowSearchResult],
        columns: Int,
        segmentsByRow: [Int: [SwitcherGridGroupSegment]]
    ) -> [SwitcherGridRowModel] {
        guard !results.isEmpty else { return [] }
        let safeColumns = max(columns, 1)
        let totalRows = (results.count + safeColumns - 1) / safeColumns

        var rows: [SwitcherGridRowModel] = []
        rows.reserveCapacity(totalRows)
        for rowIndex in 0..<totalRows {
            let startIndex = rowIndex * safeColumns
            let endIndex = min(startIndex + safeColumns, results.count)
            let items = (startIndex..<endIndex).map { index in
                SwitcherGridRowItem(index: index, result: results[index])
            }
            rows.append(
                SwitcherGridRowModel(
                    rowIndex: rowIndex,
                    items: items,
                    segments: segmentsByRow[rowIndex] ?? []
                )
            )
        }
        return rows
    }
}

/// 固定グリッド（キャプチャ表示型・アイコン型）において、複数ウィンドウを持つアプリグループを
/// 1 行単位で視覚的にまとめる背面コンテナ枠ビュー
/// 行をまたいで分断されたグループは、前後行へ続く側の辺を開放エッジとして描画し連続性を示す
struct SwitcherGridGroupFrameView: View {
    /// 描画対象の行内グループセグメント
    let segment: SwitcherGridGroupSegment

    /// 現在選択中のカード／タイルがこのグループに属しているため強調表示するかどうか
    let isHighlighted: Bool

    /// 閉じた側のコーナー半径（カード／タイル角丸 10pt + インセット 3pt の同心角丸）
    private static let closedCornerRadius: CGFloat = 13

    /// 開放エッジ側のコーナー半径（わずかな丸みを残しつつ次行・前行への連続性を示す）
    private static let openCornerRadius: CGFloat = 2

    /// 枠線の太さ
    private var strokeLineWidth: CGFloat {
        isHighlighted ? 1.5 : 1.0
    }

    /// 背景コンテナの塗りつぶし色
    private var fillColor: Color {
        isHighlighted
            ? Color.accentColor.opacity(0.14)
            : Color.primary.opacity(0.08)
    }

    /// 外枠のストローク色
    private var strokeColor: Color {
        isHighlighted
            ? Color.accentColor.opacity(0.60)
            : Color.primary.opacity(0.22)
    }

    /// 前後行への継続状態に応じた四隅角丸の背景シェイプ
    private var backgroundShape: UnevenRoundedRectangle {
        let leadingRadius = segment.continuesFromPreviousRow
            ? Self.openCornerRadius
            : Self.closedCornerRadius
        let trailingRadius = segment.continuesToNextRow
            ? Self.openCornerRadius
            : Self.closedCornerRadius

        return UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: leadingRadius,
                bottomLeading: leadingRadius,
                bottomTrailing: trailingRadius,
                topTrailing: trailingRadius
            ),
            style: .continuous
        )
    }

    /// ビューの本体構築
    var body: some View {
        ZStack {
            backgroundShape
                .fill(fillColor)

            SwitcherGridGroupBorderShape(
                closedCornerRadius: Self.closedCornerRadius,
                openEdgeInset: Self.openCornerRadius,
                lineWidth: strokeLineWidth,
                openLeading: segment.continuesFromPreviousRow,
                openTrailing: segment.continuesToNextRow
            )
            .stroke(
                strokeColor,
                style: StrokeStyle(
                    lineWidth: strokeLineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
        .allowsHitTesting(false)
    }
}

/// 前後行へ続く辺を開放して描画するグループ背面枠のカスタムシェイプ
internal struct SwitcherGridGroupBorderShape: Shape {
    /// 閉じた側の角丸半径
    let closedCornerRadius: CGFloat

    /// 開放側の水平線を背景の微小角丸手前で収めるための端オフセット
    let openEdgeInset: CGFloat

    /// ストローク線幅（枠線が矩形外へはみ出さないよう半分だけ内側へインセットするために使用）
    let lineWidth: CGFloat

    /// 左辺を開放する場合（前行からの継続）は true
    let openLeading: Bool

    /// 右辺を開放する場合（次行への継続）は true
    let openTrailing: Bool

    /// 指定矩形内に開放エッジを考慮した枠線パスを構築する
    /// - Parameter rect: 描画領域の矩形
    /// - Returns: 開放辺を除いた枠線パス
    func path(in rect: CGRect) -> Path {
        let halfLine = lineWidth / 2
        let bounds = rect.insetBy(dx: halfLine, dy: halfLine)
        guard bounds.width > 0, bounds.height > 0 else { return Path() }

        let radius = min(closedCornerRadius, bounds.width / 2, bounds.height / 2)
        let edgeOffset = min(openEdgeInset, bounds.width / 4)

        // 両端が閉じている場合は通常の連続角丸長方形として描画する
        if !openLeading && !openTrailing {
            return Path(roundedRect: bounds, cornerRadius: radius, style: .continuous)
        }

        var path = Path()

        // 両端が開いている場合（3 行以上にまたがるグループの中間行）は上下の水平線のみ描画する
        if openLeading && openTrailing {
            let startX = bounds.minX + edgeOffset
            let endX = bounds.maxX - edgeOffset
            path.move(to: CGPoint(x: startX, y: bounds.minY))
            path.addLine(to: CGPoint(x: endX, y: bounds.minY))
            path.move(to: CGPoint(x: startX, y: bounds.maxY))
            path.addLine(to: CGPoint(x: endX, y: bounds.maxY))
            return path
        }

        // 右辺が開いている場合（次行へ継続）: 右上 → 左上角丸 → 左辺 → 左下角丸 → 右下
        if openTrailing {
            let rightX = bounds.maxX - edgeOffset
            path.move(to: CGPoint(x: rightX, y: bounds.minY))
            path.addLine(to: CGPoint(x: bounds.minX + radius, y: bounds.minY))
            path.addArc(
                center: CGPoint(x: bounds.minX + radius, y: bounds.minY + radius),
                radius: radius,
                startAngle: .degrees(-90),
                endAngle: .degrees(180),
                clockwise: true
            )
            path.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY - radius))
            path.addArc(
                center: CGPoint(x: bounds.minX + radius, y: bounds.maxY - radius),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(90),
                clockwise: true
            )
            path.addLine(to: CGPoint(x: rightX, y: bounds.maxY))
            return path
        }

        // 左辺が開いている場合（前行から継続）: 左上 → 右上角丸 → 右辺 → 右下角丸 → 左下
        let leftX = bounds.minX + edgeOffset
        path.move(to: CGPoint(x: leftX, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX - radius, y: bounds.minY))
        path.addArc(
            center: CGPoint(x: bounds.maxX - radius, y: bounds.minY + radius),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - radius))
        path.addArc(
            center: CGPoint(x: bounds.maxX - radius, y: bounds.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: leftX, y: bounds.maxY))
        return path
    }
}
