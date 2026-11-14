import AppKit
import SwiftUI

/// 他アプリのフォーカスを奪わずに画面最前面へフローティング表示する NSPanel ラッパー
/// ランチャーモード時は IME 入力のために一時的なアプリアクティブ化および上端固定リサイズを制御する
@MainActor
public final class SwitcherPanel: NSPanel {
    /// パネルが外部クリック等でフォーカスを失った際に呼ばれるキャンセル通知
    public var onResignActive: (() -> Void)?

    /// ランチャー表示中に上端位置を固定するための Y 座標アンカー（AppKit 座標系での frame.maxY）
    private var anchoredTopY: CGFloat?

    /// ランチャーモード起動直前に最前面だったアプリケーション（キャンセル時のフォーカス復元用）
    private var previousFrontmostApp: NSRunningApplication?

    /// 現在のパネル表示モード
    private var currentMode: SwitcherMode = .inactive

    /// パネルを初期化する
    /// - Parameter contentView: パネル内にホストする SwiftUI リストビュー
    public init(contentView: SwitcherListView) {
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

    /// ランチャー表示中に上端位置を固定したまま指定高さへ下方向リサイズする
    /// - Parameter height: 新しいコンテンツ高さ
    public func updateAnchoredHeight(to height: CGFloat) {
        guard isVisible, currentMode == .launcher, let anchoredTopY else {
            return
        }

        let targetHeight = max(height, 48)
        guard abs(frame.height - targetHeight) > 0.5 else {
            return
        }

        let newOriginY = anchoredTopY - targetHeight
        setFrame(
            NSRect(x: frame.origin.x, y: newOriginY, width: frame.width, height: targetHeight),
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
    /// - Parameter mode: 表示するスイッチャーモード（.normal または .launcher）
    public func show(mode: SwitcherMode) {
        currentMode = mode
        if mode == .launcher {
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

        if let hostingView = contentView {
            hostingView.layoutSubtreeIfNeeded()
            let fittingSize = hostingView.fittingSize
            if fittingSize.width > 0 && fittingSize.height > 0 {
                setContentSize(fittingSize)
            }
        }

        // マウスカーソルが存在するディスプレイ（見つからない場合はメインディスプレイ）の中央を計算する
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        if let screenFrame = targetScreen?.visibleFrame {
            let originX = screenFrame.midX - (frame.width / 2.0)
            let originY = screenFrame.midY - (frame.height / 2.0)
            setFrameOrigin(NSPoint(x: originX, y: originY))
        } else {
            center()
        }

        if mode == .launcher {
            // 検索中のリサイズで検索バーが上下に移動しないよう起動時の上端座標を固定する
            anchoredTopY = frame.maxY
            // 日本語 IME 変換ウィンドウおよび入力ソース切替を確実に機能させるため一時的にアクティブ化する
            NSApplication.shared.activate()
        } else {
            anchoredTopY = nil
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

    /// ランチャー表示中に上端位置を固定したままコンテンツ高さの変化に応じて下方向へリサイズする
    public func updateAnchoredHeightIfNeeded() {
        guard isVisible, currentMode == .launcher, let anchoredTopY, let hostingView = contentView else {
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
        setFrame(
            NSRect(x: frame.origin.x, y: newOriginY, width: targetWidth, height: targetHeight),
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
        currentMode = .inactive

        orderOut(nil)
        appToRestore?.activate()
    }
}
