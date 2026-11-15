# AGENTS.md — Wintch プロジェクト開発ガイド

このドキュメントは、**Wintch** リポジトリで作業する AI エージェントおよび開発者向けのプロジェクト概要・必須開発プロセス・アーキテクチャ規約を定義します。

---

## 1. 最優先ルール：Spec Kit による仕様駆動開発（SDD）

**このリポジトリでは、いきなりコードの実装・修正を行ってはなりません（MUST NOT）。**
新機能の追加、挙動の変更、UI/UX の拡張を行う場合は、必ず実装前に **Spec Kit（`.agents/skills/speckit-*`）** を用いて仕様書および設計成果物を作成してから実装へ進んでください。

### 必須ワークフロー

1. **憲章の確認**
   - 作業前に [`.specify/memory/constitution.md`](.specify/memory/constitution.md) を確認し、5つの基本原則（最小権限・シンプルさ・ゼロレイテンシ・外部依存ゼロ・非公開 API 禁止）に反しないことを確認する。
2. **仕様書の作成（`speckit-specify`）**
   - `speckit-specify` スキル（および必要に応じて `speckit-git-feature`）を実行し、`specs/<NNN>-<feature-name>/spec.md` を作成する。
   - ユーザーストーリー、受入シナリオ、エッジケース、機能要件（FR）、成功基準（SC）を明文化する。
3. **仕様の明確化（`speckit-clarify`）**
   - 仕様に曖昧な点や設計上の分岐がある場合は、実装推測を行わず `speckit-clarify` で要件を確定させる。
4. **実装計画・タスク分解（`speckit-plan` / `speckit-tasks`）**
   - `speckit-plan` で技術設計（`plan.md` 等）を作成し、`speckit-tasks` で依存関係付きの `tasks.md` へ分解する。
   - 必要に応じて `speckit-analyze`・`speckit-checklist` で成果物間の整合性を検証する。
5. **実装と検証（`speckit-implement` / `speckit-converge`）**
   - 承認・確定した計画および `tasks.md` に沿って実装・ユニットテスト作成を行い、テストとビルドが通ることを確認する。

### 例外と運用ルール
- 明確な単純バグ修正や誤字修正、質問への調査回答のみを行う場合を除き、「機能追加や仕様変更を伴う作業」では必ず `speckit-specify` から開始してください。
- Git ブランチ運用およびコミット規約は [`.specify/extensions/git/git-config.yml`](.specify/extensions/git/git-config.yml) に従います（`sequential` 連番ブランチ、`conventional` コミットスタイル）。

---

## 2. プロジェクト概要

**Wintch**（Window + Switch）は、macOS 14.0 (Sonoma) 以降向けに設計された、軽量・最小権限の**ウィンドウ単位スイッチャー＆ランチャー**アプリケーションです。

### 主な機能
- **通常ウィンドウスイッチャー（デフォルト `Option + Tab`）**
  - 操作スペース（仮想デスクトップ）を横断して通常ウィンドウを一覧表示し、直近アクティブ順（MRU）および Z オーダーで切り替え可能。
  - 修飾キー保持中にトリガーキー（`Shift` 併用で逆順）や矢印キーで移動し、修飾キー解放で確定、`Esc` でキャンセル。
- **検索ランチャーモード（デフォルト `Option + Space`）**
  - トグル式で検索入力欄付きパネルを表示し、アプリ名・ウィンドウタイトルを対象にスペース区切り AND のファジー検索・ハイライト表示を実施。
  - 検索で一致する既存ウィンドウが 0 件の場合、インストール済みアプリケーションを新規起動候補として表示・起動可能。
- **ウィンドウ／アプリ終了操作**
  - スイッチャーまたはランチャー上で選択中のウィンドウを閉じる（同アプリ最後の 1 枚ならアプリを通常終了する）操作をサポート。
- **メニューバー常駐・設定 UI**
  - Dock アイコンを持たない常駐アプリ（`LSUIElement`）として動作し、設定画面（ショートカットカスタマイズ・競合防止・ログイン時自動起動）、権限誘導画面、「Wintchについて」画面を提供。

---

## 3. ディレクトリ構成とアーキテクチャ

Swift Package Manager（`Package.swift`, Swift 6.0, macOS 14.0+）で構成され、**MVVM + Services** アーキテクチャを採用しています。

