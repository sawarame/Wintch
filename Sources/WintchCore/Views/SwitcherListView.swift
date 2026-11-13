import SwiftUI

/// 画面中央のフローティングパネル内に表示されるウィンドウ一覧の縦型リストビュー
public struct SwitcherListView: View {
    /// スイッチャーの状態管理を行う ViewModel
    private let viewModel: SwitcherViewModel

    /// リストビューを初期化する
    /// - Parameter viewModel: スイッチャー ViewModel
    public init(viewModel: SwitcherViewModel) {
        self.viewModel = viewModel
    }

    /// ビューの本体構築
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 4) {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                        SwitcherRowView(
                            entry: entry,
                            icon: viewModel.icon(for: entry.pid),
                            isSelected: index == viewModel.selectedIndex
                        )
                        .id(entry.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectAndActivate(at: index)
                        }
                    }
                }
                .padding(10)
            }
            .frame(width: 520)
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                guard viewModel.entries.indices.contains(newIndex) else { return }
                let targetID = viewModel.entries[newIndex].id
                withAnimation(.easeOut(duration: 0.08)) {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 12)
    }
}

/// スイッチャーリスト内の1行（アプリアイコン・アプリ名・ウィンドウタイトルのみ）を表す行ビュー
private struct SwitcherRowView: View {
    /// 表示対象のウィンドウ項目
    let entry: WindowEntry
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
                Text(entry.applicationName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .fixedSize(horizontal: true, vertical: false)

                Text(entry.displayTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
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
}
