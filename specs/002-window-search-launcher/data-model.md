# データモデル・状態遷移設計 (Data Model): ウィンドウ検索ランチャーモード

**Feature**: `002-window-search-launcher`  
**Date**: 2026-11-13  
**Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/002-window-search-launcher/spec.md)

---

## 1. ドメインモデル（`Sources/WintchCore/Domain/`）

### 1.1 `ShortcutModifiers`（ショートカット修飾キーフラグ）
ランチャーショートカットや競合比較で共通利用する値型 `OptionSet`。

| フラグ | 対応キー | 表示記号 | 備考 |
|---|---|---|---|
| `.command` | Command (⌘) | `⌘` | 必須修飾キー候補 |
| `.option` | Option (⌥) | `⌥` | 必須修飾キー候補 |
| `.control` | Control (⌃) | `⌃` | 必須修飾キー候補 |
| `.shift` | Shift (⇧) | `⇧` | 併用可能（単独または組み合わせでの必須条件は満たさない） |

- **算出プロパティ**:
  - `hasPrimaryModifier: Bool` — `.command`, `.option`, `.control` のいずれかを含む場合に `true`
  - `displaySymbols: [String]` — macOS 標準順（`⌃`, `⌥`, `⇧`, `⌘`）で記号配列を返す

---

### 1.2 `LauncherShortcutPreference`（ランチャーショートカット設定）
ランチャーモードを起動・トグル終了するショートカット設定値型（`Codable`, `Equatable`, `Sendable`）。

| フィールド | 型 | デフォルト値 | 説明 |
|---|---|---|---|
| `keyCode` | `UInt16` | `49` (`Space`) | macOS 仮想キーコード |
| `modifiers` | `ShortcutModifiers` | `[.option]` | 修飾キーの組み合わせ |
| `keyLabel` | `String` | `"Space"` | 画面表示用のキー表記 |

- **バリデーションルール**:
  - `modifiers.hasPrimaryModifier == true` であること（修飾キーなし、および `.shift` のみは無効）
  - `keyCode` が有効なトリガーキー（修飾キー単体や `Esc` `53` 以外）であること
- **算出プロパティ**:
  - `displayString: String` — 例: `"⌥ + Space"`, `"⌃ + ⇧ + K"`
- **静的デフォルト**:
  - `LauncherShortcutPreference.default = LauncherShortcutPreference(keyCode: 49, modifiers: [.option], keyLabel: "Space")`

---

### 1.3 `ShortcutConflictValidator`（純粋競合検証ロジック）
通常スイッチャー (`ShortcutPreference`) とランチャー (`LauncherShortcutPreference`) の双方向競合と妥当性を検証する純粋列挙型。

- **検証メソッド**:
  - `validateLauncherShortcut(_ candidate: LauncherShortcutPreference, against normal: ShortcutPreference) -> ShortcutValidationResult`
    1. `candidate.modifiers.hasPrimaryModifier == false` → `.invalidModifier("Command / Option / Control のいずれか1つ以上の修飾キーを含めてください。")`
    2. `conflicts(launcher: candidate, normal: normal)` → `.conflictWithNormalSwitcher("通常スイッチャー（\(normal.displayString) / \(normal.reverseDisplayString)）と重複するため登録できません。")`
    3. それ以外 → `.valid`
  - `validateNormalShortcut(_ candidate: ShortcutPreference, against launcher: LauncherShortcutPreference) -> ShortcutValidationResult`
    1. `conflicts(launcher: launcher, normal: candidate)` → `.conflictWithLauncher("ランチャー（\(launcher.displayString)）と重複するため設定できません。")`
    2. それ以外 → `.valid`
  - `conflicts(launcher: LauncherShortcutPreference, normal: ShortcutPreference) -> Bool`
    - 通常スイッチャー順方向キー `(normal.trigger.keyCode, [normal.modifier.flag])`
    - 通常スイッチャー逆方向キー `(normal.trigger.keyCode, [normal.modifier.flag, .shift])`
    - `launcher.keyCode` と `launcher.modifiers` が上記いずれかに一致した場合に `true`

---

### 1.4 `WindowSearchResult`（ウィンドウ検索結果）
ファジー検索の評価結果およびハイライト範囲を表す値型（`Identifiable`, `Equatable`, `Sendable`）。

| フィールド | 型 | 説明 |
|---|---|---|
| `entry` | `WindowEntry` | 対象のウィンドウ項目 |
| `score` | `Int` | ファジーマッチ評価スコア（未検索時は `0`） |
| `matchedAppNameRanges` | `[Range<String.Index>]` | `entry.applicationName` 内のハイライト範囲配列（正規化・結合済み） |
| `matchedTitleRanges` | `[Range<String.Index>]` | `entry.windowTitle` 内のハイライト範囲配列（空タイトル時は常に `[]`） |

