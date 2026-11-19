#!/usr/bin/env bash
# Wintch.dmg ディスクイメージ組み立てスクリプト
# 組み立て済みの .app バンドルと /Applications シンボリックリンクを含む圧縮読み取り専用 DMG を作成する
# 使用例: ./scripts/build-dmg.sh [--app <app_path>] [--output <dmg_path>] [--volname <volume_name>]

set -euo pipefail

# スクリプトのあるディレクトリからリポジトリルートへ移動する
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

APP_BUNDLE="${REPO_ROOT}/.build/Wintch.app"
OUTPUT_DMG=""
VOLUME_NAME=""

# 使用法を表示する関数
usage() {
    cat <<EOF
使用法: $0 [オプション]
  --app <path>      入力となる .app バンドルのパス（既定: ./.build/Wintch.app）
  --output <path>   出力する .dmg ファイルのパス（既定: ./.build/Wintch-v<VERSION>.dmg）
  --volname <name>  DMG マウント時のボリューム名（既定: バンドル名）
  -h, --help        このヘルプを表示
EOF
}

# コマンドライン引数を解析する
while [ $# -gt 0 ]; do
    case "$1" in
        --app)
            if [ $# -lt 2 ]; then
                echo "[Wintch] エラー: --app の引数が不足しています" >&2
                exit 1
            fi
            APP_BUNDLE="$2"
            shift 2
            ;;
        --output)
            if [ $# -lt 2 ]; then
                echo "[Wintch] エラー: --output の引数が不足しています" >&2
                exit 1
            fi
            OUTPUT_DMG="$2"
            shift 2
            ;;
        --volname)
            if [ $# -lt 2 ]; then
                echo "[Wintch] エラー: --volname の引数が不足しています" >&2
                exit 1
            fi
            VOLUME_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[Wintch] エラー: 不明な引数です ($1)" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# 入力 .app バンドルの存在を検証する
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "[Wintch] エラー: .app バンドルが見つかりません (${APP_BUNDLE})" >&2
    exit 1
fi

APP_BUNDLE_NAME="$(basename "${APP_BUNDLE}")"
APP_DISPLAY_BASE="${APP_BUNDLE_NAME%.app}"

# 出力 DMG パスが未指定の場合は VERSION ファイルから既定パスを解決する
if [ -z "${OUTPUT_DMG}" ]; then
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
    OUTPUT_DMG="${REPO_ROOT}/.build/Wintch-v${APP_VERSION}.dmg"
fi

# ボリューム名が未指定の場合は .app バンドル名（拡張子なし）を使用する
if [ -z "${VOLUME_NAME}" ]; then
    VOLUME_NAME="${APP_DISPLAY_BASE}"
fi

# 必須コマンドの存在を確認する
for cmd in hdiutil ditto; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "[Wintch] エラー: ${cmd} コマンドが見つかりません" >&2
        exit 1
    fi
done

# ステージング用の一時ディレクトリを作成し、終了時に必ず削除する
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGE_DIR}"' EXIT

echo "[Wintch] DMG ステージング領域を構築しています (${APP_BUNDLE_NAME} + /Applications)..."
# コード署名・拡張属性・公証チケットを保持するため ditto でバンドルを複製する
ditto "${APP_BUNDLE}" "${STAGE_DIR}/${APP_BUNDLE_NAME}"
ln -s /Applications "${STAGE_DIR}/Applications"

OUTPUT_DIR="$(dirname "${OUTPUT_DMG}")"
mkdir -p "${OUTPUT_DIR}"
rm -f "${OUTPUT_DMG}"

echo "[Wintch] 圧縮読み取り専用 DMG (UDZO) を作成しています (${OUTPUT_DMG})..."
hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGE_DIR}" \
    -ov \
    -format UDZO \
    "${OUTPUT_DMG}"

if [ ! -f "${OUTPUT_DMG}" ]; then
    echo "[Wintch] エラー: DMG ファイルの生成に失敗しました (${OUTPUT_DMG})" >&2
    exit 1
fi

# Developer ID 署名識別子が指定されている場合は DMG 本体にも署名と検証を実施する
if [ -n "${WINTCH_SIGN_IDENTITY:-}" ]; then
    if ! command -v codesign >/dev/null 2>&1; then
        echo "[Wintch] エラー: codesign コマンドが見つかりません" >&2
        exit 1
    fi
    echo "[Wintch] DMG に Developer ID 署名を適用しています..."
    codesign --force --timestamp \
        --sign "${WINTCH_SIGN_IDENTITY}" \
        "${OUTPUT_DMG}"
    codesign --verify --strict --verbose=2 "${OUTPUT_DMG}"
fi

echo "[Wintch] 完了: ${OUTPUT_DMG} (volume: ${VOLUME_NAME})"
