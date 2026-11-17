import AppKit

/// メニューバー常駐アプリ（.accessory）において標準ウィンドウを確実に最前面・キーウィンドウとして表示するプレゼンター
@MainActor
public final class WindowFrontPresenter: WindowFrontPresenting {
    /// スクリーン情報取得用の戻り値型エイリアス
    public typealias ScreenEnvironment = (
        cursorLocation: CGPoint,
        screens: [ScreenFrameSnapshot],
        mainVisibleFrame: CGRect?
    )

    /// 自アプリを最前面へアクティブ化するクロージャ
    private let activateApplication: @MainActor () -> Void

    /// 現在のマウス位置・ディスプレイ構成を取得するクロージャ
    private let screenEnvironmentProvider: @MainActor () -> ScreenEnvironment

    /// メニュー閉鎖後のフォローアップ処理を次ランループへスケジュールするクロージャ
    private let scheduleFollowUp: @MainActor (@escaping @MainActor () -> Void) -> Void

    /// 標準の AppKit API を用いてプレゼンターを初期化する
    public convenience init() {
        self.init(
            activateApplication: {
                // macOS 14 以降の協調的アクティブ化で他アプリからフォーカスを譲られないケースを防ぐため強制アクティブ化する
                NSApplication.shared.activate(ignoringOtherApps: true)
            },
            screenEnvironmentProvider: {
                let snapshots = NSScreen.screens.map {
                    ScreenFrameSnapshot(frame: $0.frame, visibleFrame: $0.visibleFrame)
                }
                return (
                    cursorLocation: NSEvent.mouseLocation,
                    screens: snapshots,
                    mainVisibleFrame: NSScreen.main?.visibleFrame
                )
            },
            scheduleFollowUp: { work in
                // MenuBarExtra のメニュー閉鎖完了後にフォーカスが直前アプリへ引き戻されないよう次ランループで再適用する
                DispatchQueue.main.async {
                    Task { @MainActor in
                        work()
                    }
                }
            }
        )
    }

    /// テスト用にアクティブ化・画面取得・フォローアップスケジューラを注入して初期化する
    /// - Parameters:
    ///   - activateApplication: アプリをアクティブ化する処理
    ///   - screenEnvironmentProvider: ディスプレイ・カーソル情報を返すプロバイダ
    ///   - scheduleFollowUp: 次ランループ等でフォローアップを実行するスケジューラ
    public init(
        activateApplication: @escaping @MainActor () -> Void,
        screenEnvironmentProvider: @escaping @MainActor () -> ScreenEnvironment,
        scheduleFollowUp: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void
    ) {
        self.activateApplication = activateApplication
        self.screenEnvironmentProvider = screenEnvironmentProvider
        self.scheduleFollowUp = scheduleFollowUp
    }

    /// 指定ウィンドウを現在スペース上のアクティブ画面中央へ配置し、最前面・キーウィンドウとして表示する
    /// - Parameter window: 表示対象の NSWindow
    public func presentFrontmost(_ window: NSWindow) {
        prepareWindow(window)
        positionCenteredOnActiveScreen(window)
        bringToFront(window)

        scheduleFollowUp { [weak self, weak window] in
            // 次ランループまでにユーザーがウィンドウを閉じた場合は再表示・フォーカス奪取を行わない
            guard let self, let window, window.isVisible else { return }
            self.bringToFront(window)
        }
    }

    /// スペース追従・最小化解除・通常ウィンドウレベル維持の事前設定を行う
    /// - Parameter window: 対象ウィンドウ
    private func prepareWindow(_ window: NSWindow) {
        // 既に別スペースで開かれていた場合でもメニューバー操作元の現在スペースへ移動させる
        window.collectionBehavior.insert(.moveToActiveSpace)
        // 設定画面からシステム設定や他アプリへ切り替えた際に邪魔にならないよう通常レベルを維持する
        window.level = .normal
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
    }

    /// マウスカーソル所在ディスプレイ（またはメインディスプレイ）の有効領域中央へ配置する
    /// - Parameter window: 対象ウィンドウ
    private func positionCenteredOnActiveScreen(_ window: NSWindow) {
        let environment = screenEnvironmentProvider()
        guard let visibleFrame = WindowPlacement.targetVisibleFrame(
            cursorLocation: environment.cursorLocation,
            screens: environment.screens,
            fallbackVisibleFrame: environment.mainVisibleFrame
        ) else {
            window.center()
            return
        }

        let origin = WindowPlacement.centeredOrigin(windowSize: window.frame.size, in: visibleFrame)
        window.setFrameOrigin(origin)
    }

    /// アプリをアクティブ化した上でウィンドウを強制的に最前面・キーウィンドウへ引き上げる
    /// - Parameter window: 対象ウィンドウ
    private func bringToFront(_ window: NSWindow) {
        activateApplication()
        // 非アクティブ状態から呼ばれる瞬間でも他アプリウィンドウの背後に沈まないよう orderFrontRegardless を併用する
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}
