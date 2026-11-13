# データモデル設計 (Data Model): Wintch MVP

**Feature**: `001-window-switcher-mvp`  
**Created**: 2026-11-13  
**Related Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/001-window-switcher-mvp/spec.md)

本ドキュメントは、Wintch MVP におけるデータエンティティ、値オブジェクト、バリデーションルール、およびスイッチャー操作の状態遷移モデルを定義します。OS低レイヤー型（`AXUIElement`、`CGEvent` 等）は `Services/` 層内にカプセル化し、ドメインモデルおよび ViewModel からは純粋なデータ型として扱える構造を採用します。

---

## 1. ドメインエンティティおよび値オブジェクト

### 1.1 `ShortcutPreference`（ショートカット設定）
ユーザーが設定画面からカスタマイズし、永続化される起動・操作ショートカットの構成。

| フィールド | 型 | 説明 | デフォルト値 / バリデーション |
|---|---|---|---|
| `modifier` | `ModifierKeyOption` | 保持する修飾キー | `.option`（`Option` / `Control` / `Command` のいずれか必須） |
| `trigger` | `TriggerKeyOption` | 選択送りを行うトリガーキー | `.tab`（定義済みサポートキーのいずれか必須） |

#### `ModifierKeyOption`（修飾キー選択肢）
- `.option`（表示名: `Option (⌥)`）
- `.control`（表示名: `Control (⌃)`）
- `.command`（表示名: `Command (⌘)`）

