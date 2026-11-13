import AppKit
import SwiftUI

/// 他アプリのフォーカスを奪わずに画面最前面へフローティング表示する NSPanel ラッパー
@MainActor
public final class SwitcherPanel: NSPanel {
    /// パネルが外部クリック等でフォーカスを失った際に呼ばれるキャンセル通知
    public var onResignActive: (() -> Void)?

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
        self.hasShadow = false
        self.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView = hostingView
    }

    /// パネル内のクリック等のためにキーウィンドウになれることを許可する
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

    /// 現在アクティブなディスプレイの中央にパネルを配置して前面表示する
    public func showCentered() {
        if let hostingView = contentView {
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

        orderFrontRegardless()
        makeKey()
    }

    /// パネルを非表示にする
    public func hidePanel() {
        orderOut(nil)
    }
}
