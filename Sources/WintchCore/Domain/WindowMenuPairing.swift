import Foundation

/// アプリケーションの「ウィンドウ」メニューから取得した 1 項目分のスナップショット
public struct WindowMenuItemSnapshot: Sendable, Equatable {
    /// メニュー項目の表示タイトル
    public let title: String
    /// AXIdentifier 属性値（AppKit 標準のウィンドウ項目では "makeKeyAndOrderFront:"）
    public let identifier: String?
    /// チェックマーク等の状態記号（現在のアクティブウィンドウでは "✓" などが入る）
    public let mark: String?
    /// コマンドキーショートカットが割り当てられているか
    public let hasCommandKey: Bool
    /// サブメニューを持つか
    public let hasSubmenu: Bool
    /// メニュー項目が有効状態か
    public let isEnabled: Bool
    /// 元のメニュー子要素配列内におけるインデックス
    public let index: Int

    /// メニュー項目を初期化する
    /// - Parameters:
    ///   - title: メニュー項目の表示タイトル
    ///   - identifier: AXIdentifier 属性値
    ///   - mark: チェックマーク等の状態記号
    ///   - hasCommandKey: コマンドキーショートカットの有無
    ///   - hasSubmenu: サブメニューの有無
    ///   - isEnabled: 有効状態かどうか
    ///   - index: 元の配列インデックス
    public init(
        title: String,
        identifier: String? = nil,
        mark: String? = nil,
        hasCommandKey: Bool = false,
        hasSubmenu: Bool = false,
        isEnabled: Bool = true,
        index: Int
    ) {
        self.title = title
        self.identifier = identifier
        self.mark = mark
        self.hasCommandKey = hasCommandKey
        self.hasSubmenu = hasSubmenu
        self.isEnabled = isEnabled
        self.index = index
    }

