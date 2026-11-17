# 技術調査・設計判断レポート (Research): アクセシビリティ権限誘導ダイアログの説明文全文表示修正

**Feature**: `016-fix-permission-guide-text` | **Date**: 2026-11-17 | **Related Issue**: [#19](https://github.com/sawarame/Wintch/issues/19)

## 1. 不具合の根本原因調査

### 対象箇所
- [PermissionGuideView.swift](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/Views/PermissionGuideView.swift)
- [AppCoordinator.swift](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/App/AppCoordinator.swift)（`ensurePermissionWindow()`）

### 原因分析
1. **`NSWindow` の固定高さ不足**:
   `AppCoordinator.ensurePermissionWindow()` で `contentRect: NSRect(x: 0, y: 0, width: 460, height: 280)` と高さを固定値 `280pt` で生成し、非リサイズ（`styleMask: [.titled, .closable]`）のウィンドウへ `NSHostingView` をそのまま設定していた。
   一方、`PermissionGuideView` 内の要素（上下パディング `48pt`、ヘッダー部、手順ボックス 3 行、補足説明 2 行、操作ボタン行、各要素間 `spacing: 20`）の合計必要高さは `280pt` を上回っていた（約 `300pt` 以上）。
2. **SwiftUI `Text` の垂直圧縮による省略（`...`）**:
   `PermissionGuideView` 内の `Text("※ リスト型および検索ランチャーでは「画面収録」権限を使用しません（キャプチャ表示型を選択した場合のみ任意で使用します）。")` などの複数行テキストに `.fixedSize(horizontal: false, vertical: true)` が指定されていなかったため、高さ `280pt` の制約を受けた SwiftUI レイアウトエンジンが補足説明 `Text` を 1 行分に圧縮し、末尾が「`リスト型および検索ランチャーでは...`」と途中省略された。

## 2. 設計上の決定事項

### Decision 1: `PermissionGuideView` におけるテキスト折り返しと高さ保護
- **決定**: `PermissionGuideView` に幅基準定数（`preferredWidth: CGFloat = 460`）と最小高さ定数（`minimumHeight: CGFloat = 280`）を定義し、見出し・サブタイトル・手順ラベル（1〜3）・補足説明 `Text` に `.fixedSize(horizontal: false, vertical: true)` を適用する。
- **根拠**: 横幅 `460pt` の制約内では必要に応じて自然に複数行へ折り返しつつ、縦方向には SwiftUI の圧縮による 1 行切り詰め（`...` 省略）を確実に防げるため。
- **検討した代替案**:
  - 補足説明の文言を短く書き換えて 1 行に収める案 → Wintch 憲章 v2.0.0 の「最小権限およびオプトインの原則」を正確に伝える注記情報が欠落するため却下。
  - ウィンドウ横幅を大幅に広げる案 → macOS の設定・権限案内ダイアログとして過剰に横長になるため、`460pt` を基準に縦方向を内容適応させる方が自然。

### Decision 2: `AppCoordinator.ensurePermissionWindow()` の内容サイズ自動適応
- **決定**: `NSHostingView` に対して `layoutSubtreeIfNeeded()` 後に `fittingSize` を計測し、`width = max(fittingSize.width, PermissionGuideView.preferredWidth)`・`height = max(fittingSize.height, PermissionGuideView.minimumHeight)` で `NSWindow` のコンテンツサイズを設定する（`contentRect` および `window.setContentSize(_:)`）。
- **根拠**: OS の標準フォントサイズ・アプリ表示名（`Wintch` / `Wintch_dev`）の差異等によって必要高さが変わっても、常に `NSHostingView.fittingSize.height` 以上のコンテンツ領域が保証され、テキストやボタンの上下見切れを構造的に防止できるため。
- **検討した代替案**:
  - `height: 280` を `340` 等の別マジックナンバーに書き換える案 → 将来の文言変更やフォントメトリクス差異で再び見切れ・余白過多が起きるため不採用。

### Decision 3: テスト戦略
- **決定**:
  1. `PermissionGuideView` を `NSHostingView` に載せた際の `fittingSize` が横幅 `460pt`・高さ `280pt` 超で計算され、配布版（`Wintch`）・開発版（`Wintch_dev`）双方で十分な必要高さを返すことを検証する単体テストを追加する。
  2. `AppCoordinatorTests` にて `openPermissionGuide()` が生成する `NSWindow` のコンテンツ高さが `NSHostingView.fittingSize.height` 以上であることを検証し、固定 `280pt` への切り詰め退行を防止する。
- **根拠**: 画面要素が `AppKit` + `SwiftUI` で構成されており、`NSHostingView.fittingSize` と `NSWindow.contentView?.frame.size` を直接アサートすることでヘッドレス環境の `swift test` でも確実にレイアウト退行を検出できるため。
