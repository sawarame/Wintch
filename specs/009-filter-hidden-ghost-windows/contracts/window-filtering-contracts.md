# インターフェース契約 (Phase 1 Contracts): アプリ別ウィンドウプロファイルおよびフィルタリング契約

**Feature**: `009-filter-hidden-ghost-windows` | **Date**: 2026-11-15

## 1. ドメイン契約: `AppWindowProfileRegistry`

### `profile(for bundleIdentifier: String?) -> AppWindowProfile`
- **入力**: アプリケーションの Bundle Identifier（`nil` 許容）
- **出力**: 登録済みの専用 `AppWindowProfile`。未登録または `nil` の場合は `defaultProfile`（`offscreenCGPolicy: .allow`, `hiddenBackingSignatures: []`）を返す。
- **不変条件**:
  - 副作用を持たない純粋関数（`Sendable`・スレッドセーフ）で O(1) ルックアップを行う。
  - 将来アプリ対応を追加する際は、`profilesByBundleIdentifier` テーブルへの登録のみで挙動を拡張でき、呼び出し側の制御フロー変更を必要としない。

### `isHiddenBackingWindow(_ candidate: RawWindowCandidate) -> Bool`
- **事前条件**: `candidate` は収集済みの生ウィンドウ候補。
- **契約**:
  - `candidate.hasAXInfo == true` または `candidate.isOnScreen == true` または非空の `candidate.title` を持つ場合は **必ず `false`** を返す（ユーザーが開いている実ウィンドウを誤除外しない）。
  - 共通シグネチャ（`x ≈ 0, 500x500`）または `profile(for: candidate.bundleIdentifier).hiddenBackingSignatures` のいずれかに幾何一致した場合のみ `true` を返す。

---

## 2. ドメイン契約: `WindowFilter`

### `WindowFilter.isValid(_ candidate: RawWindowCandidate) -> Bool`
- **契約**:
  - 既存の共通ガード（自アプリ除外・非通常アプリ除外・許可レイヤー・透明度・最小サイズ・フローティングサイズ要件・表示中非 AX 除外）に加え、`AppWindowProfileRegistry.isHiddenBackingWindow(candidate)` が `true` の候補を除外する（`false` を返す）。
  - `OffscreenCGFallbackPolicy`（`.singleRepresentativeOnly` / `.requireAXOrMenuTitle`）は `isValid` ではなく `filterAndMap` で評価し、`WindowService.enrichCandidatesWithWindowMenu` が事前にメニュー補完を行える機会を奪わない。

### `WindowFilter.filterAndMap(_ candidates: [RawWindowCandidate], screenBounds: [WindowBounds] = []) -> [WindowEntry]`
- **契約**:
  1. `baseValidCandidates` に加えて、1 件も捕捉できなかったアプリに限り表示中（`isOnScreen == true`）の実サイズ `cg-*` を救済する既存契約を維持する。
  2. `prefiltered` 構築時、各候補のプロファイルに応じて以下を適用する：
     - `isOnScreen == true` かつ `!hasAXInfo` かつ `axCoveredPIDs` に含まれる候補の除外（既存契約）
     - `layer != 0` かつ `pidsWithPrimaryWindow` に含まれる非 AX 候補の除外（既存契約）
     - `offscreenCGPolicy == .singleRepresentativeOnly` かつ `axCoveredPIDs` に含まれる場合の非 AX 候補除外
     - `offscreenCGPolicy == .requireAXOrMenuTitle` かつ `!hasAXInfo && isOnScreen != true` かつタイトル空/nil の候補除外
  3. `offscreenCGPolicy == .singleRepresentativeOnly` かつ AX 未捕捉の場合、PID ごとに代表 1 件（表示中優先 → 面積最大 → Z 順上位）のみ残す。
  4. 同一 PID・非ディスプレイ占有級の同一矩形重複統合およびディスプレイ占有級（フルスクリーン等）の個別保持契約を維持する。

---

## 3. サービス連携契約: `WindowService`

- `WindowService.fetchRawWindowCandidates()` は従来通り `enrichCandidatesWithWindowMenu` を最後に呼び出し、取得した `[RawWindowCandidate]` を返す。
- メモアプリ等「ウインドウ」メニューに `makeKeyAndOrderFront:` やチェックマーク付きウィンドウ列を持たないアプリでメニュー抽出結果が空（`[]`）であっても、`WindowFilter.filterAndMap` が `AppWindowProfileRegistry` のポリシーに従って未表示ゴースト候補を除外するため、スイッチャー（`SwitcherViewModel`）および検索ランチャーの両方で一貫して実ウィンドウのみが表示される。
- `WindowService` 自体は特定 Bundle ID のハードコードを持たず、アプリ特性の知識はすべて `Domain/AppWindowProfile.swift` に集約する。
