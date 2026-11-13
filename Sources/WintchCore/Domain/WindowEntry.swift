import Foundation

/// フィルタリングとソートを通過し、スイッチャー UI に表示される確定ウィンドウ項目
public struct WindowEntry: Identifiable, Equatable, Sendable {
    /// ウィンドウ項目の安定識別子
    public let id: String

    /// CoreGraphics が付与するウィンドウ ID（利用可能な場合）
    public let cgWindowID: UInt32?

    /// 所有アプリケーションのプロセス ID
    public let pid: Int32

    /// リストに表示するアプリケーション名
    public let applicationName: String

    /// ウィンドウの元タイトル（未設定の場合は空文字）
    public let windowTitle: String

    /// 最小化状態かどうか
    public let isMinimized: Bool

    /// MRU 並び替えに使用する直近アクティブ日時
    public let lastActivatedAt: Date?

    /// システム上の重なり順（MRU 未記録時のフォールバック順序）
    public let zOrderIndex: Int

    /// ウィンドウ項目を初期化する
    /// - Parameters:
    ///   - id: 一意識別子
    ///   - cgWindowID: CoreGraphics ウィンドウ ID
    ///   - pid: 所有プロセス ID
    ///   - applicationName: アプリケーション名
    ///   - windowTitle: ウィンドウタイトル
    ///   - isMinimized: 最小化状態かどうか
    ///   - lastActivatedAt: 直近アクティブ日時
    ///   - zOrderIndex: 重なり順
    public init(
        id: String,
        cgWindowID: UInt32? = nil,
        pid: Int32,
        applicationName: String,
        windowTitle: String,
        isMinimized: Bool = false,
        lastActivatedAt: Date? = nil,
        zOrderIndex: Int = 0
    ) {
        self.id = id
        self.cgWindowID = cgWindowID
        self.pid = pid
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.isMinimized = isMinimized
        self.lastActivatedAt = lastActivatedAt
        self.zOrderIndex = zOrderIndex
    }

    /// UI 表示用のウィンドウタイトル（空文字の場合は補助テキストを返す）
    /// - Returns: リスト行に表示するタイトル文字列
    public var displayTitle: String {
        let trimmed = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(タイトルなし)" : trimmed
    }
}
