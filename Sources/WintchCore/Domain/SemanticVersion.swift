import Foundation

/// セマンティックバージョニング（SemVer 2.0.0）を表現・比較する純粋ドメインモデル
public struct SemanticVersion: Equatable, Hashable, Comparable, Sendable, CustomStringConvertible {
    /// メジャーバージョン番号
    public let major: Int

    /// マイナーバージョン番号
    public let minor: Int

    /// パッチバージョン番号
    public let patch: Int

    /// プレリリース識別子（ドット区切り要素。安定版では空配列）
    public let prereleaseIdentifiers: [String]

    /// プレリリース版であるかどうか
    public var isPrerelease: Bool {
        !prereleaseIdentifiers.isEmpty
    }

    /// `v` プレフィックスを除いた正規化済みバージョン文字列（例: `"0.3.0"`, `"0.3.0-beta.1"`）
    public var normalizedString: String {
        let core = "\(major).\(minor).\(patch)"
        if prereleaseIdentifiers.isEmpty {
            return core
        }
        return "\(core)-\(prereleaseIdentifiers.joined(separator: "."))"
    }

    /// 文字列表現
    public var description: String {
        normalizedString
    }

    /// 各数値要素と任意のプレリリース識別子からバージョンを初期化する
    /// - Parameters:
    ///   - major: メジャーバージョン番号（0 以上）
    ///   - minor: マイナーバージョン番号（0 以上）
    ///   - patch: パッチバージョン番号（0 以上）
    ///   - prereleaseIdentifiers: プレリリース識別子配列（既定値は空）
    public init(major: Int, minor: Int, patch: Int, prereleaseIdentifiers: [String] = []) {
        self.major = max(0, major)
        self.minor = max(0, minor)
        self.patch = max(0, patch)
        self.prereleaseIdentifiers = prereleaseIdentifiers
    }

    /// 文字列から SemVer を解析して初期化する（先頭の `v` / `V` プレフィックスを許容）
    /// - Parameter raw: バージョン文字列（例: `"v0.3.0"`, `"0.3.0-rc.1"`, `"1.2.3+build.4"`）
    public init?(string raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 先頭の `v` または `V` を 1 文字だけ除去する
        let withoutPrefix: Substring
        if trimmed.first == "v" || trimmed.first == "V" {
            withoutPrefix = trimmed.dropFirst()
        } else {
            withoutPrefix = trimmed[...]
        }
        guard !withoutPrefix.isEmpty else { return nil }

        // ビルドメタデータ (`+...`) は SemVer 2.0 仕様上バージョン優先順位に影響しないため分離して無視する
        let withoutBuild: Substring
        if let plusIndex = withoutPrefix.firstIndex(of: "+") {
            let buildPart = withoutPrefix[withoutPrefix.index(after: plusIndex)...]
            guard !buildPart.isEmpty else { return nil }
            withoutBuild = withoutPrefix[..<plusIndex]
        } else {
            withoutBuild = withoutPrefix
        }

        // コアバージョン部とプレリリース部を最初のハイフンで分離する
        let corePart: Substring
        let prereleasePart: Substring?
        if let hyphenIndex = withoutBuild.firstIndex(of: "-") {
            corePart = withoutBuild[..<hyphenIndex]
            prereleasePart = withoutBuild[withoutBuild.index(after: hyphenIndex)...]
        } else {
            corePart = withoutBuild
            prereleasePart = nil
        }

        let coreComponents = corePart.split(separator: ".", omittingEmptySubsequences: false)
        guard coreComponents.count == 3,
              let major = Self.parseStrictNonNegativeInt(coreComponents[0]),
              let minor = Self.parseStrictNonNegativeInt(coreComponents[1]),
              let patch = Self.parseStrictNonNegativeInt(coreComponents[2]) else {
            return nil
        }

        var parsedPrerelease: [String] = []
        if let prereleasePart {
            let identifiers = prereleasePart.split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty else { return nil }
            for identifier in identifiers {
                guard Self.isValidPrereleaseIdentifier(identifier) else { return nil }
                parsedPrerelease.append(String(identifier))
            }
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prereleaseIdentifiers = parsedPrerelease
    }

    /// SemVer 2.0.0 の優先順位規則に従って 2 つのバージョンを比較する
    /// - Parameters:
    ///   - lhs: 左辺のバージョン
    ///   - rhs: 右辺のバージョン
    /// - Returns: 左辺が右辺より古い（小さい）場合は true
    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // コアバージョンが同一の場合、安定版（プレリリースなし）がプレリリース版より新しい
        switch (lhs.prereleaseIdentifiers.isEmpty, rhs.prereleaseIdentifiers.isEmpty) {
        case (true, true):
            return false
        case (false, true):
            return true
        case (true, false):
            return false
        case (false, false):
            return comparePrerelease(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers)
        }
    }

    /// バージョン文字列を正規化済み文字列へ変換する
    /// - Parameter raw: 入力バージョン文字列
    /// - Returns: 解析できた場合は正規化文字列、解析不能な場合は nil
    public static func normalizedVersionString(_ raw: String) -> String? {
        SemanticVersion(string: raw)?.normalizedString
    }

    /// 先頭ゼロを持たない非負整数として文字列を厳密解析する
    /// - Parameter token: 数値トークン
    /// - Returns: 有効な非負整数（無効時は nil）
    private static func parseStrictNonNegativeInt(_ token: Substring) -> Int? {
        guard !token.isEmpty else { return nil }
        guard token.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        if token.count > 1 && token.first == "0" {
            return nil
        }
        return Int(token)
    }

    /// プレリリース識別子トークンが SemVer 2.0 規則を満たすか検証する
    /// - Parameter token: 検証対象の識別子
    /// - Returns: 有効な場合は true
    private static func isValidPrereleaseIdentifier(_ token: Substring) -> Bool {
        guard !token.isEmpty else { return false }
        let isAllowedCharset = token.allSatisfy { ch in
            ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-")
        }
        guard isAllowedCharset else { return false }
        // 数値のみの識別子は先頭ゼロを禁止する
        if token.allSatisfy({ $0.isNumber }) && token.count > 1 && token.first == "0" {
            return false
        }
        return true
    }

    /// プレリリース識別子配列を SemVer 2.0 規則に従って大小比較する
    /// - Parameters:
    ///   - lhs: 左辺のプレリリース識別子配列
    ///   - rhs: 右辺のプレリリース識別子配列
    /// - Returns: 左辺が右辺より小さい場合は true
    private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> Bool {
        let count = min(lhs.count, rhs.count)
        for index in 0..<count {
            let left = lhs[index]
            let right = rhs[index]
            if left == right { continue }

            let leftInt = Int(left)
            let rightInt = Int(right)
            switch (leftInt, rightInt) {
            case let (l?, r?):
                return l < r
            case (_?, nil):
                // SemVer 2.0: 数値識別子は非数値識別子より常に優先度が低い
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left < right
            }
        }
        return lhs.count < rhs.count
    }
}