    /// 該当メニュー項目がアクティブ印（チェックマーク等）を持つか
    public var isChecked: Bool {
        guard let mark else { return false }
        return !mark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// AXMenuBar の「ウィンドウ」メニュー項目列から実在するウィンドウ一覧を抽出する純粋ロジック
public enum WindowMenuExtractor {
    /// 標準ウィンドウ一覧アクション識別子（Cocoa / Electron / Chromium 共通）
    public static let standardWindowActionIdentifier = "makeKeyAndOrderFront:"

    /// ウィンドウ一覧メニューとして認識するメニューバー項目名（小文字正規化済み）
    private static let recognizedMenuTitles: Set<String> = [
        "window",
        "ウィンドウ",
        "ウインドウ"
    ]

    /// フォールバック判定時にウィンドウ以外として確実に除外する識別子
    private static let excludedIdentifiers: Set<String> = [
        "_toggleIPad:"
    ]

    /// メニューバー項目タイトルが「ウィンドウ」メニューを表すかを判定する
    /// - Parameter title: メニューバー項目のタイトル文字列
    /// - Returns: 「ウィンドウ」系メニューであれば true
    public static func isWindowMenuBarTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return recognizedMenuTitles.contains(normalized)
    }

    /// 「ウィンドウ」メニューの全項目スナップショットから、現在開いているウィンドウに対応する項目のみを抽出する
    /// - Parameter items: メニュー配下の全子要素スナップショット配列（セパレータ含む順序保持）
    /// - Returns: 開いているウィンドウ一覧に対応する項目配列
    public static func extractWindowListItems(from items: [WindowMenuItemSnapshot]) -> [WindowMenuItemSnapshot] {
        // 1. 最優先：AppKit / Electron / Chromium 標準の "makeKeyAndOrderFront:" 識別子を持つ有効項目のみ抽出する
        let standardItems = items.filter { item in
            item.identifier == standardWindowActionIdentifier
                && item.isEnabled
                && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !standardItems.isEmpty {
            return standardItems
        }

        // 2. フォールバック：標準識別子を使わないアプリ向けに、チェックマーク付き項目を含む末尾側の連続ブロックを探す
        let checkedIndices = items.indices.filter { isFallbackCandidate(items[$0]) && items[$0].isChecked }
        guard let anchorIndex = checkedIndices.last else {
            return []
        }

        // チェックマーク付き項目の前後でセパレータ（空タイトル等）に挟まれた連続範囲のみを切り出す
        var startIndex = anchorIndex
        while startIndex > items.startIndex && isFallbackCandidate(items[startIndex - 1]) {
            startIndex -= 1
        }
        var endIndex = anchorIndex
        while endIndex + 1 < items.endIndex && isFallbackCandidate(items[endIndex + 1]) {
            endIndex += 1
        }

        return Array(items[startIndex...endIndex])
    }

    /// フォールバック走査時に「ウィンドウ一覧の1行」になり得る項目かを判定する
    /// - Parameter item: 判定対象のメニュー項目
    /// - Returns: セパレータやシステム予約項目ではなくウィンドウ候補となり得る場合は true
    private static func isFallbackCandidate(_ item: WindowMenuItemSnapshot) -> Bool {
        let trimmedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        guard item.isEnabled, !item.hasSubmenu, !item.hasCommandKey else { return false }
        if let id = item.identifier {
            if excludedIdentifiers.contains(id) || id.hasPrefix("_NS:") {
                return false
            }
        }
        return true
    }
}

/// 同一 PID 内の生ウィンドウ候補（AX 取得済み＋CGWindow 補完）と Window メニュー項目を対応付ける純粋ロジック
public enum WindowMenuCandidatePairing {
    /// 同一 PID に属する生ウィンドウ候補へ Window メニューのタイトルを補完適用し、余剰なゴースト CGWindow 候補を整理する
    /// - Parameters:
    ///   - candidates: 同一 PID の生ウィンドウ候補一覧（hasAXInfo == true と false が混在可）
    ///   - menuItems: `WindowMenuExtractor.extractWindowListItems` で抽出済みの実オープンウィンドウ項目
    /// - Returns: タイトル補完および不要ゴースト候補除外済みの候補一覧
    public static func applyMenuTitles(
        to candidates: [RawWindowCandidate],
        menuItems: [WindowMenuItemSnapshot]
    ) -> [RawWindowCandidate] {
        // Window メニューからウィンドウ一覧が取得できないアプリでは既存候補を変更せず返す
        guard !menuItems.isEmpty else {
            return candidates
        }

        var axCandidates: [RawWindowCandidate] = []
        var cgCandidates: [RawWindowCandidate] = []
        for candidate in candidates {
            if candidate.hasAXInfo {
                axCandidates.append(candidate)
            } else {
                cgCandidates.append(candidate)
            }
        }

        // すでに AX 情報で捕捉済みのウィンドウタイトルを消費し、別スペース等にしかない未捕捉項目のみ残す
        var unmatchedMenuItems = consumeCoveredMenuItems(
            menuItems: menuItems,
            axCandidates: axCandidates
        )

        // タイトルが空の標準 AX 候補がある場合、空き殻 cg-* へタイトルが流出しないようメニューまたは cgWindowName から補完する
        let pairableCGNames = cgCandidates
            .filter { WindowFilter.isValid($0) }
            .compactMap { trimmedNonEmpty($0.cgWindowName) }
        for idx in axCandidates.indices {
            let candidate = axCandidates[idx]
            guard isMenuTrackedAXWindow(candidate),
                  trimmedNonEmpty(candidate.title) == nil else {
                continue
            }
            if let cgName = trimmedNonEmpty(candidate.cgWindowName) {
                if let exactIdx = unmatchedMenuItems.firstIndex(where: {
                    trimmedNonEmpty($0.title) == cgName
                }) {
                    let matchedItem = unmatchedMenuItems.remove(at: exactIdx)
                    axCandidates[idx] = replacingTitle(of: candidate, with: matchedItem.title)
                    continue
                }
                if let fuzzyIdx = unmatchedMenuItems.firstIndex(where: {
                    titlesMatch(cgName, $0.title)
                }) {
                    let matchedItem = unmatchedMenuItems.remove(at: fuzzyIdx)
                    axCandidates[idx] = replacingTitle(of: candidate, with: matchedItem.title)
                    continue
                }
                axCandidates[idx] = replacingTitle(of: candidate, with: cgName)
                continue
            }
            if let fallbackIdx = unmatchedMenuItems.firstIndex(where: { item in
                !pairableCGNames.contains(where: { titlesMatch($0, item.title) })
            }) ?? unmatchedMenuItems.indices.first {
                let matchedItem = unmatchedMenuItems.remove(at: fallbackIdx)
                axCandidates[idx] = replacingTitle(of: candidate, with: matchedItem.title)
            }
        }

        // チェックマーク付きの項目（アプリ内の直近アクティブウィンドウ）を優先し、残りはメニュー順を保持する
        unmatchedMenuItems.sort { lhs, rhs in
            if lhs.isChecked != rhs.isChecked {
                return lhs.isChecked && !rhs.isChecked
            }
            return lhs.index < rhs.index
        }

        // Window メニューに載る標準 AX ウィンドウで既に捕捉済みの件数を差し引き、
        // タイトル不一致（別スペース滞在中の遷移や末尾表記差など）があっても実ウィンドウ総数を超えて cg-* が増殖しないよう制限する
        let coveredAXWindowCount = axCandidates.filter { isMenuTrackedAXWindow($0) }.count
        let remainingMenuCapacity = max(0, menuItems.count - coveredAXWindowCount)

        // WindowFilter の通常判定を通過できる実質的な CGWindow 補完候補のみをペアリング対象にする
        // （極小 1x1 やツールバー帯・無名空き殻窓に貴重なメニュータイトルが奪われるのを防ぐ）
        let pairableCGIndices = cgCandidates.indices.filter { WindowFilter.isValid(cgCandidates[$0]) }
        let sortedPairableIndices = pairableCGIndices.sorted { lhsIdx, rhsIdx in
            cgCandidatePriority(cgCandidates[lhsIdx]) < cgCandidatePriority(cgCandidates[rhsIdx])
        }

        let pairCount = min(unmatchedMenuItems.count, sortedPairableIndices.count, remainingMenuCapacity)
        let selectedCGs = sortedPairableIndices.prefix(pairCount).map { cgCandidates[$0] }
        let selectedMenus = Array(unmatchedMenuItems.prefix(pairCount))
        let pairedCGCandidates = pairCGsWithMenuItems(selectedCGs, menuItems: selectedMenus)

        // Window メニューで全実ウィンドウを把握できるアプリにおいて、
        // ペア数を超過して残った cg-* 候補は裏方の不可視/ゴーストウィンドウであるため除外する
        return axCandidates + pairedCGCandidates
    }

    /// ウィンドウタイトル同士が一致するか判定する（Chrome 等による中央省略「…」の補助照合を含む）
    /// - Parameters:
    ///   - fullOrCandidate: AX ウィンドウ等から得たタイトル
    ///   - menuTitle: Window メニューから得たタイトル（または比較先タイトル）
    /// - Returns: 同一ウィンドウのタイトルとみなせる場合は true
    public static func titlesMatch(_ fullOrCandidate: String, _ menuTitle: String) -> Bool {
        let a = fullOrCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = menuTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }

        // 片方が単一の中央省略記号「…」を含む場合、前後両端の一致で照合する
        if matchesEllipsisPattern(candidate: a, patternWithEllipsis: b)
            || matchesEllipsisPattern(candidate: b, patternWithEllipsis: a) {
            return true
        }
        return false
    }

    /// AX 候補群が既にカバーしているタイトル分をメニュー項目列から差し引き、未捕捉のメニュー項目のみを返す
    /// - Parameters:
    ///   - menuItems: 抽出済みのウィンドウメニュー項目
    ///   - axCandidates: すでに AX 情報付きで構築された候補群
    /// - Returns: 未捕捉分のウィンドウメニュー項目一覧
    private static func consumeCoveredMenuItems(
        menuItems: [WindowMenuItemSnapshot],
        axCandidates: [RawWindowCandidate]
    ) -> [WindowMenuItemSnapshot] {
        var remainingAXTitles = axCandidates.compactMap { candidate -> String? in
            guard let title = candidate.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                return nil
            }
            return title
        }

        // まず完全一致を優先消費し、残りで省略一致を消費する
        var consumedMenuIndices = Set<Int>()
        for (menuPos, item) in menuItems.enumerated() {
            let trimmedMenuTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let exactIdx = remainingAXTitles.firstIndex(of: trimmedMenuTitle) {
                remainingAXTitles.remove(at: exactIdx)
                consumedMenuIndices.insert(menuPos)
            }
        }

        var unmatched: [WindowMenuItemSnapshot] = []
        for (menuPos, item) in menuItems.enumerated() {
            guard !consumedMenuIndices.contains(menuPos) else { continue }
            if let fuzzyIdx = remainingAXTitles.firstIndex(where: { titlesMatch($0, item.title) }) {
                remainingAXTitles.remove(at: fuzzyIdx)
                continue
            }
            unmatched.append(item)
        }
        return unmatched
    }

