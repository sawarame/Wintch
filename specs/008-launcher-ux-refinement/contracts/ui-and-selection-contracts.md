# Phase 1 インターフェース・UI 契約: ランチャー初期フォーカス変更と検索プレースホルダー視認性改善

**Feature**: `008-launcher-ux-refinement` | **Date**: 2026-11-15

## 1. ドメインロジック契約: `SwitcherSelection`

対象ファイル: `Sources/WintchCore/Domain/SwitcherSelection.swift`

### 公開インターフェース

```swift
public enum SwitcherSelection {
    /// スイッチャー起動時の初期選択インデックスを算出する
    /// - Parameters:
    ///   - count: 有効なウィンドウの件数
    ///   - preferSecondItem: 2件以上ある場合に2番目（インデックス1）を選択するか（通常スイッチャーは true、ランチャーは false）
    /// - Returns: 0件なら nil、1件なら 0、2件以上かつ preferSecondItem が true なら 1、false なら 0
    public static func initialIndex(count: Int, preferSecondItem: Bool = true) -> Int?
}
```

### 契約条件
- `count <= 0` の場合は `preferSecondItem` の値にかかわらず必ず `nil` を返す。
- `count == 1` の場合は `preferSecondItem` の値にかかわらず必ず `0` を返す。
- `count >= 2` かつ `preferSecondItem == true` の場合は `1` を返す（通常スイッチャー互換）。
- `count >= 2` かつ `preferSecondItem == false` の場合は `0` を返す（検索ランチャー用）。
- デフォルト引数 `preferSecondItem: Bool = true` により、既存の `SwitcherSelection.initialIndex(count:)` 呼び出しと完全なソース互換性を保つ。

---

## 2. ViewModel 契約: `SwitcherViewModel`

対象ファイル: `Sources/WintchCore/ViewModels/SwitcherViewModel.swift`

### `present(targetMode:)` の振る舞い
- `targetMode == .normal`: `SwitcherSelection.initialIndex(count: sorted.count, preferSecondItem: true)` を使用し、2件以上なら `selectedIndex == 1`、1件なら `selectedIndex == 0` とする。
- `targetMode == .launcher`: `SwitcherSelection.initialIndex(count: sorted.count, preferSecondItem: false)` を使用し、1件以上なら常に `selectedIndex == 0` とする。
- リストの並び順（`WindowSorter.sortByMRU`）は両モードとも変更しない。

---

## 3. UI コンポーネント契約: `LauncherSearchField`

対象ファイル: `Sources/WintchCore/Views/LauncherSearchField.swift`

### プレースホルダー描画仕様
- プレースホルダー文字列は `"ウィンドウまたはアプリを検索..."` を維持する。
- `NSTextField.placeholderAttributedString` を生成する静的ヘルパー（例：`static func makePlaceholderAttributedString(_ text: String = placeholderText) -> NSAttributedString`）を提供し、以下の属性を保証する：
  - `.foregroundColor`: `NSColor.secondaryLabelColor`
  - `.font`: `NSFont.systemFont(ofSize: 15, weight: .regular)`
- `makeNSView(context:)` で生成された `NSTextField` には上記 `placeholderAttributedString` が設定され、入力文字色（`textColor = .labelColor`）より控えめでありつつ `.ultraThinMaterial` 上で明確に判読可能なコントラストを確保する。
- 日本語 IME 変換制御（`hasMarkedText()` による上書き抑止・コマンド処理優先）および初回フォーカス付与挙動は一切変更しない。
