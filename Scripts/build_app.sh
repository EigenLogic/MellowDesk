#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
BUILD_ROOT="${PROJECT_DIR}/build"
APP_NAME="MellowDesk"
APP_DIR="${BUILD_ROOT}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
UNIVERSAL_BUILD="${UNIVERSAL_BUILD:-0}"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"

if [[ "${APP_DIR}" != "${PROJECT_DIR}/build/MellowDesk.app" ]]; then
    print -u2 "拒绝清理未验证的构建目录：${APP_DIR}"
    exit 1
fi

cd "${PROJECT_DIR}"
export MACOSX_DEPLOYMENT_TARGET=13.0

SWIFT_BUILD_ARGS=(-c release --product "${APP_NAME}")
if [[ "${UNIVERSAL_BUILD}" == "1" ]]; then
    SWIFT_BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

swift build "${SWIFT_BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"

/bin/rm -rf "${APP_DIR}"
/bin/mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources"
/bin/cp "${BIN_DIR}/${APP_NAME}" "${CONTENTS_DIR}/MacOS/${APP_NAME}"
/bin/cp "${PROJECT_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
/bin/cp "${PROJECT_DIR}/Resources/PrivacyInfo.xcprivacy" "${CONTENTS_DIR}/Resources/PrivacyInfo.xcprivacy"
/bin/cp "${PROJECT_DIR}/LICENSE" "${CONTENTS_DIR}/Resources/LICENSE.txt"
/bin/cp "${PROJECT_DIR}/NOTICE" "${CONTENTS_DIR}/Resources/NOTICE.txt"
if [[ -f "${PROJECT_DIR}/Resources/AppIcon.icns" ]]; then
    /bin/cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${CONTENTS_DIR}/Resources/AppIcon.icns"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"

CODESIGN_ARGS=(--force --sign "${CODE_SIGN_IDENTITY}")
if [[ "${CODE_SIGN_IDENTITY}" != "-" ]]; then
    CODESIGN_ARGS+=(--options runtime --timestamp)
fi

/usr/bin/codesign \
    "${CODESIGN_ARGS[@]}" \
    --entitlements "${PROJECT_DIR}/Resources/MellowDesk.entitlements" \
    "${APP_DIR}"

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
print "构建完成：${APP_DIR}"
