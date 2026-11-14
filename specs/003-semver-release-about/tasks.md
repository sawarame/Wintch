---

description: "セマンティックバージョニング導入・自動タグリリース・「Wintchについて」メニュー実装のための依存関係順タスクリスト"
---

# Tasks: セマンティックバージョニング導入・自動タグリリース・「Wintchについて」メニュー

**Input**: 設計ドキュメント `/specs/003-semver-release-about/`  
**Prerequisites**: [plan.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/003-semver-release-about/plan.md), [spec.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/003-semver-release-about/spec.md), [research.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/003-semver-release-about/research.md), [data-model.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/003-semver-release-about/data-model.md), [release-pipeline-contracts.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/003-semver-release-about/contracts/release-pipeline-contracts.md), [ui-contracts.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/003-semver-release-about/contracts/ui-contracts.md)

**Tests**: プロジェクト憲章（テスト可能性）および `quickstart.md` に基づき、`AppVersionInfo` の Swift Testing ユニットテストおよびローカルビルド・Universal Binary・`ditto` ZIP・`Info.plist` 検証を含みます。

**Organization**: ユーザーストーリー単位（US1, US2, US3）にフェーズを分割し、各ストーリーが独立して実装・テスト・検証可能な構成としています。すべての新規・変更 Swift コードは日本語ドキュメントコメントおよび日本語インラインコメントを必須とします。

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: 並列実行可能（異なるファイルで未完了タスクへの依存なし）
- **[Story]**: 所属するユーザーストーリー（`[US1]`, `[US2]`, `[US3]`）
- すべてのタスクに具体的なファイルパスを記載

---

## Phase 1: Setup（環境確認とバージョン定義ファイル作成）

**Purpose**: 既存プロジェクトの健全性を確認し、バージョン一元管理の基点となる `VERSION` ファイルを配置する

- [ ] T001 既存の `Package.swift` に基づく `swift test` および `scripts/build-app.sh` のベースライン動作を確認する
- [ ] T002 [P] リポジトリルートの `VERSION` ファイルに初期値 `0.1.0`（UTF-8 プレーンテキスト・1行）を作成する

---

## Phase 2: Foundational（全ストーリー共通のビルド基盤拡張）

**Purpose**: US1・US2・US3 が共通して依存する `scripts/build-app.sh` のバージョン注入および Universal Binary ビルド機能を整備する

**⚠️ CRITICAL**: バンドル内 `Info.plist` へのバージョン反映と Universal ビルド対応は、自動リリース（US1/US3）および「Wintchについて」での実機バージョン表示（US2）双方の前提条件となる

- [ ] T003 `scripts/build-app.sh` を更新し、リポジトリルートの `VERSION` 読み取り（前後空白・改行トリミング）、SemVer 正規表現検証（`^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$`）、`git rev-list --count HEAD`（取得不可時は `"1"` フォールバック）によるビルド番号算出、および `.build/Wintch.app/Contents/Info.plist` への `/usr/libexec/PlistBuddy` 注入（`CFBundleShortVersionString`・`CFBundleVersion`、元の `Resources/Info.plist` は未変更）を実装する（T002 依存）
- [ ] T004 `scripts/build-app.sh` に `--universal` 引数および環境変数 `WINTCH_UNIVERSAL=true` 対応を追加し、有効時に `swift build -c "${CONFIGURATION}" --arch arm64 --arch x86_64` と `--show-bin-path` による Universal Binary 出力パス解決を実装する（T003 依存）

**Checkpoint**: `./scripts/build-app.sh release --universal` により `VERSION` 同期済みかつアドホック署名済みの Universal `Wintch.app` を生成できる状態

---

## Phase 3: User Story 1 - 単一のバージョンファイルによる一元管理と自動タグ・リリース公開 (Priority: P1) 🎯 MVP