    /// CGWindow 候補同士のペアリング優先順位タプルを構築する（小さいほど優先）
    /// - Parameter candidate: 比較対象の CGWindow 補完候補
    /// - Returns: 比較可能な優先順位タプル
    private static func cgCandidatePriority(_ candidate: RawWindowCandidate) -> (Int, Int, Int, Int, Int) {
        let onScreenPriority = (candidate.isOnScreen == true) ? 0 : 1
        let hasCGNamePriority = (trimmedNonEmpty(candidate.cgWindowName) != nil) ? 0 : 1
        let layerPriority = (candidate.layer == 0) ? 0 : 1
        let auxiliaryShapePenalty = isAuxiliaryPopupShape(candidate) ? 1 : 0
        return (onScreenPriority, hasCGNamePriority, layerPriority, auxiliaryShapePenalty, candidate.zOrderIndex)
    }

    /// 選出済み CGWindow 候補群とメニュー項目群を、cgWindowName 一致を優先して 1 対 1 でペアリングする
    /// - Parameters:
    ///   - cgCandidates: ペアリング対象に選出された CGWindow 候補配列
    ///   - menuItems: 割り当て対象のメニュー項目配列（同件数）
    /// - Returns: タイトル割り当て済みの候補配列
    private static func pairCGsWithMenuItems(
        _ cgCandidates: [RawWindowCandidate],
        menuItems: [WindowMenuItemSnapshot]
    ) -> [RawWindowCandidate] {
        var assignedTitles = Array<String?>(repeating: nil, count: cgCandidates.count)
        var remainingMenuIndices = Array(menuItems.indices)

        // 1. cgWindowName とメニュータイトルの完全一致を優先して結び付ける
        for cgIdx in cgCandidates.indices {
            guard let cgName = trimmedNonEmpty(cgCandidates[cgIdx].cgWindowName) else { continue }
            if let pos = remainingMenuIndices.firstIndex(where: {
                trimmedNonEmpty(menuItems[$0].title) == cgName
            }) {
                let menuIdx = remainingMenuIndices.remove(at: pos)
                assignedTitles[cgIdx] = menuItems[menuIdx].title
            }
        }

        // 2. cgWindowName とメニュータイトルの省略一致を次に結び付ける
        for cgIdx in cgCandidates.indices where assignedTitles[cgIdx] == nil {
            guard let cgName = trimmedNonEmpty(cgCandidates[cgIdx].cgWindowName) else { continue }
            if let pos = remainingMenuIndices.firstIndex(where: {
                titlesMatch(cgName, menuItems[$0].title)
            }) {
                let menuIdx = remainingMenuIndices.remove(at: pos)
                assignedTitles[cgIdx] = menuItems[menuIdx].title
            }
        }

        // 3. 残りは優先順位順に割り当てる
        var remainingCursor = 0
        return cgCandidates.indices.map { cgIdx in
            let title: String
            if let matchedTitle = assignedTitles[cgIdx] {
                title = matchedTitle
            } else {
                let menuIdx = remainingMenuIndices[remainingCursor]
                remainingCursor += 1
                title = menuItems[menuIdx].title
            }
            return replacingTitle(of: cgCandidates[cgIdx], with: title)
        }
    }

