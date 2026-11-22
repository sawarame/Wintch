import SwiftUI

/// 画面中央のフローティングパネル内に表示されるウィンドウ一覧（およびランチャー検索バー）のビュー
public struct SwitcherListView: View {
    /// ランチャーのキャプチャ表示行に配置する小型サムネイルの横幅
    public static let captureThumbnailWidth: CGFloat = 80

    /// ランチャーのキャプチャ表示行に配置する小型サムネイルの高さ
    public static let captureThumbnailHeight: CGFloat = 50

    /// スイッチャーの状態管理を行う ViewModel
    private let viewModel: SwitcherViewModel

    /// コンテンツ高さ変化時にパネル側へリサイズを通知するコールバック
    private let onContentHeightChanged: ((CGFloat) -> Void)?

    /// リストビューを初期化する
    /// - Parameters:
    ///   - viewModel: スイッチャー ViewModel
    ///   - onContentHeightChanged: コンテンツ高さ変化時の通知クロージャ
    public init(
        viewModel: SwitcherViewModel,
        onContentHeightChanged: ((CGFloat) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onContentHeightChanged = onContentHeightChanged
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

    /// ビューの本体構築
    public var body: some View {
        VStack(spacing: 0) {
            if viewModel.mode == .launcher {
                searchHeaderView
                Divider()
                    .overlay(.white.opacity(0.14))

                if isLauncherCaptureStyle && !viewModel.isScreenRecordingGranted {
                    permissionBannerView
                    Divider()
                        .overlay(.white.opacity(0.14))
                }
            }

            if let emptyState = viewModel.emptyState {
                emptyResultView(for: emptyState)
            } else {
                resultListView
            }
        }
        .frame(width: 520)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.height) { _, newHeight in
                        onContentHeightChanged?(newHeight)
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
            message: SwitcherCaptureGridView.permissionBannerMessage,
            horizontalPadding: 14
        )
    }

    /// 候補 0 件時の案内表示
    /// - Parameter state: 現在の空状態種別
    private func emptyResultView(for state: LauncherEmptyState) -> some View {
        HStack {
            Spacer(minLength: 0)
            Text(state.message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.vertical, 24)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
    }

    /// 表示対象のウィンドウ候補およびアプリ起動候補を統合した単一リスト行配列
    private var listRows: [SwitcherListRow] {
        SwitcherListRow.buildRows(
            windowResults: viewModel.displayedResults,
            appResults: viewModel.displayedAppResults,
            isShowingLaunchCandidates: viewModel.isShowingLaunchCandidates,
            launchSectionHeaderTitle: viewModel.launchSectionHeaderTitle
        )
    }

    /// ウィンドウ候補および（ランチャー検索時の）アプリ起動候補を統合表示する縦型スクロールリスト
    private var resultListView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 4) {
                    // ForEach 要素の id と ScrollViewReader の scrollTo 対象 ID を一致させるため単一モデルで描画する
                    ForEach(listRows) { row in
                        switch row {
                        case let .window(index, result):
                            Group {
                                if isLauncherCaptureStyle {
                                    SwitcherCaptureRowView(
                                        result: result,
                                        thumbnail: viewModel.thumbnail(for: result.entry),
                                        icon: viewModel.icon(for: result.entry.pid),
                                        isSelected: index == viewModel.selectedIndex
                                    )
                                } else {
                                    SwitcherRowView(
                                        result: result,
                                        icon: viewModel.icon(for: result.entry.pid),
                                        isSelected: index == viewModel.selectedIndex
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
                                isSelected: unifiedIndex == viewModel.selectedIndex
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectAndActivate(at: unifiedIndex)
                            }
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                scrollToSelectedRow(using: proxy, animated: false)
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                scrollToRow(at: newIndex, using: proxy, animated: true)
            }
            .onChange(of: viewModel.searchQuery) { _, _ in
                // 手動スクロール後に selectedIndex が 0 のまま検索更新された場合も、上部余白ごと先頭候補が見える位置へ戻す
                scrollToSelectedRow(using: proxy, animated: false)
            }
            .onChange(of: viewModel.mode) { _, newMode in
                guard newMode != .inactive else { return }
                scrollToSelectedRow(using: proxy, animated: false)
            }
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
        guard let targetID = scrollTargetID(for: index) else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.08)) {
                proxy.scrollTo(targetID, anchor: .center)
            }
        } else {
            proxy.scrollTo(targetID, anchor: .center)
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
    ///   - baseWeight: 非一致部分のフォントウェイト
    ///   - baseColor: 非一致部分の文字色
    ///   - highlightColor: 一致部分の文字色
    /// - Returns: 属性付き文字列
    static func highlightedText(
        _ text: String,
        ranges: [Range<String.Index>],
        baseWeight: Font.Weight,
        baseColor: Color,
        highlightColor: Color
    ) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.font = .system(size: 13, weight: baseWeight)
        attributed.foregroundColor = baseColor

        for range in ranges {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed),
                  lower < upper else {
                continue
            }
            attributed[lower..<upper].font = .system(size: 13, weight: .bold)
            attributed[lower..<upper].foregroundColor = highlightColor
        }

        return attributed
    }

    /// アプリアイコン（未取得時は代替 SF Symbol）を描画する
    /// - Parameters:
    ///   - icon: 表示対象のアプリアイコン画像
    ///   - fallbackSymbol: アイコン未取得時の代替 SF Symbol 名
    /// - Returns: 24x24 相当のアイコンビュー
    @ViewBuilder
    static func iconView(icon: NSImage?, fallbackSymbol: String) -> some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: fallbackSymbol)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
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

/// スイッチャーリスト内の1行（アプリアイコン・アプリ名・ウィンドウタイトルのみ）を表す行ビュー
private struct SwitcherRowView: View {
    /// 表示対象の検索結果項目
    let result: WindowSearchResult
    /// 所有アプリのアイコン画像
    let icon: NSImage?
    /// 現在選択状態として強調表示するか
    let isSelected: Bool

