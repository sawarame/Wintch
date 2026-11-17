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

    /// パネルを初期化する
    /// - Parameter contentView: パネル内にホストする SwiftUI コンテンツビュー
    public init(contentView: SwitcherContentView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 240),
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
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        // ホスティングビューのレイヤー自体も角丸でクリップし、四隅の描画漏れを防ぐ
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 14
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        self.contentView = hostingView
    }

    /// 表示中に上端位置を固定したまま指定高さへ下方向リサイズする（リスト型互換）
    /// - Parameter height: 新しいコンテンツ高さ
    public func updateAnchoredHeight(to height: CGFloat) {
        updateAnchoredSize(to: CGSize(width: frame.width, height: height))
    }

    /// 表示中に上端位置および水平中心を維持したまま指定サイズへリサイズする
    /// - Parameter size: 新しいコンテンツサイズ
    public func updateAnchoredSize(to size: CGSize) {
        guard isVisible, currentMode != .inactive, let anchoredTopY else {
            return
        }

        let targetWidth = max(size.width, 200)
        let targetHeight = max(size.height, 48)
        guard abs(frame.height - targetHeight) > 0.5 || abs(frame.width - targetWidth) > 0.5 else {
            return
        }

        let newOriginY = anchoredTopY - targetHeight
        let newOriginX = frame.midX - (targetWidth / 2.0)
        setFrame(
            NSRect(x: newOriginX, y: newOriginY, width: targetWidth, height: targetHeight),
            display: true
        )
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

    /// 指定モードに応じて現在アクティブなディスプレイの中央にパネルを配置して前面表示する
    /// - Parameters:
    ///   - mode: 表示するスイッチャーモード（.normal または .launcher）
    ///   - activateApp: 表示時に自アプリを一時アクティブ化するか（nil 時は .launcher のみ true）
    public func show(mode: SwitcherMode, activateApp: Bool? = nil) {
        currentMode = mode
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
                setContentSize(fittingSize)
            }
        }

        if let screenFrame = targetScreen?.visibleFrame {
            let originX = screenFrame.midX - (frame.width / 2.0)
            let originY = screenFrame.midY - (frame.height / 2.0)
            setFrameOrigin(NSPoint(x: originX, y: originY))
        } else {
            center()
        }

        // 表示中のウィンドウクローズ等で高さが変わった際に上端位置を維持するため両モードで上端座標を記録する
        anchoredTopY = frame.maxY
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
        show(mode: .normal)
    }

    /// 表示中に上端位置を固定したままコンテンツ高さの変化に応じて下方向へリサイズする
    public func updateAnchoredHeightIfNeeded() {
        guard isVisible, currentMode != .inactive, let anchoredTopY, let hostingView = contentView else {
            return
        }

        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let targetHeight = max(fittingSize.height, 48)
        let targetWidth = fittingSize.width > 0 ? fittingSize.width : frame.width

        guard abs(frame.height - targetHeight) > 0.5 || abs(frame.width - targetWidth) > 0.5 else {
            return
        }

        let newOriginY = anchoredTopY - targetHeight
        let newOriginX = frame.midX - (targetWidth / 2.0)
        setFrame(
            NSRect(x: newOriginX, y: newOriginY, width: targetWidth, height: targetHeight),
            display: true
        )
        // リサイズ後の角丸形状に合わせて OS 側のウィンドウシャドウを再計算する
        invalidateShadow()
    }

    /// パネルを非表示にし、必要であれば直前アプリへフォーカスを戻す
    /// - Parameter restorePreviousApp: キャンセル時などに直前アプリを再アクティブ化する場合は true
    public func hidePanel(restorePreviousApp: Bool = false) {
        let appToRestore = restorePreviousApp ? previousFrontmostApp : nil
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
