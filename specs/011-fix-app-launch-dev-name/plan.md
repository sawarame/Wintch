# 実装計画 (Implementation Plan): ランチャーからのアプリ起動安定化およびローカル開発版の識別名分離

**Branch**: `011-fix-app-launch-dev-name` | **Date**: 2026-11-16 | **Spec**: [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/011-fix-app-launch-dev-name/spec.md)

**Input**: Feature specification from `/specs/011-fix-app-launch-dev-name/spec.md`

## Summary

Homebrew 配布版で発生していた「検索ランチャーから未起動アプリを起動した直後に Wintch が異常終了する不具合」を修正するとともに、ローカル開発用ビルドを「`Wintch_dev`」として配布版から明確に区別できるようにする：

1. **`InstalledAppService.launchApplication(_:)` のクラッシュ解消**: `NSWorkspace.shared.openApplication(at:configuration:completionHandler:)` に渡していた空クロージャ `{ _, _ in }` が `macos-15` SDK 環境で `@MainActor` 分離クロージャとしてコンパイルされ、`com.apple.launchservices.open-queue` からの呼び出し時に `_swift_task_isCurrentExecutor` 違反（`SIGTRAP`）を起こしていたため、`completionHandler: nil` を指定して安全に起動要求のみを発行するように修正する。
2. **開発版識別ドメインモデル (`AppIdentity`) の導入と UI 文言統一**: バンドル情報（`CFBundleDisplayName` / `CFBundleName` / `CFBundleIdentifier`）およびビルド構成に応じたフォールバックからアプリ表示名・識別子・UI 文言を一元解決する `Domain/AppIdentity.swift` を新設し、`WintchApp`・`AppCoordinator`・`AboutView`・`PermissionGuideView` のハードコードされた `"Wintch"` 表記をすべて `AppIdentity` 経由へ置き換える。
3. **バンドル組み立てスクリプト (`scripts/build-app.sh`) による開発版／配布版分離**: 既定の開発ビルド（`debug`）では出力バンドルを `.build/Wintch_dev.app`（実行ファイル・表示名 `Wintch_dev`、識別子 `dev.wintch.Wintch.dev`）として生成し、`release` ビルドでは従来通り `.build/Wintch.app`（`Wintch`、`dev.wintch.Wintch`）を維持して `.github/workflows/release.yml` との完全な互換性を保つ。

## Technical Context

**Language/Version**: Swift 6（`swift-tools-version: 6.0`）  
**Primary Dependencies**: Apple 標準フレームワークのみ（`Foundation` / `AppKit` / `SwiftUI`）。外部サードパーティ依存ゼロ。  
**Storage**: 既存の `PreferencesStore`（`UserDefaults.standard`）。`CFBundleIdentifier` を `dev.wintch.Wintch.dev` へ分離することで開発版・配布版の設定ドメインが自動分離される。  
**Testing**: Swift Testing（`import Testing`, `@Test`, `#expect`）および `swift test`  
**Target Platform**: macOS 14.0 (Sonoma) 以降（Apple Silicon / Intel）  
**Project Type**: macOS メニューバー常駐デスクトップアプリケーション（`LSUIElement = YES`、`WintchCore` + `Wintch` 構成）  
**Performance Goals**: アプリ起動要求の発行および UI 名称解決は O(1) の軽量処理であり、既存ランチャーの即時応答性（100ms 以内）に一切のオーバーヘッドを加えない。  
**Constraints**: 画面収録権限不使用、非公開 API（`CGS*` 等）不使用、日本語ドキュメントコメント（`///`）および日本語インラインコメント必須、`@Observable` / `@MainActor` 維持、`.github/workflows/release.yml` のリリースビルド出力（`./.build/Wintch.app`）を破壊しないこと。  
**Scale/Scope**: `Domain/AppIdentity.swift` の新規追加、`Services/InstalledAppService.swift`・`App/AppCoordinator.swift`・`Views/AboutView.swift`・`Views/PermissionGuideView.swift`・`Sources/Wintch/WintchApp.swift`・`scripts/build-app.sh` の最小限の更新、およびユニットテスト（`AppIdentityTests.swift` / `InstalledAppServiceTests.swift`）の追加・更新。

## Constitution Check

*GATE: Phase 0 リサーチ前および Phase 1 設計後の両時点で検証済み。*

