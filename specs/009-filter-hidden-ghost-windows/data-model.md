# データモデル設計 (Phase 1 Data Model): アプリ別ウィンドウ判定プロファイルとフィルタリング構造

**Feature**: `009-filter-hidden-ghost-windows` | **Date**: 2026-11-15

## 1. エンティティ一覧と関係

```text
AppWindowProfileRegistry (静的レジストリ / テーブル)
  ├── defaultProfile: AppWindowProfile
  ├── commonHiddenBackingSignatures: [HiddenBackingWindowSignature]
  └── profilesByBundleIdentifier: [String: AppWindowProfile]
          │
          ▼ 参照 (bundleIdentifier キー)
AppWindowProfile (値型・Sendable・Equatable)
  ├── bundleIdentifier: String?
  ├── offscreenCGPolicy: OffscreenCGFallbackPolicy
  ├── hiddenBackingSignatures: [HiddenBackingWindowSignature]
  └── rationale: String（プロファイル設定の背景説明）
          │
          ▼ 評価対象
RawWindowCandidate (既存ドメインモデル)
          │
          ▼ WindowFilter.isValid / WindowFilter.filterAndMap
WindowEntry (既存出力モデル)
```

---

## 2. 型定義仕様

### 2.1 `OffscreenCGFallbackPolicy`

AX で捕捉できず、かつ画面外（`!hasAXInfo && isOnScreen != true`）として収集された `CGWindow` 補完候補（`cg-*`）の扱い方を表す列挙型。

| ケース | 意味 | 適用例 |
|---|---|---|
| `.allow` | 実質サイズ要件と幾何除外シグネチャを通過した画面外 `cg-*` を補完候補として許可する（既定動作）。メニュー補完があれば事前に `WindowMenuCandidatePairing` がタイトル付与と上限整理を行う。 | Chrome, VS Code, Finder, WezTerm 等の一般アプリ |
| `.singleRepresentativeOnly` | 単一メインウィンドウ構成のアプリとして扱い、AX 捕捉済み（`axCoveredPIDs` 含有）なら画面外 `cg-*` を一切許可せず、AX 未捕捉時のみ表示状態・面積・Z 順に基づく最良の代表 1 件へ絞る。 | システム設定 (`com.apple.systempreferences`) |
| `.requireAXOrMenuTitle` | 画面外 `cg-*` 候補について、メニュー補完等によって非空のウィンドウタイトルが確定している候補のみを許可し、タイトル不明（`nil` または空白のみ）の画面外 `cg-*` を除外する。AX 捕捉済み（`hasAXInfo == true`）および表示中救済対象（`isOnScreen == true`）はタイトル有無にかかわらず保持する。 | メモ (`com.apple.Notes`) |

### 2.2 `HiddenBackingWindowSignature`

アプリまたは Cocoa / SwiftUI フレームワークが内部に生成する、ユーザー操作対象外の未表示バックキングウィンドウを識別する純粋な幾何条件モデル。

| フィールド | 型 | 説明 |
|---|---|---|
| `width` | `Double` | 一致判定するウィンドウ幅（ポイント） |
| `height` | `Double` | 一致判定するウィンドウ高さ（ポイント） |
| `requiresZeroOriginX` | `Bool` | 左上 X 座標が `0` 付近であることを必須とするか（`true` の場合は画面左端生成の既定バックキング窓に限定） |
| `tolerance` | `Double` | 座標・サイズ比較の許容誤差（既定 `2.0pt`） |

**判定不変条件（Validation / Guard Rules）**:
`HiddenBackingWindowSignature.matches(_ candidate: RawWindowCandidate)` が `true` を返すのは、以下の**すべて**を満たす場合のみとする。
1. `!candidate.hasAXInfo`（AX 実ウィンドウとして捕捉されていない）
2. `candidate.isOnScreen != true`（現在の操作スペース上に表示されていない）
3. `(candidate.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`（タイトルが付与されていない）
4. `abs(candidate.bounds.width - width) <= tolerance` かつ `abs(candidate.bounds.height - height) <= tolerance`
5. `requiresZeroOriginX` が `true` の場合は `abs(candidate.bounds.x) <= tolerance`

