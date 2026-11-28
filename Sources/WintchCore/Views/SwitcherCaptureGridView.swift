import SwiftUI

/// 画面中央のフローティングパネル内に表示される Windows Alt+Tab 風のウィンドウキャプチャグリッドビュー
public struct SwitcherCaptureGridView: View {
    /// スイッチャーの状態管理を行う ViewModel
    private let viewModel: SwitcherViewModel

    /// コンテンツサイズ変化時にパネル側へリサイズを通知するコールバック
    private let onContentSizeChanged: ((CGSize) -> Void)?

    /// 権限未許可バナー表示時の最小パネル幅
    public static let minWidthWithBanner: CGFloat = 360

    /// 画面収録権限が未許可のときに表示する案内メッセージ（互換用：日本語既定）
    public static var permissionBannerMessage: String {
        AppStrings.japanese.screenRecordingDeniedBanner
    }

    /// キャプチャグリッドビューを初期化する
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

    /// 現在の項目数と画面幅から算出されたグリッド列数
    private var columnsCount: Int {
        SwitcherGridLayout.columnsCount(
            itemCount: viewModel.displayedResults.count,
            availableScreenWidth: viewModel.availableScreenSize.width
        )
    }

    /// グリッド内のカード領域の合計横幅
    private var cardsWidth: CGFloat {
        CGFloat(columnsCount) * SwitcherGridLayout.cardWidth
            + CGFloat(max(columnsCount - 1, 0)) * SwitcherGridLayout.cardSpacing
    }

    /// グリッドコンテンツの全体横幅
    private var panelWidth: CGFloat {
        let baseWidth = cardsWidth + SwitcherGridLayout.gridPadding * 2
        return viewModel.isScreenRecordingGranted ? baseWidth : max(baseWidth, Self.minWidthWithBanner)
    }

    /// グリッド領域の最大スクロール高さ（中央配置のキャプチャ表示型は従来の上限を維持する）
    private var maxScrollHeight: CGFloat {
        SwitcherPanelLayout.maxCenteredCaptureGridScrollHeight(
            availableScreenHeight: viewModel.availableScreenSize.height
        )
    }

    /// 固定カード高さから確定算出されるスクロール領域の表示高さ
    private var scrollHeight: CGFloat {
        min(
            SwitcherGridLayout.contentHeight(
                itemCount: viewModel.displayedResults.count,
                columns: columnsCount,
                style: .capture
            ),
            maxScrollHeight
        )
    }

    /// 現在の表示結果・列数・グルーピング状態から構築した安全な行スナップショット配列
    private var gridRows: [SwitcherGridRowModel] {
        let segmentsByRow: [Int: [SwitcherGridGroupSegment]]
        if viewModel.isGroupingActiveForCurrentMode {
            segmentsByRow = SwitcherGridLayout.groupSegmentsByRow(
                for: viewModel.displayedGroups,
                columns: columnsCount
            )
        } else {
            segmentsByRow = [:]
        }
        return SwitcherGridRowModel.buildRows(
            from: viewModel.displayedResults,
            columns: columnsCount,
            segmentsByRow: segmentsByRow
        )
    }

    /// グルーピング ON 時に現在選択中カードが属する複数ウィンドウグループの ID
    private var highlightedGroupID: String? {
        guard viewModel.isGroupingActiveForCurrentMode else { return nil }
        return SwitcherGridLayout.selectedMultiWindowGroupID(
            selectedIndex: viewModel.selectedIndex,
            in: viewModel.displayedGroups
        )
    }

