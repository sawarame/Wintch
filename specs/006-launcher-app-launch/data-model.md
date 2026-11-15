# データモデル (Data Model): 検索ランチャーでの検索入力時におけるアプリ起動候補の併用表示

**Feature Branch**: `006-launcher-app-launch` | **Date**: 2026-11-15

## 1. ドメインモデル（`Sources/WintchCore/Domain/`）

### `LaunchableApp`
インストール済みかつ起動可能なアプリケーションを表す不変の値型（`Identifiable, Equatable, Sendable`）。

| フィールド | 型 | 制約 / 説明 |
|---|---|---|
| `id` | `String` | 一意識別子（正規化済みバンドル URL パス、未指定時は `bundleURL.standardizedFileURL.path`） |
| `displayName` | `String` | 表示・主検索用の名称（`.app` 拡張子を除いたローカライズ表示名） |
| `alternateName` | `String` | 補助検索用の別名（ファイル名由来の原語名が `displayName` と大文字小文字無視で異なる場合のみ保持、同一なら `""`） |
| `bundleIdentifier` | `String?` | バンドル識別子（例: `com.apple.Safari`）。重複排除および既存ウィンドウ候補との同一アプリ照合に利用 |
| `bundleURL` | `URL` | シンボリックリンク解決済みのアプリケーションバンドル URL |

### `AppSearchResult`
`AppSearchEngine` の検索評価結果を表す値型（`Identifiable, Equatable, Sendable`）。

| フィールド | 型 | 制約 / 説明 |
|---|---|---|
| `app` | `LaunchableApp` | 対象の起動可能アプリケーション |
| `score` | `Int` | ファジー検索で算出された一致スコア |
| `matchedDisplayNameRanges` | `[Range<String.Index>]` | `app.displayName` 内の一致文字位置範囲（昇順・結合済み） |
| `matchedAlternateNameRanges` | `[Range<String.Index>]` | `app.alternateName` 内の一致文字位置範囲（昇順・結合済み） |
| `id` | `String`（算出） | `app.id` |

### `WindowEntry`（拡張）
既存の `WindowEntry` に `bundleIdentifier: String? = nil` を追加し、`WindowFilter.filterAndMap(_:)` で `RawWindowCandidate.bundleIdentifier` を引き継ぐ。

| 追加フィールド | 型 | 制約 / 説明 |
|---|---|---|
| `bundleIdentifier` | `String?` | ウィンドウ所有アプリのバンドル識別子（デフォルト `nil`、下欄アプリ候補の重複除外に使用） |

### `TwoFieldFuzzyMatch`（`FuzzySearchMatcher` 内部共通型）
`WindowSearchEngine` および `AppSearchEngine` が共通利用する 2 フィールド評価結果。

| フィールド | 型 | 説明 |
|---|---|---|
| `score` | `Int` | 全トークンのベストフィールドスコア合算値 |
| `primaryMatchedRanges` | `[Range<String.Index>]` | 主テキストの一致文字位置範囲（昇順・結合済み） |
| `secondaryMatchedRanges` | `[Range<String.Index>]` | 補助テキストの一致文字位置範囲（昇順・結合済み） |

## 2. 統合選択インデックスと状態遷移（`SwitcherViewModel`）

### インデックス空間の定義（ランチャーモード時）

- `windowCount = displayedResults.count`
- `appCount = (mode == .launcher) ? displayedAppResults.count : 0`
- `activeResultCount = windowCount + appCount`
- インデックス範囲マッピング:
  - `0 <= selectedIndex < windowCount`: ウィンドウ候補 `displayedResults[selectedIndex]` を選択中
  - `windowCount <= selectedIndex < activeResultCount`: アプリ起動候補 `displayedAppResults[selectedIndex - windowCount]` を選択中

### 状態遷移ルール

| 操作 / イベント | ウィンドウ候補 | アプリ起動候補 | 結果・選択位置 |
|---|---|---|---|
| ランチャー起動（未入力） | 全有効ウィンドウ（MRU順） | 空（`[]`） | `selectedIndex = initialIndex`（0件不可、1件→0、2件以上→1） |
| 非空クエリ入力 | 一致ウィンドウ（スコア順） | 一致未表示アプリ（スコア順） | 双方合計 > 0 なら `selectedIndex = 0`（ウィンドウ優先）、双方 0 なら 0 件メッセージ |
| クエリを空文字へ戻す | 全有効ウィンドウ（MRU順） | 空（`[]`） | `selectedIndex = 0` |
| `↑`/`↓`・`Ctrl+N/P`・通常ショートカット | — | — | `0 ..< activeResultCount` 内で循環移動 |
| `Enter` / 行クリック（ウィンドウ範囲） | — | — | パネルを閉じ `windowService.activateWindow` を実行 |
| `Enter` / 行クリック（アプリ範囲） | — | — | パネルを閉じ `installedAppService.launchApplication` を実行 |
| `修飾キー + Q`（ウィンドウ範囲） | 残余を再計算 | 残余と検索語で再計算 | `indexAfterRemoval(current: remainingCount: activeResultCount)` |
| `修飾キー + Q`（アプリ範囲 / 0件） | 変化なし | 変化なし | 無視してパネル維持 |
| 裏スキャン完了（ランチャー検索中） | 変化なし | 最新一覧で再評価（重複除外適用） | 変化ありなら `indexAfterRemoval` で補正し UI 更新通知 |
