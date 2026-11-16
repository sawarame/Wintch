import AppKit
import SwiftUI

/// 「Wintchについて」ウィンドウでアプリアイコン・バージョン・著作権表記を表示するビュー
public struct AboutView: View {
    /// 表示対象のアプリバージョン情報
    private let versionInfo: AppVersionInfo

    /// 表示用のアプリアイコン画像（未指定時はバンドルまたは実行中アプリから取得）
    private let appIcon: NSImage?

    /// 表示対象のアプリ識別情報（開発版・配布版名称の切り替え用）
    private let appIdentity: AppIdentity

    /// 「〜について」ビューを初期化する
    /// - Parameters:
    ///   - versionInfo: 表示するバージョン情報（既定値はメインバンドルから取得）
    ///   - appIcon: 表示するアプリアイコン画像（既定値はアプリバンドルのアイコン）
    ///   - appIdentity: 表示するアプリ識別情報（既定値はメインバンドルから取得）
    public init(
        versionInfo: AppVersionInfo = .current,
        appIcon: NSImage? = nil,
        appIdentity: AppIdentity = .current
    ) {
        self.versionInfo = versionInfo
        self.appIcon = appIcon ?? Self.resolveAppIcon()
        self.appIdentity = appIdentity
    }

    /// ビューの本体構築
    public var body: some View {
        VStack(spacing: 14) {
            // バンドルアイコンが取得できない環境でも安全に代替アイコンを表示する
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
            } else {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 80, height: 80)
            }

            VStack(spacing: 4) {
                Text(appIdentity.displayName)
                    .font(.title2.bold())

                Text(versionInfo.displayVersionText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text("macOS 向けシンプルウィンドウ単位スイッチャー")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(versionInfo.copyright)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(width: 320, height: 240)
    }

    /// 実行中アプリバンドルから表示用のアプリアイコン画像を取得する
    /// - Returns: 取得できた場合は NSImage、取得できない場合は nil
    private static func resolveAppIcon() -> NSImage? {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let bundledIcon = NSImage(contentsOf: iconURL) {
            return bundledIcon
        }
        return NSApplication.shared.applicationIconImage
    }
}
