import Testing
@testable import WintchCore

/// AppVersionInfo のバンドル情報抽出およびフォールバック処理を検証するテストスイート
@Suite("AppVersionInfo テスト")
struct AppVersionInfoTests {
    /// Info.plist 辞書から表示バージョン・ビルド番号・著作権表記を正しく抽出できることを確認する
    @Test("辞書からバージョン・ビルド番号・著作権表記を正しく抽出できる")
    func extractsValidMetadata() {
        let infoDict: [String: Any] = [
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "42",
            "NSHumanReadableCopyright": "Copyright © 2026 Wintch Contributors. MIT License."
        ]

        let info = AppVersionInfo(infoDictionary: infoDict)

        #expect(info.shortVersion == "0.1.0")
        #expect(info.buildNumber == "42")
        #expect(info.copyright == "Copyright © 2026 Wintch Contributors. MIT License.")
        #expect(info.displayVersionText == "バージョン 0.1.0 (42)")
    }

    /// プレリリース表記や前後空白・改行が含まれていてもトリミングして保持できることを確認する
    @Test("プレリリース表記と前後空白のトリミングが正しく行われる")
    func trimsWhitespaceAndPreservesPrerelease() {
        let infoDict: [String: Any] = [
            "CFBundleShortVersionString": " 0.2.0-beta.1\n",
            "CFBundleVersion": " 15 ",
            "NSHumanReadableCopyright": "  MIT License  "
        ]

        let info = AppVersionInfo(infoDictionary: infoDict)

        #expect(info.shortVersion == "0.2.0-beta.1")
        #expect(info.buildNumber == "15")
        #expect(info.copyright == "MIT License")
        #expect(info.displayVersionText == "バージョン 0.2.0-beta.1 (15)")
    }

    /// バンドル辞書が nil、空文字、または文字列以外の型である場合に安全なフォールバック値を返すことを確認する
    @Test("辞書が nil や空文字・型不一致の場合はフォールバック値を返す")
    func fallsBackSafelyWhenMissingOrInvalid() {
        let nilInfo = AppVersionInfo(infoDictionary: nil)
        #expect(nilInfo.shortVersion == "dev")
        #expect(nilInfo.buildNumber == "1")
        #expect(nilInfo.copyright == "Copyright © 2026 Wintch Contributors. MIT License.")
        #expect(nilInfo.displayVersionText == "バージョン dev (1)")

        let invalidDict: [String: Any] = [
            "CFBundleShortVersionString": "   ",
            "CFBundleVersion": 123,
            "NSHumanReadableCopyright": ""
        ]
        let invalidInfo = AppVersionInfo(infoDictionary: invalidDict)
        #expect(invalidInfo.shortVersion == "dev")
        #expect(invalidInfo.buildNumber == "1")
        #expect(invalidInfo.copyright == "Copyright © 2026 Wintch Contributors. MIT License.")
    }
}