    /// 前後空白除去後に空でない文字列を返す
    /// - Parameter value: 対象のオプショナル文字列
    /// - Returns: 非空のトリム済み文字列（空または nil の場合は nil）
    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// オフスクリーンかつ横長扁平な補助ポップアップ風（予測変換ドロップダウン等）の CGWindow 形状かを判定する
    /// - Parameter candidate: 判定対象のウィンドウ候補
    /// - Returns: 実ウィンドウよりペアリング優先順位を劣後にすべき補助形状であれば true
    private static func isAuxiliaryPopupShape(_ candidate: RawWindowCandidate) -> Bool {
        guard candidate.isOnScreen != true else { return false }
        let height = candidate.bounds.height
        let width = candidate.bounds.width
        guard height > 0, height < 420.0 else { return false }
        return (width / height) > 3.0
    }

    /// メニュー項目一覧から指定タイトルに一致するインデックスを返す（別スペース遷移時は未チェック項目を優先）
    /// - Parameters:
    ///   - title: 照合対象のウィンドウタイトル
    ///   - items: 抽出済みのウィンドウメニュー項目一覧
    ///   - preferUnchecked: チェックマークが付いていない項目を優先するか（別スペース遷移時は true）
    /// - Returns: 一致したメニュー項目のインデックス（見つからない場合は nil）
    public static func matchingMenuItemIndex(
        for title: String,
        in items: [WindowMenuItemSnapshot],
        preferUnchecked: Bool
    ) -> Int? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 別スペースへの遷移時は未チェック項目群（完全一致 → 省略一致）を最優先で照合する
        if preferUnchecked {
            if let uncheckedExact = items.indices.first(where: {
                !items[$0].isChecked
                    && items[$0].title.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
            }) {
                return uncheckedExact
            }
            if let uncheckedFuzzy = items.indices.first(where: {
                !items[$0].isChecked && titlesMatch(items[$0].title, trimmed)
            }) {
                return uncheckedFuzzy
            }
        }

