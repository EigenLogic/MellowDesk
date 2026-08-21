#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DIST_DIR="${PROJECT_DIR}/dist"
APP_DIR="${PROJECT_DIR}/build/MellowDesk.app"
RELEASE_VERSION="${RELEASE_VERSION:-0.1.0-beta.7}"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-7}"
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
RELEASE_VERSION="${RELEASE_VERSION}" \
BUNDLE_IDENTIFIER="cn.eigenlogic.mellowdesk" \
APP_DISPLAY_NAME="小桌伴" \
BUNDLE_NAME="MellowDesk" \
"${SCRIPT_DIR}/build_app.sh"

APP_INFO_PLIST="${APP_DIR}/Contents/Info.plist"
assert_plist_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${APP_INFO_PLIST}")"
    if [[ "${actual}" != "${expected}" ]]; then
        print -u2 "发布包 ${key} 错误：期望 ${expected}，实际 ${actual}。"
        exit 1
    fi
}

assert_plist_value CFBundleIdentifier "cn.eigenlogic.mellowdesk"
assert_plist_value CFBundleDisplayName "小桌伴"
assert_plist_value CFBundleName "MellowDesk"
assert_plist_value CFBundleShortVersionString "${APP_VERSION}"
assert_plist_value CFBundleVersion "${BUILD_NUMBER}"
assert_plist_value MellowDeskReleaseVersion "${RELEASE_VERSION}"
assert_plist_value SUFeedURL "https://raw.githubusercontent.com/EigenLogic/MellowDesk/main/appcast.xml"
assert_plist_value SUPublicEDKey "D39NmgKuV3AeyCi8vyddX18UIDfr3Tq4yEDC3S+jlEc="
assert_plist_value SUEnableAutomaticChecks "true"
assert_plist_value SUAutomaticallyUpdate "true"
assert_plist_value SUAllowsAutomaticUpdates "true"
assert_plist_value SUEnableInstallerLauncherService "true"
assert_plist_value SUVerifyUpdateBeforeExtraction "true"
assert_plist_value SURequireSignedFeed "true"

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
SIGNATURE_DETAILS="$(/usr/bin/codesign -d --verbose=4 "${APP_DIR}" 2>&1)"
if [[ "${SIGNATURE_DETAILS}" != *"Authority=Developer ID Application:"* ]]; then
    print -u2 "App 未使用 Developer ID Application 签名。"
    exit 1
fi
if [[ "${SIGNATURE_DETAILS}" != *"Timestamp="* ]]; then
    print -u2 "App 签名缺少安全时间戳。"
    exit 1
fi
TEAM_IDENTIFIER="$(print -r -- "${SIGNATURE_DETAILS}" | /usr/bin/sed -n 's/^TeamIdentifier=//p')"
if [[ -z "${TEAM_IDENTIFIER}" ]]; then
    print -u2 "无法读取 App 的签名 TeamIdentifier。"
    exit 1
fi

assert_nested_signature() {
    local nested_path="$1"
    local nested_details
    nested_details="$(/usr/bin/codesign -d --verbose=4 "${nested_path}" 2>&1)"
    if [[ "${nested_details}" != *"Authority=Developer ID Application:"* ]]; then
        print -u2 "嵌套代码未使用 Developer ID Application 签名：${nested_path}"
        exit 1
    fi
    if [[ "${nested_details}" != *"TeamIdentifier=${TEAM_IDENTIFIER}"* ]]; then
        print -u2 "嵌套代码 TeamIdentifier 不一致：${nested_path}"
        exit 1
    fi
    if ! print -r -- "${nested_details}" | /usr/bin/grep -Eq 'flags=.*runtime'; then
        print -u2 "嵌套代码未启用 Hardened Runtime：${nested_path}"
        exit 1
    fi
    if [[ "${nested_details}" != *"Timestamp="* ]]; then
        print -u2 "嵌套代码签名缺少安全时间戳：${nested_path}"
        exit 1
    fi
    /usr/bin/codesign --verify --strict --verbose=2 "${nested_path}"
}

SPARKLE_FRAMEWORK="${APP_DIR}/Contents/Frameworks/Sparkle.framework"
assert_nested_signature "${SPARKLE_FRAMEWORK}/Versions/B/XPCServices/Installer.xpc"
assert_nested_signature "${SPARKLE_FRAMEWORK}/Versions/B/XPCServices/Downloader.xpc"
assert_nested_signature "${SPARKLE_FRAMEWORK}/Versions/B/Autoupdate"
assert_nested_signature "${SPARKLE_FRAMEWORK}/Versions/B/Updater.app"
assert_nested_signature "${SPARKLE_FRAMEWORK}"

APP_ENTITLEMENTS="$(/usr/bin/codesign -d --entitlements :- "${APP_DIR}" 2>/dev/null)"
print -r -- "${APP_ENTITLEMENTS}" | /usr/bin/grep -Fq 'cn.eigenlogic.mellowdesk-spks'
print -r -- "${APP_ENTITLEMENTS}" | /usr/bin/grep -Fq 'cn.eigenlogic.mellowdesk-spki'
if print -r -- "${APP_ENTITLEMENTS}" | /usr/bin/grep -Fq '__MELLOWDESK_BUNDLE_IDENTIFIER__'; then
    print -u2 "发布 App entitlements 仍含未展开 token。"
    exit 1
fi

if ! /usr/bin/lipo "${APP_DIR}/Contents/MacOS/MellowDesk" \
    -verify_arch arm64 x86_64; then
    print -u2 "发布二进制不是 arm64 + x86_64 universal build。"
    exit 1
fi
if ! /usr/bin/lipo "${SPARKLE_FRAMEWORK}/Versions/B/Sparkle" \
    -verify_arch arm64 x86_64; then
    print -u2 "Sparkle.framework 不是 arm64 + x86_64 universal build。"
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