> **安全性の根拠**: 仮にユーザーが偶然 `500x500` や `475x600` サイズの実ウィンドウを開いていたとしても、実ウィンドウは `hasAXInfo == true`・`isOnScreen == true`・タイトル保有のいずれかを満たすため、このガードにより誤除外されない。

### 2.3 `AppWindowProfile`

特定アプリケーションのウィンドウフィルタリング特性を 1 箇所にまとめる宣言的設定構造体。

| フィールド | 型 | 説明 |
|---|---|---|
| `bundleIdentifier` | `String?` | 対象アプリの Bundle ID（汎用既定プロファイル時は `nil`） |
| `offscreenCGPolicy` | `OffscreenCGFallbackPolicy` | 画面外・AX 未捕捉 `cg-*` の採用ポリシー |
| `hiddenBackingSignatures` | `[HiddenBackingWindowSignature]` | 当該アプリ固有の未表示補助ウィンドウ幾何シグネチャ一覧 |
| `rationale` | `String` | この個別プロファイルが必要な OS/アプリ固有背景の説明（保守者向けドキュメント用途） |

### 2.4 `AppWindowProfileRegistry`

すべてのアプリプロファイルおよび共通除外シグネチャを集約管理する純粋レジストリ。

- **静的プロパティ・テーブル**:
  - `commonHiddenBackingSignatures`: 全アプリに適用される既定の未表示バックキングウィンドウ条件
    - `HiddenBackingWindowSignature(width: 500, height: 500, requiresZeroOriginX: true)`: AppKit / SwiftUI の既定未表示 `NSWindow`（Cocoa 原点 `(0,0,500,500)`）
  - `defaultProfile`: 未登録アプリ向けの標準プロファイル（`offscreenCGPolicy: .allow`、`hiddenBackingSignatures: []`）
  - `profilesByBundleIdentifier: [String: AppWindowProfile]`:
    - `"com.apple.systempreferences"`:
      - `offscreenCGPolicy: .singleRepresentativeOnly`
      - `hiddenBackingSignatures: []`（`500x500` は共通シグネチャを自動継承）
    - `"com.apple.Notes"`:
      - `offscreenCGPolicy: .requireAXOrMenuTitle`
      - `hiddenBackingSignatures: [HiddenBackingWindowSignature(width: 475, height: 600, requiresZeroOriginX: false)]`
- **提供メソッド**:
  - `profile(for bundleIdentifier: String?) -> AppWindowProfile`
  - `isHiddenBackingWindow(_ candidate: RawWindowCandidate) -> Bool`: 共通シグネチャ群と対象アプリプロファイルの `hiddenBackingSignatures` のいずれかに一致するか判定する。

---

## 3. 既存フィルタリングパイプラインとの状態遷移

1. **収集段階（`WindowService.fetchRawWindowCandidates`）**:
   - `AX` スキャン結果と `CGWindowListCopyWindowInfo` を結合して `[RawWindowCandidate]` を生成。
2. **メニュー対象判定（`WindowService.enrichCandidatesWithWindowMenu` → `WindowFilter.isValid`）**:
   - `WindowFilter.isValid` 内の共通ガードで `AppWindowProfileRegistry.isHiddenBackingWindow(candidate)` を評価し、共通 `500x500` やメモの `475x600` 等の既知ノイズをこの段階で除外する。
   - 残った `!hasAXInfo` 候補に対して「ウインドウ」メニュー補完を試行する。
3. **最終フィルタリング（`WindowFilter.filterAndMap`）**:
   - 各候補の `profile = AppWindowProfileRegistry.profile(for: candidate.bundleIdentifier)` を取得し、`profile.offscreenCGPolicy` に応じて処理する：
     - `.allow`: 従来通りの重複座標統合のみ適用。
     - `.singleRepresentativeOnly`: AX 捕捉済みなら画面外 `cg-*` 除外、未捕捉時のみ最良代表 1 件を選出。
     - `.requireAXOrMenuTitle`: `!candidate.hasAXInfo && candidate.isOnScreen != true` かつタイトル空/nil の候補を除外。
4. **表示（`SwitcherViewModel`）**:
   - 通常スイッチャー（リスト型・キャプチャ表示型）および検索ランチャーの双方で同一の `[WindowEntry]` を使用して表示・検索・終了判定を行う。
