import AppKit
import Testing
@testable import WintchCore

/// ウィンドウ配置計算および最前面表示プレゼンターの挙動を検証するテストスイート
@Suite("WindowFrontPresenter テスト")
struct WindowFrontPresenterTests {
    /// AppKit の前面化・キー化・最小化解除の呼び出し順序と回数を観測するテスト用ウィンドウ
    @MainActor
    private final class SpyWindow: NSWindow {
        /// 記録された呼び出しイベント名一覧
        var events: [String] = []
        /// 最小化状態のスタブ値
        var stubbedMiniaturized = false
        /// 表示状態のスタブ値
        var stubbedVisible = false
        /// 外部記録用クロージャ
        var onEvent: ((String) -> Void)?

        override var isMiniaturized: Bool {
            stubbedMiniaturized
        }

        override var isVisible: Bool {
            stubbedVisible
        }

        override func deminiaturize(_ sender: Any?) {
            stubbedMiniaturized = false
            record("deminiaturize")
        }

        override func orderFrontRegardless() {
            stubbedVisible = true
            record("orderFrontRegardless")
        }

        override func makeKeyAndOrderFront(_ sender: Any?) {
            stubbedVisible = true
            record("makeKeyAndOrderFront")
        }

        override func orderOut(_ sender: Any?) {
            stubbedVisible = false
            record("orderOut")
        }

        /// イベントを順序付きで記録する
        /// - Parameter name: 発生したメソッド名
        private func record(_ name: String) {
            events.append(name)
            onEvent?(name)
        }
    }

    // MARK: - WindowPlacement 単体テスト

    /// マルチディスプレイ環境でカーソルが存在するディスプレイの有効領域が優先選択されることを検証する
    @Test("WindowPlacement はカーソル所在ディスプレイの visibleFrame を優先選択する")
    func selectsScreenContainingCursor() {
        let primary = ScreenFrameSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
        )
        let secondary = ScreenFrameSnapshot(
            frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        )

        let selected = WindowPlacement.targetVisibleFrame(
            cursorLocation: CGPoint(x: 2000, y: 500),
            screens: [primary, secondary],
            fallbackVisibleFrame: primary.visibleFrame
        )

