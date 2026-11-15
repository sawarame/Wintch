# 技術調査・設計判断レポート (Phase 0 Research): メモ等の非表示内部補助ウィンドウによる重複・ゴースト表示の除外

**Feature**: `009-filter-hidden-ghost-windows` | **Date**: 2026-11-15

## 1. 事象と実測データの整理

Mac 標準「メモ」アプリ（`com.apple.Notes`）が 1 枚しかウィンドウを開いていない状態で、通常スイッチャーおよび検索ランチャーの両方に `メモ (タイトルなし)` が複数表示される問題を実環境で計測した。

### 実測結果（`com.apple.Notes`）

- **AX（Accessibility）側の取得状況**:
  - 別スペース滞在時は `kAXWindowsAttribute` が空配列を返すが、`kAXFocusedWindowAttribute` および `kAXMainWindowAttribute` が実ウィンドウ 1 件（`AXWindow` / `AXStandardWindow`、タイトル `eco検定 – 14件のメモ`、`bounds=(487, 30, 1157, 1046)`）を返却していた。
- **`CGWindowListCopyWindowInfo` の取得状況（実質サイズ `>= 200x165`, `layer=0`）**:
  1. `id=7248`: `bounds=(487, 30, 1157, 1046)` — 上記 AX 実ウィンドウと照合済み。
  2. `id=7247`: `bounds=(828, 253, 475, 600)`、`isOnScreen` 未設定（`false`）、`AX` 対象外、`title=nil` — メモアプリ内部の未表示補助ウィンドウ。
  3. `id=7249`: `bounds=(0, 580, 500, 500)`、`isOnScreen` 未設定（`false`）、`AX` 対象外、`title=nil` — Cocoa / SwiftUI 標準の既定 `500x500` 未表示バックキングウィンドウ（画面高さ `1080` 上で Cocoa 原点 `(0, 0, 500, 500)` が CG 座標 `(0, 580, 500, 500)` に変換されたもの）。
- **「ウインドウ」メニューの取得状況**:
  - メモアプリの「ウインドウ」メニューには `メモ`（`⌘0`, `id=_NS:1215`）および `写真ブラウザ`（`id=_NS:1221`）等の固定項目のみが存在し、`makeKeyAndOrderFront:` 識別子やチェックマーク付きウィンドウ一覧ブロックを持たない。
  - そのため `WindowMenuExtractor.extractWindowListItems` が空配列 `[]` を返し、`WindowService.enrichCandidatesWithWindowMenu` が `WindowMenuCandidatePairing.applyMenuTitles`（余剰ゴースト `cg-*` 除外）を実行せず素通りさせていた。

### 他アプリでの同根事象（実測）

- **`com.google.GeminiMacOS`（Gemini）**: 開いているウィンドウが 0 枚でも `bounds=(0, 580, 500, 500)`, `isOnScreen=false`, `hasAXInfo=false`, `title=nil` の `CGWindow`（`id=7261`）を保持しており、`Gemini (タイトルなし)` として誤表示されていた。
- **`com.apple.systempreferences`（システム設定）**: 同様に `bounds=(0, 580, 500, 500)` の未表示 `CGWindow`（`id=4515`）を保持していたが、従来コードでは `WindowFilter.isHiddenSystemSettingsBackingWindow` で `com.apple.systempreferences` のみ個別対応していた。

---

## 2. 設計判断（Decisions）

### Decision 1: アプリ別ウィンドウ特性を宣言的プロファイル／レジストリ（`AppWindowProfile` + `AppWindowProfileRegistry`）へ構造化する

- **Decision**: `Domain/` 層に `AppWindowProfile.swift` を新設し、アプリごとのウィンドウ特性（画面外未捕捉 `cg-*` 補完ポリシー `OffscreenCGFallbackPolicy` および非表示補助ウィンドウ幾何シグネチャ `HiddenBackingWindowSignature`）を宣言的な値型＋Bundle ID マッピングテーブル（`AppWindowProfileRegistry`）として定義する。`WindowFilter` 内に散在していた `systemPreferencesBundleID` / `singleWindowBundleIdentifiers` / `isHiddenSystemSettingsBackingWindow` の個別分岐を撤廃し、`AppWindowProfileRegistry` を参照する統一ロジックへ統合する。
- **Rationale**:
  - 今後対応アプリが増えても、`AppWindowProfileRegistry.profilesByBundleIdentifier` に 1 エントリ（値型設定＋理由コメント）を追加するだけで済み、`WindowFilter` のフィルタリング制御フローが肥大化・スパゲッティ化しない。
  - 憲章第 7 項（過度な抽象化・複雑な独自ジェネリクスを避けた明快な Swift コード・高いテスト可能性）に最もよく適合する。
- **Alternatives considered**:
  1. `WindowFilter.swift` に `isHiddenNotesAuxWindow` 等の `if/else` 特例メソッドを追記する方式
     - 却下理由: アプリが増えるたびに `WindowFilter.filterAndMap` や `passesCommonGuards` の分岐が増え、可読性と保守性が急速に低下する。
  2. プロトコルとアプリ別クラス群（例: `NotesWindowPolicy: AppWindowPolicy` 等）によるポリモーフィズム
     - 却下理由: 単純なルール組み合わせに対してファイル数・ボイラープレートが過剰となり、憲章が禁じる過度な抽象化になりやすい。将来メニュー抽出等の振る舞い拡張が必要になった際も、`AppWindowProfile` へ設定フィールド（例: `menuPolicy`）を追加する方が見通しが良い。

