#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
cd "${PROJECT_DIR}"

/usr/bin/plutil -lint \
  Resources/Info.plist \
  Resources/MellowDesk.entitlements \
  Resources/PrivacyInfo.xcprivacy

if FORMATTER="$(xcrun --find swift-format 2>/dev/null)"; then
  "${FORMATTER}" lint --strict --recursive Sources Tests
fi

swift test

if CODE_SIGN_IDENTITY=- \
  BUNDLE_IDENTIFIER="cn.eigenlogic.mellowdesk" \
  APP_DISPLAY_NAME="小桌伴" \
  BUNDLE_NAME="MellowDesk" \
  "${SCRIPT_DIR}/build_app.sh"; then
  print -u2 "生产 bundle identifier 不得通过 ad-hoc 构建。"
  exit 1
fi

(
  unset BUNDLE_IDENTIFIER APP_DISPLAY_NAME BUNDLE_NAME
  "${SCRIPT_DIR}/build_app.sh"
)

APP_INFO_PLIST="${PROJECT_DIR}/build/MellowDesk.app/Contents/Info.plist"
assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${APP_INFO_PLIST}")"
  if [[ "${actual}" != "${expected}" ]]; then
    print -u2 "开发构建 ${key} 错误：期望 ${expected}，实际 ${actual}。"
    exit 1
  fi
}

assert_plist_value CFBundleIdentifier "cn.eigenlogic.mellowdesk.dev"
assert_plist_value CFBundleDisplayName "小桌伴 Dev"
assert_plist_value CFBundleName "MellowDesk Dev"
assert_plist_value CFBundleShortVersionString "0.1.0"
assert_plist_value CFBundleVersion "7"
assert_plist_value MellowDeskReleaseVersion "0.1.0-beta.7"
assert_plist_value SUFeedURL "https://raw.githubusercontent.com/EigenLogic/MellowDesk/main/appcast.xml"
assert_plist_value SUPublicEDKey "D39NmgKuV3AeyCi8vyddX18UIDfr3Tq4yEDC3S+jlEc="
assert_plist_value SUEnableAutomaticChecks "true"
assert_plist_value SUAutomaticallyUpdate "true"
assert_plist_value SUAllowsAutomaticUpdates "true"
assert_plist_value SUEnableInstallerLauncherService "true"
assert_plist_value SUEnableSystemProfiling "false"
assert_plist_value SUVerifyUpdateBeforeExtraction "true"
assert_plist_value SURequireSignedFeed "true"
assert_plist_value SUScheduledCheckInterval "86400"

APP_DIR="${PROJECT_DIR}/build/MellowDesk.app"
APP_EXECUTABLE="${APP_DIR}/Contents/MacOS/MellowDesk"
SPARKLE_FRAMEWORK="${APP_DIR}/Contents/Frameworks/Sparkle.framework"
APP_ENTITLEMENTS="$(/usr/bin/codesign -d --entitlements :- "${APP_DIR}" 2>/dev/null)"

print -r -- "${APP_ENTITLEMENTS}" | /usr/bin/grep -Fq 'cn.eigenlogic.mellowdesk.dev-spks'
print -r -- "${APP_ENTITLEMENTS}" | /usr/bin/grep -Fq 'cn.eigenlogic.mellowdesk.dev-spki'
if print -r -- "${APP_ENTITLEMENTS}" | /usr/bin/grep -Fq '__MELLOWDESK_BUNDLE_IDENTIFIER__'; then
  print -u2 "开发构建 entitlements 仍含未展开 token。"
  exit 1
fi

[[ -L "${SPARKLE_FRAMEWORK}/Versions/Current" ]]
/usr/bin/codesign --verify --strict --verbose=2 \
  "${SPARKLE_FRAMEWORK}/Versions/B/XPCServices/Installer.xpc" \
  "${SPARKLE_FRAMEWORK}/Versions/B/XPCServices/Downloader.xpc" \
  "${SPARKLE_FRAMEWORK}/Versions/B/Updater.app" \
  "${SPARKLE_FRAMEWORK}"
/usr/bin/otool -L "${APP_EXECUTABLE}" | /usr/bin/grep -Fq '@rpath/Sparkle.framework/'
/usr/bin/otool -l "${APP_EXECUTABLE}" | /usr/bin/grep -Fq '@executable_path/../Frameworks'
/usr/bin/grep -Eq '"version"[[:space:]]*:[[:space:]]*"2\.9\.5"' Package.resolved