#### `TriggerKeyOption`（トリガーキー選択肢）
- `.tab`（表示名: `Tab (⇥)` / macOS仮想キーコード: `48`）
- `.space`（表示名: `Space` / macOS仮想キーコード: `49`）
- `.grave`（表示名: `` ` (バッククォート) `` / macOS仮想キーコード: `50`）
- `.backslash`（表示名: `\ (バックスラッシュ)` / macOS仮想キーコード: `42`）

**バリデーションルール**:
- 修飾キーなし（単体キー）での登録は禁止する。
- `Command + Tab` が選択された場合、macOS標準アプリスイッチャーと競合するため、設定画面上に「macOS標準の Command+Tab を上書きします」等の注意ラベルを表示する（設定自体は許可する）。

---

### 1.2 `RawWindowCandidate`（ウィンドウ候補メタデータ）
`Services/` 層が `CGWindowListCopyWindowInfo` および `AXUIElement` から収集し、純粋なフィルタリング／ソートロジックへ引き渡すための値型。

| フィールド | 型 | 説明 |
|---|---|---|
| `id` | `String` | 一意の内部識別子（`axHandleHash` または `cgWindowID` ベース） |
| `cgWindowID` | `UInt32?` | CoreGraphics が付与するウィンドウID |
| `pid` | `Int32` | 所有アプリケーションのプロセスID |
| `bundleIdentifier` | `String?` | 所有アプリの Bundle ID（例: `com.apple.Safari`） |
| `applicationName` | `String` | アプリケーション表示名 |
| `title` | `String?` | `AXUIElement` 等から取得またはキャッシュされたウィンドウタイトル |
| `layer` | `Int` | ウィンドウのレイヤー番号（通常ウィンドウは `0`） |
| `bounds` | `CGRect` | ウィンドウの位置およびサイズ |
| `alpha` | `Double` | ウィンドウの不透明度（`0.0` 〜 `1.0`） |
| `isRegularApplication` | `Bool` | 通常アプリ（`activationPolicy == .regular`）であるか |
| `isSelf` | `Bool` | Wintch 自身のウィンドウであるか |
| `isMinimized` | `Bool` | 最小化状態であるか |
| `axSubrole` | `String?` | Accessibility サブロール（例: `AXStandardWindow`, `AXDialog`） |
| `lastActivatedAt` | `Date?` | アプリが記録した直近のアクティブ日時（MRU基準） |
| `zOrderIndex` | `Int` | システム上の現在のウィンドウ重なり順（0が最前面） |

**ノイズ除外（フィルタリング）ルール**:
以下の条件を **すべて** 満たす候補のみを `WindowEntry` として採用する。
1. `isSelf == false`（Wintch 自身のパネル・設定画面を除外）
2. `isRegularApplication == true`（メニューバー専用常駐ユーティリティやバックグラウンドデーモンを除外）
3. `layer == 0`（メニューバー、Dock、通知センター、壁紙、オーバーレイ等のシステムUIを除外）
4. `alpha > 0.0`（不可視の透明補助ウィンドウを除外）
5. `bounds.width >= 50 && bounds.height >= 50`（1x1ピクセルのダミーウィンドウや極小の隠しトラッキングウィンドウを除外）
6. `axSubrole` が存在する場合、標準ウィンドウ系（`AXStandardWindow` または `AXDialog` 等）であること（ツールチップやポップオーバーを除外）

---

### 1.3 `WindowEntry`（スイッチャー表示用ウィンドウ項目）
フィルタリングとソートを通過し、スイッチャーUIに表示される確定エンティティ。

| フィールド | 型 | 説明 |
|---|---|---|
| `id` | `String` | `WindowEntry` の安定識別子 |
| `cgWindowID` | `UInt32?` | CoreGraphics ウィンドウID |
| `pid` | `Int32` | 所有プロセスの PID |
| `applicationName` | `String` | リストに表示するアプリケーション名 |
| `windowTitle` | `String` | リストに表示するウィンドウタイトル（空文字の場合はフォールバック文字またはアプリ名を表示用に補助） |
| `isMinimized` | `Bool` | 最小化状態かどうか |
| `lastActivatedAt` | `Date?` | MRU 並び替えに使用した直近アクティブ日時 |
| `zOrderIndex` | `Int` | システムの重なり順（MRU未記録時のフォールバック順序） |

**ソート（MRU）ルール**:
1. `lastActivatedAt` が記録されている項目を優先し、日時の新しい順（降順）に並べる。
2. `lastActivatedAt` が未記録（アプリ起動直後など）または同一の項目同士は、`zOrderIndex` の昇順（現在画面上で手前にある順）に並べる。

---

### 1.4 `AccessibilityPermissionStatus`（権限状態）
アクセシビリティ権限の現在の許可状態を表す列挙型。

- `.granted`: 許可済み（全機能利用可能）
- `.denied`: 未許可（誘導画面を表示し、グローバル監視やウィンドウ操作を停止）

---

### 1.5 `AppPreferences`（アプリ設定状態）
設定画面で扱う基本設定の集約モデル。

| フィールド | 型 | 説明 |
|---|---|---|
| `shortcut` | `ShortcutPreference` | 永続化された起動ショートカット設定（`UserDefaults`） |
| `launchAtLogin` | `Bool` | ログイン時自動起動状態（OS `SMAppService.mainApp.status` と同期） |

---

## 2. スイッチャー操作のステートマシン（状態遷移）

```text
                [初期状態 / 待機中: .idle]
                   ▲               │
   修飾キー解放(確定) │               │ 起動ショートカット押下
   または Esc(取消) │               │ (かつ 有効ウィンドウ数 >= 1)
   または 外部クリック│               ▼
                [表示・選択中: .active(items, selectedIndex)]
                   │               ▲
                   └───────────────┘
                   トリガーキー押下 (次へ: +1 mod N)
                   Shift+トリガー (前へ: -1 mod N)
                   上下矢印キー    (+1 / -1 mod N)
```

### 状態遷移の厳密なルール
1. **起動時初期インデックス算出**:
   - 有効ウィンドウが `0` 件の場合: `.idle` のまま（パネルを表示しない）。
   - 有効ウィンドウが `1` 件の場合: `.active(items, selectedIndex: 0)`。
   - 有効ウィンドウが `2` 件以上の場合: `.active(items, selectedIndex: 1)`（直前に使っていたウィンドウを選択状態にする）。
2. **選択移動（Wrap-Around）**:
   - 次移動: `(selectedIndex + 1) % items.count`
   - 前移動: `(selectedIndex - 1 + items.count) % items.count`
3. **確定・キャンセル**:
   - **確定（修飾キー解放 / リスト項目クリック）**: パネルを閉じて `.idle` へ戻し、`selectedIndex` の `WindowEntry` に対するウィンドウアクティブ化を `WindowService` に要求する。
   - **キャンセル（`Esc` キー / パネル外フォーカス喪失）**: ウィンドウ切り替えを行わずにパネルを閉じて `.idle` へ戻す。
4. **権限剥奪時のフォールバック**:
   - 起動時・ショートカット発火時に `AccessibilityPermissionStatus == .denied` を検知した場合、`.idle` を維持し権限誘導画面を前面表示する。
