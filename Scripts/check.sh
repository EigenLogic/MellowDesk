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
"${SCRIPT_DIR}/build_app.sh"
