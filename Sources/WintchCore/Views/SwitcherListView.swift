import SwiftUI

/// フローティングパネル内に表示されるウィンドウ一覧（およびランチャー検索バー）のビュー
public struct SwitcherListView: View {
    /// ランチャーのキャプチャ表示行に配置する小型サムネイルの横幅
    public static let captureThumbnailWidth: CGFloat = 80

    /// ランチャーのキャプチャ表示行に配置する小型サムネイルの高さ
    public static let captureThumbnailHeight: CGFloat = 50

    /// 通常スイッチャーのアイコン型（グルーピング ON）行に配置する大きなアプリアイコンの描画サイズ
    public static let groupedIconDisplaySize: CGFloat = 46

    /// 通常スイッチャーのアイコン型（グルーピング ON）行におけるアイコン領域のフレームサイズ（枠・背景なし）
    public static let groupedIconContainerSize: CGFloat = 50

    /// スイッチャーの状態管理を行う ViewModel
    private let viewModel: SwitcherViewModel

    /// コンテンツ高さ変化時にパネル側へリサイズを通知するコールバック（従来互換）
    private let onContentHeightChanged: ((CGFloat) -> Void)?

    /// コンテンツサイズ（幅・高さ）変化時にパネル側へリサイズを通知するコールバック
    private let onContentSizeChanged: ((CGSize) -> Void)?