        if let exact = items.indices.first(where: {
            items[$0].title.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
        }) {
            return exact
        }
        return items.indices.first(where: {
            titlesMatch(items[$0].title, trimmed)
        })
    }

    /// RawWindowCandidate の title のみを差し替えた新しいインスタンスを返す
    /// - Parameters:
    ///   - candidate: 元の候補
    ///   - title: 設定する新しいタイトル
    /// - Returns: タイトル更新済みの RawWindowCandidate
    private static func replacingTitle(of candidate: RawWindowCandidate, with title: String) -> RawWindowCandidate {
        RawWindowCandidate(
            id: candidate.id,
            cgWindowID: candidate.cgWindowID,
            pid: candidate.pid,
            bundleIdentifier: candidate.bundleIdentifier,
            applicationName: candidate.applicationName,
            title: title,
            cgWindowName: candidate.cgWindowName,
            layer: candidate.layer,
            bounds: candidate.bounds,
            alpha: candidate.alpha,
            isRegularApplication: candidate.isRegularApplication,
            isSelf: candidate.isSelf,
            isMinimized: candidate.isMinimized,
            axRole: candidate.axRole,
            axSubrole: candidate.axSubrole,
            hasAXInfo: candidate.hasAXInfo,
            isOnScreen: candidate.isOnScreen,
            lastActivatedAt: candidate.lastActivatedAt,
            zOrderIndex: candidate.zOrderIndex
        )
    }

    /// 「ウィンドウ」メニューの総数に計上される実ウィンドウ（標準ウィンドウ／ダイアログ）の AX 候補かを判定する
    /// - Parameter candidate: 判定対象のウィンドウ候補
    /// - Returns: メニュー項目総数から差し引くべき有効な AX 候補であれば true
    private static func isMenuTrackedAXWindow(_ candidate: RawWindowCandidate) -> Bool {
        guard candidate.hasAXInfo, WindowFilter.isValid(candidate) else {
            return false
        }
        // フローティングウィンドウは「ウィンドウ」メニューに載らないため総数差し引き対象から除外する
        return candidate.axSubrole != "AXFloatingWindow" && candidate.axSubrole != "AXSystemFloatingWindow"
    }

    /// 「…」または「...」による中央・末尾・多重省略を含むパターンと対象文字列が一致するか判定する
    /// - Parameters:
    ///   - candidate: 省略なしの可能性がある文字列
    ///   - patternWithEllipsis: 省略記号を含む省略済み文字列
    /// - Returns: 順序および両端整合が取れており誤マッチ防止条件を満たす場合 true
    private static func matchesEllipsisPattern(candidate: String, patternWithEllipsis: String) -> Bool {
        for separator in ["…", "..."] {
            guard patternWithEllipsis.contains(separator) else { continue }
            let rawParts = patternWithEllipsis.components(separatedBy: separator)
            let totalLiteralCount = rawParts.reduce(0) { $0 + $1.count }
            // 省略前後の文字数が短すぎる場合は誤マッチ防止のため不採用とする
            guard totalLiteralCount >= 4, candidate.count >= totalLiteralCount else {
                continue
            }

            let startsWithWildcard = rawParts.first?.isEmpty ?? true
            let endsWithWildcard = rawParts.last?.isEmpty ?? true

            if !startsWithWildcard, let first = rawParts.first, !candidate.hasPrefix(first) {
                continue
            }
            if !endsWithWildcard, let last = rawParts.last, !candidate.hasSuffix(last) {
                continue
            }

            // 非空の各断片が先頭から末尾へ向かって順序通りに出現するかを検証する
            var searchStart = candidate.startIndex
            var matchedAll = true
            for (idx, part) in rawParts.enumerated() where !part.isEmpty {
                if idx == rawParts.count - 1 && !endsWithWildcard {
                    let remaining = candidate[searchStart...]
                    if remaining.count < part.count || !remaining.hasSuffix(part) {
                        matchedAll = false
                        break
                    }
                    searchStart = candidate.endIndex
                    continue
                }
                guard let foundRange = candidate.range(of: part, range: searchStart..<candidate.endIndex) else {
                    matchedAll = false
                    break
                }
                searchStart = foundRange.upperBound
            }
            if matchedAll {
                return true
            }
        }
        return false
    }
}
