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
}
