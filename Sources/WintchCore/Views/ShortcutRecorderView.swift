import AppKit
import SwiftUI

/// ショートカットレコーダーでキャプチャされた生のキー入力情報
public struct CapturedShortcutInput: Equatable, Sendable {
    /// 仮想キーコード
    public let keyCode: UInt16
    /// 押下されていた修飾キー集合
    public let modifiers: ShortcutModifiers
    /// 表示用キーラベル
    public let keyLabel: String

    /// キャプチャ結果を初期化する
    /// - Parameters:
    ///   - keyCode: 仮想キーコード
    ///   - modifiers: 修飾キー集合
    ///   - keyLabel: 表示用キーラベル
    public init(keyCode: UInt16, modifiers: ShortcutModifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// 通常スイッチャー用ショートカット設定値へ変換する
    /// - Returns: ShortcutPreference インスタンス
    public func toNormalShortcut() -> ShortcutPreference {
        ShortcutPreference(keyCode: keyCode, modifiers: modifiers, keyLabel: keyLabel)
    }

    /// ランチャー用ショートカット設定値へ変換する
    /// - Returns: LauncherShortcutPreference インスタンス
    public func toLauncherShortcut() -> LauncherShortcutPreference {
        LauncherShortcutPreference(keyCode: keyCode, modifiers: modifiers, keyLabel: keyLabel)
    }
}

/// 設定画面で実際のキー入力をそのまま受け取ってショートカットを記録する汎用コンポーネント
public struct ShortcutRecorderView: View {
    /// 現在設定されているショートカットの画面表示文字列
    private let displayString: String
    /// キー入力待機状態かどうか
    private let isRecording: Bool
    /// 記録開始を要求するコールバック
    private let onBeginRecording: () -> Void
    /// キャプチャされたキー入力を通知するコールバック
    private let onCapture: (CapturedShortcutInput) -> Void
    /// 記録キャンセルを通知するコールバック
    private let onCancel: () -> Void

    /// ショートカットレコーダーを初期化する
    /// - Parameters:
    ///   - displayString: 現在のショートカット表記（例: "⌥ + ⇥" / "⌥ + Space"）
    ///   - isRecording: 記録待機中かどうか
    ///   - onBeginRecording: 記録開始時のコールバック
    ///   - onCapture: キー入力確定時のコールバック
    ///   - onCancel: キャンセル時のコールバック
    public init(
        displayString: String,
        isRecording: Bool,
        onBeginRecording: @escaping () -> Void,
        onCapture: @escaping (CapturedShortcutInput) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.displayString = displayString
        self.isRecording = isRecording
        self.onBeginRecording = onBeginRecording
        self.onCapture = onCapture
        self.onCancel = onCancel
    }

    /// ビューの本体構築
    public var body: some View {
        Button {
            if isRecording {
                onCancel()
            } else {
                onBeginRecording()
            }
        } label: {
            Text(isRecording ? "キーを入力... (Esc でキャンセル)" : displayString)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minWidth: 160)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isRecording ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: isRecording ? 1.5 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .background(
            LocalKeyCaptureBridge(
                isRecording: isRecording,
                onCapture: onCapture,
                onCancel: onCancel
            )
            .frame(width: 0, height: 0)
        )
        .onDisappear {
            if isRecording {
                onCancel()
            }
        }
    }
}

/// SwiftUI の再描画を跨いでローカルキー監視インスタンスのライフサイクルを安定管理するブリッジビュー
private struct LocalKeyCaptureBridge: NSViewRepresentable {
    /// 記録待機中かどうか
    let isRecording: Bool
    /// 有効キー入力通知
    let onCapture: (CapturedShortcutInput) -> Void
    /// キャンセル通知
    let onCancel: () -> Void

    /// ダミーのホスト NSView を生成する
    /// - Parameter context: Representable コンテキスト
    /// - Returns: 空の NSView
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    /// 記録状態の変化に応じてローカルキーイベントモニターを登録または解除する
    /// - Parameters:
    ///   - nsView: ホスト NSView
    ///   - context: Representable コンテキスト
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCapture = onCapture
        context.coordinator.onCancel = onCancel
        if isRecording {
            context.coordinator.installMonitorIfNeeded()
        } else {
            context.coordinator.removeMonitor()
        }
    }

    /// ビュー破棄時に必ずイベントモニターを解除する
    /// - Parameters:
    ///   - nsView: ホスト NSView
    ///   - coordinator: コーディネーター
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    /// コーディネーターを生成する
    /// - Returns: キー監視コーディネーター
    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    /// NSEvent ローカルモニターを保持・制御するコーディネーター
    @MainActor
    final class Coordinator {
        /// 有効キー入力通知
        var onCapture: (CapturedShortcutInput) -> Void
        /// キャンセル通知
        var onCancel: () -> Void
        /// 登録中のイベントモニター参照
        private var eventMonitor: Any?

        /// コーディネーターを初期化する
        /// - Parameters:
        ///   - onCapture: キー入力通知クロージャ
        ///   - onCancel: キャンセル通知クロージャ
        init(
            onCapture: @escaping (CapturedShortcutInput) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        /// ローカルキーダウンモニターが未登録であれば登録する
        func installMonitorIfNeeded() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let keyCode = event.keyCode

                // Esc キーは変更キャンセルとして扱う
                if keyCode == LauncherShortcutPreference.escapeKeyCode {
                    self.onCancel()
                    return nil
                }

                // 修飾キー単体の押下はトリガーキーにならないため無視する
                if LauncherShortcutPreference.isNonTriggerKeyCode(keyCode) {
                    return nil
                }

                let modifiers = self.extractModifiers(from: event.modifierFlags)
                let keyLabel = LauncherShortcutPreference.resolveKeyLabel(
                    for: keyCode,
                    charactersIgnoringModifiers: event.charactersIgnoringModifiers
                )
                let captured = CapturedShortcutInput(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    keyLabel: keyLabel
                )
                self.onCapture(captured)
                return nil
            }
        }

        /// 登録済みのローカルキーダウンモニターを解除する
        func removeMonitor() {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }

        /// NSEvent.ModifierFlags から比較用の修飾キー集合を抽出する
        /// - Parameter flags: AppKit イベント修飾キーフラグ
        /// - Returns: ShortcutModifiers 値
        private func extractModifiers(from flags: NSEvent.ModifierFlags) -> ShortcutModifiers {
            var result: ShortcutModifiers = []
            if flags.contains(.control) { result.insert(.control) }
            if flags.contains(.option) { result.insert(.option) }
            if flags.contains(.shift) { result.insert(.shift) }
            if flags.contains(.command) { result.insert(.command) }
            return result
        }
    }
}
