import Foundation
import Testing
@testable import WintchCore

/// WindowSorter の MRU および Zオーダーソートロジックを検証するテストスイート
@Suite("WindowSorter テスト")
struct WindowSorterTests {
    /// lastActivatedAt の新しい順に並び、未記録のものは後ろで zOrderIndex 昇順になることを検証する
    @Test("MRU日時降順とZオーダー昇順のハイブリッドソート")
    func sortByMRUAndZOrder() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let older = now.addingTimeInterval(-60)

        let entries = [
            WindowEntry(id: "untracked-back", pid: 1, applicationName: "A", windowTitle: "1", lastActivatedAt: nil, zOrderIndex: 5),
            WindowEntry(id: "older", pid: 2, applicationName: "B", windowTitle: "2", lastActivatedAt: older, zOrderIndex: 2),
            WindowEntry(id: "untracked-front", pid: 3, applicationName: "C", windowTitle: "3", lastActivatedAt: nil, zOrderIndex: 1),
            WindowEntry(id: "newest", pid: 4, applicationName: "D", windowTitle: "4", lastActivatedAt: now, zOrderIndex: 4)
        ]

        let sorted = WindowSorter.sortByMRU(entries)
        #expect(sorted.map(\.id) == ["newest", "older", "untracked-front", "untracked-back"])
    }

    /// すべての日時が未記録の場合、システム重なり順 (zOrderIndex) の昇順になることを検証する
    @Test("MRU未記録のみの場合はZオーダー昇順で並ぶ")
    func sortFallbackToZOrderOnly() {
        let entries = [
            WindowEntry(id: "w3", pid: 1, applicationName: "A", windowTitle: "3", zOrderIndex: 10),
            WindowEntry(id: "w1", pid: 2, applicationName: "B", windowTitle: "1", zOrderIndex: 0),
            WindowEntry(id: "w2", pid: 3, applicationName: "C", windowTitle: "2", zOrderIndex: 3)
        ]

        let sorted = WindowSorter.sortByMRU(entries)
        #expect(sorted.map(\.id) == ["w1", "w2", "w3"])
    }
}
