# インターフェース契約 (Contracts): 検索ランチャーでの検索入力時におけるアプリ起動候補の併用表示

**Feature Branch**: `006-launcher-app-launch` | **Date**: 2026-11-15

## 1. `AppSearchEngine` ドメイン契約

- **シグネチャ**:
  ```swift
  public static func search(
      query: String,
      in apps: [LaunchableApp],
      excludingWindowEntries: [WindowEntry] = []
  ) -> [AppSearchResult]
  ```
- **契約条件**:
  1. `query` が空文字または空白文字のみの場合、即座に空配列 `[]` を返す。
  2. `excludingWindowEntries` に含まれるウィンドウと同一アプリケーション（双方の `bundleIdentifier` が非空なら大文字小文字無視で一致、いずれか欠落時は `applicationName` と `displayName` または非空の `alternateName` が大文字小文字無視で一致）と判定されたアプリは候補から除外する。
  3. 残ったアプリに対し、`FuzzySearchMatcher.evaluate` で `primaryText: app.displayName`, `secondaryText: alternateName`（`displayName` と大文字小文字無視で同一なら `""`）, `primaryFieldBonus: 25` で評価する。
  4. スコア降順、同スコア時は `displayName.localizedStandardCompare` 昇順（さらに同値時は `id` 昇順）でソートして返す。

## 2. `InstalledAppServicing` サービス契約

- **プロトコル定義**: `@MainActor public protocol InstalledAppServicing: AnyObject`
  - `func cachedInstalledApps() -> [LaunchableApp]`
    - メモリキャッシュを同期で即座に返す（検索入力時のゼロレイテンシ保証）。
  - `@discardableResult func refreshInstalledApps() async -> [LaunchableApp]`
    - バックグラウンドスレッドで標準アプリディレクトリおよび個別対象アプリを走査し、重複排除・除外フィルタ適用後にキャッシュを更新して返す。多重呼び出し時は進行中タスクを合流する。
  - `func launchApplication(_ app: LaunchableApp)`
    - `NSWorkspace.shared.openApplication(at:configuration:)`（`activates = true`）で対象アプリを起動・前面化する。

## 3. `IconProviding` 拡張契約

- **追加メソッド**:
  - `func icon(forAppURL url: URL) -> NSImage?`
    - アプリケーションバンドルの `standardizedFileURL` をキーにアイコンをキャッシュ・返却する。

## 4. `SwitcherViewModel` 統合操作契約

- **公開プロパティ**:
  - `displayedAppResults: [AppSearchResult]`（非検索時は常に空）
  - `isShowingLaunchCandidates: Bool`（`mode == .launcher && !displayedAppResults.isEmpty`）
- **公開メソッド**:
  - `func icon(forAppURL url: URL) -> NSImage?`
  - `func preloadInstalledApps()`
  - `func moveSelection(_ direction: ArrowDirection)`: 統合件数 `displayedResults.count + (mode == .launcher ? displayedAppResults.count : 0)` を対象に循環移動。
  - `func selectAndActivate(at index: Int)` / `func confirmSelection()`: ウィンドウ範囲ならウィンドウアクティブ化、アプリ範囲ならアプリ起動。
  - `func closeSelectedWindow() async`: `displayedResults.indices.contains(selectedIndex)` を満たさない場合（アプリ候補選択中または 0 件）は無視。成功後は同一検索語でウィンドウ候補と未表示アプリ候補の双方を再評価。

## 5. `SwitcherListView` 表示契約

- 検索ランチャー表示時:
  - `displayedResults` が非空なら上部にウィンドウ候補一覧を表示。
  - `displayedAppResults` が非空なら下部に（`displayedResults` も非空なら `Divider` 付きで）セクション案内ヘッダとアプリ起動候補行を表示。
    - ウィンドウ候補あり時ヘッダ: `アプリを起動`
    - ウィンドウ候補 0 件時ヘッダ: `一致するウィンドウがないため、アプリを起動`
  - 双方空のときのみ `一致するウィンドウがありません` を表示。
  - 単一 `ScrollViewReader` + `ScrollView` により、ウィンドウ候補（`"window-<id>"`）およびアプリ候補（`"app-<id>"`）の選択行へ自動スクロール追従し、パネル上端位置を固定したまま高さを下方向へ伸縮する。
