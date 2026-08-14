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
BUILD_NUMBER="${BUILD_NUMBER:-4}"
RELEASE_VERSION="${RELEASE_VERSION:-0.1.0-beta.4}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-cn.eigenlogic.mellowdesk.dev}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-小桌伴 Dev}"
BUNDLE_NAME="${BUNDLE_NAME:-MellowDesk Dev}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://raw.githubusercontent.com/EigenLogic/MellowDesk/main/appcast.xml}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-D39NmgKuV3AeyCi8vyddX18UIDfr3Tq4yEDC3S+jlEc=}"
DERIVED_ENTITLEMENTS="${BUILD_ROOT}/MellowDesk.build.entitlements"

if [[ -z "${RELEASE_VERSION}" || -z "${BUNDLE_IDENTIFIER}" || -z "${APP_DISPLAY_NAME}" || -z "${BUNDLE_NAME}" || -z "${SPARKLE_FEED_URL}" || -z "${SPARKLE_PUBLIC_KEY}" ]]; then
    print -u2 "App 身份配置不能为空。"
    exit 1
fi

if [[ "${BUNDLE_IDENTIFIER}" == "cn.eigenlogic.mellowdesk" && "${CODE_SIGN_IDENTITY}" == "-" ]]; then
    print -u2 "拒绝使用 ad-hoc 签名构建生产 bundle identifier。"
    exit 1
fi

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
SPARKLE_FRAMEWORK_SOURCE="${PROJECT_DIR}/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

if [[ ! -d "${SPARKLE_FRAMEWORK_SOURCE}" ]]; then
    print -u2 "未找到 Sparkle.framework：${SPARKLE_FRAMEWORK_SOURCE}"
    exit 1
fi

/bin/rm -rf "${APP_DIR}"
/bin/mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources" "${CONTENTS_DIR}/Frameworks"
/bin/cp "${BIN_DIR}/${APP_NAME}" "${CONTENTS_DIR}/MacOS/${APP_NAME}"
/usr/bin/ditto "${SPARKLE_FRAMEWORK_SOURCE}" "${CONTENTS_DIR}/Frameworks/Sparkle.framework"
/bin/cp "${PROJECT_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
/bin/cp "${PROJECT_DIR}/Resources/PrivacyInfo.xcprivacy" "${CONTENTS_DIR}/Resources/PrivacyInfo.xcprivacy"
/bin/cp "${PROJECT_DIR}/LICENSE" "${CONTENTS_DIR}/Resources/LICENSE.txt"
/bin/cp "${PROJECT_DIR}/NOTICE" "${CONTENTS_DIR}/Resources/NOTICE.txt"
if [[ -f "${PROJECT_DIR}/Resources/AppIcon.icns" ]]; then
    /bin/cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${CONTENTS_DIR}/Resources/AppIcon.icns"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :MellowDeskReleaseVersion ${RELEASE_VERSION}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_IDENTIFIER}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${APP_DISPLAY_NAME}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${BUNDLE_NAME}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL ${SPARKLE_FEED_URL}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${SPARKLE_PUBLIC_KEY}" "${CONTENTS_DIR}/Info.plist"

if ! /usr/bin/otool -l "${CONTENTS_DIR}/MacOS/${APP_NAME}" | rg -q '@executable_path/../Frameworks'; then
    /usr/bin/install_name_tool -add_rpath '@executable_path/../Frameworks' "${CONTENTS_DIR}/MacOS/${APP_NAME}"
fi

/bin/cp "${PROJECT_DIR}/Resources/MellowDesk.entitlements" "${DERIVED_ENTITLEMENTS}"
/usr/libexec/PlistBuddy \
    -c "Set :com.apple.security.temporary-exception.mach-lookup.global-name:0 ${BUNDLE_IDENTIFIER}-spks" \
    -c "Set :com.apple.security.temporary-exception.mach-lookup.global-name:1 ${BUNDLE_IDENTIFIER}-spki" \
    "${DERIVED_ENTITLEMENTS}"

if rg -q '__MELLOWDESK_BUNDLE_IDENTIFIER__' "${DERIVED_ENTITLEMENTS}"; then
    print -u2 "派生 entitlements 仍包含未展开的 bundle identifier。"
    exit 1
fi

CODESIGN_ARGS=(--force --sign "${CODE_SIGN_IDENTITY}")
if [[ "${CODE_SIGN_IDENTITY}" != "-" ]]; then
    CODESIGN_ARGS+=(--options runtime --timestamp)
fi

/usr/bin/codesign \
    "${CODESIGN_ARGS[@]}" \
    "${CONTENTS_DIR}/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
/usr/bin/codesign \
    "${CODESIGN_ARGS[@]}" \
    --preserve-metadata=entitlements \
    "${CONTENTS_DIR}/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
/usr/bin/codesign \
    "${CODESIGN_ARGS[@]}" \
    "${CONTENTS_DIR}/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
/usr/bin/codesign \
    "${CODESIGN_ARGS[@]}" \
    "${CONTENTS_DIR}/Frameworks/Sparkle.framework/Versions/B/Updater.app"
/usr/bin/codesign \
    "${CODESIGN_ARGS[@]}" \
    "${CONTENTS_DIR}/Frameworks/Sparkle.framework"
/usr/bin/codesign \
    "${CODESIGN_ARGS[@]}" \
    --entitlements "${DERIVED_ENTITLEMENTS}" \
    "${APP_DIR}"

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
/usr/bin/otool -L "${CONTENTS_DIR}/MacOS/${APP_NAME}" | rg -q '@rpath/Sparkle.framework/'
[[ -L "${CONTENTS_DIR}/Frameworks/Sparkle.framework/Versions/Current" ]]
print "构建完成：${APP_DIR}"
