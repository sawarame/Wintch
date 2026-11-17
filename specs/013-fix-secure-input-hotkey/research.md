# Phase 0 調査・技術設計判断レポート (Research): セキュア入力フォーカス中のショートカット起動と安定復帰

**Feature**: `013-fix-secure-input-hotkey` | **Date**: 2026-11-17

## 1. 問題の技術的根本原因

### 1.1 主原因：macOS Secure Event Input による `CGEventTap` の遮断
- `HotKeyMonitorService`（`Sources/WintchCore/Services/HotKeyMonitorService.swift`）は、`CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, ...)` による単一の `CGEventTap` で `keyDown` と `flagsChanged` を監視している。
- Chrome / Microsoft Edge 等のブラウザで `<input type="password">` 等のパスワード入力フォームにフォーカスすると、OS の **Secure Event Input**（`EnableSecureEventInput()`）が有効化される（`IsSecureEventInputEnabled() == true`）。
- macOS のキーロガー保護仕様により、Secure Event Input 有効中は他プロセスが作成した `CGEventTap` へキーボードイベント（`keyDown` / `flagsChanged`）が一切配送されなくなる。そのため、`HotKeyMonitorService.handleCGEvent` が呼ばれず、`Option + Tab` や `Option + Space` が無反応になる。

### 1.2 「稀にしばらく使えなくなる」症状の要因
1. **ブラウザ側での `DisableSecureEventInput()` 解除遅延・残留**:
   - Chromium 系ブラウザのフォーカス遷移・タブ切替・自動入力ポップアップ・パスワード表示トグル等のタイミングにより、パスワード欄からフォーカスを外した後も `kCGSSessionSecureInputPID` がブラウザの PID を保持したまま一時的に解除されない現象が発生する。この間は引き続き `CGEventTap` が遮断される。
2. **`CGEventTap` タイムアウトクールダウン中の無反応期間**:
   - `HotKeyMonitorService` の `TapTimeoutRecoveryTracker` は 10 秒間に 3 回を超えて `.tapDisabledByTimeout` が発生すると 5 秒間のクールダウン（`reenableAfterCooldown(seconds: 5.0)`）に入る。この待機中も `CGEventTap` は停止状態となりショートカットが通らない。

---

## 2. 技術選定と設計判断

### 2.1 グローバル起動検知の 2 系統ハイブリッド化（`CGEventTap` + Carbon `RegisterEventHotKey`）
- **Decision**: 通常時は既存の `CGEventTap` を主経路として維持しつつ、Carbon（`HIToolbox`）の `RegisterEventHotKey` を代替起動経路として常時併用する。
- **Rationale**:
  - `RegisterEventHotKey` は Apple 標準の公開フレームワーク（`import Carbon`）であり、憲章の「外部依存ゼロ」「非公開 API 禁止」に適合する（`swift -e 'import Carbon; print(IsSecureEventInputEnabled())'` にて macOS 14+ / Swift 6 SDK で追加設定なしに利用可能であることを確認済み）。
  - `RegisterEventHotKey` は **`IsSecureEventInputEnabled() == true` の状態でも OS から `kEventHotKeyPressed` 通知を受信できる**（`Option + Tab`、`Option + Shift + Tab`、`Option + Space` 等の通常キー＋修飾キー組み合わせ）。
  - また、`CGEventTap` が 5 秒クールダウン等で一時停止している間も `RegisterEventHotKey` 側で起動を受け付けられる。
- **Alternatives considered**:
  - *代替案 1: `NSEvent.addGlobalMonitorForEvents` の併用* → グローバルモニタも Secure Event Input 中は遮断されるため解決にならない。却下。
  - *代替案 2: `CGEventTap` を全廃して `RegisterEventHotKey` のみに一本化* → `RegisterEventHotKey` は修飾キー解放（`flagsChanged`）や表示中の任意キー横取り（`Esc` / 矢印 / `Q`）を行えず、通常時の非アクティブ起動維持にも不向きなため却下。
  - *代替案 3: セキュア入力中は制限として受け入れ、起動不能のままとする* → ユーザー体験の課題（Issue #15）を根本解決できないため却下。

### 2.2 セキュア入力中の通常スイッチャー起動における「一時アクティブ化」とキャンセル時フォーカス復元
- **Decision**: Carbon 代替経路経由または `IsSecureEventInputEnabled() == true` の状態で通常スイッチャーが起動された場合のみ、`SwitcherPanel` 表示時に `NSApplication.shared.activate()` を実行し、パネルをキーウィンドウとして前面化する。`Esc` 等でキャンセル終了した際は直前にフォーカスしていたアプリへフォーカスを復元する。通常時（セキュア入力無効かつ `CGEventTap` 経路）は従来通り `.nonactivatingPanel` のまま裏アプリを非アクティブ化しない。
- **Rationale**:
  - `RegisterEventHotKey` は「押した瞬間」しか通知しないため、ブラウザが前面のままで Secure Input を保持し続けると、表示中の `Esc` キャンセル・矢印移動・`Q` ウィンドウ終了・`Option` 離し確定が `CGEventTap` に届かない。
  - 一時アクティブ化によりフォーカスを Wintch へ移せば、ブラウザ側の Secure Input が解除され、さらに Wintch 自身がアクティブなキーウィンドウとなるため、**ローカル `NSEvent` モニタ（`NSEvent.addLocalMonitorForEvents`）および `CGEventTap` の双方で `Esc`・矢印・`Q`・`Tab`・`flagsChanged` を確実に処理できる**。
  - 検索ランチャーは従来から `NSApplication.shared.activate()` と `previousFrontmostApp` 復元を実装済みであり、同じ仕組みをフラグ制御で通常スイッチャーの一時アクティブ化にも統一適用できる。
