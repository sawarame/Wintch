# 実装計画 (Implementation Plan): セマンティックバージョニング導入・自動タグリリース・「Wintchについて」メニュー

**Branch**: `003-semver-release-about` | **Date**: 2026-11-14 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/003-semver-release-about/spec.md)

**Input**: Feature specification from `/specs/003-semver-release-about/spec.md`

## Summary

リポジトリルートに単一のバージョンファイル `VERSION`（初期値 `0.1.0`、SemVer 準拠・プレリリース許容）を導入し、ビルドスクリプト `scripts/build-app.sh` がバンドル出力先 `.build/Wintch.app/Contents/Info.plist` へ表示バージョンと Git コミット数ベースのビルド番号を動的に反映する。また、`.github/workflows/release.yml` によって `main` ブランチへの `VERSION` 更新の反映時にテスト実行・自動タグ作成（`v<VERSION>`）・Universal Binary（`arm64` + `x86_64`）ビルド・`ditto -c -k --keepParent` による `Wintch-v<VERSION>.zip` 生成・GitHub Release 公開までを一貫自動化する（手動 `v*` タグ push およびリリース公開イベントにも対応）。さらに、アプリ内に `AppVersionInfo` ドメインモデルと SwiftUI `AboutView` を追加し、メニューバーの「Wintchについて」からアプリアイコン・バージョン情報・著作権表記を確認できるようにする。

## Technical Context

**Language/Version**: Swift 6（`Apple Swift version 6.4.2` / `swift-tools-version: 6.0` を確認済み）、Bash、GitHub Actions YAML  
**Primary Dependencies**: Apple 標準フレームワークのみ（`SwiftUI`, `AppKit`, `Foundation`）、macOS 標準ビルドツール（`swift`, `PlistBuddy`, `qlmanage`, `sips`, `iconutil`, `codesign`, `ditto`）、GitHub CLI（`gh`）。外部サードパーティライブラリ依存ゼロ。  
**Storage**: リポジトリルートの `VERSION` プレーンテキストファイル（ビルド時にバンドル内 `Info.plist` へ反映）  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `swift test`、ローカル `.app` ビルド・`lipo`・`PlistBuddy`・`ditto` 検証  
**Target Platform**: macOS 14.0 (Sonoma) 以降（リリース成果物は Apple Silicon `arm64` + Intel `x86_64` Universal Binary、CI ランナーは `macos-15`）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`LSUIElement = YES`、`WintchCore` + `Wintch` 2ターゲット構成）  
**Performance Goals**: 「Wintchについて」メニュー選択から 0.5 秒以内にウィンドウ表示、常駐時メモリ・CPU オーバーヘッド増加ゼロ（ウィンドウは遅延生成）  
**Constraints**: 画面収録権限不使用、非公開 API 不使用、外部 Swift パッケージ依存ゼロ、`Resources/Info.plist` をビルドで汚さないこと、`GITHUB_TOKEN` のみで追加シークレット不要な自動タグ→リリース連携、日本語コメント・JSDoc/DocC 形式ドキュメントコメント必須  
**Scale/Scope**: 既存のメニューバー＋設定＋権限誘導画面に「Wintchについて」ウィンドウを追加し、ビルド・CI リリースパイプラインを整備

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限の原則（Privacy by Design）** | バージョン取得と「Wintchについて」画面はアプリ自身のバンドル情報のみを参照し、画面収録権限や追加の OS 権限を一切使用しない | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | バージョン管理は単一 `VERSION` ファイルのみ、About 画面もアイコン・アプリ名・バージョン・著作権表記の最小構成に留める | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | `aboutWindow` はユーザー操作時に遅延生成するため、アプリ起動速度や常駐メモリ・ホットキー応答に影響を与えない | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | アプリ側は Apple 標準フレームワークのみ使用。CI/ビルドも macOS 標準コマンドと `actions/checkout` + `gh` CLI のみで構成 | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。`Bundle.main.infoDictionary` 欠損時（`swift run` 等）やアイコン未設定時もフォールバック値でクラッシュを防止 | PASS |
| **6. 技術スタック・MVVM + Services** | `AboutView` は SwiftUI で構築し、ウィンドウ管理は `AppCoordinator` に集約。`AppVersionInfo` は純粋な値型として `Domain/` に配置 | PASS |
| **7. 可読性・テスト可能性・ライセンス** | `AppVersionInfo` を `Bundle` 非依存の辞書注入で単体テスト可能にし、日本語コメント・ドキュメントコメント規約および MIT License 表記を維持 | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/003-semver-release-about/
├── plan.md                                  # 本実装計画書
├── research.md                              # Phase 0 技術調査レポート
├── data-model.md                            # Phase 1 バージョンモデル・状態遷移設計
├── quickstart.md                            # Phase 1 ビルド・リリース・UI 検証ガイド
├── contracts/                               # Phase 1 契約仕様
│   ├── release-pipeline-contracts.md        # ビルドスクリプト・ZIP・GitHub Actions 契約
│   └── ui-contracts.md                      # メニュー項目・About ウィンドウ UI 契約
└── checklists/
    └── requirements.md                      # 仕様品質チェックリスト
```

### Source Code (repository root)

既存の `WintchCore`（ライブラリ）＋ `Wintch`（実行ターゲット）＋ `scripts/` 構成を維持し、以下を追加・更新する。

```text
.
├── VERSION                                  # [新規] 単一のセマンティックバージョン定義ファイル（初期値: 0.1.0）
├── .github/
│   └── workflows/
│       └── release.yml                      # [新規] SemVer 検証・自動タグ作成・Universal ビルド・ZIP 生成・GitHub Release 公開
├── scripts/
│   └── build-app.sh                         # [更新] VERSION 読み込み・SemVer 検証・PlistBuddy 注入・--universal 対応
├── Sources/
│   ├── Wintch/
│   │   └── WintchApp.swift                  # [更新] MenuBarExtra に「Wintchについて」メニュー項目を追加
│   └── WintchCore/
│       ├── App/
│       │   └── AppCoordinator.swift         # [更新] openAbout() および aboutWindow（再利用可能 NSWindow）追加
│       ├── Domain/
│       │   └── AppVersionInfo.swift         # [新規] Bundle 情報からバージョン・ビルド番号・著作権を抽出する純粋値型
│       └── Views/
│           └── AboutView.swift              # [新規] アプリアイコン・アプリ名・バージョン・著作権表記を表示する SwiftUI ビュー
└── Tests/
    └── WintchCoreTests/
        └── AppVersionInfoTests.swift        # [新規] AppVersionInfo の正常系・トリミング・フォールバック単体テスト
```

**Structure Decision**:
- バージョン抽出ロジックを `Sources/WintchCore/Domain/AppVersionInfo.swift` へ切り出すことで、UI や `Bundle.main` に依存しない単体テストを Swift Testing で実行可能にする。
- ビルドと CI 連携では `scripts/build-app.sh` をローカルと GitHub Actions の共通エントリポイントとし、`VERSION` 読み取りと `Info.plist` 注入を一箇所に集約する。
- `.github/workflows/release.yml` では `GITHUB_TOKEN` 制約（自動作成タグで別ワークフローが起動しない仕様）を踏まえ、タグ作成ジョブ（`prepare`）とビルド公開ジョブ（`release`）を単一ワークフロー内で直列接続する。

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
