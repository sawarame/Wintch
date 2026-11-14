# 技術調査レポート (Research): ウィンドウ検索ランチャーモード

**Feature**: `002-window-search-launcher`  
**Date**: 2026-11-13  
**Purpose**: ランチャーモード（検索入力・ファジーマッチ・ハイライト・IME共存・上端固定リサイズ・ショートカットレコーダー・競合防止）を実装するにあたっての技術的選択肢・設計判断・根拠を整理する。

---

## 1. 日本語 IME 共存とランチャー入力フィールドの設計

### Decision
- ランチャーモードの検索入力欄には AppKit の `NSTextField`（`NSViewRepresentable` 経由で SwiftUI に統合）を使用し、`NSTextFieldDelegate` の `control(_:textView:doCommandBy:)` により `Enter`（`insertNewline:`）、`Esc`（`cancelOperation:`）、`↑`/`↓`/`Ctrl+N`/`Ctrl+P`（`moveUp:` / `moveDown:`）を処理する。
- ランチャーパネル表示時は、`NSWorkspace.shared.frontmostApplication` を直前アプリとして記録した上で `NSApplication.shared.activate()` を呼び出して `SwitcherPanel` をキーウィンドウ化し、テキストフィールドをファーストレスポンダにする。`Esc`・トグル再押下によるキャンセル時は、パネルを閉じた後に直前アプリを再度アクティブ化して元の作業状態へ戻す（通常スイッチャーモード時は従来通り `NSApplication.shared.activate()` を呼ばず `.nonactivatingPanel` のまま動作させる）。
- `HotKeyMonitorService`（`CGEventTap`）では、**通常スイッチャー表示中のみ** `Esc`・`↑`・`↓`・`modifierReleased` をグローバル横取りし、**ランチャー表示中**はランチャー自身の起動ショートカット（トグル終了用）のみを監視・消費し、その他のキー（`Esc`・`↑`・`↓`・`Enter`・文字入力・IME 操作）はすべてキーウィンドウのレスポンダーチェーンへ通過させる。

### Rationale
1. **IME の確実な動作保証**: macOS の日本語 IME（ライブ変換・ローマ字かな変換・変換候補ウィンドウ）は、テキストフィールドを保持するアプリがアクティブ（`NSApp.isActive == true`）かつ `NSTextField` のフィールドエディタ（`NSTextView`）がファーストレスポンダである状態で最も安定して動作する。
2. **IME 変換中キー操作の自動優先**: AppKit の `NSTextView` は、未確定文字列（`hasMarkedText() == true`）や変換候補ウィンドウが表示されている最中の `Enter`・`Esc`・`↑`・`↓` を内部のテキスト入力システム（`InputMethodKit`）で消費し、`control(_:textView:doCommandBy:)` には転送しない。そのため、「変換確定の `Enter` でウィンドウが切り替わる」「変換キャンセルの `Esc` でランチャーが閉じてしまう」事故を構造的に 0% にできる（FR-012 / SC-005 準拠）。
3. **`Ctrl + N` / `Ctrl + P` の自然な統合**: Cocoa テキストシステムでは `Ctrl + N` が `moveDown:`、`Ctrl + P` が `moveUp:` に標準バインドされているため、`doCommandBy` で `moveUp:` / `moveDown:` をハンドルするだけで `↑` / `↓` と `Ctrl + N` / `Ctrl + P` の双方を一貫して処理できる（さらに `hasMarkedText()` が false であることを明示確認することで安全性を二重担保する）。

### Alternatives Considered
- **SwiftUI 標準 `TextField` + `CGEventTap` によるキー横取り**: `CGEventTap` は OS のセッション先頭でイベントを横取りするため、IME 変換中かどうかの判定ができず、変換候補の上下移動や確定 `Enter` を奪ってしまうため不採用。
- **SwiftUI 標準 `TextField` + `.onKeyPress` (macOS 14+)**: `.onKeyPress` は `Ctrl+N`/`Ctrl+P` や IME 変換確定時のイベント伝播タイミングが環境・IME 種別によって不安定になりやすいため、AppKit フィールドエディタを直接制御できる `NSTextField` ラッパーを採用した。