- **Alternatives considered**:
  - *非アクティブのまま修飾キーのポーリングのみ行う* → ブラウザ側が Secure Input を離さず、`Esc` キャンセル・矢印移動・`Q` 終了が効かない／ブラウザにキーが漏れる副作用があるためユーザー合意の上で不採用。

### 2.3 二重発火防止（純粋ロジック `HotKeyTriggerDeduplicator` の導入）
- **Decision**: `CGEventTap` と Carbon `RegisterEventHotKey` が同一キー押下に対して二重に発火しないよう、発生元（`.cgEventTap` / `.carbonHotKey`）と単調増加時刻（`systemUptime`）に基づく重複排除ロジックを `Domain/`（または純粋判定型）として切り出す。
- **Rationale**:
  - 通常時、`CGEventTap`（`.headInsertEventTap`）が一致イベントを消費（`return nil`）すれば通常は Carbon に流れないが、タイミングや OS バージョン差・セキュア入力解除直後の境界で両方から発火するリスクを完全に潰す必要がある。
  - `CGEventTap` 側がトリガーイベントを受理・消費した直近一定時間（例：`0.15` 秒以内）の同一種別トリガーを Carbon 側が受け取った場合は重複として破棄し、逆に Carbon 側が先に処理した直近の同一種別トリガーを `CGEventTap` 側が遅れて受け取った場合も破棄することで、**通常時・境界時の二重移動を 0% に抑える**。
  - 同一ソース（例：`CGEventTap` 連続押下や Carbon 連続押下）は連打・キーリピートとしてそのまま通すため、高速連打の操作性を阻害しない。

### 2.4 素早い修飾キー解放の取りこぼし防止（安全ガード付き修飾キー解放ウォッチドッグ）
- **Decision**: フォールバック（一時アクティブ化）で通常モードが起動されたセッション中に限り、`MainActor` 上で軽量なローカル `NSEvent` モニタ（`keyDown` / `flagsChanged`）と短い周期（例：20ms）の修飾キー解放監視ウォッチドッグを動作させる。ただし、`CGEventSource.flagsState(.combinedSessionState)` は Secure Input 有効中はゼロ化／制限される恐れがあるため、**`!IsSecureEventInputEnabled()` が確認できた時点**、または `NSApp.isActive` 成立後のローカル `NSEvent.modifierFlags` 確認によってのみ解放判定を行う。
- **Rationale**:
  - ユーザーがパスワード欄で `Option + Tab` を押した直後（Wintch の `activate()` が完了する前の 10〜30ms 以内）に `Option` を離すと、離した瞬間の `flagsChanged` が Secure Input に遮断されて取りこぼされる。
  - フォーカス移行が完了して `!IsSecureEventInputEnabled()` になった直後に `CGEventSource.flagsState(.combinedSessionState)` を確認すれば、既に離されている `Option` を即座に検知して `.modifierReleased` を発火できる。
  - 一方、`IsSecureEventInputEnabled() == true` のままの状態で `CGEventSource.flagsState` を信用すると「押しているのに離されたと誤認して即確定する」バグを起こし得るため、`!IsSecureEventInputEnabled()` ガードが必須となる。
  - `activeMode` が `.inactive` に戻った時点、または `flagsChanged` で解放検知した時点で即座にローカルモニタとウォッチドッグを停止するため、常駐時の CPU 負荷はゼロになる。

### 2.5 設定変更・ショートカット記録中・OS 予約キーとの整合
- **Decision**:
  - `updateShortcut(_:)` / `updateLauncherShortcut(_:)` 呼び出し時、および `isSuspendedForRecording` の切り替え時に、`RegisterEventHotKey` の登録（通常順方向・通常逆順 `Shift` 併用・ランチャー）を動的に登録／解除する。
  - 特に `isSuspendedForRecording == true` の間は Carbon ホットキーをすべて `UnregisterEventHotKey` で解除し、`ShortcutRecorderView` でのキー入力が Carbon に横取りされないようにする。
  - `RegisterEventHotKey` の戻り値が `noErr` 以外となった場合や、`Command + Tab` のように OS（Dock / WindowServer）が最優先で横取りするシステム予約ショートカットが設定されている場合は、エラーでクラッシュや監視停止を起こさず安全にログ記録して処理を継続する（通常時は `CGEventTap` により従来通り動作する）。

### 2.6 `HotKeyEvent`・既存テスト互換性の維持
- **Decision**: 既存の `HotKeyEvent` 列挙型（`.triggerPressed(isShiftPressed: Bool)` 等）のケースシグネチャは変更せず、`HotKeyMonitoring` プロトコルに「現在の通常モード提示でアプリ一時アクティブ化が必要か」を伝える軽量プロパティ（例：`requiresAppActivationOnPresentation`）を追加する（または `SwitcherViewModel` が `hotKeyMonitor` から参照して `shouldActivateAppForCurrentSession` を確定する）。
- **Rationale**: 既存の `SwitcherViewModelTests` および `HotKeyMonitorDecisionTests` にある多数の `.triggerPressed(isShiftPressed:)` 呼び出し・検証を壊さずに最小限のインターフェース拡張で要件を満たせる。
