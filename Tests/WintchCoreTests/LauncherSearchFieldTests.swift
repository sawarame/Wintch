import AppKit
import SwiftUI
import Testing
@testable import WintchCore

/// LauncherSearchField のプレースホルダー文字列と視認性スタイルを検証するテストスイート
@Suite("LauncherSearchField テスト")
struct LauncherSearchFieldTests {
    /// プレースホルダー属性文字列に適切な文言・視認性の高い色・フォントが設定されることを検証する
    @Test("プレースホルダー属性文字列に secondaryLabelColor と 15pt フォントが設定される")
    @MainActor
    func placeholderAttributedStringUsesReadableSecondaryColor() {
        let attributed = LauncherSearchField.makePlaceholderAttributedString()

        #expect(attributed.string == "ウィンドウまたはアプリを検索...")
        #expect(attributed.length > 0)

        let attributes = attributed.attributes(at: 0, effectiveRange: nil)
        let foregroundColor = attributes[.foregroundColor] as? NSColor
        let font = attributes[.font] as? NSFont

        // 薄い placeholderTextColor ではなく外観・コントラスト設定に追従する secondaryLabelColor を使う
        #expect(foregroundColor == NSColor.secondaryLabelColor)
        #expect(font == NSFont.systemFont(ofSize: 15, weight: .regular))
    }

    /// 生成された NSTextField に視認性改善済みプレースホルダーと通常入力テキスト色が設定されることを検証する
    @Test("生成された NSTextField にプレースホルダー属性文字列と入力文字色が適用される")
    @MainActor
    func configuredTextFieldAppliesPlaceholderAndLabelColor() {
        let field = LauncherSearchField(
            text: .constant(""),
            isActive: true,
            onMoveSelection: { _ in },
            onConfirm: {},
            onCancel: {}
        )
        let textField = field.makeConfiguredTextField(delegate: nil)

        #expect(textField.placeholderAttributedString?.string == "ウィンドウまたはアプリを検索...")
        let attributes = textField.placeholderAttributedString?.attributes(at: 0, effectiveRange: nil)
        #expect(attributes?[.foregroundColor] as? NSColor == NSColor.secondaryLabelColor)
        // 入力された検索文字は labelColor で描画され、プレースホルダーと明確に区別できる
        #expect(textField.textColor == NSColor.labelColor)
    }
}
