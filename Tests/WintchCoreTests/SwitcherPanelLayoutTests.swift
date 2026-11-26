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

    /// リスト表示パネルの横幅がディスプレイ有効幅に応じて従来 520pt より拡大し、狭幅・広幅・異常値で安全にクランプされることを検証する
    @Test("リスト表示パネルの横幅がディスプレイ幅に応じて拡大し上下限で安全にクランプされる")
    func listPanelWidthScalesWithScreenWidthAndClampsSafely() {
        // 標準ノート（1280pt / 1440pt / 1512pt）では従来の固定幅 520pt より明確に広がる
        let width1280 = SwitcherPanelLayout.listPanelWidth(availableScreenWidth: 1280)
        let width1440 = SwitcherPanelLayout.listPanelWidth(availableScreenWidth: 1440)
        let width1512 = SwitcherPanelLayout.listPanelWidth(availableScreenWidth: 1512)
        #expect(width1280 == 680)
        #expect(width1440 == 720)
        #expect(width1512 == 756)
        #expect(width1280 > 520)
        #expect(width1440 > width1280)
        #expect(width1512 > width1440)

        // 大型外部ディスプレイ（1728pt / 1920pt / 2560pt）では上限 800pt にクランプされ間延びしない
        #expect(SwitcherPanelLayout.listPanelWidth(availableScreenWidth: 1728) == 800)
        #expect(SwitcherPanelLayout.listPanelWidth(availableScreenWidth: 1920) == 800)
        #expect(SwitcherPanelLayout.listPanelWidth(availableScreenWidth: 2560) == 800)

        // 狭い画面では画面幅 85% 以内にクランプされ画面外へはみ出さない
        let width700 = SwitcherPanelLayout.listPanelWidth(availableScreenWidth: 700)
        #expect(width700 == 595)
        #expect(width700 <= 700 * SwitcherPanelLayout.maxListScreenWidthRatio)

        let width500 = SwitcherPanelLayout.listPanelWidth(availableScreenWidth: 500)
        #expect(width500 == 425)
        #expect(width500 <= 500 * SwitcherPanelLayout.maxListScreenWidthRatio)

        // 極小画面では有効幅を超えない安全な幅に収まり、0 以下の異常値では既定の最小目標幅へフォールバックする
        #expect(SwitcherPanelLayout.listPanelWidth(availableScreenWidth: 300) == 300)
        #expect(SwitcherPanelLayout.listPanelWidth(availableScreenWidth: 0) == SwitcherPanelLayout.minListPanelWidth)
        #expect(SwitcherPanelLayout.listPanelWidth(availableScreenWidth: -100) == SwitcherPanelLayout.minListPanelWidth)
    }

    /// SwitcherPanelResizeStabilizer が端数丸め・往復振動検出・連続更新上限・サイクルリセットを正しく制御することを検証する
    @Test("SwitcherPanelResizeStabilizer が端数誤差・往復振動・連続更新上限を遮断しサイクルリセット後に再追従する")
    func resizeStabilizerPreventsFractionalJitterOscillationAndRunaway() {
        // 1. 下限クランプ・整数ポイント丸め・非有限値の安全な正規化
        #expect(
            SwitcherPanelResizeStabilizer.normalizedSize(from: CGSize(width: 120.4, height: 30.2))
                == CGSize(width: 200, height: 48)
        )
        #expect(
            SwitcherPanelResizeStabilizer.normalizedSize(from: CGSize(width: 800.4, height: 664.6))
                == CGSize(width: 800, height: 665)
        )
        #expect(
            SwitcherPanelResizeStabilizer.normalizedSize(
                from: CGSize(width: CGFloat.nan, height: CGFloat.infinity)
            ) == CGSize(width: 200, height: 48)
        )

        var stabilizer = SwitcherPanelResizeStabilizer(maxUpdatesPerCycle: 4)

        // 2. 非 Retina 環境で起きやすい 0.4pt 等のサブピクセル差は無視する
        #expect(
            stabilizer.resolveTargetSize(
                requestedSize: CGSize(width: 800.2, height: 664.4),
                currentFrameSize: CGSize(width: 800, height: 664)
            ) == nil
        )
        #expect(stabilizer.appliedCountInCycle == 0)

        // 3. 1pt 以上の変化（664 -> 665）は初回のみ許可し、直後に 665 -> 664 へ戻る往復振動は即座に遮断する
        let first = stabilizer.resolveTargetSize(
            requestedSize: CGSize(width: 800, height: 664.6),
            currentFrameSize: CGSize(width: 800, height: 664)
        )
        #expect(first == CGSize(width: 800, height: 665))
        #expect(stabilizer.appliedCountInCycle == 1)

        let pingPong = stabilizer.resolveTargetSize(
            requestedSize: CGSize(width: 800, height: 664),
            currentFrameSize: CGSize(width: 800, height: 665)
        )
        #expect(pingPong == nil)
        #expect(stabilizer.appliedCountInCycle == 1)

        // 4. サイクルリセット後は同じ 664 への正当な縮小も再び許可される
        stabilizer.resetCycle()
        let afterReset = stabilizer.resolveTargetSize(
            requestedSize: CGSize(width: 800, height: 664),
            currentFrameSize: CGSize(width: 800, height: 665)
        )
        #expect(afterReset == CGSize(width: 800, height: 664))

        // 5. 単調増加する異常連打でも maxUpdatesPerCycle（4 回）で確実に打ち切る
        var current = CGSize(width: 800, height: 664)
        var applied = 1
        for step in 1...10 {
            let nextRequest = CGSize(width: 800, height: 664 + CGFloat(step * 10))
            if let resolved = stabilizer.resolveTargetSize(requestedSize: nextRequest, currentFrameSize: current) {
                current = resolved
                applied += 1
            }
        }
        #expect(applied == 4)
        #expect(stabilizer.appliedCountInCycle == 4)
    }

    /// リスト行の保守的最小高さに基づき、多数候補時のみ固定最大高さモードへ切り替わることを検証する
    @Test("リスト行の最小保証高さに応じて固定最大高さモードと非遅延モードが適切に分岐する")
    func listFixedMaxScrollHeightThresholdBehavior() {
        let now = Date()
        /// テスト用のダミーウィンドウ行配列を生成するローカルヘルパー
        func makeWindowRows(count: Int) -> [SwitcherListRow] {
            (0..<count).map { index in
                let entry = WindowEntry(
                    id: "w-\(index)",
                    cgWindowID: UInt32(100 + index),
                    pid: Int32(10 + index),
                    bundleIdentifier: "com.example.app\(index)",
                    applicationName: "App\(index)",
                    windowTitle: "Window \(index)",
                    lastActivatedAt: now
                )
                return .window(index: index, result: WindowSearchResult(entry: entry))
            }
        }

        let maxScrollHeight: CGFloat = 748

        // 少数件数（3 件）は maxScrollHeight 未満のため非遅延 VStack モード
        let fewRows = makeWindowRows(count: 3)
        #expect(
            SwitcherPanelLayout.shouldUseFixedMaxScrollHeight(
                rows: fewRows,
                isGrouped: false,
                usesTallWindowRow: true,
                maxScrollHeight: maxScrollHeight
            ) == false
        )

        // キャプチャ行 15 件（最小高さ >= 900pt）は確実に 748pt を超えるため固定最大高さ＋LazyVStack モード
        let manyCaptureRows = makeWindowRows(count: 15)
        #expect(
            SwitcherPanelLayout.shouldUseFixedMaxScrollHeight(
                rows: manyCaptureRows,
                isGrouped: false,
                usesTallWindowRow: true,
                maxScrollHeight: maxScrollHeight
            ) == true
        )

        // 通常グルーピングリスト行 30 件も確実に 748pt を超えるため固定最大高さモード
        let manyGroupedListRows = makeWindowRows(count: 30)
        #expect(
            SwitcherPanelLayout.shouldUseFixedMaxScrollHeight(
                rows: manyGroupedListRows,
                isGrouped: true,
                usesTallWindowRow: false,
                maxScrollHeight: maxScrollHeight
            ) == true
        )

        // 0 件および異常な maxScrollHeight <= 0 では常に false
        #expect(
            SwitcherPanelLayout.shouldUseFixedMaxScrollHeight(
                rows: [],
                isGrouped: false,
                usesTallWindowRow: false,
                maxScrollHeight: maxScrollHeight
            ) == false
        )
        #expect(
            SwitcherPanelLayout.shouldUseFixedMaxScrollHeight(
                rows: manyCaptureRows,
                isGrouped: false,
                usesTallWindowRow: true,
                maxScrollHeight: 0
            ) == false
        )
    }
}