---

## 2. 上端固定の下方向リサイズ制御 (`SwitcherPanel`)

### Decision
- `SwitcherPanel` に「上端アンカー座標（`anchoredTopY: CGFloat?`）」を保持する。
- ランチャー初回表示時は初期リストを含むパネル高さから画面中央の矩形を計算して配置し、その時点の `frame.maxY`（AppKit の左下原点座標系におけるパネル上端の Y 座標）を `anchoredTopY` として保存する。
- 検索クエリ変更等により SwiftUI コンテンツの `fittingSize` が変化した際は、`hostingView.layoutSubtreeIfNeeded()` 後の `fittingSize.height` を取得し、`newOriginY = anchoredTopY - newHeight` として `setFrame(_:display:)` で下方向のみ伸縮させる。
- パネルを非表示（`hidePanel()`）にしたタイミングで `anchoredTopY` をリセットする。

### Rationale
- AppKit 座標系は左下が `(0, 0)` であるため、`frame.maxY` を一定に保つことで「検索ボックスの上端および画面上の垂直位置を 0pt ズレなく固定し、リストの下端だけが伸び縮みする」挙動（FR-013 / SC-003）を実現できる。
- macOS 14.0 (Sonoma) がターゲットであるため、macOS 15.0 以降の API（`onGeometryChange` 等）には依存せず、`NSHostingView` の `layout()` または `SwitcherListView` からの高さ更新通知 + `layoutSubtreeIfNeeded()` で確実に動作させる。

### Alternatives Considered
- **パネルを常に最大高さ（420pt+検索欄）に固定する**: リストが 1〜2 件に絞られた際に大きな空白領域が残り視認性が低下するため、上端固定・下方向伸縮方式を採用した。
- **毎回 `showCentered()` で中央寄せし直す**: 件数が減るたびに検索ボックスが画面中央へ向かって下に移動してしまい、視線とタイピング体験が損なわれるため不採用。

---

## 3. ファジー検索アルゴリズムとハイライト用範囲計算 (`WindowSearchEngine`)

### Decision
- `Sources/WintchCore/Domain/WindowSearchEngine.swift` に純粋ロジックとしてファジー検索エンジンを実装する（Apple 標準ライブラリ `Foundation` のみ使用・外部依存ゼロ）。
- **検索仕様**:
  - クエリの前後空白をトリミングし、空文字の場合は全 `WindowEntry` を既存の MRU 順（インデックス順）のままスコア 0・ハイライトなしで返す。
  - クエリを空白文字（`whereSeparator: \.isWhitespace`）で複数トークンへ分割し、**すべてのトークンが一致する（AND 条件）** エントリのみを残す。
  - 検索対象テキストは `entry.applicationName` と `entry.windowTitle`（空白トリミング後が空なら空文字扱いとし、`"(タイトルなし)"` という表示用プレースホルダ文字列にはマッチさせない）。
  - 文字比較は大文字・小文字および全角/半角・発音区別符号の揺れに寛容な正規化（例：`lowercased()` / `folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)`、かつ Unicode スカラー／文字単位で元文字列の `Range<String.Index>` を保持する方式）で行う。
- **スコアリング設計（各トークンの最良マッチスコアを合算）**:
  - サブシーケンス一致を必須とし、以下の加点を適用する：
    1. **先頭一致ボーナス**: 文字列先頭（インデックス 0）での一致
    2. **連続一致ボーナス**: 直前のマッチ文字と連続して一致した場合に加点（連続長に応じて増加）
    3. **単語境界ボーナス**: スペース・`-`・`_`・`/`・`.` の直後、またはキャメルケース境界（小文字の次の大文字）での一致
    4. **完全一致 / 前方一致ボーナス**: フィールド全体がトークンで始まる・一致する場合の大幅加点
    5. **フィールド重み**: `applicationName` での一致にはわずかな優先度ボーナスを付与（例：「code」検索時にタイトルに code を含むブラウザより VS Code 本体を上位にするため）
    6. **コンパクトさ調整**: 最初の一致から最後の一致までのスパンが狭いほど高スコア
  - 各トークンについて `applicationName` と `windowTitle` の両方で評価し、両方一致する場合は両方の一致範囲をハイライト対象に記録した上で高い方のスコアを採用する。
  - 全体の並び順は **`totalScore` 降順、同点時は元の MRU インデックス昇順** とする。
