import SwiftUI

/// 画面中央のフローティングパネル内に表示されるウィンドウ一覧（およびランチャー検索バー）のビュー
public struct SwitcherListView: View {
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

    /// ビューの本体構築
    public var body: some View {
        VStack(spacing: 0) {
            if viewModel.mode == .launcher {
                searchHeaderView
                Divider()
                    .overlay(.white.opacity(0.14))
            }

            if viewModel.mode == .launcher && viewModel.displayedResults.isEmpty {
                emptyResultView
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
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 12)
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

    /// 検索一致 0 件時の案内表示
    private var emptyResultView: some View {
        HStack {
            Spacer(minLength: 0)
            Text("一致するウィンドウがありません")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.vertical, 24)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
    }

    /// ウィンドウ候補一覧の縦型スクロールリスト
    private var resultListView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 4) {
                    ForEach(Array(viewModel.displayedResults.enumerated()), id: \.element.id) { index, result in
                        SwitcherRowView(
                            result: result,
                            icon: viewModel.icon(for: result.entry.pid),
                            isSelected: index == viewModel.selectedIndex
                        )
                        .id(result.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectAndActivate(at: index)
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                guard viewModel.displayedResults.indices.contains(newIndex) else { return }
                let targetID = viewModel.displayedResults[newIndex].id
                withAnimation(.easeOut(duration: 0.08)) {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
        }
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
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "macwindow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(
                    highlightedText(
                        result.entry.applicationName,
                        ranges: result.matchedAppNameRanges,
                        baseWeight: .semibold,
                        baseColor: isSelected ? .white : .primary,
                        highlightColor: isSelected ? .white : .accentColor
                    )
                )
                .fixedSize(horizontal: true, vertical: false)

                Text(
                    highlightedText(
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
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }

    /// 検索一致範囲に太字とハイライトカラーを適用した AttributedString を構築する
    /// - Parameters:
    ///   - text: 元の表示テキスト
    ///   - ranges: ハイライト対象の文字位置範囲配列
    ///   - baseWeight: 非一致部分のフォントウェイト
    ///   - baseColor: 非一致部分の文字色
    ///   - highlightColor: 一致部分の文字色
    /// - Returns: 属性付き文字列
    private func highlightedText(
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
}
