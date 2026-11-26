import AppKit
import SwiftUI

/// 他アプリのフォーカスを奪わずに画面最前面へフローティング表示する NSPanel ラッパー
/// ランチャーモード時は IME 入力のために一時的なアプリアクティブ化および上端固定リサイズを制御する
@MainActor
public final class SwitcherPanel: NSPanel {
    /// パネルが外部クリック等でフォーカスを失った際に呼ばれるキャンセル通知
    public var onResignActive: (() -> Void)?

    /// レイアウト計算直前に表示先ディスプレイの利用可能サイズを伝える通知
    public var onPrepareScreenSize: ((CGSize) -> Void)?

    /// ランチャー表示中に上端位置を固定するための Y 座標アンカー（AppKit 座標系での frame.maxY）
    private var anchoredTopY: CGFloat?

    /// ランチャーモード起動直前に最前面だったアプリケーション（キャンセル時のフォーカス復元用）
    private var previousFrontmostApp: NSRunningApplication?

    /// 現在のパネル表示モード
    private var currentMode: SwitcherMode = .inactive

    /// 現在の表示セッションで自アプリの一時アクティブ化を実施したかどうか
    private var didActivateAppForCurrentSession: Bool = false

    /// 連続リサイズ要求の整数丸め・往復振動検出・上限ガードを管理する安定化器
    private var resizeStabilizer = SwitcherPanelResizeStabilizer()

    /// `setFrame` 実行中に発生する同期レイアウト由来の再入フィードバックを遮断するフラグ
    private var isApplyingFrameUpdate: Bool = false

    /// 非同期コアレッシング中の最新リサイズ要求サイズ
    private var pendingTargetSize: CGSize?

    /// メインランループ次ターンへの非同期リサイズ反映をスケジュール済みかどうか
    private var hasScheduledSizeUpdate: Bool = false

    /// 表示セッション切替時に旧セッションの遅延リサイズ要求を破棄するための世代トークン
    private var resizeSessionToken: Int = 0

    /// テスト検証用：現在の表示セッション中に実際に `setFrame` を適用した回数
    internal private(set) var appliedResizeCountForTesting: Int = 0

