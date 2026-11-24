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

    /// グリッドコンテンツの全体横幅
    private var panelWidth: CGFloat {
        let cardsWidth = CGFloat(columnsCount) * SwitcherGridLayout.cardWidth
            + CGFloat(max(columnsCount - 1, 0)) * SwitcherGridLayout.cardSpacing
        let baseWidth = cardsWidth + SwitcherGridLayout.gridPadding * 2
        return viewModel.isScreenRecordingGranted ? baseWidth : max(baseWidth, Self.minWidthWithBanner)
    }

    /// グリッド領域の最大スクロール高さ（中央配置のキャプチャ表示板は従来の上限を維持する）
    private var maxScrollHeight: CGFloat {
        SwitcherPanelLayout.maxCenteredCaptureGridScrollHeight(
            availableScreenHeight: viewModel.availableScreenSize.height
        )
    }

    /// LazyVGrid に渡す固定幅カラム配列
    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(SwitcherGridLayout.cardWidth), spacing: SwitcherGridLayout.cardSpacing),
            count: columnsCount
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

    /// 画面収録権限が未許可のときに表示するコンパクトな案内バナー（ホールド操作中にクリック不能な設定リンクは設けない）
    var permissionBannerView: some View {
        ScreenRecordingPermissionBannerView(
            message: viewModel.strings.screenRecordingDeniedBanner,
            horizontalPadding: SwitcherGridLayout.gridPadding
        )
    }

    /// スクロール追従付きの複数行カードグリッド
    private var gridScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: gridColumns, spacing: SwitcherGridLayout.cardSpacing) {
                    ForEach(Array(viewModel.displayedResults.enumerated()), id: \.element.id) { index, result in
                        SwitcherCaptureCardView(
                            entry: result.entry,
                            thumbnail: viewModel.thumbnail(for: result.entry),
                            icon: viewModel.icon(for: result.entry.pid),
                            isSelected: index == viewModel.selectedIndex,
                            isClosing: viewModel.isClosingWindow(id: result.entry.id),
                            language: viewModel.resolvedLanguage
                        )
                        .id(result.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectAndActivate(at: index)
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

    /// 現在選択中のカードへスクロール位置を追従させる
    /// - Parameters:
    ///   - proxy: 制御対象の `ScrollViewProxy`
    ///   - animated: 短いアニメーションを適用する場合は true
    private func scrollToSelectedItem(using proxy: ScrollViewProxy, animated: Bool) {
        scrollToItem(at: viewModel.selectedIndex, using: proxy, animated: animated)
    }

    /// 指定インデックスのカードへスクロール位置を追従させる
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
