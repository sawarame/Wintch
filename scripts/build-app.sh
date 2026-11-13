#!/usr/bin/env bash
# Wintch.app バンドル組み立てスクリプト
# swift build の実行バイナリを macOS アプリケーションバンドル (.app) 形式にパッケージ化する

set -euo pipefail

# スクリプトのあるディレクトリからリポジトリルートへ移動する
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

CONFIGURATION="${1:-debug}"
APP_NAME="Wintch"
APP_BUNDLE="${REPO_ROOT}/.build/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "[Wintch] ビルドを実行しています (${CONFIGURATION})..."
swift build -c "${CONFIGURATION}"

BIN_PATH="$(swift build -c "${CONFIGURATION}" --show-bin-path)"
EXECUTABLE_PATH="${BIN_PATH}/${APP_NAME}"

if [ ! -f "${EXECUTABLE_PATH}" ]; then
    echo "[Wintch] エラー: 実行バイナリが見つかりません (${EXECUTABLE_PATH})" >&2
    exit 1
fi

echo "[Wintch] .app バンドルを組み立てています..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"
cp "${REPO_ROOT}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

# メニューバー用 SVG アイコンをバンドルリソースへ配置する
if [ -f "${REPO_ROOT}/Resources/Icons/MenuBarIcon.svg" ]; then
    cp "${REPO_ROOT}/Resources/Icons/MenuBarIcon.svg" "${RESOURCES_DIR}/MenuBarIcon.svg"
fi

# AppIcon.svg から macOS 標準アイコン (.icns) を生成して組み込む
APP_ICON_SVG="${REPO_ROOT}/Resources/Icons/AppIcon.svg"
if [ -f "${APP_ICON_SVG}" ] && command -v qlmanage >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
    echo "[Wintch] アプリアイコン (AppIcon.icns) を生成しています..."
    ICON_TMP_DIR="$(mktemp -d)"
    ICONSET_DIR="${ICON_TMP_DIR}/AppIcon.iconset"
    mkdir -p "${ICONSET_DIR}"

    qlmanage -t -s 1024 -o "${ICON_TMP_DIR}" "${APP_ICON_SVG}" >/dev/null 2>&1
    BASE_PNG="${ICON_TMP_DIR}/AppIcon.svg.png"

    if [ -f "${BASE_PNG}" ]; then
        sips -z 16 16     "${BASE_PNG}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
        sips -z 32 32     "${BASE_PNG}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
        sips -z 32 32     "${BASE_PNG}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
        sips -z 64 64     "${BASE_PNG}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
        sips -z 128 128   "${BASE_PNG}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
        sips -z 256 256   "${BASE_PNG}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
        sips -z 256 256   "${BASE_PNG}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
        sips -z 512 512   "${BASE_PNG}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
        sips -z 512 512   "${BASE_PNG}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
        cp "${BASE_PNG}"               "${ICONSET_DIR}/icon_512x512@2x.png"
        iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
    fi
    rm -rf "${ICON_TMP_DIR}"
fi

# アドホック署名を付与してローカル実行・アクセシビリティ権限登録を安定させる
if command -v codesign >/dev/null 2>&1; then
    echo "[Wintch] アドホック署名を適用しています..."
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi

echo "[Wintch] 完了: ${APP_BUNDLE}"
