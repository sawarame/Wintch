import AppKit
import SwiftUI

/// ランチャーモード専用の検索入力フィールド（AppKit NSTextField ラッパー）
/// 日本語 IME 変換中のキー操作を優先しつつ、確定・キャンセル・上下移動コマンドを処理する
public struct LauncherSearchField: NSViewRepresentable {
    /// 検索文字列の双方向バインディング
    @Binding private var text: String
    /// フィールドが現在表示・フォーカス対象としてアクティブか
    private let isActive: Bool
    /// 選択行を上下に移動するコールバック
    private let onMoveSelection: (ArrowDirection) -> Void
    /// Enter キーで選択項目を確定するコールバック
    private let onConfirm: () -> Void
    /// Esc キーでパネルをキャンセル終了するコールバック
    private let onCancel: () -> Void

    /// 検索入力フィールドを初期化する
    /// - Parameters:
    ///   - text: 検索文字列バインディング
    ///   - isActive: アクティブ表示状態かどうか
    ///   - onMoveSelection: 上下移動時のコールバック
    ///   - onConfirm: 確定時のコールバック
    ///   - onCancel: キャンセル時のコールバック
    public init(
        text: Binding<String>,
        isActive: Bool,
        onMoveSelection: @escaping (ArrowDirection) -> Void,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._text = text
        self.isActive = isActive
        self.onMoveSelection = onMoveSelection
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    /// ホストする NSTextField を生成する
    /// - Parameter context: Representable コンテキスト
    /// - Returns: 設定済みの NSTextField
    public func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = "ウィンドウを検索..."
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        textField.textColor = .labelColor
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingHead
        if let cell = textField.cell as? NSTextFieldCell {
            cell.isScrollable = true
            cell.wraps = false
        }
        return textField
    }

    /// SwiftUI の状態変化を NSTextField へ反映し、必要時にファーストレスポンダを取得する
    /// - Parameters:
    ///   - nsView: 対象の NSTextField
    ///   - context: Representable コンテキスト
    public func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self

        // 日本語 IME 変換中の未確定文字列を壊さないよう、hasMarkedText 中は上書きしない
        let hasMarkedText = (nsView.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
        if !hasMarkedText && nsView.stringValue != text {
            nsView.stringValue = text
        }

        if isActive {
            if !context.coordinator.didFocusForCurrentSession {
                DispatchQueue.main.async {
                    guard let window = nsView.window else { return }
                    let editor = nsView.currentEditor()
                    if window.firstResponder !== nsView && (editor == nil || window.firstResponder !== editor) {
                        window.makeFirstResponder(nsView)
                    }
                    context.coordinator.didFocusForCurrentSession = true
                }
            }
        } else {
            context.coordinator.didFocusForCurrentSession = false
        }
    }

    /// コーディネーターを生成する
    /// - Returns: NSTextFieldDelegate 実装コーディネーター
    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// NSTextField の入力変更と特殊キーコマンドを橋渡しするコーディネーター
    @MainActor
    public final class Coordinator: NSObject, NSTextFieldDelegate {
        /// 親ビュー参照
        var parent: LauncherSearchField
        /// 現在の表示セッションで初回フォーカスを付与済みか
        var didFocusForCurrentSession = false

        /// コーディネーターを初期化する
        /// - Parameter parent: 親となる LauncherSearchField
        init(parent: LauncherSearchField) {
            self.parent = parent
        }

        /// テキスト入力変化を SwiftUI バインディングへ反映する
        /// - Parameter obj: 変更通知オブジェクト
        public func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        /// Enter・Esc・矢印・Ctrl+N/P などのコマンドを判定し、IME 非変換時のみランチャー操作へ委譲する
        /// - Parameters:
        ///   - control: イベント発生元コントロール
        ///   - textView: 編集中のフィールドエディタ
        ///   - commandSelector: Cocoa テキストコマンドセレクタ
        /// - Returns: イベントを処理済みとする場合は true
        public func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            // 日本語 IME 等で未確定文字列がある場合は IME の操作を最優先する
            if textView.hasMarkedText() {
                return false
            }

            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onConfirm()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveSelection(.up)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveSelection(.down)
                return true
            default:
                return false
            }
        }
    }
}