### Decision 2: `x ≈ 0, 500x500` の未表示バックキングウィンドウ除外を全アプリ共通ルールへ昇格する

- **Decision**: `x ≈ 0` かつ `500x500`（許容誤差 `2.0pt`）、かつ `!hasAXInfo`・`isOnScreen != true`・タイトル空/nil の候補を除外するルールを、`com.apple.systempreferences` 限定から **全アプリ共通の `commonHiddenBackingSignatures`** へ引き上げる。
- **Rationale**:
  - `com.apple.systempreferences`、`com.apple.Notes`、`com.google.GeminiMacOS` の 3 アプリすべてで同一座標・同サイズ（`(0, screenHeight - 500, 500, 500)`）の AppKit/SwiftUI 既定未表示ウィンドウが確認されており、OS/フレームワーク横断の構造的ノイズであるため。
  - `hasAXInfo == true`（実際に開いているウィンドウ）または `isOnScreen == true`（画面上に表示中のウィンドウ）またはタイトル取得済みのウィンドウは対象外とするため、ユーザーが偶然 `x=0, 500x500` に配置した実ウィンドウを誤除外しない。
- **Alternatives considered**:
  - `Notes` と `Gemini` を個別にブラックリスト登録する方式
    - 却下理由: SwiftUI / AppKit 採用アプリ全般で再発するため、アプリ単位のモグラ叩きになる。

### Decision 3: メモアプリ（`com.apple.Notes`）の `OffscreenCGFallbackPolicy` と補助窓シグネチャの併用

- **Decision**: `com.apple.Notes` のプロファイルを `offscreenCGPolicy = .requireAXOrMenuTitle` とし、さらに既知の `475x600` 未表示補助ウィンドウを `hiddenBackingSignatures` に登録する。
- **Rationale**:
  - メモアプリは実ウィンドウ 1 枚でも「ウインドウ」メニューに `makeKeyAndOrderFront:` 項目を出さないため、`WindowMenuCandidatePairing` による余剰 `cg-*` 刈り込みが働かない。また、すべてのウィンドウを閉じた後も `475x600` と `500x500` の `cg-*` を残し続ける。
  - `.requireAXOrMenuTitle` により、「AX で捕捉済みの実ウィンドウ（同スペースの `AXWindows`、別スペースでも `AXFocusedWindow`/`AXMainWindow` で取得可能、かつ訪問済みキャッシュ維持）」および「メニュー補完等でタイトルが判明したウィンドウ」だけを保持し、正体不明のタイトルなし画面外 `cg-*` を確実に抑止できる。
  - 同時に `475x600` シグネチャも定義しておくことで、意図と根拠がプロファイル定義上に明文化され、`WindowService.enrichCandidatesWithWindowMenu` の事前フィルタ（`WindowFilter.isValid`）段階で不要なメニュー問い合わせも回避できる。
- **Alternatives considered**:
  1. 全アプリ一律で `.requireAXOrMenuTitle` にする方式
     - 却下理由: 「ウインドウ」メニューを実装していない、あるいはメニューからタイトルを取れない一般アプリ（テスト済みの Terminal や起動直後の別スペース Chrome / WezTerm 等）で、正当な別スペース実ウィンドウが消えてしまうリスクがある。
  2. メモアプリを `singleRepresentativeOnly`（システム設定と同じ単一ウィンドウ扱い）にする方式
     - 却下理由: メモアプリは個別メモを独立ウィンドウとして複数開くことが可能であり、2 枚以上開いた場合に 1 枚へ潰れてしまったり、逆に 0 枚（全閉）時に `475x600` の代表 1 件が残ってしまったりする。

### Decision 4: `WindowFilter.isValid` と `WindowFilter.filterAndMap` の責務境界を維持する

- **Decision**:
  - `HiddenBackingWindowSignature`（既知の未表示内部ウィンドウ幾何条件：`500x500` やメモの `475x600`）の除外は `WindowFilter.isValid`（`passesCommonGuards` 経由）で行う。
  - `OffscreenCGFallbackPolicy`（`.singleRepresentativeOnly` や `.requireAXOrMenuTitle` のように候補間の関係や補完後タイトル有無を見るルール）は `WindowFilter.filterAndMap` で行う。
- **Rationale**:
  - `WindowService.enrichCandidatesWithWindowMenu` は `WindowFilter.isValid(candidate)` を基準にメニュー問い合わせ対象 PID を決めている。もし `isValid` 側で `title == nil` を一律弾いてしまうと、今後 `.requireAXOrMenuTitle` を適用したアプリが将来または特定状況で「ウインドウ」メニューからタイトル補完を受けられなくなる。
  - 既存の `singleWindowBundleIdentifiers` が `filterAndMap` 側に置かれていたのと同じ境界を保つことで、実行パイプライン（`fetchCG + AX` → `isValid` でメニュー対象選定 → `enrichCandidatesWithWindowMenu` → `filterAndMap`）の整合性が保たれる。
- **Alternatives considered**:
  - `WindowService` 内で直接プロファイル判定して候補を捨てる方式
    - 却下理由: 純粋なドメイン判定ロジックが `Services/` へ漏出し、単体テスト性が低下する（憲章および `AGENTS.md` の層分離原則に反する）。