    /// リストビューを初期化する
    /// - Parameters:
    ///   - viewModel: スイッチャー ViewModel
    ///   - onContentHeightChanged: コンテンツ高さ変化時の通知クロージャ
    ///   - onContentSizeChanged: コンテンツサイズ変化時の通知クロージャ
    public init(
        viewModel: SwitcherViewModel,
        onContentHeightChanged: ((CGFloat) -> Void)? = nil,
        onContentSizeChanged: ((CGSize) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onContentHeightChanged = onContentHeightChanged
        self.onContentSizeChanged = onContentSizeChanged
    }

    /// 検索文字列の双方向バインディング
    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { viewModel.searchQuery },
            set: { viewModel.updateSearchQuery($0) }
        )
    }

    /// 現在の表示状態がランチャーのキャプチャ表示型かどうか
    private var isLauncherCaptureStyle: Bool {
        viewModel.mode == .launcher && viewModel.launcherDisplayStyle == .capture
    }

    /// 現在の表示状態が通常スイッチャーのアイコン型（グルーピング ON）かどうか
    private var isNormalIconGroupedStyle: Bool {
        viewModel.mode == .normal
            && viewModel.isNormalSwitcherGroupedByApp
            && viewModel.normalDisplayStyle == .icon
    }

    /// ウィンドウ行にキャプチャサムネイル枠付き行を使用するかどうか
    /// 検索ランチャーのキャプチャ表示型、およびグルーピング ON 時の通常スイッチャー（キャプチャ表示型）で有効
    private var usesCaptureRowStyle: Bool {
        if isLauncherCaptureStyle {
            return true
        }
        return viewModel.mode == .normal
            && viewModel.isNormalSwitcherGroupedByApp
            && viewModel.normalDisplayStyle == .capture
    }

    /// 画面収録権限未許可バナーを表示すべきかどうか（実際にキャプチャ表示が有効なモードかつ未許可時のみ）
    private var showsScreenRecordingPermissionBanner: Bool {
        viewModel.isCaptureActiveForCurrentMode && !viewModel.isScreenRecordingGranted
    }

    /// アクティブディスプレイの有効幅に応じたリストパネル横幅
    private var panelWidth: CGFloat {
        SwitcherPanelLayout.listPanelWidth(
            availableScreenWidth: viewModel.availableScreenSize.width
        )
    }

    /// アクティブディスプレイの有効高さおよび上部ヘッダ有無に応じたリスト領域の最大スクロール高さ
    private var maxScrollHeight: CGFloat {
        SwitcherPanelLayout.maxListScrollHeight(
            availableScreenHeight: viewModel.availableScreenSize.height,
            hasSearchHeader: viewModel.mode == .launcher,
            hasPermissionBanner: showsScreenRecordingPermissionBanner
        )
    }

    /// ビューの本体構築
    public var body: some View {
        VStack(spacing: 0) {
            if viewModel.mode == .launcher {
                searchHeaderView
                Divider()
                    .overlay(.white.opacity(0.14))
            }

            if showsScreenRecordingPermissionBanner {
                permissionBannerView
                Divider()
                    .overlay(.white.opacity(0.14))
            }

            if let emptyState = viewModel.emptyState {
                emptyResultView(for: emptyState)
            } else {
                resultListView
            }
        }
        .frame(width: panelWidth)
        .background(
            GeometryReader { proxy in
                let roundedSize = CGSize(
                    width: proxy.size.width.rounded(),
                    height: proxy.size.height.rounded()
                )
                Color.clear
                    .onChange(of: roundedSize) { oldSize, newSize in
                        onContentSizeChanged?(newSize)
                        if abs(oldSize.height - newSize.height) >= 1.0 {
                            onContentHeightChanged?(newSize.height)
                        }
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
    }

    /// ランチャーモード上部の検索入力ヘッダ
    private var searchHeaderView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            LauncherSearchField(
                text: searchQueryBinding,
                isActive: viewModel.mode == .launcher,
                placeholder: viewModel.strings.launcherSearchPlaceholder,
                onMoveSelection: { direction in
                    viewModel.moveSelection(direction)
                },
                onConfirm: {
                    viewModel.confirmSelection()
                },
                onCancel: {
                    viewModel.cancel(reason: .cancelled)
                }
            )
            .frame(height: 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// ランチャーのキャプチャ表示型で画面収録権限が未許可のときに表示する非インタラクティブな警告バナー
    var permissionBannerView: some View {
        ScreenRecordingPermissionBannerView(
            message: viewModel.strings.screenRecordingDeniedBanner,
            horizontalPadding: 14
        )
    }

    /// 候補 0 件時の案内表示
    /// - Parameter state: 現在の空状態種別
    private func emptyResultView(for state: LauncherEmptyState) -> some View {
        HStack {
            Spacer(minLength: 0)
            Text(state.message(in: viewModel.resolvedLanguage))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 24)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
    }

    /// 現在の表示モードでアプリグルーピング表示が有効かどうか
    private var isGrouped: Bool {
        viewModel.isGroupingActiveForCurrentMode && !viewModel.displayedGroups.isEmpty
    }

    /// 表示対象のウィンドウ候補およびアプリ起動候補を統合した単一リスト行配列
    private var listRows: [SwitcherListRow] {
        SwitcherListRow.buildRows(
            windowResults: viewModel.displayedResults,
            windowGroups: isGrouped ? viewModel.displayedGroups : nil,
            appResults: viewModel.displayedAppResults,
            isShowingLaunchCandidates: viewModel.isShowingLaunchCandidates,
            launchSectionHeaderTitle: viewModel.launchSectionHeaderTitle
        )
    }

    /// リスト最上部（上部余白・先頭見出し行を含む y == 0）へ確実に復帰するための固定スクロールアンカー ID
    private static let topScrollAnchorID = "__wintch_list_top_anchor__"

    /// 現在のリスト行数が最大スクロール高さ以上になることが保証され、固定高さ＋遅延スタックを使うべきかどうか
    private var usesFixedMaxScrollHeight: Bool {
        SwitcherPanelLayout.shouldUseFixedMaxScrollHeight(
            rows: listRows,
            isGrouped: isGrouped,
            usesTallWindowRow: isNormalIconGroupedStyle || usesCaptureRowStyle,
            maxScrollHeight: maxScrollHeight
        )
    }

    /// ウィンドウ候補および（ランチャー検索時の）アプリ起動候補を統合表示する縦型スクロールリスト
    private var resultListView: some View {
        ScrollViewReader { proxy in
            Group {
                if usesFixedMaxScrollHeight {
                    // 候補が多く確実に maxScrollHeight へ達する場合は、確定高さ＋LazyVStack とし
                    // .fixedSize(vertical: true) を外すことで推定高さ変動とパネルリサイズの循環を遮断する
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            topScrollAnchorView
                            LazyVStack(spacing: 4) {
                                listRowsContent
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
                        }
                    }
                    .frame(height: maxScrollHeight)
                } else {
                    // 少数件数時は非遅延 VStack で全行を 1 パス確定計測し、遅延プリフェッチ由来の高さ振動を防ぐ
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            topScrollAnchorView
                            VStack(spacing: 4) {
                                listRowsContent
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
                        }
                    }
                    .frame(maxHeight: maxScrollHeight)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onAppear {
                scrollToSelectedRow(using: proxy, animated: false)
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                scrollToRow(at: newIndex, using: proxy, animated: true)
            }
            .onChange(of: viewModel.searchQuery) { _, _ in
                // 手動スクロール後に selectedIndex が 0 のまま検索更新された場合も、上部余白・先頭見出しごと見える位置へ戻す
                scrollToSelectedRow(using: proxy, animated: false)
                DispatchQueue.main.async {
                    scrollToSelectedRow(using: proxy, animated: false)
                }
            }
            .onChange(of: viewModel.mode) { _, newMode in
                guard newMode != .inactive else { return }
                scrollToSelectedRow(using: proxy, animated: false)
            }
        }
    }

    /// 上部余白（10pt）を兼ねる常駐スクロールアンカービュー
    private var topScrollAnchorView: some View {
        // 上部余白（10pt）を兼ねる非ゼロ高さの常駐アンカーをリスト先頭の y == 0 に置き、
        // 長距離スクロールや検索更新時でも height == 0 無視や見積もり高さズレなしに最上部へ復帰させる
        Color.clear
            .frame(height: 10)
            .id(Self.topScrollAnchorID)
    }

    /// 統合リスト行配列（グループ見出し・ウィンドウ行・アプリ起動セクション）を描画する共通コンテンツ
    @ViewBuilder
    private var listRowsContent: some View {
        // ForEach 要素の id と ScrollViewReader の scrollTo 対象 ID を一致させるため単一モデルで描画する
        ForEach(listRows) { row in
            switch row {
            case let .appGroupHeader(_, applicationName, representativePID, matchedAppNameRanges, isFirstGroup):
                appGroupHeaderView(
                    applicationName: applicationName,
                    icon: viewModel.icon(for: representativePID),
                    matchedRanges: matchedAppNameRanges,
                    isFirstGroup: isFirstGroup
                )

            case let .window(index, result):
                let isClosing = viewModel.isClosingWindow(id: result.entry.id)
                Group {
                    if isNormalIconGroupedStyle {
                        SwitcherGroupedIconRowView(
                            result: result,
                            icon: viewModel.icon(for: result.entry.pid),
                            isSelected: index == viewModel.selectedIndex,
                            isClosing: isClosing,
                            language: viewModel.resolvedLanguage
                        )
                    } else if usesCaptureRowStyle {
                        SwitcherCaptureRowView(
                            result: result,
                            thumbnail: viewModel.isCaptureActiveForCurrentMode
                                ? viewModel.thumbnail(for: result.entry)
                                : nil,
                            icon: viewModel.icon(for: result.entry.pid),
                            isSelected: index == viewModel.selectedIndex,
                            isClosing: isClosing,
                            showsAppHeader: !isGrouped,
                            language: viewModel.resolvedLanguage
                        )
                    } else {
                        SwitcherRowView(
                            result: result,
                            icon: viewModel.icon(for: result.entry.pid),
                            isSelected: index == viewModel.selectedIndex,
                            isClosing: isClosing,
                            showsAppInfo: !isGrouped,
                            language: viewModel.resolvedLanguage
                        )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectAndActivate(at: index)
                }

            case let .launchSectionHeader(title, hasPrecedingWindows):
                appLaunchSectionHeader(
                    title: title,
                    hasPrecedingWindows: hasPrecedingWindows
                )

            case let .appLaunch(unifiedIndex, result):
                AppLaunchRowView(
                    result: result,
                    icon: viewModel.icon(forAppURL: result.app.bundleURL),
                    isSelected: unifiedIndex == viewModel.selectedIndex,
                    launchBadgeTitle: viewModel.strings.launcherLaunchBadge
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectAndActivate(at: unifiedIndex)
                }
            }
        }
    }

    /// グルーピング表示時のアプリ見出し行（非選択・非クリック可能）
    /// - Parameters:
    ///   - applicationName: グループ見出しのアプリケーション名
    ///   - icon: アプリケーションアイコン画像
    ///   - matchedRanges: 検索一致時のアプリ名ハイライト範囲
    ///   - isFirstGroup: リスト先頭のグループかどうか
    private func appGroupHeaderView(
        applicationName: String,
        icon: NSImage?,
        matchedRanges: [Range<String.Index>],
        isFirstGroup: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isFirstGroup {
                Divider()
                    .overlay(.white.opacity(0.12))
                    .padding(.vertical, 4)
            }

            HStack(spacing: 8) {
                SwitcherRowStyling.iconView(icon: icon, fallbackSymbol: "macwindow", size: 18)

                let trimmedName = applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayAppName = trimmedName.isEmpty ? viewModel.strings.unknownApplication : applicationName
                Text(
                    SwitcherRowStyling.highlightedText(
                        displayAppName,
                        ranges: trimmedName.isEmpty ? [] : matchedRanges,
                        fontSize: 12,
                        baseWeight: .semibold,
                        baseColor: .primary,
                        highlightColor: .accentColor
                    )
                )
                .lineLimit(1)
                .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.top, isFirstGroup ? 2 : 4)
            .padding(.bottom, 2)
        }
    }

    /// アプリ起動候補セクションの区切り線と見出し
    /// - Parameters:
    ///   - title: セクション見出し文言
    ///   - hasPrecedingWindows: 上部にウィンドウ候補が 1 件以上存在するか
    private func appLaunchSectionHeader(title: String, hasPrecedingWindows: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasPrecedingWindows {
                Divider()
                    .overlay(.white.opacity(0.14))
                    .padding(.vertical, 4)
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.top, hasPrecedingWindows ? 4 : 2)
            .padding(.bottom, 2)
        }
    }

    /// 現在選択中の行へスクロール位置を追従させる
    /// - Parameters:
    ///   - proxy: 制御対象の `ScrollViewProxy`
    ///   - animated: 短いアニメーションを適用する場合は `true`
    private func scrollToSelectedRow(using proxy: ScrollViewProxy, animated: Bool) {
        scrollToRow(at: viewModel.selectedIndex, using: proxy, animated: animated)
    }

    /// 指定インデックスに対応する行へスクロール位置を追従させる
    /// - Parameters:
    ///   - index: 選択中の統一インデックス
    ///   - proxy: 制御対象の `ScrollViewProxy`
    ///   - animated: 短いアニメーションを適用する場合は `true`
    private func scrollToRow(
        at index: Int,
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        // 先頭候補（index == 0）へ戻る際は、LazyVStack 外の上端アンカーへ anchor: .top で確実に最上部（y == 0）へ復帰させる
        let targetID: String
        let anchor: UnitPoint
        if index == 0, !listRows.isEmpty {
            targetID = Self.topScrollAnchorID
            anchor = .top
        } else if let resolvedID = scrollTargetID(for: index) {
            targetID = resolvedID
            anchor = .center
        } else {
            return
        }

        if animated {
            withAnimation(.easeOut(duration: 0.08)) {
                proxy.scrollTo(targetID, anchor: anchor)
            }
        } else {
            proxy.scrollTo(targetID, anchor: anchor)
        }
    }

    /// 統一選択インデックスに対応する ScrollViewReader 用の識別子を返す
    /// - Parameter index: 統一インデックス
    /// - Returns: 該当行が存在する場合は識別子、範囲外なら nil
    private func scrollTargetID(for index: Int) -> String? {
        SwitcherListRow.scrollTargetID(
            for: index,
            windowResults: viewModel.displayedResults,
            appResults: viewModel.displayedAppResults,
            isShowingLaunchCandidates: viewModel.isShowingLaunchCandidates
        )
    }
}

/// リスト行内で使用するアイコン・ハイライト装飾・文字スタイル生成の共通部品
private enum SwitcherRowStyling {
    /// 検索一致範囲に太字とハイライトカラーを適用した AttributedString を構築する
    /// - Parameters:
    ///   - text: 元の表示テキスト
    ///   - ranges: ハイライト対象の文字位置範囲配列
    ///   - fontSize: フォントサイズ（既定値は 13）
    ///   - baseWeight: 非一致部分のフォントウェイト
    ///   - baseColor: 非一致部分の文字色
    ///   - highlightColor: 一致部分の文字色
    /// - Returns: 属性付き文字列
    static func highlightedText(
        _ text: String,
        ranges: [Range<String.Index>],
        fontSize: CGFloat = 13,
        baseWeight: Font.Weight,
        baseColor: Color,
        highlightColor: Color
    ) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.font = .system(size: fontSize, weight: baseWeight)
        attributed.foregroundColor = baseColor

        for range in ranges {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed),
                  lower < upper else {
                continue
            }
            attributed[lower..<upper].font = .system(size: fontSize, weight: .bold)
            attributed[lower..<upper].foregroundColor = highlightColor
        }

        return attributed
    }

    /// アプリアイコン（未取得時は代替 SF Symbol）を描画する
    /// - Parameters:
    ///   - icon: 表示対象のアプリアイコン画像
    ///   - fallbackSymbol: アイコン未取得時の代替 SF Symbol 名
    ///   - size: 描画サイズ（既定値は 24）
    /// - Returns: 指定サイズ相当のアイコンビュー
    @ViewBuilder
    static func iconView(icon: NSImage?, fallbackSymbol: String, size: CGFloat = 24) -> some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackSymbol)
                .resizable()
                .scaledToFit()
                .frame(width: max(size - 2, 12), height: max(size - 2, 12))
                .foregroundStyle(.secondary)
        }
    }

    /// 行の選択状態に応じた背景シェイプを返す
    /// - Parameter isSelected: 現在選択中かどうか
    /// - Returns: 選択ハイライト背景ビュー
    static func rowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.accentColor : Color.clear)
    }
}