**Goal**: `main` ブランチへの `VERSION` 更新反映時に自動で SemVer 検証・タグ重複確認・`swift test` を実行し、`v<VERSION>` タグを自動作成してそのまま Universal Binary ビルド・`ditto` による `Wintch-v<VERSION>.zip` 生成・GitHub Release 公開（プレリリース自動判定含む）までを完結させる

**Independent Test**: `VERSION` の更新を模擬した検証（正規表現・プレリリース判定・重複タグ検出）およびローカルでの `./scripts/build-app.sh release --universal` + `ditto -c -k --keepParent ./.build/Wintch.app ./.build/Wintch-v0.1.0.zip` の展開構造・`Info.plist`・`lipo -info` が契約通り動作し、`.github/workflows/release.yml` が全要件を満たしていること

### Implementation for User Story 1

- [ ] T005 [P] [US1] `.github/workflows/release.yml` を新規作成し、`macos-15` ランナー、`contents: write` 権限、`actions/checkout@v4`（`fetch-depth: 0`）、およびバージョン単位の `concurrency` グループ定義の基盤を構築する
- [ ] T006 [US1] `.github/workflows/release.yml` の `prepare` ジョブに `push`（`branches: [main]`, `paths: ['VERSION']`）トリガー時の `VERSION` トリミング・SemVer 検証・既存タグ `v<VERSION>` 重複エラー停止・`swift test` 実行・`github-actions[bot]` 名義でのタグ `v<VERSION>` 作成と push 処理を実装する（T005 依存）
- [ ] T007 [US1] `.github/workflows/release.yml` の `release` ジョブに `./scripts/build-app.sh release --universal` 実行、`ditto -c -k --keepParent ./.build/Wintch.app "./.build/Wintch-v${VERSION}.zip"` による ZIP 生成、プレリリース判定（`-` を含む場合 `--prerelease` 付与）、および `gh release create`（`--generate-notes` 付き）での公開処理を実装する（T004, T006 依存）

**Checkpoint**: User Story 1（`VERSION` 更新 → 自動タグ → Universal ビルド → ZIP 添付リリース公開）のパイプライン一式が完成した状態

---

## Phase 4: User Story 2 - 「Wintchについて」メニューからのアプリアイコン・バージョン確認 (Priority: P1)

**Goal**: メニューバー常駐メニューに「Wintchについて」を追加し、クリック時にアプリアイコン・アプリ名・表示バージョン・ビルド番号・著作権表記を表示する専用 SwiftUI ウィンドウを最前面に表示し、重複生成せず再利用できるようにする

**Independent Test**: `AppVersionInfoTests`（正常抽出・空白トリミング・未設定/型不一致時フォールバック）が `swift test` で全パスし、ビルドした `.build/Wintch.app` を起動してメニューバーから「Wintchについて」を開閉した際にアイコン・`0.1.0`・ビルド番号・著作権表記が正しく表示され、重複やアプリ終了が起きないこと

### Tests for User Story 2 ⚠️

> **NOTE**: 純粋ドメインモデル `AppVersionInfo` のテストを先に記述し、実装前に失敗することを確認する

- [ ] T008 [P] [US2] `AppVersionInfo` のユニットテスト（`CFBundleShortVersionString`・`CFBundleVersion`・`NSHumanReadableCopyright` の正常取得、前後空白・改行トリミング、`nil`・空文字・非文字列時のフォールバック値 `"dev"` / `"1"` / `"Copyright © 2026 Wintch Contributors. MIT License."`、`displayVersionText` 書式 `"バージョン <shortVersion> (<buildNumber>)"`）を `Tests/WintchCoreTests/AppVersionInfoTests.swift` に作成する

### Implementation for User Story 2

