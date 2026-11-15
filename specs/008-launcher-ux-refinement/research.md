# Phase 0 技術調査・設計判断レポート: ランチャー初期フォーカス変更と検索プレースホルダー視認性改善

**Feature**: `008-launcher-ux-refinement` | **Date**: 2026-11-15

## 1. ランチャー起動時の初期選択インデックス算出方式

### 現状の調査結果
- `Sources/WintchCore/Domain/SwitcherSelection.swift` の `SwitcherSelection.initialIndex(count: Int) -> Int?` は現在 `count == 1 ? 0 : 1` を返しており、モード（通常スイッチャー vs 検索ランチャー）の区別を持たない。
- `Sources/WintchCore/ViewModels/SwitcherViewModel.swift` の `present(targetMode: SwitcherMode)`（435行目付近）では、`.normal` と `.launcher` の双方がこの同じ `SwitcherSelection.initialIndex(count: sorted.count)` を呼び出している。
- そのため、2件以上のウィンドウが存在する状態で検索ランチャーを起動すると、常にインデックス `1`（2番目のウィンドウ）が初期選択されてしまっていた。

### 設計判断
- **Decision**: `SwitcherSelection.initialIndex` に起動対象モードに応じた分岐を導入する。具体的には、既存呼び出しとの互換性を保ちつつ `SwitcherSelection.initialIndex(count: Int, preferSecondItem: Bool = true) -> Int?`（または `SwitcherSelection.initialIndex(count: Int, isLauncher: Bool)` / `SwitcherMode` が `Domain/` ではなく `ViewModels/` にある点を踏まえ `Domain/` 純粋型としての独立性を保つため `preferSecondItem: Bool` もしくは `SwitcherInitialSelectionPolicy`、あるいは `SwitcherMode` を引数に取らない純粋フラグ/列挙型）を検討する。
- **検討した選択肢と選定理由**:
  - **選択肢 A（採用）**: `SwitcherSelection.initialIndex(count: Int, preferSecondItem: Bool = true) -> Int?`（あるいは `initialIndex(count: Int)` を維持しつつ `initialLauncherIndex(count: Int) -> Int?` または `initialIndex(count: Int, prefersSecondItem: Bool = true)` を定義）。
    - `Domain/` 層は `ViewModels/`（`SwitcherMode` が定義されている場所）に依存すべきではない（MVVM 層の依存方向: `Views` → `ViewModels` → `Domain`）。
    - `preferSecondItem: Bool = true`（デフォルト `true` で通常スイッチャー互換）または `enum InitialSelectionRule { case first, secondIfMultiple }` を `SwitcherSelection` 内に定義すれば、`Domain/` から `ViewModels/` への逆依存を作らずに、純粋関数として明確にユニットテスト可能になる。
    - より意図が自己文書化される形として、`SwitcherSelection.initialIndex(count: Int, preferSecond: Bool = true) -> Int?`（または `initialIndex(count: Int)` は通常用として残し、`initialIndex(count: Int, selectFirst: Bool)` 等）にする。`preferSecond: Bool = true` なら既存の `SwitcherSelectionTests` や呼び出し互換も壊れず、`SwitcherViewModel.present(targetMode:)` では `preferSecond: targetMode != .launcher` を渡すだけで 1 行で明確に表現できる。
  - **選択肢 B（不採用）**: `SwitcherMode` を `Domain/` へ移動し `initialIndex(count:mode:)` とする。
    - 今回の変更スコープ外である `SwitcherMode` のファイル移動・公開API整理を伴い、差分が不要に広がるため見送る。
  - **選択肢 C（不採用）**: `SwitcherViewModel.present` 側で `targetMode == .launcher ? 0 : initial` と上書きする。
    - 初期選択ルールが `Domain/SwitcherSelection` と `ViewModels/SwitcherViewModel` に分散し、憲章の「選択位置算出などの純粋ビジネスロジックは Domain に切り出し単体テスト可能にする」方針に反するため見送る。

### 検索入力・削除・リスト操作との相互作用
- 検索ランチャー起動直後：`selectedIndex == 0`（1番目）。
- `updateSearchQuery` で検索文字入力時：既存の実装（329行目）により `selectedIndex = 0` に設定される。
- 検索文字を全削除して空文字に戻した時：`updateSearchQuery("")` で全ウィンドウが再設定され、`selectedIndex = 0`（1番目）となるため、起動直後の選択状態と完全に一貫する。
- `moveSelection(.down)` / `.triggerPressed(isShiftPressed: false)`：インデックス `0` → `1`（2番目）へ移動。
- `moveSelection(.up)` / `.triggerPressed(isShiftPressed: true)`：インデックス `0` → `count - 1`（末尾）へ循環移動。