/// スイッチャーリスト内の1行（フラット時はアイコン・アプリ名・タイトル、グルーピング時はタイトルのみインデント表示）を表す行ビュー
private struct SwitcherRowView: View {
    /// 表示対象の検索結果項目
    let result: WindowSearchResult
    /// 所有アプリのアイコン画像
    let icon: NSImage?
    /// 現在選択状態として強調表示するか
    let isSelected: Bool
    /// 現在クローズ／終了処理を実行中かどうか
    let isClosing: Bool
    /// 行内にアプリアイコンとアプリ名を表示するか（グルーピング ON 時は false）
    let showsAppInfo: Bool
    /// 補助表示テキストに使用する解決済み言語
    let language: ResolvedAppLanguage

    /// 行ビューの本体構築
    var body: some View {
        HStack(spacing: 12) {
            if showsAppInfo {
                SwitcherRowStyling.iconView(icon: icon, fallbackSymbol: "macwindow")

                HStack(spacing: 8) {
                    Text(
                        SwitcherRowStyling.highlightedText(
                            result.entry.displayApplicationName(in: language),
                            ranges: result.matchedAppNameRanges,
                            baseWeight: .semibold,
                            baseColor: isSelected ? .white : .primary,
                            highlightColor: isSelected ? .white : .accentColor
                        )
                    )
                    .fixedSize(horizontal: true, vertical: false)

                    Text(
                        SwitcherRowStyling.highlightedText(
                            result.entry.displayTitle(in: language),
                            ranges: result.matchedTitleRanges,
                            baseWeight: .regular,
                            baseColor: isSelected ? .white.opacity(0.9) : .secondary,
                            highlightColor: isSelected ? .white : .accentColor
                        )
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
            } else {
                Text(
                    SwitcherRowStyling.highlightedText(
                        result.entry.displayTitle(in: language),
                        ranges: result.matchedTitleRanges,
                        baseWeight: .regular,
                        baseColor: isSelected ? .white : .primary,
                        highlightColor: isSelected ? .white : .accentColor
                    )
                )
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            if isClosing {
                SwitcherClosingIndicatorView(usesLightAppearance: isSelected)
            }
        }
        .padding(.leading, showsAppInfo ? 12 : 34)
        .padding(.trailing, 12)
        .padding(.vertical, showsAppInfo ? 8 : 6)
        .background(SwitcherRowStyling.rowBackground(isSelected: isSelected))
    }
}

/// 通常スイッチャーのアイコン型（グルーピング ON）における1行（背景・枠線なしの大きなアプリアイコン・ウィンドウタイトル）を表す行ビュー
private struct SwitcherGroupedIconRowView: View {
    /// 表示対象の検索結果項目
    let result: WindowSearchResult
    /// 所有アプリのアイコン画像
    let icon: NSImage?
    /// 現在選択状態として強調表示するか
    let isSelected: Bool
    /// 現在クローズ／終了処理を実行中かどうか
    let isClosing: Bool
    /// 補助表示テキストに使用する解決済み言語
    let language: ResolvedAppLanguage

    /// 行ビューの本体構築
    var body: some View {
        HStack(spacing: 12) {
            largeIconView
                .frame(
                    width: SwitcherListView.groupedIconContainerSize,
                    height: SwitcherListView.groupedIconContainerSize
                )

            Text(
                SwitcherRowStyling.highlightedText(
                    result.entry.displayTitle(in: language),
                    ranges: result.matchedTitleRanges,
                    baseWeight: .medium,
                    baseColor: isSelected ? .white : .primary,
                    highlightColor: isSelected ? .white : .accentColor
                )
            )
            .lineLimit(2)
            .truncationMode(.tail)

            Spacer(minLength: 0)

            if isClosing {
                SwitcherClosingIndicatorView(usesLightAppearance: isSelected)
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(SwitcherRowStyling.rowBackground(isSelected: isSelected))
    }

    /// 灰色背景や枠線を持たない大きなアプリアイコン（未取得時は macwindow シンボルフォールバック）
    @ViewBuilder
    private var largeIconView: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: SwitcherListView.groupedIconDisplaySize,
                    height: SwitcherListView.groupedIconDisplaySize
                )
        } else {
            Image(systemName: "macwindow")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
        }
    }
}

/// 検索ランチャーのキャプチャ表示型における1行（小型サムネイル・アプリアイコン・アプリ名・ウィンドウタイトル）を表す行ビュー
private struct SwitcherCaptureRowView: View {
    /// 表示対象の検索結果項目
    let result: WindowSearchResult
    /// メモリ上のキャプチャサムネイル（未取得・取得不能時は nil）
    let thumbnail: NSImage?
    /// 所有アプリのアイコン画像
    let icon: NSImage?
    /// 現在選択状態として強調表示するか
    let isSelected: Bool
    /// 現在クローズ／終了処理を実行中かどうか
    let isClosing: Bool
    /// 行内にアプリアイコン・アプリ名ヘッダ行を表示するか（グルーピング ON 時は false）
    let showsAppHeader: Bool
    /// 補助表示テキストに使用する解決済み言語
    let language: ResolvedAppLanguage

    /// 行ビューの本体構築
    var body: some View {
        HStack(spacing: 12) {
            thumbnailPreview
                .frame(
                    width: SwitcherListView.captureThumbnailWidth,
                    height: SwitcherListView.captureThumbnailHeight
                )
                .background(Color.black.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(isSelected ? 0.35 : 0.14), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                if showsAppHeader {
                    HStack(spacing: 6) {
                        smallAppIcon

                        Text(
                            SwitcherRowStyling.highlightedText(
                                result.entry.displayApplicationName(in: language),
                                ranges: result.matchedAppNameRanges,
                                baseWeight: .semibold,
                                baseColor: isSelected ? .white : .primary,
                                highlightColor: isSelected ? .white : .accentColor
                            )
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }
                }

                Text(
                    SwitcherRowStyling.highlightedText(
                        result.entry.displayTitle(in: language),
                        ranges: result.matchedTitleRanges,
                        baseWeight: showsAppHeader ? .regular : .medium,
                        baseColor: showsAppHeader
                            ? (isSelected ? .white.opacity(0.9) : .secondary)
                            : (isSelected ? .white : .primary),
                        highlightColor: isSelected ? .white : .accentColor
                    )
                )
                .lineLimit(showsAppHeader ? 1 : 2)
                .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            if isClosing {
                SwitcherClosingIndicatorView(usesLightAppearance: isSelected)
            }
        }
        .padding(.leading, showsAppHeader ? 12 : 24)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(SwitcherRowStyling.rowBackground(isSelected: isSelected))
    }

    /// キャプチャサムネイルまたはアプリアイコンプレースホルダーを描画するプレビュー枠
    @ViewBuilder
    private var thumbnailPreview: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                Color.clear
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "macwindow")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                }
            }
        }
    }

    /// アプリ名左側に配置する小型アプリアイコン
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
                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
        }
    }
}