- [ ] T009 [P] [US2] `AppVersionInfo`（`Equatable`, `Sendable`、`shortVersion: String` フォールバック `"dev"`、`buildNumber: String` フォールバック `"1"`、`copyright: String` フォールバック `"Copyright © 2026 Wintch Contributors. MIT License."`、`displayVersionText: String`、`init(infoDictionary: [String: Any]?)`、`static var current: AppVersionInfo`）を `Sources/WintchCore/Domain/AppVersionInfo.swift` に実装する
- [ ] T010 [US2] SwiftUI ビュー `AboutView`（アプリアイコン `NSApplication.shared.applicationIconImage` の 80x80pt 表示＋取得不可時フォールバック、アプリ名 `"Wintch"`、テキスト選択可能なバージョン表記 `versionInfo.displayVersionText`、簡潔なアプリ説明と `versionInfo.copyright`、余白の整った固定サイズレイアウト）を `Sources/WintchCore/Views/AboutView.swift` に作成する（T009 依存）
- [ ] T011 [US2] `AppCoordinator` に `aboutWindow: NSWindow?`、`openAbout()`（`NSApplication.shared.activate()`、`window.center()`、`window.makeKeyAndOrderFront(nil)`）、および `ensureAboutWindow()`（タイトル `"Wintchについて"`、スタイル `[.titled, .closable]`、`isReleasedWhenClosed = false`）を追加して `Sources/WintchCore/App/AppCoordinator.swift` を更新する（T010 依存）
- [ ] T012 [US2] `MenuBarExtra` 内の「設定を開く...」の前に `Button("Wintchについて") { appDelegate.coordinator.openAbout() }` と区切り線（または同等の明瞭な配置）を追加して `Sources/Wintch/WintchApp.swift` を更新する（T011 依存）

**Checkpoint**: User Story 2（「Wintchについて」メニューおよび専用ウィンドウと `AppVersionInfoTests`）が単独で動作・検証可能な状態

---

## Phase 5: User Story 3 - 手動タグ作成によるリリースビルドの自動反映 (Priority: P2)

**Goal**: 手動での `v*` タグ push、GitHub UI 上でのリリース公開イベント（`release: published`）、および手動実行（`workflow_dispatch`）のすべての経路でも、`VERSION` との整合性検証・`swift test`・Universal ビルド・`Wintch-v<VERSION>.zip` 添付（既存リリース時は `--clobber` 上書き）が安全・冪等に実行されるようにする

**Independent Test**: `.github/workflows/release.yml` において `push.tags: ['v*']`、`release.types: [published]`、`workflow_dispatch` の各イベント分岐でタグ名と `VERSION` の一致検証および `gh release view` による作成/上書き分岐が正しく構成されていること

### Implementation for User Story 3

- [ ] T013 [US3] `.github/workflows/release.yml` の `prepare` ジョブを拡張し、`push`（`tags: ['v*']`）、`release`（`types: [published]`）、および `workflow_dispatch` トリガーに対応させ、タグ名から `v` を除いた値と `VERSION` ファイル値の完全一致検証（不一致時エラー停止）、SemVer 検証、`swift test` ゲート、および必要時のタグ作成分岐を実装する（T006 依存）
- [ ] T014 [US3] `.github/workflows/release.yml` の `release` ジョブを拡張し、`gh release view "v${VERSION}"` でリリース有無を確認し、未作成時は `gh release create`、作成済み時は `gh release upload "v${VERSION}" "./.build/Wintch-v${VERSION}.zip" --clobber` を実行する冪等な成果物反映ロジックを実装する（T007, T013 依存）

**Checkpoint**: 自動タグ作成・手動タグ push・GitHub UI リリース公開のすべてに対応したリリース自動化が完成した状態

---

## Phase 6: Polish & Cross-Cutting Concerns（仕上げ・品質・全体検証）

**Purpose**: 日本語コメント規約・ドキュメント整備・全ユニットテスト・ローカル Universal ビルド＆ZIP 検証を一括で確認する