---

## 2. 検索プレースホルダーの視認性改善方式

### 現状の調査結果
- `Sources/WintchCore/Views/SwitcherListView.swift` のパネル背景は `.background(.ultraThinMaterial)` を使用している。
- 検索ヘッダ（`searchHeaderView`）では、左側の虫眼鏡アイコン（`magnifyingglass`）が `.foregroundStyle(.secondary)` で描画され、各ウィンドウ行のウィンドウタイトルも `.secondary` で描画されている。
- 一方、検索入力欄 `Sources/WintchCore/Views/LauncherSearchField.swift` は `NSTextField` をラップした `NSViewRepresentable` であり、`drawsBackground = false` の上で `textField.placeholderString = "ウィンドウまたはアプリを検索..."` のみを設定している。
- macOS の標準 `NSTextField.placeholderString` は `NSColor.placeholderTextColor`（ライトモード時は黒の約 25% 不透明度）で描画されるため、`.ultraThinMaterial` の半透明背景かつ背後が明るい画面の上では文字が極端に薄くなり、隣接する虫眼鏡アイコン（`.secondary`）や行内のウィンドウタイトル（`.secondary`）と比べて著しく読みづらくなっている。

### 設計判断
- **Decision**: `LauncherSearchField` の `makeNSView` において、`placeholderString` の代わりに `placeholderAttributedString` を設定し、前景色として `NSColor.secondaryLabelColor`（フォントは本文と同じ `NSFont.systemFont(ofSize: 15, weight: .regular)`）を指定する。
- **Rationale**:
  1. `NSColor.secondaryLabelColor` は macOS 標準のセマンティックカラーであり、ライトモード・ダークモード双方およびアクセシビリティ設定（「コントラストを上げる」有効時など）に自動追従する。
  2. 不透明度が約 50%〜55% 程度（`placeholderTextColor` の約 2 倍）となるため、明るい背景上の `.ultraThinMaterial` でも文字の輪郭をはっきりと判読でき、同時に同じヘッダ内の虫眼鏡アイコン（SwiftUI `.secondary`）やリスト行のウィンドウタイトル（`.secondary`）と視覚的トーンが統一される。
  3. 実際の入力文字は `NSColor.labelColor`（約 85%〜100% 不透明度）で描画されるため、「プレースホルダー（未入力案内）」と「ユーザーが入力した検索文字列」のコントラスト差が明確に保たれ、誤認を防げる。
  4. `NSTextField` 標準の `placeholderAttributedString` 機構をそのまま利用するため、文字入力開始時および日本語 IME の未確定入力（`hasMarkedText`）開始時に OS 標準挙動で即座にプレースホルダーが非表示となり、IME 制御やテキスト入力に一切干渉しない。
- **検討した代替案**:
  - **代替案 A**: `NSColor.labelColor.withAlphaComponent(0.65)` の固定アルファ値にする。
    - 「コントラストを上げる」等のシステムアクセシビリティ設定への自動追従性が `NSColor.secondaryLabelColor` に劣るため、まずは標準セマンティックカラーである `NSColor.secondaryLabelColor` を採用する。
  - **代替案 B**: SwiftUI 側でプレースホルダー用 `Text` を `ZStack` で重ねる。
    - 日本語 IME の未確定文字列（`hasMarkedText`）編集中は SwiftUI バインディング `text` が即座に更新されないケースがあり、IME 未確定文字とプレースホルダーが二重表示されるリスクがある。`NSTextField.placeholderAttributedString` を使えば AppKit のフィールドエディタが未確定文字の有無を認識して自動でプレースホルダーを消すため安全。

---

## 3. 既存仕様書との整合化範囲

- `specs/002-window-search-launcher/spec.md`:
  - User Story 1 受入シナリオ 1 の「2番目の項目（ウィンドウB）が初期選択される」および `FR-006` の「2件以上の場合は2番目の項目、1件のみの場合は1番目の項目を初期選択しなければならない」に `008-launcher-ux-refinement` による改定注記（1番目を初期選択する旨）を追記し整合化する。
- `specs/004-launcher-switcher-nav/spec.md`:
  - User Story 1 受入シナリオ 1 の「（初期選択は2番目の項目）」に `008-launcher-ux-refinement` による改定注記を追記し整合化する。
