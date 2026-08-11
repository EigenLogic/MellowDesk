#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"

"${SCRIPT_DIR}/build_app.sh"
/usr/bin/open "${PROJECT_DIR}/build/MellowDesk.app"
