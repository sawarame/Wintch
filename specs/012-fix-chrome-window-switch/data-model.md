# データモデル設計: 複数ウィンドウ切り替え・キャッシュ整合性制御

**Feature**: `012-fix-chrome-window-switch` | **Date**: 2026-11-17

## 1. 既存データモデルの役割と拡張ポイント

本修正では永続化ストアや UI 向けモデル（`WindowEntry` / `RawWindowCandidate`）の公開プロパティ破壊を行わず、内部制御用の純粋構造体・キャッシュ状態の扱いを厳密化する。

### 1.1 `WindowMenuItemSnapshot`（既存: `Domain/WindowMenuPairing.swift`）
- **属性**: `title: String`, `identifier: String?`, `mark: String?`, `hasCommandKey: Bool`, `hasSubmenu: Bool`, `isEnabled: Bool`, `index: Int`, `isChecked: Bool`
- **利用拡張**:
  - 確定操作時のメニュー項目照合において、`preferUnchecked: Bool`（別スペース不在時の切り替えかどうか）に応じて、`isChecked == false` の項目を第 1 優先、見つからない場合に全項目を対象とする純粋選択ルールを適用する。

### 1.2 `CachedWindowMenuState`（既存: `Services/WindowService.swift`）
- **属性**: `items: [ScannedWindowMenuItem]`, `fetchedAt: Date`
- **鮮度ルール（新規明確化）**:
  - `enrichCandidatesWithWindowMenu` だけでなく、`resolveWindowMenuItemElement` でも `Date().timeIntervalSince(fetchedAt) <= WindowService.windowMenuCacheTTL`（2.0 秒）を検証する。
  - TTL 超過時、またはキャッシュ由来の `AXUIElement` に対する `kAXPressAction` 実行が `.success` 以外を返した場合は、該当 PID のメニューキャッシュを無効化して即座に最新メニューを再取得する。

### 1.3 `CachedAXWindow` と生存 CGWindow 照合コンテキスト（`Services/WindowService.swift`）
- **属性**: `id`, `pid`, `axElement`, `cgWindowID: UInt32?`, `bounds: CGRect?`, `isMinimized: Bool`, `isPresentInLatestAXScan: Bool`, `lastActivatedAt: Date?`
- **置換削除の安全条件**:
  - `applyAXWindowSnapshots` での同矩形旧タブ削除判定において、単に `isDisplaySpanningBounds` かどうかだけでなく、以下の両方を確認する：
    1. `allowDisplaySpanningReplacement == true`（同一スペース上の AX イベント通知由来かつスペース移動中ではない）であること。
    2. 旧キャッシュ要素に紐づいていた `cgWindowID` が、現在システム上に「新ウィンドウとは別の独立 CGWindow」として生存していないこと（別スペースで生きている同矩形ウィンドウを誤削除しない）。

### 1.4 `ActivationPlan`（新規純粋値型・`Services/WindowService.swift` 内テスト可能モデル）
`activateWindow(_ entry: WindowEntry)` 実行時の挙動分岐を明快かつユニットテスト可能にするための内部状態モデル。

| 状態ケース | 条件 | 即時実行アクション | フォローアップ処理 |
|---|---|---|---|
| **同スペース即時前面化** | `hasCachedAX && isPresentInCurrentSpace` | `raiseAXWindow` + `app.activate`（必要なら最小化解除） | 80ms 後に MRU / 状態同期確認（必要時のみ） |
| **メニュー経由別スペース遷移（成功）** | `needsMenuNavigation && menuPressSucceeded` | メニュー項目の `kAXPressAction` のみ実行（`app.activate` を同期併走させない） | 段階ポーリング（例: 60ms, 140ms, 280ms, 450ms）で対象ウィンドウの現在スペース出現を検知し、未アクティブなら `app.activate` + `raiseAXWindow` + MRU 更新 |
| **メニューフォールバック遷移** | `needsMenuNavigation && !menuPressSucceeded` | `app.activate` +（`targetAX` があれば）`raiseAXWindow` | 段階ポーリングで対象タイトルの再解決・`raiseAXWindow` 試行 |

## 2. 状態遷移（連続切り替え時のキャンセル制御）

```text
[待機中]
  │ activateWindow(A)
  ▼
[A 用 pendingActivationFollowUpTask 起動]
  │
  ├─ 途中で activateWindow(B) が発生 ──▶ A 用タスクを cancel() ──▶ [B 用タスク起動]
  │
  ├─ ポーリングで対象ウィンドウが現在スペースに捕捉された
  │     └──▶ 未アクティブなら app.activate() + raiseAXWindow(resolved) + MRU 更新 ──▶ [完了]
  │
  └─ 最大試行回数到達（未解決）
        └──▶ 未アクティブなら app.activate()（別ウィンドウ誤選択防止のため曖昧な raiseAXWindow は行わない） ──▶ [完了]
```
