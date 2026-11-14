#!/usr/bin/env bash
# Wintch.app バンドル組み立てスクリプト
# swift build の実行バイナリを macOS アプリケーションバンドル (.app) 形式にパッケージ化する
# 使用例: ./scripts/build-app.sh [debug|release] [--universal]

set -euo pipefail

# スクリプトのあるディレクトリからリポジトリルートへ移動する
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

CONFIGURATION="debug"
IS_UNIVERSAL="${WINTCH_UNIVERSAL:-false}"

# コマンドライン引数を解析する
for arg in "$@"; do
    case "${arg}" in
        debug|release)
            CONFIGURATION="${arg}"
            ;;
        --universal)
            IS_UNIVERSAL="true"
            ;;
        *)
            echo "[Wintch] エラー: 不明な引数です (${arg})" >&2
            echo "使用法: $0 [debug|release] [--universal]" >&2
            exit 1
            ;;
    esac
done

# VERSION ファイルからセマンティックバージョンを読み取り検証する
VERSION_FILE="${REPO_ROOT}/VERSION"
if [ ! -f "${VERSION_FILE}" ]; then
    echo "[Wintch] エラー: VERSION ファイルが見つかりません (${VERSION_FILE})" >&2
    exit 1
fi

APP_VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
SEMVER_REGEX='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
if [[ ! "${APP_VERSION}" =~ ${SEMVER_REGEX} ]]; then
    echo "[Wintch] エラー: VERSION の値がセマンティックバージョニング形式ではありません (${APP_VERSION})" >&2
    exit 1
fi

# Git コミット数をビルド番号として算出し、取得できない場合は 1 へフォールバックする
if BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null)" && [[ "${BUILD_NUMBER}" =~ ^[1-9][0-9]*$ ]]; then
    :
else
    BUILD_NUMBER="1"
fi

APP_NAME="Wintch"
APP_BUNDLE="${REPO_ROOT}/.build/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# アーキテクチャ指定に応じて swift build の引数を組み立てる
SWIFT_BUILD_ARGS=(-c "${CONFIGURATION}")
ARCH_LABEL="native"
if [ "${IS_UNIVERSAL}" = "true" ]; then
    SWIFT_BUILD_ARGS+=(--arch arm64 --arch x86_64)
    ARCH_LABEL="universal (arm64 + x86_64)"
fi

echo "[Wintch] ビルドを実行しています (${CONFIGURATION}, ${ARCH_LABEL}, v${APP_VERSION} [${BUILD_NUMBER}])..."
swift build "${SWIFT_BUILD_ARGS[@]}"

BIN_PATH="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
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

# バンドル内の Info.plist にのみバージョンとビルド番号を反映する（元ファイルは変更しない）
if [ -x "/usr/libexec/PlistBuddy" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "${CONTENTS_DIR}/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"
else
    echo "[Wintch] エラー: /usr/libexec/PlistBuddy が見つかりません" >&2
    exit 1
fi

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

echo "[Wintch] 完了: ${APP_BUNDLE} (v${APP_VERSION}, build ${BUILD_NUMBER})"
