# Swift 6.0 コーディング規約 (Swift Coding Rules)

Wintch プロジェクトで Swift ソースコードを記述・修正する際の必須ルールです。

## 1. Swift 6.0 と Strict Concurrency

- `Package.swift` は `swift-tools-version: 6.0` を前提とする。
- データ競合を防ぐため、`@MainActor` とバックグラウンド処理（`Task.detached`, `CGEventTap` スレッド、`AXUIElement` IPC ワーカーキュー、`ScreenCaptureKit` 非同期コールバック）の境界を明確に分離し、`Sendable` 準拠を保つ。
- C コールバックやシステムコールバックからクロージャ・参照を受け渡す際は、`@MainActor` 分離違反によるランタイムクラッシュが起きないよう注意する（例: `NSWorkspace.openApplication` への `completionHandler` 渡しによる実行キュー不一致に注意）。

## 2. アーキテクチャおよびレイヤー境界

- **状態管理**: ViewModel および Coordinator には `@Observable` と `@MainActor` を使用する。レガシーな `ObservableObject` / `@Published` は使用しない。
- **低レイヤー API の隔離**: `CGWindowListCopyWindowInfo`、`AXUIElement`、`AXObserver`、`CGEventTap`、`Carbon` ホットキー、`ScreenCaptureKit`、`NSWorkspace` などの OS 依存処理はすべて `Sources/WintchCore/Services/` に隔離し、`Views/` や `ViewModels/` から直接呼び出さない。
- **純粋ロジックの分離**: フィルタリング・ソート・ファジー検索・選択インデックス計算・グリッド配置・ショートカット競合判定・プロファイル判定などのビジネスロジックは `Sources/WintchCore/Domain/` に純粋関数または `Equatable & Sendable` な値型として切り出し、ユニットテスト可能に保つ。
- **依存性注入**: `Services/` の具象型は `Services/Protocols/` に定義したプロトコルへ準拠させ、`AppCoordinator` および ViewModel はプロトコル型経由で依存を注入してモックテスト可能にする。
- **外部ライブラリ禁止・非公開 API 禁止**: サードパーティ依存の追加や `CGS*` 等の非公開 API の使用は厳禁。

## 3. コメントとドキュメンテーション（日本語必須）

- **コメントの日本語化**: ソースコード内のすべてのコメント（インラインコメント、ブロックコメント、`MARK` コメントの説明文）は**必ず日本語**で記述する。
- **ドキュメントコメントの必須化**: すべての `class`、`struct`、`enum`、`protocol`、`func`、`init`、公開プロパティには SwiftDoc 形式（`///`）で日本語のドキュメントコメントを記述する。
- **記述内容**: 関数・メソッド・イニシャライザのドキュメントコメントには、概要説明、`- Parameter <引数名>:`（または `- Parameters:`）、`- Returns:`（戻り値がある場合）を漏れなく日本語で記載する。

### 良い例

```swift
/// 指定されたウィンドウ候補がスイッチャー表示対象として有効か判定する
/// - Parameter candidate: 判定対象の生ウィンドウ候補
/// - Returns: 表示対象とする場合は true
public static func isValid(_ candidate: RawWindowCandidate) -> Bool {
    // 最小サイズ未満のノイズ要素を早期除外する
    guard candidate.bounds.width >= minimumDimension else { return false }
    return true
}
```

## 4. コード品質と保守性

- **重複排除**: 検索・ハイライト、行構築、パネルスタイル（ボーダーやマテリアル等）などのロジックが複数箇所で重複しないよう、共通ヘルパー・共通型へ抽出する。
- **単一責務・浅いネスト**: 関数は単一責務に保ち、早期リターン（`guard`）を用いてネストを浅く保つ。
- **過度な抽象化の回避**: 複雑な独自ジェネリクスや自作マクロは避け、標準的で読みやすい Swift コードを書く。
- **アプリ別分岐の宣言的管理**: 特定アプリ（メモ、システム設定、Chrome 等）のウィンドウ収集特性を扱う場合は、手続き的な `if bundleID == ...` を各所へ散在させず、`AppWindowProfileRegistry` の宣言的プロファイルとして集約する。
