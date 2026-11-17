# 検証ガイド (Quickstart): 設定画面等の最前面表示修正

**Feature**: `015-fix-settings-frontmost` | **Date**: 2026-11-17

## 1. 自動ユニットテストの実行

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

期待結果：
- `WindowFrontPresenterTests`（配置計算・`WindowFrontPresenter` の同期／非同期動作・最小化解除・スペース設定・通常レベル維持）がすべて成功すること。
- `AppCoordinatorTests`（`openSettings` / `openAbout` / `openPermissionGuide` / 権限剥奪時表示での `WindowFrontPresenting` 呼び出し）および既存全テストがすべて成功すること。

## 2. アプリバンドルビルド

```bash
./scripts/build-app.sh
```

期待結果：
- ビルド警告・エラーなく `.build/Wintch.app` が生成されること。

## 3. 実機手動検証シナリオ（Issue #18 再現手順ベース）

1. `.build/Wintch.app` を起動し、メニューバーに Wintch アイコンが表示され、Dock にアイコンが出ないことを確認する。
2. 任意の他アプリ（Safari や Terminal、Xcode 等）のウィンドウを画面前面・中央に大きく表示し、そのアプリをアクティブにする。
3. メニューバーの Wintch アイコンをクリックし、「設定を開く...」を選択する。
   - **期待**: Wintch の設定画面が他アプリのウィンドウより一番手前に表示され、タイトルバーがアクティブ状態で即座に操作できる。Dock アイコンは増えない。
4. 設定画面内のボタンからシステム設定を開く、または背後の他アプリをクリックする。
   - **期待**: システム設定や他アプリが自然に手前へ切り替わる（設定画面が最前面に居座り続けない）。
5. 設定画面が背後に隠れた状態で、再度メニューバーから「設定を開く...」を選択する。
   - **期待**: 設定画面が再び一番手前に表示される。
6. 同様に「Wintchについて」および（権限未許可環境での）権限誘導画面も一番手前に表示されることを確認する。
7. 別の操作スペース（仮想デスクトップ）へ移動した状態で「設定を開く...」を実行し、現在のスペースの手前に設定画面が表示されることを確認する。
