import CoreGraphics
import Foundation
import Testing
@testable import WintchCore

/// SwitcherPanelLayout の垂直配置判定・座標計算・一覧最大高さ算出を検証するテストスイート
@Suite("SwitcherPanelLayout テスト")
struct SwitcherPanelLayoutTests {
    /// モード・表示形式・グルーピング設定の全組み合わせに対して、
    /// 通常スイッチャーかつグルーピング OFF のキャプチャ表示型のみ中央配置となり、それ以外は上寄せ配置になることを検証する
    @Test("グルーピング OFF のキャプチャ表示型スイッチャーのみ中央配置となり他はすべて上寄せ配置となる")
    func verticalPlacementMatrix() {
        // 通常スイッチャー（グルーピング OFF）
        #expect(
            SwitcherPanelLayout.verticalPlacement(
                mode: .normal,
                normalDisplayStyle: .list,
                isNormalSwitcherGroupedByApp: false
            ) == .upperAnchored
        )
        #expect(
            SwitcherPanelLayout.verticalPlacement(
                mode: .normal,
                normalDisplayStyle: .icon,
                isNormalSwitcherGroupedByApp: false
            ) == .upperAnchored
        )
        #expect(
            SwitcherPanelLayout.verticalPlacement(
                mode: .normal,
                normalDisplayStyle: .capture,
                isNormalSwitcherGroupedByApp: false
            ) == .centered
        )

        // 通常スイッチャー（グルーピング ON）は全形式で上寄せ配置
        for style in SwitcherDisplayStyle.allCases {
            #expect(
                SwitcherPanelLayout.verticalPlacement(
                    mode: .normal,
                    normalDisplayStyle: style,
                    isNormalSwitcherGroupedByApp: true
                ) == .upperAnchored
            )
        }

        // 検索ランチャーは通常スイッチャーの設定にかかわらず常に上寄せ配置
        for style in SwitcherDisplayStyle.allCases {
            for isGrouped in [false, true] {
                #expect(
                    SwitcherPanelLayout.verticalPlacement(
                        mode: .launcher,
                        normalDisplayStyle: style,
                        isNormalSwitcherGroupedByApp: isGrouped
                    ) == .upperAnchored
                )
            }
        }
    }

    /// SwitcherViewModel.panelVerticalPlacement が現在のモード・表示形式・グルーピング状態に追従することを検証する
    @Test("SwitcherViewModel の panelVerticalPlacement がモードと設定変更に連動する")
    @MainActor
    func viewModelPanelVerticalPlacementReflectsModeAndSettings() {
        let windowService = MockWindowService()
        windowService.stubbedCandidates = [
            RawWindowCandidate(
                id: "w1",
                cgWindowID: 101,
                pid: 10,
                applicationName: "Safari",
                title: "Main",
                lastActivatedAt: Date()
            )
        ]

        let viewModel = SwitcherViewModel(
            windowService: windowService,
            hotKeyMonitor: MockHotKeyMonitor(),
            permissionService: MockAccessibilityPermissionService(),
            iconProvider: MockIconProvider(),
            screenRecordingPermissionService: MockScreenRecordingPermissionService(),
            windowCaptureService: MockWindowCaptureService(),
            normalDisplayStyle: .capture,
            launcherDisplayStyle: .capture,
            isNormalSwitcherGroupedByApp: false,
            isLauncherGroupedByApp: false
        )

        // 通常スイッチャー・キャプチャ表示型・グルーピング OFF → 中央配置
        viewModel.handleHotKeyEvent(.triggerPressed(isShiftPressed: false))
        #expect(viewModel.mode == .normal)
        #expect(viewModel.panelVerticalPlacement == .centered)

        // グルーピング ON へ切り替えると縦型リストとなるため上寄せ配置へ切り替わる
        viewModel.updateNormalSwitcherGrouping(true)
        #expect(viewModel.panelVerticalPlacement == .upperAnchored)

        // グルーピング OFF でもアイコン型やリスト型は上寄せ配置
        viewModel.updateNormalSwitcherGrouping(false)
        viewModel.updateNormalDisplayStyle(.icon)
        #expect(viewModel.panelVerticalPlacement == .upperAnchored)
        viewModel.updateNormalDisplayStyle(.list)
        #expect(viewModel.panelVerticalPlacement == .upperAnchored)

        // 検索ランチャーはキャプチャ表示型・グルーピング OFF でも上寄せ配置
        viewModel.cancel()
        viewModel.updateNormalDisplayStyle(.capture)
        viewModel.handleHotKeyEvent(.launcherTriggerPressed)
        #expect(viewModel.mode == .launcher)
        #expect(viewModel.panelVerticalPlacement == .upperAnchored)
    }

    /// 上寄せ配置の原点計算が中央配置より上方に配置され、パネル高さが変わっても上端位置が一定に保たれることを検証する
    @Test("上寄せ配置はディスプレイ上端基準で一定の上端位置に配置され中央配置より上に位置する")
    func upperAnchoredOriginPlacesHigherWithStableTopEdge() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1440, height: 900)
        let smallPanel = CGSize(width: 520, height: 140)
        let tallPanel = CGSize(width: 520, height: 640)

        let smallUpper = SwitcherPanelLayout.panelOrigin(
            panelSize: smallPanel,
            in: visibleFrame,
            placement: .upperAnchored
        )
        let tallUpper = SwitcherPanelLayout.panelOrigin(
            panelSize: tallPanel,
            in: visibleFrame,
            placement: .upperAnchored
        )
        let smallCentered = SwitcherPanelLayout.panelOrigin(
            panelSize: smallPanel,
            in: visibleFrame,
            placement: .centered
        )

        // 水平方向は常に中央配置
        #expect(smallUpper.x == smallCentered.x)
        #expect(tallUpper.x == smallCentered.x)

        // 期待上端位置: visibleFrame.maxY (950) - 900 * 0.14 (126) = 824
        let expectedTopY = visibleFrame.maxY - SwitcherPanelLayout.upperTopOffset(for: visibleFrame.height)
        #expect(abs((smallUpper.y + smallPanel.height) - expectedTopY) < 0.001)
        #expect(abs((tallUpper.y + tallPanel.height) - expectedTopY) < 0.001)

        // 中央配置より明確に上に表示され、下端も有効表示領域内に収まること
        #expect(smallUpper.y > smallCentered.y)
        #expect(tallUpper.y >= visibleFrame.minY)

        // 中央配置は WindowPlacement.centeredOrigin と完全一致すること
        #expect(
            smallCentered == WindowPlacement.centeredOrigin(windowSize: smallPanel, in: visibleFrame)
        )
    }

    /// 画面より大きいパネルや下端超過サイズでも有効領域内に安全クランプされることを検証する
    @Test("パネル高さが大きい場合も画面上端および下端に対して安全にクランプされる")
    func panelOriginClampsSafelyForLargePanels() {
        let visibleFrame = CGRect(x: 0, y: 40, width: 1280, height: 700)

        // 上端オフセット (98pt) を適用すると下端が minY を割る高さ (650pt) は minY にクランプされる
        let nearFullHeight = CGSize(width: 520, height: 650)
        let nearFullOrigin = SwitcherPanelLayout.panelOrigin(
            panelSize: nearFullHeight,
            in: visibleFrame,
            placement: .upperAnchored
        )
        #expect(nearFullOrigin.y == visibleFrame.minY)
        #expect(nearFullOrigin.y + nearFullHeight.height <= visibleFrame.maxY)

        // 画面高さを超える異常サイズ (800pt) でも上端が visibleFrame.maxY（メニューバー直下）を超えない
        let oversized = CGSize(width: 520, height: 800)
        let oversizedOrigin = SwitcherPanelLayout.panelOrigin(
            panelSize: oversized,
            in: visibleFrame,
            placement: .upperAnchored
        )
        #expect(oversizedOrigin.y + oversized.height == visibleFrame.maxY)
    }

    /// ディスプレイ有効高さとヘッダ有無に応じて一覧最大高さが従来 420pt より拡大し、画面内に収まることを検証する
    @Test("一覧の最大スクロール高さがディスプレイサイズとヘッダ有無に応じて動的に拡大し画面内へ収まる")
    func maxScrollHeightsScaleWithScreenHeightAndHeaders() {
        // 標準ノート（有効高さ 900pt）
        let normalList900 = SwitcherPanelLayout.maxListScrollHeight(
            availableScreenHeight: 900,
            hasSearchHeader: false,
            hasPermissionBanner: false
        )
        let launcherList900 = SwitcherPanelLayout.maxListScrollHeight(
            availableScreenHeight: 900,
            hasSearchHeader: true,
            hasPermissionBanner: false
        )
        let launcherBanner900 = SwitcherPanelLayout.maxListScrollHeight(
            availableScreenHeight: 900,
            hasSearchHeader: true,
            hasPermissionBanner: true
        )

        // 従来の固定値 420pt より大きく表示領域が広がっていること
        #expect(normalList900 > 420)
        #expect(launcherList900 > 420)
        #expect(launcherBanner900 > 420)
        #expect(normalList900 > launcherList900)
        #expect(launcherList900 > launcherBanner900)

        // 上端オフセット + ヘッダ予約 + リスト最大高さ + 下端余白 <= 画面高さ を満たすこと
        let topOffset900 = SwitcherPanelLayout.upperTopOffset(for: 900)
        let bottomMargin900 = SwitcherPanelLayout.upperBottomMargin(for: 900)
        #expect(
            topOffset900
                + SwitcherPanelLayout.searchHeaderReservedHeight
                + SwitcherPanelLayout.permissionBannerReservedHeight
                + launcherBanner900
                + bottomMargin900
                <= 900.001
        )

        // 大型外部ディスプレイ（有効高さ 1380pt）ではさらに多くのウィンドウを一覧できること
        let normalList1380 = SwitcherPanelLayout.maxListScrollHeight(
            availableScreenHeight: 1380,
            hasSearchHeader: false,
            hasPermissionBanner: false
        )
        #expect(normalList1380 > normalList900)

        // アイコン型グリッドも従来の 560pt 上限を超えて拡大すること
        let iconGrid1080 = SwitcherPanelLayout.maxIconGridScrollHeight(availableScreenHeight: 1080)
        #expect(iconGrid1080 > 560)

        // 中央配置のキャプチャ表示型グリッドは従来の 220pt〜560pt（72%）制約を維持すること
        #expect(SwitcherPanelLayout.maxCenteredCaptureGridScrollHeight(availableScreenHeight: 1080) == 560)
        #expect(SwitcherPanelLayout.maxCenteredCaptureGridScrollHeight(availableScreenHeight: 500) == 360)
        #expect(SwitcherPanelLayout.maxCenteredCaptureGridScrollHeight(availableScreenHeight: 200) == 220)

        // 極小ディスプレイ・異常値でも安全な正の高さを返すこと
        #expect(
            SwitcherPanelLayout.maxListScrollHeight(
                availableScreenHeight: 300,
                hasSearchHeader: true,
                hasPermissionBanner: true
            ) >= 48
        )
        #expect(
            SwitcherPanelLayout.maxListScrollHeight(
                availableScreenHeight: 0,
                hasSearchHeader: false,
                hasPermissionBanner: false
            ) >= 48
        )
    }
}