    /// パネルを初期化する
    /// - Parameter contentView: パネル内にホストする SwiftUI コンテンツビュー
    public init(contentView: SwitcherContentView) {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SwitcherPanelLayout.minListPanelWidth,
                height: 240
            ),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // フローティング・全スペース参加・フルスクリーン補助を設定する
        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isReleasedWhenClosed = false
        self.isOpaque = false
        self.backgroundColor = .clear
        // ウィンドウ外側に自然な角丸シャドウを描画するため OS 側のシャドウを有効化する
        self.hasShadow = true
        self.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: contentView)
        // NSHostingView の自動ウィンドウサイズ制約が SwitcherPanel 側の上端固定 setFrame と
        // 競合・押し戻し（リサイズフィードバックループ）を起こさないよう、サイズ制御をパネル側へ一本化する
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        // ホスティングビューのレイヤー自体も角丸でクリップし、四隅の描画漏れを防ぐ
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 14
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        self.contentView = hostingView
    }

    /// コンテンツ構成（検索結果・グルーピング・言語等）の変化開始を通知し、リサイズ安定化サイクルをリセットする
    public func beginContentResizeCycle() {
        resizeStabilizer.resetCycle()
    }

    /// 表示中に上端位置を固定したまま指定高さへ下方向リサイズする（リスト型互換）
    /// - Parameter height: 新しいコンテンツ高さ
    public func updateAnchoredHeight(to height: CGFloat) {
        updateAnchoredSize(to: CGSize(width: frame.width, height: height))
    }

    /// 表示中に上端位置および水平中心を維持したまま指定サイズへリサイズをスケジュールする
    /// SwiftUI の RunLoop Observer 内からの同期 `setFrame` による無限レイアウト循環を防ぐため、
    /// 再入を遮断しつつ最新サイズのみを次ターンへ非同期コアレッシング実行する
    /// - Parameter size: 新しいコンテンツサイズ
    public func updateAnchoredSize(to size: CGSize) {
        guard isVisible, currentMode != .inactive, anchoredTopY != nil else {
            return
        }
        // `setFrame` 内部の同期レイアウトから戻ってきたサイズ通知はフィードバックループ原因のため無視する
        guard !isApplyingFrameUpdate else {
            return
        }

        pendingTargetSize = size
        guard !hasScheduledSizeUpdate else {
            return
        }
        hasScheduledSizeUpdate = true
        let expectedToken = resizeSessionToken
        // 現在の RunLoop Observer（SwiftUI UpdateGroup）を抜けた後の次ターンで 1 回だけ適用する
        // `.common` モードでスケジュールし、イベント追跡中や RunLoop 駆動テスト環境でも確実に反映する
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                self?.flushPendingAnchoredSizeUpdate(expectedToken: expectedToken)
            }
        }
    }

    /// コアレッシング済みの最新リサイズ要求を取り出してパネルフレームへ反映する
    /// - Parameter expectedToken: スケジュール時点の表示セッショントークン
    private func flushPendingAnchoredSizeUpdate(expectedToken: Int) {
        hasScheduledSizeUpdate = false
        guard expectedToken == resizeSessionToken,
              let requestedSize = pendingTargetSize else {
            return
        }
        pendingTargetSize = nil
        applyAnchoredSizeIfNeeded(requestedSize)
    }

    /// 安定化器で正規化・振動検出を通過したサイズのみを上端固定で `NSWindow.setFrame` へ適用する
    /// - Parameter size: 適用候補のコンテンツサイズ
    private func applyAnchoredSizeIfNeeded(_ size: CGSize) {
        guard isVisible, currentMode != .inactive, let anchoredTopY, !isApplyingFrameUpdate else {
            return
        }
        guard let targetSize = resizeStabilizer.resolveTargetSize(
            requestedSize: size,
            currentFrameSize: frame.size
        ) else {
            return
        }

        // 非 Retina 環境（backingScale = 1.0）でも端数ズレが起きないよう整数ポイント座標で適用する
        let newOriginY = (anchoredTopY - targetSize.height).rounded()
        let newOriginX = (frame.midX - (targetSize.width / 2.0)).rounded()
        isApplyingFrameUpdate = true
        defer { isApplyingFrameUpdate = false }
        setFrame(
            NSRect(x: newOriginX, y: newOriginY, width: targetSize.width, height: targetSize.height),
            display: true
        )
        appliedResizeCountForTesting += 1
        // リサイズ後の角丸形状に合わせて OS 側のウィンドウシャドウを再計算する
        invalidateShadow()
    }

    /// パネル内のクリックやテキスト入力のためにキーウィンドウになれることを許可する
    public override var canBecomeKey: Bool { true }

    /// メインウィンドウにはならないように制限する
    public override var canBecomeMain: Bool { false }

    /// パネルがキーウィンドウでなくなった際（外部クリック等）にキャンセル処理を実行する
    public override func resignKey() {
        super.resignKey()
        if isVisible {
            onResignActive?()
        }
    }

    /// 指定モードおよび垂直配置スタイルに応じて現在アクティブなディスプレイへパネルを配置して前面表示する
    /// - Parameters:
    ///   - mode: 表示するスイッチャーモード（.normal または .launcher）
    ///   - activateApp: 表示時に自アプリを一時アクティブ化するか（nil 時は .launcher のみ true）
    ///   - verticalPlacement: パネルの垂直配置スタイル（既定値はディスプレイ上部寄りの上端固定 `.upperAnchored`）
    public func show(
        mode: SwitcherMode,
        activateApp: Bool? = nil,
        verticalPlacement: SwitcherPanelVerticalPlacement = .upperAnchored
    ) {
        currentMode = mode
        resizeSessionToken &+= 1
        pendingTargetSize = nil
        hasScheduledSizeUpdate = false
        resizeStabilizer.resetCycle()
        appliedResizeCountForTesting = 0
        let shouldActivate = activateApp ?? (mode == .launcher)
        didActivateAppForCurrentSession = shouldActivate
        if shouldActivate {
            // キャンセル時に元アプリへフォーカスを戻せるよう直前アプリを記録する
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousFrontmostApp = frontmost
            } else {
                previousFrontmostApp = nil
            }
        } else {
            previousFrontmostApp = nil
        }

        // マウスカーソルが存在するディスプレイ（見つからない場合はメインディスプレイ）を特定し、
        // コンテンツの列数・最大高さ計算に必要な利用可能サイズを先に反映する
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        if let visibleSize = targetScreen?.visibleFrame.size {
            onPrepareScreenSize?(visibleSize)
        }

        if let hostingView = contentView {
            hostingView.layoutSubtreeIfNeeded()
            let fittingSize = hostingView.fittingSize
            if fittingSize.width > 0 && fittingSize.height > 0 {
                let normalized = SwitcherPanelResizeStabilizer.normalizedSize(from: fittingSize)
                setContentSize(normalized)
            }
        }

        if let screenFrame = targetScreen?.visibleFrame {
            let origin = SwitcherPanelLayout.panelOrigin(
                panelSize: frame.size,
                in: screenFrame,
                placement: verticalPlacement
            )
            setFrameOrigin(NSPoint(x: origin.x.rounded(), y: origin.y.rounded()))
        } else {
            center()
        }

        // 表示中のウィンドウクローズ等で高さが変わった際に上端位置を維持するため両モードで上端座標を記録する
        anchoredTopY = frame.maxY.rounded()
        if shouldActivate {
            // 日本語 IME 変換やセキュア入力解除のため一時的に自アプリをアクティブ化する
            NSApplication.shared.activate()
        }

        orderFrontRegardless()
        makeKey()
        // 表示時のコンテンツサイズに合わせて OS 側のウィンドウシャドウを再計算する
        invalidateShadow()
    }

    /// 通常スイッチャー用の従来互換メソッド（画面中央表示）
    public func showCentered() {
        show(mode: .normal, verticalPlacement: .centered)
    }

    /// 表示中に上端位置を固定したままコンテンツ高さの変化に応じて下方向へリサイズする
    public func updateAnchoredHeightIfNeeded() {
        guard isVisible, currentMode != .inactive, anchoredTopY != nil, !isApplyingFrameUpdate, let hostingView = contentView else {
            return
        }

        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let targetWidth = fittingSize.width > 0 ? fittingSize.width : frame.width
        updateAnchoredSize(to: CGSize(width: targetWidth, height: fittingSize.height))
    }

    /// パネルを非表示にし、必要であれば直前アプリへフォーカスを戻す
    /// - Parameter restorePreviousApp: キャンセル時などに直前アプリを再アクティブ化する場合は true
    public func hidePanel(restorePreviousApp: Bool = false) {
        let appToRestore = restorePreviousApp ? previousFrontmostApp : nil
        resizeSessionToken &+= 1
        pendingTargetSize = nil
        hasScheduledSizeUpdate = false
        resizeStabilizer.resetCycle()
        anchoredTopY = nil
        previousFrontmostApp = nil
        didActivateAppForCurrentSession = false
        currentMode = .inactive

        orderOut(nil)
        appToRestore?.activate()
    }

    /// ウィンドウクローズ時の自動 Space 移動等で一時的に失われたパネルの前面表示・フォーカスを復元する
    /// - Parameter mode: 復元対象の現在モード
    public func restoreFocusIfNeeded(mode: SwitcherMode) {
        guard isVisible, currentMode == mode, mode != .inactive else { return }
        if mode == .launcher || didActivateAppForCurrentSession {
            // アクティブ表示セッション中はキーボード入力を受け付けるためアプリ自体も最前面へ戻す
            NSApplication.shared.activate()
        }
        orderFrontRegardless()
        makeKey()
    }
}