- [ ] T015 [P] 新規・更新した全 Swift ファイル（`Sources/WintchCore/Domain/AppVersionInfo.swift`, `Sources/WintchCore/Views/AboutView.swift`, `Sources/WintchCore/App/AppCoordinator.swift`, `Sources/Wintch/WintchApp.swift`, `Tests/WintchCoreTests/AppVersionInfoTests.swift`）のクラス・関数・メソッドに日本語ドキュメントコメント（概要・`@param`・`@returns`）と日本語インラインコメントが漏れなく記述されているか点検・補完する
- [ ] T016 [P] `README.md` を更新し、プロジェクト構成一覧への `VERSION`・`.github/workflows/release.yml`・`AppVersionInfo.swift`・`AboutView.swift` の追記、および `--universal` ビルドとセマンティックバージョニングによる自動リリース手順を記載する
- [ ] T017 [quickstart.md](file:///Users/sawarame_yasushi/dev/Wintch/specs/003-semver-release-about/quickstart.md) に沿って `swift test`、`./scripts/build-app.sh release --universal`、`PlistBuddy` / `lipo -info` / `codesign --verify`、`ditto -c -k --keepParent` の ZIP 構造確認、および `.github/workflows/release.yml` の構文・ロジック検証を実行し、全検証結果を記録する

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: `T001`・`T002` は依存なしで即時着手可能
- **Foundational (Phase 2)**: `T002` 完了後に `T003` → `T004` の順で実施。完了まで US1 のビルド連携ジョブおよび US2 の実機バージョン表示確認は待機
- **User Story 1 (Phase 3 - P1 🎯 MVP)**: `T005` は早期に並列着手可能、`T006` は `T005` 依存、`T007` は `T004`・`T006` 依存
- **User Story 2 (Phase 4 - P1)**: `T008` と `T009` は並列着手可能 → `T010` → `T011` → `T012` の順で統合（US1 とは別ファイル群のため並行開発可能）
- **User Story 3 (Phase 5 - P2)**: US1 の `T006`・`T007` 完了後に `T013` → `T014` で `.github/workflows/release.yml` を拡張
- **Polish (Phase 6)**: 全ストーリー完了後に `T015`・`T016` を並列実行し、最後に `T017` で総合検証

### Parallel Opportunities

- **Setup**: `T001` と `T002` は並列実行可能
- **US1 vs US2**: Phase 1 (`T002`) 完了後、CI/ビルド側（`T003`〜`T007`）と Swift アプリ側（`T008`〜`T012`）は変更ファイルが完全に分離しているため並行実装可能
- **US2 Tests & Domain**: `T008`（`AppVersionInfoTests.swift`）と `T009`（`AppVersionInfo.swift`）は別ファイルのため並列実行可能
- **Polish**: `T015`（コードコメント点検）と `T016`（`README.md` 更新）は並列実行可能

---

## Parallel Example: Foundational & User Story 2

```text
# ビルド基盤の整備（T003→T004）と並行して、US2 のテスト・モデル・CI 骨格を同時進行可能:
- T005 [US1]: .github/workflows/release.yml（ワークフロー骨格）
- T008 [US2]: Tests/WintchCoreTests/AppVersionInfoTests.swift
- T009 [US2]: Sources/WintchCore/Domain/AppVersionInfo.swift
```

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 2)

1. Phase 1（`T001`〜`T002`）で `VERSION` ファイルを配置する
2. Phase 2（`T003`〜`T004`）で `scripts/build-app.sh` のバージョン同期と Universal ビルドを完成させる
3. Phase 3（US1: `T005`〜`T007`）と Phase 4（US2: `T008`〜`T012`）を実装する
4. **STOP & VALIDATE**: `swift test`、Universal `.app` ビルド、`ditto` ZIP 展開、「Wintchについて」ウィンドウ表示を検証する

### Incremental Delivery

1. Setup + Foundational 完了 → `VERSION` 同期＆Universal ビルドが可能に
2. US1 完了 → `VERSION` 更新による自動タグ作成・リリース公開基盤が完成
3. US2 完了 → 「Wintchについて」メニューからアプリアイコン・バージョンを確認可能に
4. US3 完了（`T013`〜`T014`） → 手動タグ作成や GitHub UI リリース公開でも冪等に ZIP が反映される状態が完成
5. Polish（`T015`〜`T017`） → 日本語コメント規約・README・全総合検証を完了
