import Testing
@testable import WintchCore

/// AppIdentity のバンドル識別情報抽出・開発版判定・UI 文言生成を検証するテストスイート
@Suite("AppIdentity テスト")
struct AppIdentityTests {
    /// 開発用バンドル辞書から表示名・識別子・開発版フラグ・各種 UI 文言を正しく解決できることを検証する
    @Test("開発版バンドル情報から Wintch_dev と各 UI 文言を正しく導出する")
    func resolvesDevelopmentIdentityFromBundleDictionary() {
        let infoDict: [String: Any] = [
            "CFBundleDisplayName": "Wintch_dev",
            "CFBundleName": "Wintch",
            "CFBundleIdentifier": "dev.wintch.Wintch.dev"
        ]

        let identity = AppIdentity(infoDictionary: infoDict)

        #expect(identity.displayName == "Wintch_dev")
        #expect(identity.bundleIdentifier == "dev.wintch.Wintch.dev")
        #expect(identity.isDevelopment == true)
        #expect(identity.aboutMenuTitle == "Wintch_devについて")
        #expect(identity.quitMenuTitle == "Wintch_dev を終了")
        #expect(identity.settingsWindowTitle == "Wintch_dev 設定")
        #expect(identity.permissionGuideWindowTitle == "Wintch_dev - 権限の確認")
        #expect(identity.accessibilitySwitchInstruction == "2. 一覧の「Wintch_dev」のスイッチをオンにします")
    }

    /// 配布用バンドル辞書から正規の Wintch 表示情報と非開発版判定が導出されることを検証する
    @Test("配布版バンドル情報から正規の Wintch 情報と UI 文言を導出する")
    func resolvesReleaseIdentityFromBundleDictionary() {
        let infoDict: [String: Any] = [
            "CFBundleDisplayName": "Wintch",
            "CFBundleName": "Wintch",
            "CFBundleIdentifier": "dev.wintch.Wintch"
        ]

        let identity = AppIdentity(infoDictionary: infoDict)

        #expect(identity.displayName == "Wintch")
        #expect(identity.bundleIdentifier == "dev.wintch.Wintch")
        #expect(identity.isDevelopment == false)
        #expect(identity.aboutMenuTitle == "Wintchについて")
        #expect(identity.quitMenuTitle == "Wintch を終了")
        #expect(identity.settingsWindowTitle == "Wintch 設定")
        #expect(identity.permissionGuideWindowTitle == "Wintch - 権限の確認")
        #expect(identity.accessibilitySwitchInstruction == "2. 一覧の「Wintch」のスイッチをオンにします")
    }

    /// CFBundleDisplayName が未設定または空白のみの場合に CFBundleName へフォールバックし前後空白を除去することを検証する
    @Test("CFBundleDisplayName 不在時は CFBundleName を使用し前後空白をトリミングする")
    func fallsBackToBundleNameAndTrimsWhitespace() {
        let infoDict: [String: Any] = [
            "CFBundleDisplayName": "   \n",
            "CFBundleName": " Wintch_dev\t",
            "CFBundleIdentifier": " dev.wintch.Wintch.dev "
        ]

        let identity = AppIdentity(infoDictionary: infoDict)

        #expect(identity.displayName == "Wintch_dev")
        #expect(identity.bundleIdentifier == "dev.wintch.Wintch.dev")
        #expect(identity.isDevelopment == true)
    }

    /// 辞書が nil または不正型のとき、明示したフォールバック値へ安全にフォールバックすることを検証する
    @Test("辞書欠損や不正型の場合はフォールバック値を使用して安全に初期化する")
    func fallsBackSafelyWhenMissingOrInvalid() {
        let devFallback = AppIdentity(
            infoDictionary: nil,
            fallbackDisplayName: AppIdentity.developmentDisplayName,
            fallbackBundleIdentifier: AppIdentity.developmentBundleIdentifier
        )
        #expect(devFallback.displayName == "Wintch_dev")
        #expect(devFallback.bundleIdentifier == "dev.wintch.Wintch.dev")
        #expect(devFallback.isDevelopment == true)

        let invalidDict: [String: Any] = [
            "CFBundleDisplayName": 123,
            "CFBundleName": "",
            "CFBundleIdentifier": "   "
        ]
        let releaseFallback = AppIdentity(
            infoDictionary: invalidDict,
            fallbackDisplayName: AppIdentity.releaseDisplayName,
            fallbackBundleIdentifier: AppIdentity.releaseBundleIdentifier
        )
        #expect(releaseFallback.displayName == "Wintch")
        #expect(releaseFallback.bundleIdentifier == "dev.wintch.Wintch")
        #expect(releaseFallback.isDevelopment == false)
    }

    /// バンドル識別子の .dev 接尾辞または表示名によって開発版判定が一貫して行われることを検証する
    @Test("開発用識別子の接尾辞や表示名によって開発版判定が行われる")
    func detectsDevelopmentVariantByNameOrIdentifierSuffix() {
        let bySuffix = AppIdentity(infoDictionary: [
            "CFBundleDisplayName": "Wintch",
            "CFBundleIdentifier": "com.example.Wintch.dev"
        ])
        #expect(bySuffix.isDevelopment == true)

        let byDisplayName = AppIdentity(infoDictionary: [
            "CFBundleDisplayName": "Wintch_dev",
            "CFBundleIdentifier": "dev.wintch.Wintch"
        ])
        #expect(byDisplayName.isDevelopment == true)
    }
}
