import AppKit
import ApplicationServices

/// AXIsProcessTrusted を用いてアクセシビリティ権限の監視とシステム設定への誘導を行うサービス
@MainActor
public final class AccessibilityPermissionService: AccessibilityPermissionServicing {
    /// 権限状態を定期確認するためのバックグラウンド監視タスク
    private var monitorTask: Task<Void, Never>?

    /// 直前に通知した権限状態
    private var lastObservedStatus: AccessibilityPermissionStatus?

    /// AccessibilityPermissionService を初期化する
    public init() {}

    /// 現在のアクセシビリティ権限状態を取得する
    /// - Returns: 許可済みなら .granted、未許可なら .denied
    public func currentStatus() -> AccessibilityPermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// 権限状態の変化を定期的に監視する（1秒間隔の軽量ポーリング）
    /// - Parameter onChange: 権限状態が変化した際に実行されるコールバック
    public func startMonitoring(onChange: @escaping (AccessibilityPermissionStatus) -> Void) {
        stopMonitoring()
        let initial = currentStatus()
        lastObservedStatus = initial

        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { break }
                let latest = self.currentStatus()
                if latest != self.lastObservedStatus {
                    self.lastObservedStatus = latest
                    onChange(latest)
                }
            }
        }
    }

    /// 権限状態の定期監視を停止する
    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// macOS の「システム設定 > プライバシーとセキュリティ > アクセシビリティ」画面を開く
    public func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
