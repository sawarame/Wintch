import SwiftUI

/// メニューバーの「表示形式」セクション配下に並べる機能別サブメニュー入り口の種別
public enum MenuBarDisplaySubmenuKind: Equatable, Sendable, CaseIterable {
    /// 通常スイッチャー用の表示設定サブメニュー入り口
    case normalSwitcher
    /// 検索ランチャー用の表示設定サブメニュー入り口
    case searchLauncher
}

/// メニューバーの「表示形式」セクション内に配置する各サブメニュー入り口の構成情報
public struct MenuBarDisplaySubmenuDescriptor: Equatable, Sendable {
    /// サブメニューが担当する機能の種別
    public let kind: MenuBarDisplaySubmenuKind

    /// サブメニューのタイトル文言
    public let title: String

    /// サブメニュー内に並べる表示形式選択肢のタイトル一覧
    public let displayStyleTitles: [String]

    /// サブメニュー内に配置するアプリグルーピングトグルの文言
    public let groupByAppTitle: String

    /// サブメニュー構成情報を初期化する
    /// - Parameters:
    ///   - kind: サブメニューが担当する機能の種別
    ///   - title: サブメニューのタイトル文言
    ///   - displayStyleTitles: 表示形式選択肢のタイトル一覧
    ///   - groupByAppTitle: アプリグルーピングトグルの文言
    public init(
        kind: MenuBarDisplaySubmenuKind,
        title: String,
        displayStyleTitles: [String],
        groupByAppTitle: String
    ) {
        self.kind = kind
        self.title = title
        self.displayStyleTitles = displayStyleTitles
        self.groupByAppTitle = groupByAppTitle
    }
}

/// メニューバー常駐アイコンから開くメニュー本体を構築するビュー
public struct MenuBarContentView: View {
    /// アプリ全体の状態・設定操作を統括するコーディネーター
    private let coordinator: AppCoordinator

    /// メニューバーコンテンツビューを初期化する
    /// - Parameter coordinator: アプリ全体の状態・設定操作を統括するコーディネーター
    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// 指定言語における「表示形式」セクション配下のサブメニュー入り口構成一覧を返す
    /// - Parameter language: 解決済みの表示言語
    /// - Returns: 通常スイッチャー・検索ランチャーの順に並んだ独立サブメニュー構成一覧
    nonisolated public static func displaySubmenuDescriptors(
        in language: ResolvedAppLanguage
    ) -> [MenuBarDisplaySubmenuDescriptor] {
        let strings = AppStrings(language: language)
        return [
            MenuBarDisplaySubmenuDescriptor(
                kind: .normalSwitcher,
                title: strings.menuBarNormalSwitcher,
                displayStyleTitles: SwitcherDisplayStyle.allCases.map { $0.displayName(in: language) },
                groupByAppTitle: strings.groupByAppToggle
            ),
            MenuBarDisplaySubmenuDescriptor(
                kind: .searchLauncher,
                title: strings.menuBarSearchLauncher,
                displayStyleTitles: LauncherDisplayStyle.allCases.map { $0.displayName(in: language) },
                groupByAppTitle: strings.groupByAppToggle
            )
        ]
    }

    /// メニューバーと設定画面で共有される通常スイッチャー表示形式の双方向バインディング
    internal var normalDisplayStyleBinding: Binding<SwitcherDisplayStyle> {
        Binding(
            get: { coordinator.normalDisplayStyle },
            set: { coordinator.updateNormalDisplayStyle($0) }
        )
    }

    /// メニューバーと設定画面で共有される検索ランチャー表示形式の双方向バインディング
    internal var launcherDisplayStyleBinding: Binding<LauncherDisplayStyle> {
        Binding(
            get: { coordinator.launcherDisplayStyle },
            set: { coordinator.updateLauncherDisplayStyle($0) }
        )
    }

    /// メニューバーと設定画面で共有される通常スイッチャーのアプリグルーピング設定の双方向バインディング
    internal var normalGroupingBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isNormalSwitcherGroupedByApp },
            set: { coordinator.updateNormalSwitcherGrouping($0) }
        )
    }

    /// メニューバーと設定画面で共有される検索ランチャーのアプリグルーピング設定の双方向バインディング
    internal var launcherGroupingBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isLauncherGroupedByApp },
            set: { coordinator.updateLauncherGrouping($0) }
        )
    }

    /// メニューバーのトップレベル項目および各機能別サブメニューを構築する
    public var body: some View {
        let language = coordinator.resolvedLanguage
        let strings = coordinator.strings

        if coordinator.permissionStatus == .denied {
            Button(strings.menuBarAccessibilityRequired) {
                coordinator.openPermissionGuide()
            }

            Divider()
        }

        // 通常スイッチャーと検索ランチャーの区切りを明確にするため、機能ごとに独立したサブメニュー入り口を設ける
        Section(strings.menuBarDisplayStyle) {
            normalSwitcherMenu(language: language, strings: strings)
            searchLauncherMenu(language: language, strings: strings)
        }

        Divider()

        Button(strings.menuBarOpenSettings) {
            coordinator.openSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button(coordinator.appIdentity.quitMenuTitle(in: language)) {
            coordinator.quit()
        }
        .keyboardShortcut("q")
    }

    /// 通常スイッチャーの表示形式およびグルーピング設定サブメニューを構築する
    /// - Parameters:
    ///   - language: 現在の解決済み表示言語
    ///   - strings: 現在言語のローカライズ文言テーブル
    /// - Returns: 通常スイッチャー用サブメニュービュー
    @ViewBuilder
    private func normalSwitcherMenu(
        language: ResolvedAppLanguage,
        strings: AppStrings
    ) -> some View {
        Menu(strings.menuBarNormalSwitcher) {
            Picker(strings.menuBarDisplayStyle, selection: normalDisplayStyleBinding) {
                ForEach(SwitcherDisplayStyle.allCases, id: \.self) { style in
                    Text(style.displayName(in: language)).tag(style)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Toggle(strings.groupByAppToggle, isOn: normalGroupingBinding)
        }
    }

    /// 検索ランチャーの表示形式およびグルーピング設定サブメニューを構築する
    /// - Parameters:
    ///   - language: 現在の解決済み表示言語
    ///   - strings: 現在言語のローカライズ文言テーブル
    /// - Returns: 検索ランチャー用サブメニュービュー
    @ViewBuilder
    private func searchLauncherMenu(
        language: ResolvedAppLanguage,
        strings: AppStrings
    ) -> some View {
        Menu(strings.menuBarSearchLauncher) {
            Picker(strings.menuBarDisplayStyle, selection: launcherDisplayStyleBinding) {
                ForEach(LauncherDisplayStyle.allCases, id: \.self) { style in
                    Text(style.displayName(in: language)).tag(style)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Toggle(strings.groupByAppToggle, isOn: launcherGroupingBinding)
        }
    }
}
