import Foundation

/// AX で捕捉できず画面外に存在する CGWindow 補完候補（cg-*）の採用ポリシー
public enum OffscreenCGFallbackPolicy: Equatable, Sendable {
    /// 実質サイズ要件および未表示バックキングウィンドウ除外を通過した画面外候補を補完許可する（標準動作）
    case allow
    /// 単一メインウィンドウ構成アプリとして扱い、AX 捕捉済み時は画面外補完を出さず、未捕捉時のみ最良代表 1 件に絞る
    case singleRepresentativeOnly
    /// メニュー補完等で非空タイトルが確定した画面外候補のみ許可し、タイトル不明の画面外候補は除外する
    case requireAXOrMenuTitle
}

/// アプリまたはフレームワークが内部に保持する未表示バックキングウィンドウを識別する幾何シグネチャ
public struct HiddenBackingWindowSignature: Equatable, Sendable {
    /// 一致判定するウィンドウ幅（ポイント）
    public let width: Double
    /// 一致判定するウィンドウ高さ（ポイント）
    public let height: Double
    /// 左上 X 座標が 0 付近であることを必須とするか
    public let requiresZeroOriginX: Bool
    /// 座標・サイズ比較の許容誤差（ポイント）
    public let tolerance: Double

    /// 未表示バックキングウィンドウの幾何シグネチャを初期化する
    /// - Parameters:
    ///   - width: 一致判定するウィンドウ幅（ポイント）
    ///   - height: 一致判定するウィンドウ高さ（ポイント）
    ///   - requiresZeroOriginX: X 座標が 0 付近である必要があるか
    ///   - tolerance: 比較時の許容誤差（既定値 2.0pt）
    public init(
        width: Double,
        height: Double,
        requiresZeroOriginX: Bool,
        tolerance: Double = 2.0
    ) {
        self.width = width
        self.height = height
        self.requiresZeroOriginX = requiresZeroOriginX
        self.tolerance = tolerance
    }

    /// 候補が「ユーザー操作対象外の未表示バックキングウィンドウ」に該当するか安全ガード付きで判定する
    /// - Parameter candidate: 判定対象の生ウィンドウ候補
    /// - Returns: 未表示の内部補助ウィンドウと断定できる場合は true
    public func matches(_ candidate: RawWindowCandidate) -> Bool {
        // AX 実ウィンドウとして捕捉済み、画面表示中、または実タイトル付きのウィンドウは絶対に誤除外しない
        guard !candidate.hasAXInfo,
              candidate.isOnScreen != true else {
            return false
        }
        let trimmedTitle = (candidate.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty else {
            return false
        }

        // X 座標制約および幅・高さが許容誤差内で一致するかを確認する
        if requiresZeroOriginX, abs(candidate.bounds.x) > tolerance {
            return false
        }
        return abs(candidate.bounds.width - width) <= tolerance
            && abs(candidate.bounds.height - height) <= tolerance
    }
}

/// 特定アプリケーションのウィンドウ収集・除外特性を宣言的に定義するプロファイル
public struct AppWindowProfile: Equatable, Sendable {
    /// 対象アプリケーションの Bundle Identifier（汎用既定プロファイル時は nil）
    public let bundleIdentifier: String?
    /// AX 未捕捉かつ画面外の CGWindow 補完候補に対する採用ポリシー
    public let offscreenCGPolicy: OffscreenCGFallbackPolicy
    /// 当該アプリ固有の未表示補助ウィンドウ幾何シグネチャ群
    public let hiddenBackingSignatures: [HiddenBackingWindowSignature]
    /// このプロファイル定義が必要となったアプリ／OS 固有の背景説明
    public let rationale: String

