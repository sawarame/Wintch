import Foundation
import Testing
@testable import WintchCore

/// アプリ別ウィンドウプロファイルおよび未表示補助ウィンドウ幾何シグネチャの単体テスト
@Suite("AppWindowProfile テスト")
struct AppWindowProfileTests {
    /// 未登録および nil の Bundle ID に対して標準プロファイルが返されることを検証する
    @Test("未登録・nilのBundle IDには標準プロファイルを返す")
    func unknownBundleIdentifierFallsBackToDefaultProfile() {
        let nilProfile = AppWindowProfileRegistry.profile(for: nil)
        #expect(nilProfile.bundleIdentifier == nil)
        #expect(nilProfile.offscreenCGPolicy == .allow)
        #expect(nilProfile.hiddenBackingSignatures.isEmpty)

        let unknownProfile = AppWindowProfileRegistry.profile(for: "com.example.unknown")
        #expect(unknownProfile.offscreenCGPolicy == .allow)
        #expect(unknownProfile.hiddenBackingSignatures.isEmpty)
    }

    /// 登録済みアプリ（システム設定・メモ・Google Chrome・Figma）の個別プロファイルが正しく解決されることを検証する
    @Test("システム設定・メモ・Google Chrome・Figmaの個別プロファイルを正しく解決する")
    func registeredProfilesResolveExpectedPolicies() {
        let settingsProfile = AppWindowProfileRegistry.profile(for: "com.apple.systempreferences")
        #expect(settingsProfile.bundleIdentifier == "com.apple.systempreferences")
        #expect(settingsProfile.offscreenCGPolicy == .singleRepresentativeOnly)

        let notesProfile = AppWindowProfileRegistry.profile(for: "com.apple.Notes")
        #expect(notesProfile.bundleIdentifier == "com.apple.Notes")
        #expect(notesProfile.offscreenCGPolicy == .requireAXOrMenuTitle)
        #expect(
            notesProfile.hiddenBackingSignatures.contains(
                HiddenBackingWindowSignature(width: 475, height: 600, requiresZeroOriginX: false)
            )
        )

        let chromeProfile = AppWindowProfileRegistry.profile(for: "com.google.Chrome")
        #expect(chromeProfile.bundleIdentifier == "com.google.Chrome")
        #expect(chromeProfile.offscreenCGPolicy == .requireAXOrMenuTitle)
        #expect(chromeProfile.hiddenBackingSignatures.isEmpty)