    /// 行ビューの本体構築
    var body: some View {
        HStack(spacing: 12) {
            SwitcherRowStyling.iconView(icon: icon, fallbackSymbol: "macwindow")

            HStack(spacing: 8) {
                Text(
                    SwitcherRowStyling.highlightedText(
                        result.entry.applicationName,
                        ranges: result.matchedAppNameRanges,
                        baseWeight: .semibold,
                        baseColor: isSelected ? .white : .primary,
                        highlightColor: isSelected ? .white : .accentColor
                    )
                )
                .fixedSize(horizontal: true, vertical: false)

                Text(
                    SwitcherRowStyling.highlightedText(
                        result.entry.displayTitle,
                        ranges: result.matchedTitleRanges,
                        baseWeight: .regular,
                        baseColor: isSelected ? .white.opacity(0.9) : .secondary,
                        highlightColor: isSelected ? .white : .accentColor
                    )
                )
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SwitcherRowStyling.rowBackground(isSelected: isSelected))
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
                HStack(spacing: 6) {
                    smallAppIcon

                    Text(
                        SwitcherRowStyling.highlightedText(
                            result.entry.applicationName,
                            ranges: result.matchedAppNameRanges,
                            baseWeight: .semibold,
                            baseColor: isSelected ? .white : .primary,
                            highlightColor: isSelected ? .white : .accentColor
                        )
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                }

                Text(
                    SwitcherRowStyling.highlightedText(
                        result.entry.displayTitle,
                        ranges: result.matchedTitleRanges,
                        baseWeight: .regular,
                        baseColor: isSelected ? .white.opacity(0.9) : .secondary,
                        highlightColor: isSelected ? .white : .accentColor
                    )
                )
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
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

            Text("起動")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? .white.opacity(0.95) : .secondary)
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
