# 技術調査レポート (Research): 検索ランチャー表示中の通常スイッチャーショートカットによる候補移動

**Feature**: `004-launcher-switcher-nav`  
**Date**: 2026-11-14  
**Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/004-launcher-switcher-nav/spec.md)

---

## 1. イベント監視層（`HotKeyMonitorService`）のイベント消費と配送設計

### Decision
`HotKeyMonitorService.handleCGEvent` の `.launcher` モード分岐において、`isLauncherMatch` 判定の後に `isNormalMatch` が一致した場合、イベントを消費（`nil` を返却）しつつ `dispatchEvent(.triggerPressed(isShiftPressed: flags.contains(.maskShift)))` を呼び出す。さらに、`keyDown` イベントのモード別判定・消費ロジックを純粋な構造体・静的メソッド（`HotKeyKeyDownDecision` および `resolveKeyDown(...)`）として切り出し、`CGEventTap` コールバックとユニットテストの双方から同一ロジックを参照する。

### Rationale
- 既存の `HotKeyMonitorService` では `.launcher` モード中に `isNormalMatch` を `return nil` で消費していたため検索欄や背面アプリへのキー漏れ自体は既に防がれていたが、`dispatchEvent` が呼ばれていなかったために候補移動が動作していなかった。
- 判定時に `isLauncherMatch` を `isNormalMatch` より先に評価する順序を維持することで、万一外部から `UserDefaults` を直接編集して両設定が重複したケースでも、ランチャー自身のトグル終了操作が優先される（仕様の Assumptions 準拠）。
- 判定ロジックを `CGEvent` に依存しない純粋メソッドへ分離することで、アクセシビリティ権限や実 UI なしに `swift test` 上で全モード（`.inactive` / `.normal` / `.launcher`）の順逆判定・消費判定を網羅的に検証できる。

### Alternatives Considered
- **`SwitcherPanel` / `LauncherSearchField` の `NSResponder` で `Option + Tab` を拾う案**:
  `Option + Tab` は macOS のテキスト入力やフォーカス移動機構（キービュー ループ）と干渉しやすく、さらに通常スイッチャーの設定が `Control + Space` や `Command + ` ` 等にカスタマイズされた場合、アプリ単位のローカルイベント監視や `NSTextFieldDelegate` だけではOSや他コントロールのショートカット処理より先に安定して横取り・消費することが難しい。すでに `CGEventTap` が `.headInsertEventTap` で `shortcut` 設定を常時保持・同期判定しているため、サービス層で統一処理する方が確実で一貫性が高い。
- **`HotKeyEvent` にランチャー専用の移動イベント（例：`.launcherMoveNext`）を追加する案**:
  `.triggerPressed(isShiftPressed:)` は「通常スイッチャーのショートカットが押された」という発生源の事実をそのまま表現しており、`SwitcherViewModel` 側で現在の `mode`（`.inactive` / `.normal` / `.launcher`）に応じて意味付けを切り替える既存設計と自然に合致する。イベント種別を不要に増やさずプロトコル互換性も維持できるため、既存の `.triggerPressed(isShiftPressed:)` を再利用する。

---

## 2. 修飾キー解放・キーリピート・IME 入力との相互作用

### Decision
1. **修飾キー解放（`flagsChanged`）**:
   既存の `if snapshot.activeMode == .normal && !snapshot.shortcut.modifiers.isSubset(of: currentModifiers)` 条件を維持し、`.launcher` モード中は `.modifierReleased` を一切送信しない（ViewModel 側でも `if mode == .normal` ガードを維持する）。
2. **キーリピート**:
   `CGEventTap` の `.keyDown` 判定はオートリピートイベント（`keyboardEventAutorepeat != 0`）を除外せずそのまま処理・消費するため、`Option` を押したまま `Tab` を押し続けた場合も連続して「次へ」「前へ」移動が行われ、検索欄に文字が漏れない。
3. **日本語 IME 入力との共存**:
   `CGEventTap` で消費されるのは `isLauncherMatch` と `isNormalMatch` のみであり、`Enter`・`Esc`・`↑`・`↓`・`Ctrl+N`/`Ctrl+P`・文字キーは従来通り `Unmanaged.passUnretained(event)` で `LauncherSearchField`（`NSTextField`）および IME へ素通しされる。また、`isNormalMatch` は `CGEventTap` 側で消費されるため、IME の未確定文字列（`markedText`）が存在する状態で `Option + Tab` 等が押されてもフィールドエディタの未確定文字列が破壊されたり確定されたりすることなくリストの選択移動のみが行われる。

### Rationale
- トグル式ランチャーの操作体験（FR-004：修飾キーを離しても確定しない）を損なわず、かつ IME 優先ルール（`002-window-search-launcher` FR-012）を完全に維持できる。

### Alternatives Considered
- **IME 変換中（`hasMarkedText() == true`）は通常スイッチャーショートカットも通過させる案**:
  通常スイッチャーショートカットは必ず `Command` / `Option` / `Control` を1つ以上含むグローバルショートカットであり、`Option + Tab` 等を通過させても IME 候補選択には使われず、むしろ検索欄のフォーカスループ移動や不正文字入力を招くリスクが高い。したがって `.launcher` 中は常に消費して選択移動として扱う方が安全である。

---

## 3. ViewModel 層（`SwitcherViewModel`）の選択移動統合

### Decision
`SwitcherViewModel.handleTriggerPressed(isShiftPressed:)` において、`.normal` と `.launcher` を統合し、`moveSelection(isShiftPressed ? .up : .down)` を呼び出す。

### Rationale
- `moveSelection(_:)` はすでに `guard mode != .inactive, !displayedResults.isEmpty else { return }` を備えており、表示中の `displayedResults`（未入力時は MRU 全件、検索時は一致スコア順の絞り込み結果）の件数に基づいて `SwitcherSelection.nextIndex` / `SwitcherSelection.previousIndex` による循環移動（Wrap-Around）を実行する。
- これにより、以下のエッジケースが追加分岐なしで自動的に満たされる：
  - 検索結果 0 件時は選択移動せず安全に無視される（FR-006）。
  - 候補 1 件時は `0` のまま維持される。
  - 絞り込み中（`searchQuery` 非空）は `searchQuery` や `displayedResults` を変更せず、`selectedIndex` のみ更新される（FR-005）。
  - `SwitcherListView` 側は既存の `.onChange(of: viewModel.selectedIndex)` により自動で選択行のハイライト更新とスクロール追従が行われるため、View 側の変更は不要。

### Alternatives Considered
- `.launcher` 用に別のインデックス更新メソッドを新設する案：既存の `moveSelection(_:)` と完全に同一のロジック重複になるため不採用。
