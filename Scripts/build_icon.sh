#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SOURCE_SVG="${PROJECT_DIR}/Resources/AppIcon.svg"
ICONSET_DIR="${PROJECT_DIR}/build/AppIcon.iconset"
MASTER_PNG="${PROJECT_DIR}/build/AppIcon-1024.png"
QUICKLOOK_DIR="${PROJECT_DIR}/build/AppIcon.quicklook"
OUTPUT_ICNS="${PROJECT_DIR}/Resources/AppIcon.icns"
README_PNG="${PROJECT_DIR}/docs/assets/app-icon.png"

MAGICK_BIN="$(command -v magick || true)"
if [[ -z "${MAGICK_BIN}" ]]; then
    print -u2 "需要 ImageMagick：brew install imagemagick"
    exit 1
fi

if [[ "${ICONSET_DIR}" != "${PROJECT_DIR}/build/AppIcon.iconset" \
    || "${QUICKLOOK_DIR}" != "${PROJECT_DIR}/build/AppIcon.quicklook" ]]; then
    print -u2 "拒绝清理未验证的图标构建目录。"
    exit 1
fi

/bin/rm -rf "${ICONSET_DIR}" "${QUICKLOOK_DIR}"
/bin/mkdir -p "${ICONSET_DIR}" "${QUICKLOOK_DIR}" "${PROJECT_DIR}/docs/assets"
/usr/bin/qlmanage -t -s 1024 -o "${QUICKLOOK_DIR}" "${SOURCE_SVG}" >/dev/null 2>&1
"${MAGICK_BIN}" "${QUICKLOOK_DIR}/AppIcon.svg.png" \
    -alpha on -fuzz 2% -transparent white "${MASTER_PNG}"

for size in 16 32 128 256 512; do
    /usr/bin/sips -z "${size}" "${size}" "${MASTER_PNG}" \
        --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    /usr/bin/sips -z "${retina_size}" "${retina_size}" "${MASTER_PNG}" \
        --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
done

/usr/bin/iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICNS}"
/bin/cp "${MASTER_PNG}" "${README_PNG}"
print "图标已生成：${OUTPUT_ICNS}"
