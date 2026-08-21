#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DIST_DIR="${PROJECT_DIR}/dist"
RELEASE_VERSION="${RELEASE_VERSION:-0.1.0-beta.7}"
BUILD_NUMBER="${BUILD_NUMBER:-7}"
TAG_NAME="v${RELEASE_VERSION}"
ARCHIVE_NAME="MellowDesk-${RELEASE_VERSION}-macOS-universal.zip"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"
RELEASE_NOTES_PATH="${PROJECT_DIR}/docs/releases/v${RELEASE_VERSION}.md"
APPCAST_PATH="${PROJECT_DIR}/appcast.xml"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-mellowdesk}"
GENERATE_APPCAST="${PROJECT_DIR}/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
DOWNLOAD_URL_PREFIX="https://github.com/EigenLogic/MellowDesk/releases/download/${TAG_NAME}/"

for required_path in \
    "${ARCHIVE_PATH}" \
    "${CHECKSUM_PATH}" \
    "${RELEASE_NOTES_PATH}" \
    "${GENERATE_APPCAST}"; do
    if [[ ! -e "${required_path}" ]]; then
        print -u2 "生成 appcast 缺少文件：${required_path}"
        exit 1
    fi
done

(cd "${DIST_DIR}" && /usr/bin/shasum -a 256 -c "${ARCHIVE_NAME}.sha256")

STAGING_DIR="$(/usr/bin/mktemp -d /tmp/mellowdesk-appcast.XXXXXX)"
cleanup() {
    /bin/rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT

/bin/cp "${ARCHIVE_PATH}" "${STAGING_DIR}/${ARCHIVE_NAME}"
/bin/cp \
    "${RELEASE_NOTES_PATH}" \
    "${STAGING_DIR}/${ARCHIVE_NAME:r}.md"
if [[ -f "${APPCAST_PATH}" ]]; then
    /bin/cp "${APPCAST_PATH}" "${STAGING_DIR}/appcast.xml"
fi

"${GENERATE_APPCAST}" \
    --account "${SPARKLE_KEY_ACCOUNT}" \
    --download-url-prefix "${DOWNLOAD_URL_PREFIX}" \
    --embed-release-notes \
    --maximum-deltas 0 \
    --maximum-versions 5 \
    "${STAGING_DIR}"

GENERATED_APPCAST="${STAGING_DIR}/appcast.xml"
/usr/bin/xmllint --noout "${GENERATED_APPCAST}"
/usr/bin/grep -Fq 'sparkle:edSignature=' "${GENERATED_APPCAST}"
/usr/bin/grep -Fq "${DOWNLOAD_URL_PREFIX}${ARCHIVE_NAME}" "${GENERATED_APPCAST}"
/usr/bin/grep -Fq "<sparkle:version>${BUILD_NUMBER}</sparkle:version>" "${GENERATED_APPCAST}"

/bin/cp "${GENERATED_APPCAST}" "${APPCAST_PATH}"
print "已生成并签名：${APPCAST_PATH}"