/// アプリ起動候補リスト内の1行（アプリアイコン・アプリ名・別名・起動バッジ）を表す行ビュー
private struct AppLaunchRowView: View {
    /// 表示対象のアプリ検索結果項目
    let result: AppSearchResult
    /// アプリケーションアイコン画像
    let icon: NSImage?
    /// 現在選択状態として強調表示するか
    let isSelected: Bool
    /// 右端に表示するローカライズ済み「起動」バッジ文言
    let launchBadgeTitle: String

    /// 行ビューの本体構築
    var body: some View {
        HStack(spacing: 12) {
            SwitcherRowStyling.iconView(icon: icon, fallbackSymbol: "app")

            HStack(spacing: 8) {
                Text(
                    SwitcherRowStyling.highlightedText(
                        result.app.displayName,
                        ranges: result.matchedDisplayNameRanges,
                        baseWeight: .semibold,
                        baseColor: isSelected ? .white : .primary,
                        highlightColor: isSelected ? .white : .accentColor
                    )
                )
                .fixedSize(horizontal: true, vertical: false)

                if !result.app.alternateName.isEmpty {
                    Text(
                        SwitcherRowStyling.highlightedText(
                            result.app.alternateName,
                            ranges: result.matchedAlternateNameRanges,
                            baseWeight: .regular,
                            baseColor: isSelected ? .white.opacity(0.9) : .secondary,
                            highlightColor: isSelected ? .white : .accentColor
                        )
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)

            Text(launchBadgeTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? .white.opacity(0.95) : .secondary)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.22) : Color.primary.opacity(0.08))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SwitcherRowStyling.rowBackground(isSelected: isSelected))
    }
}
