# 技術調査・設計判断レポート (Research): 画面収録権限未許可時のスイッチャー内設定リンク削除

**Feature**: `017-remove-switcher-permission-link` | **Date**: 2026-11-17 | **Related Issue**: [#23](https://github.com/sawarame/Wintch/issues/23)

## 1. 現状の調査結果

### 対象箇所の特定
コードベース全体を検索した結果、スイッチャー表示中に画面収録権限の設定画面へ遷移するリンクおよび関連処理は以下の箇所にのみ存在することを確認した。

1. [SwitcherCaptureGridView.swift](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/Views/SwitcherCaptureGridView.swift)
   - `permissionBannerView`（97〜119行目）内の `Button("設定を開く") { viewModel.openScreenRecordingSettings() }`（`.buttonStyle(.link)`）。
2. [SwitcherViewModel.swift](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/ViewModels/SwitcherViewModel.swift)
   - `onOpenScreenRecordingSettingsRequested: (() -> Void)?`（116行目）
   - `openScreenRecordingSettings()`（238〜242行目）
3. [SwitcherViewModelTests.swift](file:///Users/sawarame_yasushi/dev/Wintch/Tests/WintchCoreTests/SwitcherViewModelTests.swift)
   - `captureStyleFallbackSessionSafetyAndOptInIsolation()`（1092〜1099行目）の `openScreenRecordingSettings()` 呼び出し検証。

なお、設定画面（[SettingsView.swift](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/Views/SettingsView.swift) および [SettingsViewModel.swift](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/ViewModels/SettingsViewModel.swift)）の「システム設定を開く」導線は独立ウィンドウ上でマウス操作可能であるため、本変更の対象外であり影響を受けない。また、リスト型スイッチャー（[SwitcherListView.swift](file:///Users/sawarame_yasushi/dev/Wintch/Sources/WintchCore/Views/SwitcherListView.swift)）には画面収録権限に関する表示・リンクは存在しない。

## 2. 設計上の決定事項

### Decision 1: スイッチャーパネル上の設定リンクのみを削除し、非インタラクティブな案内バナーは維持する
- **決定**: `SwitcherCaptureGridView.permissionBannerView` から `Button("設定を開く")` および `Spacer(minLength: 4)` を削除し、警告アイコンと説明テキスト（「画面収録権限が未許可のためプレースホルダーを表示しています」）のみの非インタラクティブ表示とする。
- **根拠**:
  - Issue #23 の指摘（「Option+Tab で両手が塞がっているためリンクをクリックすることは不可能なので、リンクをなくす」）に直接対応するため。
  - 案内バナー自体（なぜキャプチャではなくアプリアイコンのプレースホルダーが表示されているかの説明）を残すことで、Wintch 憲章 v2.0.0 の原則5（権限未許可環境でも分かりやすい案内により安全に切り替えを継続できること）を満たせるため。
- **検討した代替案**:
  - `permissionBannerView` を丸ごと削除する案 → ユーザーがキャプチャ表示型を選択したにもかかわらずサムネイルが出ない理由が分からなくなるため不採用。
  - 案内文に「設定画面から〜」等を長々と追記する案 → Issue #23 の趣旨（リンクをなくすこと）を超えた過剰な変更を避け、コンパクトさを維持するため既存の明快な文言をそのまま保持する。

### Decision 2: テキストの途中省略防止と左寄せレイアウトの維持
- **決定**: `permissionBannerView` の `Text` に対して `.fixedSize(horizontal: false, vertical: true)` および `.frame(maxWidth: .infinity, alignment: .leading)` を適用し、`.lineLimit(1)` / `.truncationMode(.tail)` による途中省略をなくす。
- **根拠**: 1 枚のみの表示時（パネル最小幅 `360pt`）でも、リンク削除後のテキストが途中で `...` に切り詰められるのを防ぎ、複数枚表示時（`470pt` 以上）でも左寄せで自然なレイアウトを保つため。

### Decision 3: `SwitcherViewModel` から不要な導線（Dead Code）を削除する
- **決定**: `SwitcherViewModel` の `openScreenRecordingSettings()` および `onOpenScreenRecordingSettingsRequested` を削除する。`screenRecordingPermissionService` 自体は `currentStatus()` の確認に引き続き必要なため保持する。
- **根拠**: 呼び出し元が `SwitcherCaptureGridView` のみに限定されていたため、廃止後に残すと誤用や不要なメンテナンス負債となる。`ScreenRecordingPermissionServicing.openSystemSettings()` は `SettingsViewModel` 側で引き続き使用される。
- **検討した代替案**:
  - `SwitcherViewModel.openScreenRecordingSettings()` を互換のために残す案 → パブリックに使う箇所が存在せず、Issue により明示的に廃止された導線であるため削除する方が簡潔（憲章「シンプルさの徹底」にも合致）。

### Decision 4: 検証戦略
- **決定**:
  1. `SwitcherCaptureGridView` のバナーテキスト定数・レイアウトにおいてクリック可能なボタン要素が存在しないこと、および `NSHostingView` 上でアクセシビリティ／コントロール要素としての設定ボタンが生成されないこと・テキスト高さが圧縮されないことを Swift Testing で検証する。
  2. `SwitcherViewModelTests` から削除された `openScreenRecordingSettings()` のテスト記述を整理し、権限未許可フォールバック動作（プレースホルダー表示のまま選択・確定・キャンセル可能であること）が維持されることを検証する。
  3. `SettingsViewModelTests` にて設定画面側の「システム設定を開く」機能が変更なく動作することを回帰確認する。