    /// アプリ別ウィンドウプロファイルを初期化する
    /// - Parameters:
    ///   - bundleIdentifier: 対象アプリの Bundle ID（汎用既定プロファイル時は nil）
    ///   - offscreenCGPolicy: 画面外 CGWindow 補完候補の採用ポリシー
    ///   - hiddenBackingSignatures: アプリ固有の未表示補助ウィンドウシグネチャ一覧
    ///   - rationale: プロファイル定義の根拠説明
    public init(
        bundleIdentifier: String?,
        offscreenCGPolicy: OffscreenCGFallbackPolicy,
        hiddenBackingSignatures: [HiddenBackingWindowSignature] = [],
        rationale: String = ""
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.offscreenCGPolicy = offscreenCGPolicy
        self.hiddenBackingSignatures = hiddenBackingSignatures
        self.rationale = rationale
    }
}

/// アプリ横断の共通バックキングウィンドウ除外ルールとアプリ別プロファイルを集約管理するレジストリ
public enum AppWindowProfileRegistry {
    /// 未登録アプリおよび汎用処理向けの既定プロファイル
    public static let defaultProfile = AppWindowProfile(
        bundleIdentifier: nil,
        offscreenCGPolicy: .allow,
        hiddenBackingSignatures: [],
        rationale: "標準アプリ向け既定ポリシー（別スペースの正当な CGWindow 補完を許可）"
    )

    /// 特定アプリに依存せず AppKit / SwiftUI 全般で生成される共通の未表示バックキングウィンドウ条件
    public static let commonHiddenBackingSignatures: [HiddenBackingWindowSignature] = [
        // Cocoa / SwiftUI の未表示 NSWindow 既定枠（原点 (0, 0), 500x500）が CG 座標で x=0, 500x500 として現れる裏方ウィンドウ
        HiddenBackingWindowSignature(
            width: 500.0,
            height: 500.0,
            requiresZeroOriginX: true
        )
    ]

    /// Bundle Identifier をキーとしたアプリ固有プロファイル定義テーブル
    /// （今後の個別アプリ対応は原則として本テーブルへのエントリ追加のみで完結させる）
    public static let profilesByBundleIdentifier: [String: AppWindowProfile] = [
        "com.apple.systempreferences": AppWindowProfile(
            bundleIdentifier: "com.apple.systempreferences",
            offscreenCGPolicy: .singleRepresentativeOnly,
            hiddenBackingSignatures: [],
            rationale: "システム設定は単一メインウィンドウ構成であり、ウインドウメニュー一覧を持たないため代表 1 件へ制限する"
        ),
        "com.apple.Notes": AppWindowProfile(
            bundleIdentifier: "com.apple.Notes",
            offscreenCGPolicy: .requireAXOrMenuTitle,
            hiddenBackingSignatures: [
                // メモアプリが画面中央付近に未表示で保持する 475x600 の内部補助パネル（ウェルカム／補助シート用裏方窓）
                HiddenBackingWindowSignature(
                    width: 475.0,
                    height: 600.0,
                    requiresZeroOriginX: false
                )
            ],
            rationale: "メモアプリはウインドウメニューに makeKeyAndOrderFront: 一覧を持たず、未表示の 475x600 / 500x500 補助 CGWindow を保持するため、AX またはメニュー確定タイトルを持つ実ウィンドウのみを残す"
        ),
        "com.google.Chrome": AppWindowProfile(
            bundleIdentifier: "com.google.Chrome",
            offscreenCGPolicy: .requireAXOrMenuTitle,
            hiddenBackingSignatures: [],
            rationale: "Google Chrome は全タブ・全ウィンドウ閉鎖後も画面外に無名の空き殻 CGWindow（フルスクリーン残骸や予測変換ポップアップ等）を保持するため、AX またはウィンドウメニュー等でタイトルが確定した実ウィンドウのみを許可する"
        )
    ]

    /// 指定された Bundle Identifier に対応するウィンドウプロファイルを返す
    /// - Parameter bundleIdentifier: 対象アプリの Bundle Identifier（nil 可）
    /// - Returns: 登録済みプロファイル（未登録時は `defaultProfile`）
    public static func profile(for bundleIdentifier: String?) -> AppWindowProfile {
        guard let bundleIdentifier,
              let registered = profilesByBundleIdentifier[bundleIdentifier] else {
            return defaultProfile
        }
        return registered
    }

    /// 候補が共通ルールまたは対象アプリ固有の未表示バックキングウィンドウシグネチャに一致するか判定する
    /// - Parameter candidate: 判定対象の生ウィンドウ候補
    /// - Returns: 未表示の内部補助ウィンドウに該当する場合は true
    public static func isHiddenBackingWindow(_ candidate: RawWindowCandidate) -> Bool {
        if commonHiddenBackingSignatures.contains(where: { $0.matches(candidate) }) {
            return true
        }
        let appProfile = profile(for: candidate.bundleIdentifier)
        return appProfile.hiddenBackingSignatures.contains(where: { $0.matches(candidate) })
    }
}