- **ハイライトデータ表現**:
  - `WindowSearchResult` に `matchedAppNameRanges: [Range<String.Index>]` と `matchedTitleRanges: [Range<String.Index>]` を保持させ、View 側では `AttributedString` を生成して該当範囲を `.font = .system(size: 13, weight: .bold)`（または未選択時アクセントカラー / 選択時白太字）で描画する。

### Rationale
- `String.Index` ベースの `Range` を返すことで、日本語・絵文字・合成文字（濁点分離等）を含むタイトルでもインデックスずれやクラッシュを一切起こさずに安全なハイライト描画ができる。
- 50〜200 件規模のウィンドウ一覧に対して、純粋な線形文字走査によるファジーマッチは数ミリ秒以内で完了するため、SC-002（100ms 以内）を余裕で満たす。

### Alternatives Considered
- **外部ファジー検索ライブラリ（Fuse-Swift 等）の導入**: プロジェクト憲章「依存関係の最小化（外部ライブラリ依存ゼロ）」に反するため不採用。
- **正規表現ベースの部分一致のみ**: `"vsc"` → `"Visual Studio Code"` のような略語・飛び文字検索ができないため不採用。

---

## 4. ランチャーショートカットモデル・レコーダー・双方向競合制御

### Decision
- **データモデル (`LauncherShortcutPreference`)**:
  - `keyCode: UInt16`（macOS 仮想キーコード）
  - `modifiers: ShortcutModifiers`（`OptionSet` / `Codable`：`command`, `option`, `control`, `shift`）
  - `keyLabel: String`（例：`"Space"`, `"K"`, `"⇥"` 等、レコーダー入力時の文字またはキーコード変換テーブルから生成した表示名）
  - デフォルト値：`LauncherShortcutPreference.default` = `keyCode: 49` (`Space`), `modifiers: [.option]`, `keyLabel: "Space"`（表示文字列 `"⌥ + Space"`）。
  - 永続化：`PreferencesStore` に別キー（例 `"dev.wintch.launcherShortcutPreference"`）で JSON 保存し、既存の `ShortcutPreference` 保存データとの後方互換性を完全に保つ。
- **バリデーションと双方向競合検証 (`ShortcutConflictValidator`)**:
  - Domain 層に純粋ロジックとして配置し、単体テストで 100% 検証可能にする。
  - **ランチャーショートカット単体検証**:
    - `modifiers.containsAnyPrimary`（`.command`, `.option`, `.control` のいずれか 1 つ以上）が必須。修飾キーなし、または `.shift` のみの組み合わせは無効（エラーメッセージを返却）。
  - **双方向競合判定**:
    - 通常スイッチャー `ShortcutPreference` は「順方向（`[normal.modifier]` + `normal.trigger.keyCode`）」と「逆方向（`[normal.modifier, .shift]` + `normal.trigger.keyCode`）」の 2 つを占有する。
    - `LauncherShortcutPreference` がこのどちらかと `(keyCode, modifiers)` が完全一致する場合は競合と判定する。
    - レコーダー側での変更時、および通常スイッチャー Picker 側での変更時の**双方**で `SettingsViewModel` が検証し、競合する場合は変更を保存・適用せず、エラーメッセージ（例：「通常スイッチャー（⌥ + ⇥ / ⌥ + ⇧ + ⇥）と重複するため設定できません」）を画面に表示する。