```text
.
├── Package.swift                        # SwiftPM 定義（外部依存なし）
├── VERSION                              # アプリバージョン（SemVer 一元管理）
├── Resources/                           # Info.plist・アイコン原画 (SVG)
├── Sources/
│   ├── Wintch/
│   │   └── WintchApp.swift              # エントリポイント・MenuBarExtra
│   └── WintchCore/
│       ├── App/                         # AppCoordinator（DI・ウィンドウ/権限統括）
│       ├── Domain/                      # 純粋ビジネスロジック・ドメインモデル（OS API 非依存）
│       ├── Services/                    # macOS API 隔離層（AX / CGWindow / CGEventTap / NSWorkspace 等）
│       │   └── Protocols/               # テスト用モック差し替えのためのサービスプロトコル群
│       ├── ViewModels/                  # @Observable / @MainActor 状態管理
│       └── Views/                       # SwiftUI ビューおよび必要最小限の AppKit ラッパー (NSPanel 等)
├── Tests/
│   └── WintchCoreTests/                 # Swift Testing ユニットテストおよび Mocks/
├── scripts/
│   └── build-app.sh                     # .app バンドル組み立て・アイコン生成・アドホック署名
├── specs/                               # Spec Kit による機能仕様書・計画・タスク一覧
└── .specify/                            # Spec Kit 憲章・テンプレート・設定
```

### アーキテクチャ上の厳守事項
- **最上位方針**: [`.specify/memory/constitution.md`](.specify/memory/constitution.md) を遵守すること。
  - `ScreenCaptureKit` などの画面収録権限・サムネイル取得は一切使用しない。
  - 外部ライブラリ（サードパーティ SPM パッケージ）を追加せず、Apple 標準フレームワークのみを使用する。
  - `CGS*` 等の非公開 API は一切使用しない。
- **低レイヤー API の隔離**: `CGWindowListCopyWindowInfo`、`AXUIElement`、`AXObserver`、`CGEventTap`、`NSWorkspace` などの OS 依存処理は `Sources/WintchCore/Services/` に隔離し、`Views/` や `ViewModels/` から直接呼び出さない。
- **状態管理**: `@Observable` マクロおよび `@MainActor` を使用する（レガシーな `ObservableObject` / `@Published` は使用しない）。
- **テスト可能性**: フィルタリング・ソート・ファジー検索・選択位置計算・ショートカット検証などのビジネスロジックは `Domain/` に純粋関数・値型として切り出し、ユニットテスト可能にする。

---

## 4. コーディング・ドキュメント規約

- **完全日本語化**:
  - チャット応答、仕様書（`spec.md` 等）、設計書（`plan.md` 等）、タスクリスト（`tasks.md` 等）はすべて **日本語** で記述する。
  - コード内のすべてのコメント（インライン・ブロック）は **日本語** で記述する（英語コメントは禁止）。
  - すべてのクラス・構造体・列挙型・関数・メソッドには、標準形式（SwiftDoc `///`、`- Parameter`、`- Returns:`）で **日本語** のドキュメントコメントを記載する。
- **Swift 6.0 並行性（Strict Concurrency）**:
  - データ競合を防ぐため、`@MainActor` と `Sendable` 境界（バックグラウンド探索・AX IPC ワーカーキュー等）を明確に分離する。
- **コード品質**:
  - ロジックの重複（検索アルゴリズムや UI スタイルなど）を避け、共通ヘルパーへ抽出する。
  - 過度な抽象化や複雑な独自ジェネリクス・自作マクロは避け、明快で保守しやすい Swift コードを書く。

---

## 5. ビルド・テスト手順

### ユニットテスト（Swift Testing）
```bash
swift test
```
> **注意**: システムの `xcode-select` が Command Line Tools を指している環境で `TestingMacros` 関連のビルドエラーが発生する場合は、Xcode の Developer ディレクトリを指定して実行してください。
> ```bash
> DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
> ```

### `.app` バンドルのビルドと起動
```bash
# Debug ビルド (.build/Wintch.app を生成)
./scripts/build-app.sh

# Release ビルド / Universal Binary ビルド
./scripts/build-app.sh release
./scripts/build-app.sh release --universal

# アプリ起動
open .build/Wintch.app
```
- リリース自動化は [`.github/workflows/release.yml`](.github/workflows/release.yml) と [`VERSION`](VERSION) で管理されています。
- ローカルのアドホック署名で再ビルドした際、macOS の `cdhash` 識別によりアクセシビリティ権限の再登録（「システム設定 ＞ プライバシーとセキュリティ ＞ アクセシビリティ」から一度削除して追加し直す）が必要になる場合があります。