        let figmaProfile = AppWindowProfileRegistry.profile(for: "com.figma.Desktop")
        #expect(figmaProfile.bundleIdentifier == "com.figma.Desktop")
        #expect(figmaProfile.offscreenCGPolicy == .requireAXOrMenuTitle)
        #expect(
            figmaProfile.hiddenBackingSignatures.contains(
                HiddenBackingWindowSignature(width: 400, height: 600, requiresZeroOriginX: false)
            )
        )
    }

    /// 共通 500x500 シグネチャとメモ固有 475x600 シグネチャが安全ガード付きで一致判定されることを検証する
    @Test("未表示バックキングウィンドウの幾何シグネチャが安全ガード付きで一致する")
    func hiddenBackingSignatureMatchesSafelyWithGuards() {
        // 全アプリ共通：画面左端（x ≈ 0）の 500x500 未表示バックキングウィンドウに一致
        let genericBacking500 = RawWindowCandidate(
            id: "cg-gemini-500",
            cgWindowID: 7261,
            pid: 72152,
            bundleIdentifier: "com.google.GeminiMacOS",
            applicationName: "Gemini",
            title: nil,
            bounds: WindowBounds(x: 0, y: 580, width: 500, height: 500),
            axSubrole: nil,
            hasAXInfo: false,
            isOnScreen: false
        )
        #expect(AppWindowProfileRegistry.isHiddenBackingWindow(genericBacking500))

        // 許容誤差（2.0pt）境界内は一致し、x が大きく離れた 500x500 は共通ルールでは誤一致しない
        let nearZero500 = RawWindowCandidate(
            id: "cg-near-500",
            pid: 999,
            bundleIdentifier: "com.example.app",
            applicationName: "Example",
            title: "   ",
            bounds: WindowBounds(x: 1.5, y: 400, width: 501.0, height: 499.0),
            axSubrole: nil,
            hasAXInfo: false,
            isOnScreen: nil
        )
        #expect(AppWindowProfileRegistry.isHiddenBackingWindow(nearZero500))

        let centered500 = RawWindowCandidate(
            id: "cg-centered-500",
            pid: 999,
            bundleIdentifier: "com.example.app",
            applicationName: "Example",
            title: nil,
            bounds: WindowBounds(x: 400, y: 200, width: 500, height: 500),
            axSubrole: nil,
            hasAXInfo: false,
            isOnScreen: false
        )
        #expect(!AppWindowProfileRegistry.isHiddenBackingWindow(centered500))

        // メモ固有：画面中央付近（x ≠ 0）の 475x600 未表示補助ウィンドウに一致
        let notesAux475 = RawWindowCandidate(
            id: "cg-notes-475",
            cgWindowID: 7247,
            pid: 71905,
            bundleIdentifier: "com.apple.Notes",
            applicationName: "メモ",
            title: nil,
            bounds: WindowBounds(x: 828, y: 253, width: 475, height: 600),
            axSubrole: nil,
            hasAXInfo: false,
            isOnScreen: false
        )
        #expect(AppWindowProfileRegistry.isHiddenBackingWindow(notesAux475))

        // 他アプリの 475x600 はメモ固有ルールに巻き込まれない
        let otherApp475 = RawWindowCandidate(
            id: "cg-other-475",
            pid: 888,
            bundleIdentifier: "com.example.other",
            applicationName: "Other",
            title: nil,
            bounds: WindowBounds(x: 828, y: 253, width: 475, height: 600),
            axSubrole: nil,
            hasAXInfo: false,
            isOnScreen: false
        )
        #expect(!AppWindowProfileRegistry.isHiddenBackingWindow(otherApp475))

        // Figma 固有：画面中央付近の 400x600 未表示補助ウィンドウに一致し、他アプリには巻き込まれない
        let figmaAux400 = RawWindowCandidate(
            id: "cg-figma-400",
            cgWindowID: 175,
            pid: 4111,
            bundleIdentifier: "com.figma.Desktop",
            applicationName: "Figma",
            title: nil,
            cgWindowName: "Figma",
            layer: 3,
            bounds: WindowBounds(x: 760, y: 208, width: 400, height: 600),
            axSubrole: nil,
            hasAXInfo: false,
            isOnScreen: false
        )
        #expect(AppWindowProfileRegistry.isHiddenBackingWindow(figmaAux400))

        let otherApp400 = RawWindowCandidate(
            id: "cg-other-400",
            pid: 889,
            bundleIdentifier: "com.example.other",
            applicationName: "Other",
            title: nil,
            bounds: WindowBounds(x: 760, y: 208, width: 400, height: 600),
            axSubrole: nil,
            hasAXInfo: false,
            isOnScreen: false
        )
        #expect(!AppWindowProfileRegistry.isHiddenBackingWindow(otherApp400))
    }

    /// ユーザーが実際に開いているウィンドウ（AX 捕捉済み・画面表示中・タイトル保持）は
    /// 同一座標・同サイズであっても絶対に除外しないことを検証する
    @Test("AX捕捉済み・表示中・タイトル保持の実ウィンドウは幾何一致しても誤除外しない")
    func realWindowsAreNeverMatchedAsHiddenBacking() {
        let axReal500 = RawWindowCandidate(
            id: "ax-real-500",
            pid: 100,
            bundleIdentifier: "com.apple.Notes",
            applicationName: "メモ",
            title: nil,
            bounds: WindowBounds(x: 0, y: 580, width: 500, height: 500),
            axRole: "AXWindow",
            axSubrole: "AXStandardWindow",
            hasAXInfo: true,
            isOnScreen: false
        )
        #expect(!AppWindowProfileRegistry.isHiddenBackingWindow(axReal500))

        let onScreen475 = RawWindowCandidate(
            id: "cg-onscreen-475",
            pid: 100,
            bundleIdentifier: "com.apple.Notes",
            applicationName: "メモ",
            title: nil,
            bounds: WindowBounds(x: 828, y: 253, width: 475, height: 600),
            axSubrole: nil,
            hasAXInfo: false,
            isOnScreen: true
        )
        #expect(!AppWindowProfileRegistry.isHiddenBackingWindow(onScreen475))

        let titled500 = RawWindowCandidate(
            id: "cg-titled-500",
            pid: 100,
            bundleIdentifier: "com.example.app",
            applicationName: "Example",
            title: "メモウィンドウ",
            bounds: WindowBounds(x: 0, y: 580, width: 500, height: 500),
            axSubrole: nil,
            hasAXInfo: false,
            isOnScreen: false
        )
        #expect(!AppWindowProfileRegistry.isHiddenBackingWindow(titled500))

        let figmaOnScreen400 = RawWindowCandidate(
            id: "cg-figma-onscreen-400",
            pid: 4111,
            bundleIdentifier: "com.figma.Desktop",
            applicationName: "Figma",
            title: nil,
            bounds: WindowBounds(x: 760, y: 208, width: 400, height: 600),
            axSubrole: nil,
            hasAXInfo: false,
            isOnScreen: true
        )
        #expect(!AppWindowProfileRegistry.isHiddenBackingWindow(figmaOnScreen400))
    }
}
