# Phase 0 技術調査・設計判断レポート: スイッチャーおよび検索ランチャーからの選択中ウィンドウ終了

**Feature**: `005-close-selected-window`  
**Date**: 2026-11-15  
**Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/005-close-selected-window/spec.md)

## 調査目的

`005-close-selected-window` の仕様を満たすため、既存の `WintchCore`（`HotKeyMonitorService` / `WindowService` / `SwitcherViewModel` / `SwitcherPanel`）の構造を調査し、以下 5 点の技術方針を決定した。

---

## 1. Accessibility API による単一ウィンドウの安全なクローズ方法

### Decision
対象ウィンドウの `AXUIElement` から `kAXCloseButtonAttribute` を取得し、`kAXEnabledAttribute` が有効（未設定または `true`）であることを確認した上で `AXUIElementPerformAction(closeButton, kAXPressAction as CFString)` を実行する。

### Rationale
- macOS 標準のウィンドウの閉じるボタン押下（`Command + W` 相当）と同一のセマンティクスを持ち、同一アプリケーションの他ウィンドウやアプリケーションプロセス自体を終了（Quit）させない。
- 画面収録権限および非公開 API（`CGS*` 等）を一切使用せず、憲章の「1. 最小権限の原則」「5. 非公開 API の禁止」を完全に満たす。
- 未保存の変更があるドキュメントウィンドウに対しては、対象アプリケーション側が標準の保存確認ダイアログ（シート等）を表示し、強制破棄を回避できる。
- クローズボタンを持たない特殊ウィンドウや `kAXEnabledAttribute == false` のウィンドウに対しては無理に閉じようとせず、安全に「閉じられなかった（失敗／非対応）」として返すことでクラッシュを防止できる。

### Alternatives Considered
- **AppleScript / `NSRunningApplication.terminate()`**: `terminate()` はアプリ全体を終了させてしまい「選択ウィンドウ 1 枚のみを閉じる」仕様（FR-002）に反する。AppleScript はアプリごとの自動化権限ダイアログが別途必要になり最小権限の原則に反するため不採用。
- **キーイベント合成（`CGEvent` で `Command + W` を送信）**: ウィンドウを最前面へアクティブ化する必要があり、パネルを開いたまま連続整理する UX（FR-005）を損なう上、前面化に伴うフォーカス競合が起きやすいため不採用。

---

## 2. クローズ実行後のウィンドウ消滅確認と一覧更新タイミング

### Decision
`WindowServicing` に非同期のクローズメソッド `closeWindow(_ entry: WindowEntry) async -> Bool` を追加し、`kAXPressAction` 送信後に短時間（最大約 150ms、短い間隔で再確認）ウィンドウの存否を確認して、`AXUIElement` が消滅した場合のみキャッシュから除去して `true` を返し、残存している場合（未保存確認ダイアログ表示中やクローズ非対応等）はキャッシュを保持したまま `false` を返す設計とする。

### Rationale
- 通常ウィンドウであれば `kAXPressAction` 実行後おおむね数ミリ秒〜数十ミリ秒以内に `kAXWindowsAttribute` から消滅するか、`AXUIElementCopyAttributeValue` が失敗（または `kAXUIElementDestroyedNotification` 受信）する。これにより 200ms 以内の即時応答目標（SC-001）を満たしつつ、実態と一致したリスト更新ができる。
- もし `kAXPressAction` 送信直後に即断で一覧から削除してしまうと、未保存確認ダイアログが出ているウィンドウが一覧から消えてしまい、ユーザーがその状態に気づけない不整合が生じる。生存確認を挟むことで、閉じられたウィンドウだけを正確に除外できる。
- また、`WindowService` の `fetchRawWindowCandidates()` で `AXUIElement` 未キャッシュだった別スペースのウィンドウ（`cg-\(windowID)`）が指定された場合でも、クローズ実行前に `refreshAXWindows(for: entry.pid, ...)` で最新スキャンを試み、位置・タイトル等で `AXUIElement` を解決するフォールバックを入れることで、別操作スペースのウィンドウも確実に閉じられる。

### Alternatives Considered
- **送信と同時に楽観的削除し、後から `AXObserver` 通知のみで同期する方式**: 楽観的削除後に未保存ダイアログでキャンセルされた場合、パネルへウィンドウを再挿入する必要があり選択カーソルが乱れるため不採用。
- **確認なしで同期メソッドにする方式**: 閉じないウィンドウや非同期破棄のウィンドウの判別ができず、リスト更新の不整合が起きるため不採用。

---

## 3. キー判定（`HotKeyMonitorService`）と優先順位・文字入力防止

### Decision
1. `HotKeyEvent` に `.closeSelectedWindowPressed` ケースを追加する。
2. 仮想キーコード `12`（ANSI `Q` キー）かつ `modifiers.subtracting(.shift) == shortcut.modifiers` をクローズ操作の条件として `HotKeyMonitorService.resolveKeyDown` 内に組み込む（`.normal` および `.launcher` 双方で有効）。
3. 判定優先順位は以下の通りとし、既存機能・設定変更との衝突を防ぐ：
   - `.normal` モード: `Esc` / `↑` / `↓` → `isNormalMatch`（移動）→ `isLauncherMatch`（消費して無視）→ `isCloseWindowMatch`（`.closeSelectedWindowPressed` 通知＆消費）
   - `.launcher` モード: `isLauncherMatch`（トグル終了）→ `isNormalMatch`（候補移動）→ `isCloseWindowMatch`（`.closeSelectedWindowPressed` 通知＆消費）→ その他通過（単体 `Q` や `Shift + Q` 含む）