| 憲章原則・制約 | 設計上の準拠状況 | 判定 |
|---|---|---|
| **1. 最小権限およびオプトインの原則（Privacy by Design）** | 画面収録権限には一切触れず、開発版のアクセシビリティ権限管理を別識別子で独立させるのみ | PASS |
| **2. 過剰機能の排除（シンプルさの徹底）** | ユーザー設定画面に開発用切り替え項目を増やさず、ビルド構成に応じた自動識別と既存 UI 文言の動的化にとどめる | PASS |
| **3. 起動と応答の高速性（ゼロレイテンシ）** | 不要な完了クロージャ削除によりオーバーヘッドが減り、識別名解決も辞書参照のみで遅延ゼロ | PASS |
| **4. 依存関係の最小化（外部依存ゼロ）** | Apple 標準フレームワークおよび既存 `PlistBuddy` 等の標準ビルドツールのみを使用 | PASS |
| **5. 非公開APIの禁止と安全なフォールバック** | 非公開 API 不使用。`completionHandler: nil` により実行スレッド不一致クラッシュを根絶し、未バンドル実行時も安全なフォールバック名称を返す | PASS |
| **6. 技術スタック・MVVM + Services** | アプリ識別情報の解決ロジックを `Domain/AppIdentity.swift` へ隔離し、OS 起動 API は `Services/InstalledAppService.swift` 内に限定する | PASS |
| **7. 可読性・テスト可能性・ライセンス** | 過度な抽象化を避けた不変値型 `AppIdentity` と最小限のテスト注入フックで純粋単体テストを可能にし、日本語ドキュメント・コメントを整備する | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/011-fix-app-launch-dev-name/
├── spec.md                                        # 機能仕様書
├── plan.md                                        # 本実装計画書
├── research.md                                    # Phase 0 調査・クラッシュ解析・設計判断レポート
├── data-model.md                                  # Phase 1 AppIdentity・ビルドバリアント・起動モデル
├── quickstart.md                                  # Phase 1 ビルド・実機・リリースバイナリ検証ガイド
├── contracts/
│   └── app-launch-and-identity-contracts.md       # Phase 1 サービス・UI・ビルドスクリプト契約
└── checklists/
    └── requirements.md                            # 仕様品質チェックリスト
```

### Source Code (repository root)

既存の `WintchCore` + `Wintch` パッケージ構造を変更せず、以下のファイルを追加・更新する。

```text
Sources/Wintch/
└── WintchApp.swift                                # [更新] メニュー項目（「〜について」「〜 を終了」）を AppIdentity.current 由来に変更

Sources/WintchCore/
├── Domain/
│   └── AppIdentity.swift                          # [新規] バンドル情報・開発版判定・UI 表示文言を解決する純粋値型
├── Services/
│   └── InstalledAppService.swift                  # [更新] NSWorkspace.openApplication に completionHandler: nil を指定（テスト用フック対応）
├── App/
│   └── AppCoordinator.swift                       # [更新] AppIdentity 保持と設定/About/権限ウィンドウタイトルの動的化
└── Views/
    ├── AboutView.swift                            # [更新] 見出しアプリ名を AppIdentity 由来に変更
    └── PermissionGuideView.swift                  # [更新] 手順 2 のスイッチ対象アプリ名を AppIdentity 由来に変更

scripts/
└── build-app.sh                                   # [更新] debug 時は Wintch_dev.app / dev.wintch.Wintch.dev、release 時は Wintch.app / dev.wintch.Wintch を出力

Tests/WintchCoreTests/
├── AppIdentityTests.swift                         # [新規] 開発版/配布版/空白/欠損フォールバックおよび UI 文言生成の単体テスト
└── InstalledAppServiceTests.swift                 # [更新] launchApplication(_:) の起動構成および非同期安全性の検証テスト追加
```

**Structure Decision**:
- `Resources/Info.plist` はリリース用の正本（`Wintch` / `dev.wintch.Wintch`）として無変更のまま維持し、`scripts/build-app.sh` が生成バンドル内の `Contents/Info.plist` のみを書き換えることで、リポジトリ差分を汚さずに開発版と配布版を確実に分離する。
- `AppVersionInfo` はバージョン・ビルド番号・著作権表記の単一責務を保ったまま、新規の `AppIdentity` に識別名・識別子・UI 文言解決を集約することで、既存テストおよび呼び出し側との互換性を維持する。

## Complexity Tracking

> 憲章違反（Constitution Check における逸脱）は存在しないため、該当なし。
