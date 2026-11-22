import SwiftUI

/// 画面中央のフローティングパネル内に表示される macOS Command+Tab 風のウィンドウアイコングリッドビュー
public struct SwitcherIconGridView: View {
    /// スイッチャーの状態管理を行う ViewModel
    private let viewModel: SwitcherViewModel

    /// コンテンツサイズ変化時にパネル側へリサイズを通知するコールバック
    private let onContentSizeChanged: ((CGSize) -> Void)?

    /// アイコングリッドビューを初期化する
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

    /// アプリグルーピング表示を適用するかどうか
    private var isGrouped: Bool {
        viewModel.isNormalSwitcherGroupedByApp && !viewModel.displayedGroups.isEmpty
    }

    /// 現在の項目数（またはグループ構成）と画面幅から算出されたグリッド列数
    private var columnsCount: Int {
        if isGrouped {
            return SwitcherGridLayout.groupedColumnsCount(
                sectionCounts: viewModel.displayedGroups.map(\.results.count),
                availableScreenWidth: viewModel.availableScreenSize.width,
                style: .icon
            )
        }
        return SwitcherGridLayout.columnsCount(
            itemCount: viewModel.displayedResults.count,
            availableScreenWidth: viewModel.availableScreenSize.width,
            style: .icon
        )
    }

    /// グリッドコンテンツの全体横幅
    private var panelWidth: CGFloat {
        let tilesWidth = CGFloat(columnsCount) * SwitcherGridLayout.iconTileWidth
            + CGFloat(max(columnsCount - 1, 0)) * SwitcherGridLayout.cardSpacing
        let baseWidth = tilesWidth + SwitcherGridLayout.gridPadding * 2
        return isGrouped ? max(baseWidth, SwitcherGridLayout.iconGroupedMinPanelWidth) : baseWidth
    }

    /// グリッド領域の最大スクロール高さ
    private var maxScrollHeight: CGFloat {
        min(max(viewModel.availableScreenSize.height * 0.72, 220), 560)
    }

    /// LazyVGrid に渡す固定幅カラム配列
    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(SwitcherGridLayout.iconTileWidth), spacing: SwitcherGridLayout.cardSpacing),
            count: columnsCount
        )
    }

    /// ビューの本体構築
    public var body: some View {
        gridScrollView
            .frame(width: panelWidth)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size) { _, newSize in
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

    /// スクロール追従付きの複数行アイコンタイルグリッド（グルーピング ON 時はアプリ別セクション構成）
    private var gridScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                Group {
                    if isGrouped {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(viewModel.displayedGroups.enumerated()), id: \.element.id) { groupIndex, group in
                                VStack(alignment: .leading, spacing: 8) {
                                    SwitcherGridSectionHeaderView(
                                        applicationName: group.applicationName,
                                        icon: viewModel.icon(for: group.representativePID),
                                        isFirstSection: groupIndex == 0
                                    )

                                    LazyVGrid(
                                        columns: gridColumns,
                                        alignment: .leading,
                                        spacing: SwitcherGridLayout.cardSpacing
                                    ) {
                                        ForEach(Array(group.results.enumerated()), id: \.element.id) { offset, result in
                                            let index = group.startIndex + offset
                                            SwitcherIconTileView(
                                                entry: result.entry,
                                                icon: viewModel.icon(for: result.entry.pid),
                                                isSelected: index == viewModel.selectedIndex,
                                                showsApplicationName: false
                                            )
                                            .id(result.id)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                viewModel.selectAndActivate(at: index)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: SwitcherGridLayout.cardSpacing) {
                            ForEach(Array(viewModel.displayedResults.enumerated()), id: \.element.id) { index, result in
                                SwitcherIconTileView(
                                    entry: result.entry,
                                    icon: viewModel.icon(for: result.entry.pid),
                                    isSelected: index == viewModel.selectedIndex,
                                    showsApplicationName: true
                                )
                                .id(result.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectAndActivate(at: index)
                                }
                            }
                        }
                    }
                }
                .padding(SwitcherGridLayout.gridPadding)
            }
            .frame(maxHeight: maxScrollHeight)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                scrollToSelectedItem(using: proxy, animated: false)
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                scrollToItem(at: newIndex, using: proxy, animated: true)
            }
        }
    }

    /// 現在選択中のタイルへスクロール位置を追従させる
    /// - Parameters:
    ///   - proxy: 制御対象の `ScrollViewProxy`
    ///   - animated: 短いアニメーションを適用する場合は true
    private func scrollToSelectedItem(using proxy: ScrollViewProxy, animated: Bool) {
        scrollToItem(at: viewModel.selectedIndex, using: proxy, animated: animated)
    }

    /// 指定インデックスのタイルへスクロール位置を追従させる
    /// - Parameters:
    ///   - index: 対象の選択インデックス
    ///   - proxy: 制御対象の `ScrollViewProxy`
    ///   - animated: 短いアニメーションを適用する場合は true
    private func scrollToItem(at index: Int, using proxy: ScrollViewProxy, animated: Bool) {
        guard viewModel.displayedResults.indices.contains(index) else { return }
        let targetID = viewModel.displayedResults[index].id
        if animated {
            withAnimation(.easeOut(duration: 0.08)) {
                proxy.scrollTo(targetID, anchor: .center)
            }
        } else {
            proxy.scrollTo(targetID, anchor: .center)
        }
    }
}

/// アイコングリッド内の 1 ウィンドウ分タイル（大型アプリアイコン・アプリ名・ウィンドウタイトル）を表すビュー
private struct SwitcherIconTileView: View {
    /// 表示対象のウィンドウ項目
    let entry: WindowEntry
    /// 所有アプリアイコン
    let icon: NSImage?
    /// 現在選択状態として強調表示するか
    let isSelected: Bool
    /// タイル下部にアプリケーション名を表示するか（グルーピング ON 時は false）
    let showsApplicationName: Bool

    /// タイルビューの本体構築
    var body: some View {
        VStack(spacing: 6) {
            appIconArea
                .frame(width: 60, height: 60)

            VStack(spacing: 2) {
                if showsApplicationName {
                    Text(entry.applicationName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Text(entry.displayTitle)
                    .font(.system(size: showsApplicationName ? 10.5 : 11, weight: showsApplicationName ? .regular : .medium))
                    .foregroundStyle(
                        showsApplicationName
                            ? (isSelected ? .white.opacity(0.88) : .secondary)
                            : (isSelected ? .white : .primary)
                    )
                    .lineLimit(showsApplicationName ? 1 : 2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(width: SwitcherGridLayout.iconTileWidth, height: SwitcherGridLayout.iconTileHeight)
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

    /// タイル上部中央に配置する大きなアプリアイコン（未取得時は macwindow シンボルフォールバック）
    @ViewBuilder
    private var appIconArea: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)
        } else {
            Image(systemName: "macwindow")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
        }
    }
}
