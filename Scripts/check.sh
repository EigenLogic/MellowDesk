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
