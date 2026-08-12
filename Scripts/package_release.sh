#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DIST_DIR="${PROJECT_DIR}/dist"
APP_DIR="${PROJECT_DIR}/build/MellowDesk.app"
RELEASE_VERSION="${RELEASE_VERSION:-0.1.0-beta.2}"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:?Set CODE_SIGN_IDENTITY to a Developer ID Application identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
ALLOW_UNNOTARIZED="${ALLOW_UNNOTARIZED:-0}"
ARCHIVE_NAME="MellowDesk-${RELEASE_VERSION}-macOS-universal.zip"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"

if [[ "${APP_DIR}" != "${PROJECT_DIR}/build/MellowDesk.app" ]]; then
    print -u2 "拒绝处理未验证的 App 路径：${APP_DIR}"
    exit 1
fi

if [[ -z "${NOTARY_PROFILE}" && "${ALLOW_UNNOTARIZED}" != "1" ]]; then
    print -u2 "NOTARY_PROFILE 未设置；公开发布包必须完成 Apple 公证。"
    print -u2 "仅本地测试时可显式设置 ALLOW_UNNOTARIZED=1。"
    exit 1
fi

/bin/mkdir -p "${DIST_DIR}"

CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY}" \
UNIVERSAL_BUILD=1 \
APP_VERSION="${APP_VERSION}" \
BUILD_NUMBER="${BUILD_NUMBER}" \
"${SCRIPT_DIR}/build_app.sh"

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
SIGNATURE_DETAILS="$(/usr/bin/codesign -d --verbose=4 "${APP_DIR}" 2>&1)"
if [[ "${SIGNATURE_DETAILS}" != *"Authority=Developer ID Application:"* ]]; then
    print -u2 "App 未使用 Developer ID Application 签名。"
    exit 1
fi

if ! /usr/bin/lipo "${APP_DIR}/Contents/MacOS/MellowDesk" \
    -verify_arch arm64 x86_64; then
    print -u2 "发布二进制不是 arm64 + x86_64 universal build。"
    exit 1
fi

/bin/rm -f "${ARCHIVE_PATH}" "${CHECKSUM_PATH}"
/usr/bin/ditto -c -k --keepParent "${APP_DIR}" "${ARCHIVE_PATH}"

if [[ -n "${NOTARY_PROFILE}" ]]; then
    /usr/bin/xcrun notarytool submit "${ARCHIVE_PATH}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait
    /usr/bin/xcrun stapler staple "${APP_DIR}"
    /usr/bin/xcrun stapler validate "${APP_DIR}"
    /usr/sbin/spctl --assess --type execute --verbose=4 "${APP_DIR}"

    /bin/rm -f "${ARCHIVE_PATH}"
    /usr/bin/ditto -c -k --keepParent "${APP_DIR}" "${ARCHIVE_PATH}"
else
    print -u2 "本地测试候选：已显式允许跳过 Apple 公证，不得上传为公开 Release。"
fi

cd "${DIST_DIR}"
/usr/bin/shasum -a 256 "${ARCHIVE_NAME}" > "${ARCHIVE_NAME}.sha256"
/usr/bin/lipo -info "${APP_DIR}/Contents/MacOS/MellowDesk"
print "发布候选：${ARCHIVE_PATH}"
print "校验文件：${CHECKSUM_PATH}"