        #expect(selected == secondary.visibleFrame)
    }

    /// カーソル位置がいずれのディスプレイにも一致しない場合はフォールバック領域を返すことを検証する
    @Test("WindowPlacement はカーソル非該当時にフォールバックまたは先頭ディスプレイを返す")
    func fallsBackWhenCursorOutsideScreens() {
        let first = ScreenFrameSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 40, width: 1440, height: 835)
        )
        let fallback = CGRect(x: 100, y: 100, width: 800, height: 600)

        let withFallback = WindowPlacement.targetVisibleFrame(
            cursorLocation: CGPoint(x: -500, y: -500),
            screens: [first],
            fallbackVisibleFrame: fallback
        )
        #expect(withFallback == fallback)

        let withoutFallback = WindowPlacement.targetVisibleFrame(
            cursorLocation: CGPoint(x: -500, y: -500),
            screens: [first],
            fallbackVisibleFrame: nil
        )
        #expect(withoutFallback == first.visibleFrame)
    }

    /// 有効表示領域に対して標準ウィンドウを中央配置し、画面より大きい場合も上端が収まることを検証する
    @Test("WindowPlacement は中央原点座標の計算と大サイズウィンドウの上端クランプを正しく行う")
    func computesCenteredOriginAndClampsOversizedWindow() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1000, height: 800)

        let centered = WindowPlacement.centeredOrigin(
            windowSize: CGSize(width: 480, height: 500),
            in: visibleFrame
        )
        #expect(centered == CGPoint(x: 360, y: 200))

        // 高さが有効領域を超える場合も、maxY（タイトルバー上端）が visibleFrame.maxY を超えない
        let oversized = WindowPlacement.centeredOrigin(
            windowSize: CGSize(width: 1200, height: 900),
            in: visibleFrame
        )
        #expect(oversized.x == 100)
        #expect(oversized.y == -50)
        #expect(oversized.y + 900 == visibleFrame.maxY)
    }

    // MARK: - WindowFrontPresenter 単体テスト

    /// 即時表示時とメニュー閉鎖後フォローアップの両方でアクティブ化・前面化が正しい順序で実行されることを検証する
    @Test("presentFrontmost は即時に最前面化・アクティブ化し次ランループのフォローアップも実行する")
    @MainActor
    func presentFrontmostActivatesAndOrdersFrontImmediatelyAndOnFollowUp() {
        var timeline: [String] = []
        var scheduledClosures: [@MainActor () -> Void] = []

        let screen = ScreenFrameSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
            visibleFrame: CGRect(x: 0, y: 25, width: 1600, height: 950)
        )
        let presenter = WindowFrontPresenter(
            activateApplication: {
                timeline.append("activate")
            },
            screenEnvironmentProvider: {
                (cursorLocation: CGPoint(x: 500, y: 500), screens: [screen], mainVisibleFrame: screen.visibleFrame)
            },
            scheduleFollowUp: { work in
                scheduledClosures.append(work)
            }
        )

        let window = SpyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.stubbedMiniaturized = true
        window.onEvent = { event in
            timeline.append(event)
        }

        presenter.presentFrontmost(window)

        // 事前準備・即時最前面化の検証（タイトルバー込みの window.frame.size 基準で中央配置される）
        let expectedOrigin = WindowPlacement.centeredOrigin(
            windowSize: window.frame.size,
            in: screen.visibleFrame
        )
        #expect(window.collectionBehavior.contains(.moveToActiveSpace))
        #expect(window.level == .normal)
        #expect(window.frame.origin == expectedOrigin)
        #expect(timeline == [
            "deminiaturize",
            "activate",
            "orderFrontRegardless",
            "makeKeyAndOrderFront"
        ])
        #expect(scheduledClosures.count == 1)

        // MenuBarExtra メニュー閉鎖後の次ランループ再前面化をシミュレートする
        scheduledClosures[0]()
        #expect(timeline == [
            "deminiaturize",
            "activate",
            "orderFrontRegardless",
            "makeKeyAndOrderFront",
            "activate",
            "orderFrontRegardless",
            "makeKeyAndOrderFront"
        ])
    }

    /// 次ランループ発火前にユーザーがウィンドウを閉じていた場合、不要な再アクティブ化を行わないことを検証する
    @Test("ウィンドウがフォローアップ実行前に閉じられた場合は再前面化をスキップする")
    @MainActor
    func skipsFollowUpWhenWindowAlreadyClosed() {
        var activateCount = 0
        var scheduledClosures: [@MainActor () -> Void] = []

        let presenter = WindowFrontPresenter(
            activateApplication: {
                activateCount += 1
            },
            screenEnvironmentProvider: {
                (cursorLocation: .zero, screens: [], mainVisibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800))
            },
            scheduleFollowUp: { work in
                scheduledClosures.append(work)
            }
        )

        let window = SpyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        presenter.presentFrontmost(window)
        #expect(activateCount == 1)
        #expect(scheduledClosures.count == 1)

        // フォローアップ前にウィンドウを閉じる
        window.orderOut(nil)
        scheduledClosures[0]()

        // 再アクティブ化・再表示が走らないこと
        #expect(activateCount == 1)
        #expect(window.events == ["orderFrontRegardless", "makeKeyAndOrderFront", "orderOut"])
    }

    /// 常駐アプリとしての非侵襲性を保つため、最前面表示処理が Dock アイコン用ポリシー変更や常時フローティング固定を行わないことを検証する
    @Test("presentFrontmost は常時フローティング固定を行わず通常ウィンドウレベルを維持する")
    @MainActor
    func keepsNormalWindowLevelWithoutPersistentFloating() {
        let presenter = WindowFrontPresenter(
            activateApplication: {},
            screenEnvironmentProvider: {
                (cursorLocation: .zero, screens: [], mainVisibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800))
            },
            scheduleFollowUp: { work in
                work()
            }
        )
        let window = SpyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        presenter.presentFrontmost(window)

        #expect(window.level == .normal)
    }
}
