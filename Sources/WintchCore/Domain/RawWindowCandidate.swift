import Foundation

/// ウィンドウの位置およびサイズを表す純粋な幾何情報
public struct WindowBounds: Equatable, Sendable {
    /// 左上 X 座標
    public let x: Double
    /// 左上 Y 座標
    public let y: Double
    /// ウィンドウの幅（ポイント）
    public let width: Double
    /// ウィンドウの高さ（ポイント）
    public let height: Double

    /// ウィンドウ矩形を初期化する
    /// - Parameters:
    ///   - x: X 座標
    ///   - y: Y 座標
    ///   - width: 幅
    ///   - height: 高さ
    public init(x: Double = 0, y: Double = 0, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// サービス層が収集し、ノイズ除外やソート前段として扱う生のウィンドウ候補メタデータ
public struct RawWindowCandidate: Equatable, Sendable {
    /// 一意の内部識別子（AX 参照識別または CGWindowID ベース）
    public let id: String

    /// CoreGraphics が付与するウィンドウ ID（取得可能な場合）
    public let cgWindowID: UInt32?

    /// 所有アプリケーションのプロセス ID
    public let pid: Int32

    /// 所有アプリケーションの Bundle Identifier
    public let bundleIdentifier: String?

    /// アプリケーションの表示名
    public let applicationName: String

    /// アクセシビリティ API 等から取得またはキャッシュされたウィンドウタイトル
    public let title: String?

    /// ウィンドウのレイヤー番号（通常ウィンドウは 0）
    public let layer: Int

    /// ウィンドウの位置およびサイズ
    public let bounds: WindowBounds

    /// ウィンドウの不透明度（0.0 〜 1.0）
    public let alpha: Double

    /// 通常アプリケーション（activationPolicy == .regular）に属するか
    public let isRegularApplication: Bool

    /// Wintch 自身のウィンドウであるか
    public let isSelf: Bool

    /// 最小化状態であるか
    public let isMinimized: Bool

    /// アクセシビリティのロール（例: "AXWindow"）
    public let axRole: String?

    /// アクセシビリティのサブロール（例: "AXStandardWindow", "AXDialog"）
    public let axSubrole: String?

    /// AXUIElement 由来のウィンドウ候補かどうか（false は CGWindow のみの補完候補）
    public let hasAXInfo: Bool

    /// 現在の操作スペース上で画面に表示されているか（kCGWindowIsOnscreen）
    public let isOnScreen: Bool?

    /// アプリ内で記録した直近アクティブ日時（MRU ソート基準）
    public let lastActivatedAt: Date?

    /// システム上の現在の重なり順（0 が最前面）
    public let zOrderIndex: Int

    /// 生のウィンドウ候補データを初期化する
    /// - Parameters:
    ///   - id: 一意識別子
    ///   - cgWindowID: CoreGraphics ウィンドウ ID
    ///   - pid: 所有プロセス ID
    ///   - bundleIdentifier: 所有アプリの Bundle ID
    ///   - applicationName: アプリ表示名
    ///   - title: ウィンドウタイトル
    ///   - layer: ウィンドウレイヤー番号
    ///   - bounds: ウィンドウ座標・サイズ
    ///   - alpha: 不透明度
    ///   - isRegularApplication: 通常アプリかどうか
    ///   - isSelf: 自アプリかどうか
    ///   - isMinimized: 最小化状態かどうか
    ///   - axRole: アクセシビリティロール
    ///   - axSubrole: アクセシビリティサブロール
    ///   - hasAXInfo: AX 情報に基づく候補かどうか（省略時はロール・サブロールの有無から自動判定）
    ///   - isOnScreen: 現在画面に表示中かどうか
    ///   - lastActivatedAt: 直近アクティブ日時
    ///   - zOrderIndex: システム上の重なり順
    public init(
        id: String,
        cgWindowID: UInt32? = nil,
        pid: Int32,
        bundleIdentifier: String? = nil,
        applicationName: String,
        title: String? = nil,
        layer: Int = 0,
        bounds: WindowBounds = WindowBounds(width: 800, height: 600),
        alpha: Double = 1.0,
        isRegularApplication: Bool = true,
        isSelf: Bool = false,
        isMinimized: Bool = false,
        axRole: String? = nil,
        axSubrole: String? = "AXStandardWindow",
        hasAXInfo: Bool? = nil,
        isOnScreen: Bool? = nil,
        lastActivatedAt: Date? = nil,
        zOrderIndex: Int = 0
    ) {
        self.id = id
        self.cgWindowID = cgWindowID
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.title = title
        self.layer = layer
        self.bounds = bounds
        self.alpha = alpha
        self.isRegularApplication = isRegularApplication
        self.isSelf = isSelf
        self.isMinimized = isMinimized
        self.axRole = axRole
        self.axSubrole = axSubrole
        self.hasAXInfo = hasAXInfo ?? (axRole != nil || axSubrole != nil)
        self.isOnScreen = isOnScreen
        self.lastActivatedAt = lastActivatedAt
        self.zOrderIndex = zOrderIndex
    }
}