### Rationale
- `ShortcutConflictValidator` により通常スイッチャーの必須修飾キー `shortcut.modifiers` には必ず `Command` / `Option` / `Control` のいずれか 1 つ以上が含まれ、`.shift` は禁止されている。そのため、単体 `Q`（`modifiers == []`）や大文字入力 `Shift + Q`（`modifiers == [.shift]`）が `isCloseWindowMatch` に一致することは絶対にない。
- `HotKeyMonitorService` の `CGEventTap` コールバックで `shouldConsume: true`（`nil` 返却）としてイベントを消費するため、以下の 3 つの問題を一括で防げる（FR-010）：
  1. 検索ランチャー入力欄へ `Option + Q` 由来の特殊文字（英語配列の `œ` 等）が入力されること。
  2. 通常スイッチャーの修飾キーに `Command` が設定されている場合に、`Command + Q` として Wintch 自身や背面のアプリが終了（Quit）してしまうこと。
  3. 背面アプリケーションへキーイベントが漏洩すること。
- `modifiers.subtracting(.shift) == shortcut.modifiers` とすることで、通常スイッチャーで `Option + Shift + Tab` による逆順移動の直後に `Shift` が残ったまま `Q` を押しても自然に閉じる動作が反応する。

### Alternatives Considered
- **SwiftUI の `.onKeyPress` や `NSResponder.performKeyEquivalent` で検知する方式**: 通常スイッチャー（`nonactivatingPanel` で非アクティブのまま表示される場合や `Command + Q` をメニュー/OS が横取りする場合）で確実に捕捉できず、OS の `Command + Q` 終了や `Option + Q` 特殊文字入力を防ぎにくいため不採用。既存の `HotKeyMonitorService` へ統合するのがアーキテクチャ上最も一貫性がある。
- **設定画面で `Q` との衝突バリデーションを新設する方式**: 既存のテストや保存済み設定への後方互換性を維持し、憲章のシンプルさを保つため、`resolveKeyDown` 側で既存ショートカット優先の決定論的順序を定める方針とした。

---

## 4. `SwitcherViewModel` における一覧更新・選択位置維持・再入制御

### Decision
- `SwitcherViewModel` に `closeSelectedWindow()`（および `handleHotKeyEvent(.closeSelectedWindowPressed)` からの起動、`isClosingWindow` による再入防止ガード）を実装する。
- `windowService.closeWindow(target)` が `true` を返した場合のみ、`allEntries` から `target.id` を除外し、現在のモードに応じてリストと選択位置を再構築する：
  - **通常スイッチャー（`.normal`）**:
    - `allEntries` が空になったら `dismiss(reason: .cancelled)` でパネルを閉じる（残余 0 件）。
    - 残っている場合は `displayedResults` を再構築し、`selectedIndex = min(previousIndex, displayedResults.count - 1)` に調整する。
  - **検索ランチャー（`.launcher`）**:
    - `allEntries` 自体が空になったら（開いている通常ウィンドウが全件 0 件）、`dismiss(reason: .cancelled)` でパネルを閉じる（FR-007）。
    - 1 件以上残っている場合は、`WindowSearchEngine.search(query: searchQuery, in: allEntries)` で絞り込み結果を再計算する。
    - 絞り込み結果が 1 件以上あれば `selectedIndex = min(previousIndex, displayedResults.count - 1)` に維持し、絞り込み結果が 0 件になった場合は `selectedIndex = 0`（0 件案内表示）のままパネルと検索語を維持する。
- クローズ処理完了後にパネルリサイズ用コールバック `onSearchResultsUpdated?()`（またはパネル高さ更新通知）を発火する。

### Rationale
- `allEntries` と `displayedResults` の双方から対象ウィンドウを整合的に除外することで、検索キーワードを後から消した際にも閉じたウィンドウが復活しない。
- インデックス補正ルール `min(previousIndex, count - 1)` により、途中のウィンドウを閉じれば同じ位置（次の項目）が選択され、末尾のウィンドウを閉じれば新しい末尾が選択されるため、連続削除が直感的になる（FR-006）。
- `isClosingWindow` ガード（またはタスクの直列実行）により、クローズ確認中に素早く連打された場合でも同一ウィンドウへの二重送信やインデックス破壊を防止できる。

### Alternatives Considered
- **クローズ後に `fetchRawWindowCandidates()` を丸ごと再取得して `allEntries` を置き換える方式**: タイミングによっては未保存ダイアログ以外の遅延や別アプリのフォーカス変動で MRU 順が意図せず入れ替わり、連続して順番にウィンドウを閉じているユーザーのカーソル位置が飛ぶ恐れがあるため不採用。`allEntries` からの明示的除外が最も安定する。

---

## 5. `SwitcherPanel` の高さ追従（通常スイッチャー・検索ランチャー共通）

### Decision
`SwitcherPanel.updateAnchoredHeight(to:)` および `updateAnchoredHeightIfNeeded()` の高さ追従制御を見直し、ランチャーモード（`.launcher`）だけでなく通常スイッチャーモード（`.normal`）でリスト件数が減少した際にも、コンテンツの `fittingSize` に合わせてパネル高さ（およびシャドウ）が正しく縮小更新されるようにする。

### Rationale
- これまで `SwitcherPanel` はランチャーモード専用で上端固定リサイズを行っていたため、通常スイッチャー表示中にウィンドウを閉じて候補行数が減ると、パネルの高さが変わらず余白が残る可能性がある。
- 通常スイッチャー時は表示中パネルの中央（または上端）を基準に `fittingSize` へリサイズし `invalidateShadow()` を呼ぶことで、ウィンドウを閉じた直後にリストと枠線が滑らかに縮み、視覚的フィードバックが明確になる（SC-001）。
