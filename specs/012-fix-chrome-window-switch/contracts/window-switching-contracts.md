# 契約仕様 (Contracts): ウィンドウ照合・補助窓抑制・アクティブ化制御

**Feature**: `012-fix-chrome-window-switch` | **Date**: 2026-11-17

## 1. ドメイン純粋ロジック契約（`Domain/WindowMenuPairing.swift`）

### 1.1 `WindowMenuCandidatePairing.titlesMatch(_:_:)`
- **契約**:
  - 前後の空白・改行をトリムし、空文字同士・空文字片側は `false` を返す。
  - 完全一致時は即座に `true` を返す。
  - 省略記号（`"…"` または `"..."`）が文字列内に **1 個または複数個** 含まれる場合でも、省略記号を任意の 0 文字以上ワイルドカードとして照合し、非ワイルドカード断片の総文字数が **4 文字以上** かつ先頭・中間・末尾の順序整合が満たされる場合に `true` を返す。
  - **非破壊保証**: 元の `parts.count == 2` で成立していた単一中央省略テストケース（日本語 `…` および ASCII `...`）をすべて満たしつつ、元タイトル自体に `…` / `...` が含まれるケースを救済する。

### 1.2 `WindowMenuCandidatePairing.cgCandidatePriority(_:)`（ペアリング順位制御）
- **契約**:
  - `WindowFilter.isValid` を通過した `cg-*` 候補同士を以下の辞書順優先度で並べる（小さいほど優先）：
    1. `onScreenPriority`: 画面表示中（`isOnScreen == true`）が `0`、それ以外が `1`
    2. `layerPriority`: 通常レイヤー（`layer == 0`）が `0`、それ以外が `1`
    3. `auxiliaryShapePenalty`: 通常ウィンドウ規模の候補が `0`、オフスクリーンかつ横長扁平な補助ポップアップ形状（例: `isOnScreen != true` かつ `bounds.height < 420 && (bounds.width / bounds.height) > 3.0`）は `1`
    4. `zOrderIndex`: 同一優先度群内では従来通りシステム Z オーダー昇順
  - **非破壊保証**:
    - ほかに本物の通常サイズ CGWindow 候補が存在しない場合は、補助形状の候補でも従来通り通過する。
    - 複数の標準サイズ CGWindow 候補（`1728x1117`, `1200x800` 等）同士の順序は `zOrderIndex` 昇順のまま変化しない。

### 1.3 `WindowMenuCandidatePairing.matchingMenuItemIndex(for:in:preferUnchecked:)`
- **契約**:
  - メニュー項目配列から対象タイトルに一致するインデックスを返す純粋関数。
  - `preferUnchecked == true`（別スペース不在時の切り替え）では、以下の 4 段階で照合する：
    1. 未チェック（`!isChecked`）かつトリム後完全一致
    2. 未チェック（`!isChecked`）かつ `titlesMatch` 省略一致
    3. チェック済み含む全体からトリム後完全一致
    4. チェック済み含む全体から `titlesMatch` 省略一致
  - `preferUnchecked == false` の場合は全体から完全一致優先・省略一致次点で照合する。
  - 対象タイトルが空文字の場合は `nil` を返す。

## 2. サービス層ロジック契約（`Services/WindowService.swift`）

### 2.1 `WindowService.shouldEvictCachedWindowAsReplacedTab(...)`
- **契約**:
  - 同一 PID のキャッシュ済みウィンドウ候補を「タブ切り替えにより消えた旧タブ」として削除してよいかを判定する。
  - 以下のすべてを満たす場合のみ `true` を返す：
    1. `allowDisplaySpanningReplacement == true`（同一スペース内 AX 通知由来かつスペース変更保留中でない）
    2. `isReplacedTabBounds(...) == true`（同一最小化状態かつ `areBoundsNearlyEqual`）
    3. 旧候補の `cgWindowID` が、現在のシステム `CGWindowList` 内に「置換先ウィンドウが照合した CGWindow とは別の独立 CGWindow」として生存していないこと（`activeSurvivingCGWindowIDs` に含まれない、または未設定）
  - **非破壊保証**: `scanAllRegularApps()`（スイッチャー起動直前）やスペース変更直後は `allowDisplaySpanningReplacement == false` であるため、別スペースの同矩形通常ウィンドウが誤削除されることはない。

### 2.2 `WindowService.isMenuCacheFresh(fetchedAt:now:ttl:)`
- **契約**:
  - `now.timeIntervalSince(fetchedAt) <= ttl`（通常 `windowMenuCacheTTL = 2.0` 秒、かつ `>= 0`）のときのみ `true`。
  - 期限切れキャッシュの `AXUIElement` を確定操作でそのまま使わないことを保証する。

### 2.3 `WindowService.activateWindow(_:)`
- **契約**:
  - 前回の未完了フォローアップタスクが存在する場合は即座にキャンセルする。
  - `needsMenuNavigation == true` かつメニュー項目による `kAXPressAction` が `.success` の場合、同期的に `app.activate(options: [])` を並走させない。
  - キャッシュ済みメニュー項目の `kAXPressAction` が `.success` 以外を返した場合は、対象 PID のメニューキャッシュを破棄して最新メニューを再取得し、一致項目が見つかれば 1 回だけリトライする。
  - フォローアップタスクでは、対象ウィンドウが現在スペースの AX スナップショットで解決されるまで段階的に確認し、解決した時点（またはタイムアウト時）にアプリが未アクティブであれば `app.activate(options: [])` を実行し、解決済みウィンドウに対して `raiseAXWindow` および MRU 時刻更新を行う。解決できなかった場合は曖昧な別ウィンドウへの `raiseAXWindow` は行わない。
