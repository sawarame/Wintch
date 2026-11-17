import AppKit
import SwiftUI
import Testing
@testable import WintchCore

/// PermissionGuideViewModel の権限検知・設定誘導・自動更新を検証するテストスイート
@Suite("PermissionGuideViewModel テスト")
struct PermissionGuideViewModelTests {
    /// 「システム設定を開く」アクションが権限サービスのメソッドを呼び出すことを検証する
    @Test("システム設定を開く操作がサービスに委譲される")
    @MainActor
    func openSystemSettingsDelegatesToService() {
        let permissionService = MockAccessibilityPermissionService()
        permissionService.stubbedStatus = .denied

        let viewModel = PermissionGuideViewModel(permissionService: permissionService)
        #expect(viewModel.status == .denied)

        viewModel.openSystemSettings()
        #expect(permissionService.openSettingsCallCount == 1)
    }

    /// 権限状態を手動更新またはサービス変更検知した際に状態とコールバックが反映されることを検証する
    @Test("権限付与への変化を検知して状態更新とコールバック通知を行う")
    @MainActor
    func permissionGrantedUpdatesStatusAndNotifies() {
        let permissionService = MockAccessibilityPermissionService()
        permissionService.stubbedStatus = .denied

        var grantedCount = 0
        let viewModel = PermissionGuideViewModel(permissionService: permissionService)
        viewModel.onPermissionGranted = {
            grantedCount += 1
        }

        permissionService.stubbedStatus = .granted
        viewModel.refreshStatus()

        #expect(viewModel.status == .granted)
        #expect(grantedCount == 1)
    }

    /// 権限誘導ビューが配布版・開発版いずれの識別情報でも複数行説明を圧縮せず必要高さを確保することを検証する
    @Test("PermissionGuideView の必要サイズが固定 280pt を超えて複数行テキストを収容できる")
    @MainActor
    func permissionGuideViewFitsAllWrappedTextWithoutTruncation() {
        let permissionService = MockAccessibilityPermissionService()
        permissionService.stubbedStatus = .denied
        let viewModel = PermissionGuideViewModel(permissionService: permissionService)

        let identities = [
            AppIdentity(
                infoDictionary: ["CFBundleDisplayName": "Wintch", "CFBundleIdentifier": "dev.wintch.Wintch"]
            ),
            AppIdentity(
                infoDictionary: ["CFBundleDisplayName": "Wintch_dev", "CFBundleIdentifier": "dev.wintch.Wintch.dev"]
            )
        ]

        for identity in identities {
            let hostingView = NSHostingView(
                rootView: PermissionGuideView(viewModel: viewModel, appIdentity: identity)
            )
            hostingView.layoutSubtreeIfNeeded()
            let fittingSize = hostingView.fittingSize

            #expect(fittingSize.width == PermissionGuideView.preferredWidth)
            #expect(fittingSize.height > PermissionGuideView.minimumHeight)
        }
    }
}
