# 技術調査 (Research): 検索ランチャーでの検索入力時におけるアプリ起動候補の併用表示

**Feature Branch**: `006-launcher-app-launch` | **Date**: 2026-11-15

## 1. インストール済みアプリケーションの収集方式

- **Decision**: 標準ディレクトリ群（`/Applications`, `/System/Applications`, `~/Applications`, `/System/Library/CoreServices/Applications`, および `/System/Library/CoreServices/Finder.app`）を `FileManager` で最大深さ 3 まで再帰走査し、シンボリックリンク解決後の `.app` バンドルの `Info.plist` と `FileManager.default.displayName(atPath:)` を用いてバックグラウンドで収集・キャッシュする。
- **Rationale**:
  - 外部ライブラリ・Spotlight (`NSMetadataQuery`) の非同期インデックス依存・非公開 API を使用せず、Apple 標準フレームワークのみで決定的に高速収集できる。
  - macOS Sonoma 以降の `Safari.app` のように `/Applications/Safari.app` が `/System/Cryptexes/App/...` へのシンボリックリンクになっている構成にも対応でき、`bundleIdentifier ?? resolvedURL.path` による重複排除で安全に 1 件へ統合できる。
  - アプリ起動時（`AppCoordinator.start()`）の事前取得＋ランチャー起動時の裏リフレッシュ＋メモリキャッシュ参照の組み合わせにより、検索入力時の再計算を 0ms〜数ms（ゼロレイテンシ）に抑えられる。
- **Alternatives considered**:
  - `NSMetadataQuery`（Spotlight）: Spotlight インデックス無効環境や権限制約で取得漏れが起きうる点、単体テスト時の決定的モック／一時ディレクトリ検証が困難な点から不採用。
  - LaunchServices 非公開／低レベルコールバック: 憲章第5原則（非公開 API 禁止）および将来の App Store 審査対応のため不採用。

## 2. 日本語・英語の併用検索と共通ファジー検索基盤

- **Decision**: 既存の `WindowSearchEngine` に含まれていた DP ベース 2 フィールドファジー検索（空白区切り AND・大文字小文字／発音区別符号／全角半角正規化・単語境界／連続加点・一致文字範囲抽出）を `FuzzySearchMatcher` として共通抽出し、`WindowSearchEngine` と `AppSearchEngine` の双方で再利用する。
- **Rationale**:
  - ロジックの重複を完全に排除しつつ、ウィンドウ検索とアプリ検索で一貫した検索スコア・ハイライト体験を提供できる。
  - アプリ側の主フィールドに `displayName`（ローカライズ名、例：「メモ」）、補助フィールドに `alternateName`（ファイル名由来の原語名、例：「Notes」）を割り当てることで、日本語環境でも英語入力・日本語入力の双方でヒットし、該当文字箇所をそれぞれハイライト描画できる。
- **Alternatives considered**:
  - アプリ検索用に簡易な部分一致 (`localizedStandardContains`) を別途実装する案: 略称検索（`"vsc"`, `"ss"` 等）やハイライト範囲抽出の体験がウィンドウ検索と乖離し、コードも重複するため不採用。

## 3. 上部ウィンドウ候補と下部アプリ起動候補の重複除外方式

- **Decision**: `WindowEntry` に既存の `RawWindowCandidate.bundleIdentifier` を引き継ぎ、`AppSearchEngine.search(query:in:excludingWindowEntries:)` にて「上のウィンドウ検索結果に含まれているウィンドウ群」と同一アプリを除外する。
- **Rationale**:
  - `bundleIdentifier` が双方に存在する場合は大文字小文字無視の厳密一致で判定できるため、「システム設定」と「System Settings」や「Code」と「Visual Studio Code」のように名前表記が異なるケースでも誤表示・誤除外なく 100% 正確に重複排除できる。
  - テストデータ等で `bundleIdentifier` が未設定（`nil`）の場合に限り、`WindowEntry.applicationName` と `LaunchableApp.displayName` / `alternateName` の大文字小文字無視一致へフォールバックすることで、既存テストおよびモック互換性を保てる。
  - 除外基準を「全開ウィンドウ」ではなく「検索結果の上欄に表示中のウィンドウ群」とすることで、別タイトル条件で絞り込まれて上欄に表示されていないアプリは必要に応じて下欄からアクセスできる。
- **Alternatives considered**:
  - アプリ名文字列のみで照合する案: 日本語ローカライズ名と英語プロセス名の差異（例：`Code` vs `Visual Studio Code`）で取りこぼしが発生するため、`bundleIdentifier` 優先照合を採用。

## 4. 統合リスト表示・選択カーソル・パネル伸縮の UI 設計

- **Decision**: `SwitcherViewModel` はウィンドウ候補（`0 ..< displayedResults.count`）とアプリ起動候補（`displayedResults.count ..< totalCount`）を単一の `selectedIndex` でシームレスに貫通制御し、`SwitcherListView` 側も単一の `ScrollViewReader` + `ScrollView` 内にウィンドウ候補セクションと（区切り線＋ヘッダ付きの）アプリ起動候補セクションを配置する。
- **Rationale**:
  - 矢印キー・`Ctrl + N` / `Ctrl + P`・通常スイッチャーショートカット（`Option + Tab` / `Option + Shift + Tab`）による循環移動および `ScrollViewReader` の自動スクロール追従が、セクションを跨いでも一切途切れず動作する。
  - 既存の `SwitcherPanel` 上端固定リサイズ機構（`GeometryReader` + `updateAnchoredHeight` / `updateAnchoredHeightIfNeeded`）がそのまま機能し、ウィンドウのみ・混在表示・アプリのみ・0 件メッセージのいずれの遷移でも検索入力欄が上下に揺れない。
- **Alternatives considered**:
  - 上下セクションを別々の `ScrollView` に分割する案: 双方の候補数が多い場合にパネル全体の高さバランス制御や上下移動時のスクロール追従が分断されるため、単一 `ScrollView` 統合方式を採用。