- **ショートカットレコーダー (`ShortcutRecorderView`) と `HotKeyMonitorService` の協調**:
  - `HotKeyMonitoring` に `isSuspendedForRecording: Bool` プロパティを追加する。
  - ユーザーが `SettingsView` のショートカットレコーダーをクリックして記録待機状態に入った際、`HotKeyMonitorService.isSuspendedForRecording = true` とし、`CGEventTap` が既存のショートカットを消費せずに `SettingsView` のローカル `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` へイベントを流すようにする。
  - これにより、ユーザーが確認のために現在のショートカット（例：`⌥ + Space` や `⌥ + Tab`）を押しても裏でスイッチャーが開くことなく、レコーダーが正確にキーを受け取って重複エラー検証や登録を行える。
  - 記録完了時・`Esc` キャンセル時・レコーダーがフォーカスを失った際・設定画面が閉じた際に `isSuspendedForRecording = false` へ必ず戻す。

### Rationale
- 「記録中にグローバルホットキーが発動してしまう」問題は macOS ショートカットレコーダー実装で最も多い落とし穴だが、`isSuspendedForRecording` フラグを `HotKeyMonitorService` のロック付き状態（`TapState`）に組み込むことで非同期レースなしに安全に回避できる。
- レコーダー側では `NSEvent.charactersIgnoringModifiers` と仮想キーコード静的マップ（`Tab`, `Space`, `Return`, 矢印, ファンクションキー等）を組み合わせることで、非推奨・複雑な Carbon `UCKeyTranslate` API に頼らず JIS/US 配列の主要な文字キー・記号キー・特殊キーをシンプルに表記できる。

### Alternatives Considered
- **Carbon `RegisterEventHotKey` API の併用**: `CGEventTap` と別系統の監視機構が増え、修飾キーリリース判定や記録時サスペンドとの整合が複雑化するため、既存の単一 `CGEventTap` に統一する方針とした。
- **ランチャー用も固定選択肢 Picker にする**: ユーザーが任意のキーを直感的に記録できる仕様要件（FR-015）を満たすため、ショートカットレコーダーを採用した。

---

## 5. モード共存・状態遷移設計 (`SwitcherViewModel` & `HotKeyMonitorService`)

### Decision
- スイッチャーの表示モードを `SwitcherMode` 列挙型（`.inactive`, `.normal`, `.launcher`）として明確化する（または `isPresented: Bool` + `mode: SwitcherPresentationMode`）。
- `HotKeyMonitorService` の `TapState` でも現在のモード（`.inactive`, `.normal`, `.launcher`）を同期保持する：
  - `.inactive` 時：通常スイッチャーショートカット（順・逆）→ `.triggerPressed(isShiftPressed:)`、ランチャーショートカット → `.launcherTriggerPressed` を通知し消費。
  - `.normal` 時：従来通り `triggerPressed`、`modifierReleased`、`escapePressed`、`arrowPressed` のみ処理。**ランチャーショートカットは無視**（何も通知しない / パスまたは消費なし）。
  - `.launcher` 時：ランチャーショートカットの再押下を検知して `.launcherTriggerPressed` を通知（トグル終了用）し消費するとともに、通常スイッチャーショートカット（順・逆）も `.triggerPressed(isShiftPressed:)` として通知・消費し、モードを切り替えずランチャー内の候補移動に利用する（※ `004-launcher-switcher-nav` にて改定）。**`modifierReleased`・`Esc`・`↑`/`↓` は `CGEventTap` では横取りしない**（`Esc`・`↑`・`↓` はパネル内のテキストフィールド／レスポンダーが IME 優先で処理する）。

### Rationale
- 「通常モードは押しっぱなし確定・グローバルキー横取り」「ランチャーモードはトグル式・パネル内テキスト入力＋IME優先」という異なる2つの入力ライフサイクルが、単一の状態変数によってクリーンに分離され、一方の表示中に他方へ誤遷移するバグ（FR-004）を防止できる。
