# 実装計画 (Implementation Plan): 複数ウィンドウを持つブラウザ（Chrome 等）の正確な切り替えと一覧・キャプチャ整合性の確保

**Branch**: `012-fix-chrome-window-switch` | **Date**: 2026-11-17 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/012-fix-chrome-window-switch/spec.md)

**Input**: Feature specification from `/specs/012-fix-chrome-window-switch/spec.md`

## Summary

Google Chrome 等で複数ウィンドウを開いている際、「キャプチャが取れない状態になる」「選択しても別の Chrome ウィンドウに移動してしまう」という不具合（GitHub Issue #13）を修正する。

調査（[research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/012-fix-chrome-window-switch/research.md)）により、本不具合は以下の 4 つの複合要因による連鎖であることが判明しているため、ドメイン層・サービス層の双方で一貫した対策を実施する：
1. **補助 CGWindow へのタイトル誤割り当て防止（`Domain/WindowMenuPairing.swift`）**: `cgCandidatePriority` でオフスクリーンの横長扁平ポップアップ（オムニボックス予測変換等 `1344x378` 相当）を通常実ウィンドウより劣後に配置し、実ウィンドウがタイトルを奪われてキャプチャ不能になる現象を防ぐ。
2. **別スペース同矩形ウィンドウの誤削除防止（`Services/WindowService.swift`）**: `applyAXWindowSnapshots` での旧タブ除去判定において、全体再スキャン／スペース移動時（`allowDisplaySpanningReplacement == false`）の削除を抑止し、さらに生存中の独立 `CGWindowID` を持つキャッシュ候補は同矩形であっても削除しないことで、別スペースの通常サイズウィンドウが `cg-*` へ降格するのを防ぐ。
3. **メニュー照合の堅牢化と鮮度保証（`Domain/WindowMenuPairing.swift`, `Services/WindowService.swift`）**: `titlesMatch` をタイトル自体に `…` / `...` を含む多重省略に対応させ、別スペース遷移時は未チェック項目優先の `matchingMenuItemIndex` を導入する。さらに `resolveWindowMenuItemElement` に `windowMenuCacheTTL` チェックと `kAXPressAction` 失敗時のキャッシュ破棄リトライを追加する。
4. **メニュー遷移と `app.activate()` の競合解消（`Services/WindowService.swift`）**: 別スペース遷移でメニュー押下が成功した場合は同期的な `app.activate(options: [])` を直後に競合実行せず、前回のフォローアップタスクをキャンセルした上で段階ポーリングにより対象ウィンドウの出現・スペース遷移を確認してから未アクティブ時のみ前面化および `raiseAXWindow` を確定する。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`, Strict Concurrency 準拠）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`Foundation` / `AppKit` / `ApplicationServices` / `CoreGraphics` / `ScreenCaptureKit`）。外部サードパーティ依存ゼロ。  
**Storage**: N/A（新規の永続化データや設定項目なし。既存のメモリ内キャッシュ制御のみ改善）  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`WintchCore` + `Wintch` 構成）  
**Performance Goals**: スイッチャー／ランチャー表示（`fetchRawWindowCandidates`）に対する追加 IPC・同期待機ゼロ（体感遅延 0ms 維持）。確定時のメニュー鮮度再確認も TTL 内キャッシュ＋必要時のみの単発再取得にとどめる。  
**Constraints**:
- リスト型スイッチャーおよび検索ランチャーでの画面収録権限不使用の原則を維持する。
- 非公開 API（`CGS*` 等）は一切使用しない。
- コード内コメントおよびドキュメントコメント（`///`）はすべて日本語で記述する。
- 既存の `WindowFilter` / `WindowMenuPairing` / `WindowCaptureAndMatchingTests` の既存挙動を壊さないこと。

**Scale/Scope**: `Domain/WindowMenuPairing.swift` と `Services/WindowService.swift` の 2 ファイルを中心としたピンポイント修正と、対応するユニットテスト（`WindowMenuPairingTests.swift`, `WindowCaptureAndMatchingTests.swift`）の拡充。

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限およびオプトインの原則（Privacy by Design）** | 画面収録権限の追加要求・利用拡張は一切行わず、AX 情報・CGWindow メタデータ・メニュー項目のみで完結する | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | UI や設定項目を増やさず、既存の切り替え・一覧整合性の正確性のみを修正する | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | 一覧取得経路に追加の同期待機を入れず、段階ポーリングもウィンドウ確定後の非同期フォローアップのみに限定する | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | Apple 標準フレームワークのみを使用（外部依存追加なし） | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。メニュー項目解決失敗時は `app.activate()` へ安全にフォールバックし、曖昧な別ウィンドウへの強制フォーカスは行わない | PASS |
| **6. 技術スタック・MVVM + Services** | 純粋判定ロジック（タイトル省略照合・CGWindow 優先順位・メニュー選択ルール）を `Domain/` へ配置し、OS API 制御を `Services/WindowService.swift` に隔離する | PASS |
| **7. 可読性・テスト可能性・ライセンス** | 値型・純粋関数中心の明快な設計とし、新規・変更ロジックすべてに日本語ドキュメントコメントと Swift Testing ユニットテストを整備する | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/012-fix-chrome-window-switch/
├── spec.md                                   # 機能仕様書
├── plan.md                                   # 本実装計画書
├── research.md                               # Phase 0 原因調査・実機確認・設計判断レポート
├── data-model.md                             # Phase 1 状態モデル・キャッシュ鮮度・遷移設計
├── quickstart.md                             # Phase 1 ビルド・自動テスト・実機検証ガイド
├── contracts/
│   └── window-switching-contracts.md         # Phase 1 ドメイン・サービス契約仕様
└── checklists/
    └── requirements.md                       # 仕様品質チェックリスト
```

### Source Code (repository root)

既存の `WintchCore` + `Wintch` 構造を維持し、以下のファイルのみを更新する。

```text
Sources/WintchCore/
├── Domain/
│   └── WindowMenuPairing.swift               # [更新] 多重省略記号対応・補助窓劣後優先順位・未チェック優先メニュー選択ヘルパー追加
└── Services/
    └── WindowService.swift                   # [更新] 生存 CGWindow を考慮した旧タブ誤削除防止、メニューキャッシュ鮮度/リトライ、非競合アクティブ化＆段階フォローアップ

Tests/WintchCoreTests/
├── WindowMenuPairingTests.swift              # [更新] オムニボックス補助窓優先順位、多重省略、未チェック優先選択のテスト追加
└── WindowCaptureAndMatchingTests.swift       # [更新] 別スペース同矩形保護、メニューキャッシュ鮮度判定、アクティブ化計画のテスト追加
```

**Structure Decision**:
- ビジネスロジック上の純粋判定（文字列照合、ペアリング優先順位、メニュー候補選択、旧タブ置換条件判定、アクティブ化プラン計算）はすべて `nonisolated static` または `Domain/` 純粋関数として実装し、実機プロセスや WindowServer に依存せず高速かつ確実に Swift Testing で単体検証できるようにする。
- `WindowCaptureService.swift`・`WindowFilter.swift`・`ViewModels/`・`Views/` は今回の課題において責務上の問題がない（`WindowService` と `WindowMenuPairing` 側が正しい実ウィンドウを渡し確実にアクティブ化すれば解消する）ため変更対象を最小限にとどめる。

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