    /// ビューの本体構築
    public var body: some View {
        VStack(spacing: 0) {
            if !viewModel.isScreenRecordingGranted {
                permissionBannerView
                Divider()
                    .overlay(.white.opacity(0.14))
            }

            gridScrollView
        }
        .frame(width: panelWidth)
        .background(
            GeometryReader { proxy in
                let roundedSize = CGSize(
                    width: proxy.size.width.rounded(),
                    height: proxy.size.height.rounded()
                )
                Color.clear
                    .onChange(of: roundedSize, initial: true) { _, newSize in
                        onContentSizeChanged?(newSize)
                    }
            }
        )
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            ZStack {
                // 明るい背景でも角丸の輪郭を視認できる外側の暗色ボーダー
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.black.opacity(0.16), lineWidth: 1)
                // 暗い背景でガラス調の輪郭を際立たせる内側の明色ハイライト
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.white.opacity(0.20), lineWidth: 1)
                    .padding(1)
            }
        }
        .onAppear {
            viewModel.updateGridColumnCount(columnsCount)
        }
        .onChange(of: columnsCount) { _, newColumns in
            viewModel.updateGridColumnCount(newColumns)
        }
    }

    /// 画面収録権限が未許可のときに表示するコンパクトな案内バナー（ホールド操作中にクリック不能な設定リンクは設けない）
    var permissionBannerView: some View {
        ScreenRecordingPermissionBannerView(
            message: viewModel.strings.screenRecordingDeniedBanner,
            horizontalPadding: SwitcherGridLayout.gridPadding
        )
    }

    /// スクロール追従付きの複数行カードグリッド（グルーピング ON 時は複数ウィンドウグループのみ背面枠でまとめる）
    private var gridScrollView: some View {
        let rows = gridRows
        let activeGroupID = highlightedGroupID

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .center, spacing: SwitcherGridLayout.cardSpacing) {
                    ForEach(rows) { row in
                        gridRowView(
                            row: row,
                            highlightedGroupID: activeGroupID
                        )
                        .id(Self.rowScrollID(for: row.rowIndex))
                    }
                }
                .padding(SwitcherGridLayout.gridPadding)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: scrollHeight)
            .onAppear {
                scrollToSelectedItem(using: proxy, animated: false)
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                scrollToItem(at: newIndex, using: proxy, animated: true)
            }
        }
    }

    /// グリッドの 1 行分（複数ウィンドウのグループ背面枠＋前面カード列）を構築する
    /// - Parameters:
    ///   - row: 描画対象の行スナップショットモデル
    ///   - highlightedGroupID: 現在選択中のカードが属する複数ウィンドウグループ ID（該当なし時は nil）
    /// - Returns: 1 行分のグリッドビュー
    private func gridRowView(
        row: SwitcherGridRowModel,
        highlightedGroupID: String?
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(row.segments) { segment in
                let frame = SwitcherGridLayout.segmentFrameInRow(
                    for: segment,
                    itemWidth: SwitcherGridLayout.cardWidth,
                    itemHeight: SwitcherGridLayout.cardHeight
                )
                SwitcherGridGroupFrameView(
                    segment: segment,
                    isHighlighted: segment.groupID == highlightedGroupID
                )
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
            }

            HStack(spacing: SwitcherGridLayout.cardSpacing) {
                ForEach(row.items) { item in
                    SwitcherCaptureCardView(
                        entry: item.result.entry,
                        thumbnail: viewModel.thumbnail(for: item.result.entry),
                        icon: viewModel.icon(for: item.result.entry.pid),
                        isSelected: item.index == viewModel.selectedIndex,
                        isClosing: viewModel.isClosingWindow(id: item.result.entry.id),
                        language: viewModel.resolvedLanguage
                    )
                    .id(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectAndActivate(at: item.index)
                    }
                }
            }
        }
        .frame(width: cardsWidth, height: SwitcherGridLayout.cardHeight, alignment: .topLeading)
    }

    /// 行インデックスに対応する ScrollViewReader 用アンカー ID を返す
    /// - Parameter rowIndex: 行インデックス（0 始まり）
    /// - Returns: 行単位のスクロール識別子
    private static func rowScrollID(for rowIndex: Int) -> String {
        "capture-grid-row-\(rowIndex)"
    }

    /// 現在選択中のカードへスクロール位置を追従させる
    /// - Parameters:
    ///   - proxy: 制御対象の `ScrollViewProxy`
    ///   - animated: 短いアニメーションを適用する場合は true
    private func scrollToSelectedItem(using proxy: ScrollViewProxy, animated: Bool) {
        scrollToItem(at: viewModel.selectedIndex, using: proxy, animated: animated)
    }

    /// 指定インデックスのカードを含む行へスクロール位置を追従させる
    /// - Parameters:
    ///   - index: 対象の選択インデックス
    ///   - proxy: 制御対象の `ScrollViewProxy`
    ///   - animated: 短いアニメーションを適用する場合は true
    private func scrollToItem(at index: Int, using proxy: ScrollViewProxy, animated: Bool) {
        guard viewModel.displayedResults.indices.contains(index) else { return }
        let targetRow = index / max(columnsCount, 1)
        let targetID = Self.rowScrollID(for: targetRow)
        if animated {
            withAnimation(.easeOut(duration: 0.08)) {
                proxy.scrollTo(targetID, anchor: .center)
            }
        } else {
            proxy.scrollTo(targetID, anchor: .center)
        }
    }
}

/// グリッド内の 1 ウィンドウ分カード（サムネイル/プレースホルダー・アプリアイコン・アプリ名・タイトル）を表すビュー
private struct SwitcherCaptureCardView: View {
    /// 表示対象のウィンドウ項目
    let entry: WindowEntry
    /// メモリ上のキャプチャサムネイル（未取得・取得不能時は nil）
    let thumbnail: NSImage?
    /// 所有アプリアイコン
    let icon: NSImage?
    /// 現在選択状態として強調表示するか
    let isSelected: Bool
    /// 現在クローズ／終了処理を実行中かどうか
    let isClosing: Bool
    /// 補助表示テキストに使用する解決済み言語
    let language: ResolvedAppLanguage

    /// カードビューの本体構築
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            previewArea
                .frame(height: 112)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.16))
                .overlay {
                    if isClosing {
                        ZStack {
                            Color.black.opacity(0.38)
                            SwitcherClosingIndicatorView(
                                usesLightAppearance: true,
                                controlSize: .regular
                            )
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }

            HStack(spacing: 6) {
                smallAppIcon

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.displayApplicationName(in: language))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(entry.displayTitle(in: language))
                        .font(.system(size: 10.5))
                        .foregroundStyle(isSelected ? .white.opacity(0.88) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .frame(width: SwitcherGridLayout.cardWidth, height: SwitcherGridLayout.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.90) : Color.primary.opacity(0.06))
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
            }
        }
    }

    /// サムネイル画像またはアプリアイコンプレースホルダーを表示するプレビュー領域
    @ViewBuilder
    private var previewArea: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            placeholderContent
        }
    }

    /// 未取得時・権限未許可時・最小化ウィンドウ等に表示するアイコンプレースホルダー
    @ViewBuilder
    private var placeholderContent: some View {
        ZStack {
            Color.clear
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
            } else {
                Image(systemName: "macwindow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// カード下部の小型アプリアイコン
    @ViewBuilder
    private var smallAppIcon: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "macwindow")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
        }
    }
}

/// 通常スイッチャーおよび検索ランチャーのキャプチャ表示型で共通利用する、非インタラクティブな画面収録権限未許可バナー
struct ScreenRecordingPermissionBannerView: View {
    /// 表示する案内メッセージ
    let message: String
    /// バナー左右のパディング幅
    let horizontalPadding: CGFloat

    /// バナーの本体構築
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 9)
    }
}