- `id: String` — `entry.id` を委譲

---

### 1.5 `WindowSearchEngine`（純粋ファジー検索エンジン）
`[WindowEntry]` と検索文字列を受け取り、`[WindowSearchResult]` を返す純粋ロジック。

- **入力**: `query: String`, `entries: [WindowEntry]`（MRU ソート済み）
- **処理規則**:
  1. `query` を空白文字でトリミングし、空文字なら全 `entries` を元の MRU 順で `WindowSearchResult(entry: $0, score: 0, matchedAppNameRanges: [], matchedTitleRanges: [])` に変換して返す。
  2. 空白で分割した全トークンに対し、各 `entry` が**すべてのトークンで一致（AND 条件）** することを判定する。
  3. `entry.windowTitle` が空白のみ（または空文字）の場合は空文字列として検索し、`"(タイトルなし)"` にはマッチさせない。
  4. トークンごとに `entry.applicationName` および `entry.windowTitle` に対して大文字小文字・発音区別符号を区別しないサブシーケンス一致を評価し、最高スコアとハイライト用 `Range<String.Index>` を取得する（アプリ名一致には適度な重みを加算）。
  5. 一致した全エントリを **`score` 降順、同スコア時は元の MRU インデックス昇順** でソートして返す。

---

## 2. UI・ViewModel 状態モデル

### 2.1 `SwitcherMode`（スイッチャー表示モード）

```swift
public enum SwitcherMode: Equatable, Sendable {
    /// 非表示
    case inactive
    /// 従来の修飾キー保持式ウィンドウ切り替えモード
    case normal
    /// 検索入力ボックス付きランチャーモード（トグル式）
    case launcher
}
```

### 2.2 `SwitcherViewModel` の状態遷移

| イベント / 操作 | 現在の `mode` | 遷移先 `mode` | 状態変化 |
|---|---|---|---|
| `triggerPressed(isShiftPressed:)` | `.inactive` | `.normal`（権限あり & 1件以上） | `allEntries = sorted`, `displayedResults = 変換後全件`, `selectedIndex = initialIndex(count)` |
| `triggerPressed(isShiftPressed:)` | `.normal` | `.normal` | `selectedIndex` を次/前へ移動 |
| `triggerPressed(isShiftPressed:)` | `.launcher` | `.launcher` | `displayedResults` 件数内で次へ（順方向）/ 前へ（`isShiftPressed == true`）選択移動（0件時は変更なし、FR-004 改定 / `004-launcher-switcher-nav`） |
| `launcherTriggerPressed` | `.inactive` | `.launcher`（権限あり & 1件以上） | `searchQuery = ""`, `allEntries = sorted`, `displayedResults = 変換後全件`, `selectedIndex = initialIndex(count)` |
| `launcherTriggerPressed` | `.normal` | `.normal` | 無視（FR-004） |
| `launcherTriggerPressed` | `.launcher` | `.inactive` | ウィンドウ切り替えせずパネルを閉じる（トグル終了） |
| `updateSearchQuery(_:)` | `.launcher` | `.launcher` | `WindowSearchEngine.search` で `displayedResults` を更新。空→非空またはクエリ変更時は `selectedIndex = 0`（0件時は `0`）、空に戻した場合は MRU 全件＋`0`（または仕様通りリセット） |
| `modifierReleased` | `.normal` | `.inactive` | `selectedIndex` のウィンドウをアクティブ化して閉じる |
| `modifierReleased` | `.launcher` | `.launcher` | 無視（トグル式のため閉じない） |
| `confirmSelection()` (`Enter` / Click) | `.normal` / `.launcher` | `.inactive` | `displayedResults.indices.contains(selectedIndex)` なら対象をアクティブ化して閉じる。0件時は何もしない |
| `cancel()` (`Esc` / 外部クリック) | `.normal` / `.launcher` | `.inactive` | 切り替えせずパネルを閉じる |
| `arrowPressed` / `moveSelection(_:)` | `.normal` / `.launcher` | 同じモード | `displayedResults` 件数内で循環移動（0件時は何もしない） |

> [!NOTE]
> クエリを一度入力してからすべてバックスペースで空に戻した場合の選択位置は、検索バー操作中の自然な挙動として先頭（`0`）または候補存在時の先頭を維持する（初回起動未入力時は `initialIndex` ＝ 2件以上なら `1`）。
