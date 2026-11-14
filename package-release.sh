#!/bin/bash
# Run from a Mac with Xcode command-line tools and Homebrew libmtp installed.
set -euo pipefail
cd "$(dirname "$0")"
PROJECT_ROOT="$PWD"
STAGE="$(mktemp -d /private/tmp/mac-switch-mtp-release.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
python3 vendor/download_sources.py release-assets/third-party-sources

SWITCH_MTP_APP_PATH="$STAGE/Switch MTP.app" bash build.sh
python3 vendor/verify_bundle.py "$STAGE/Switch MTP.app" --deployment-target "${SWITCH_MTP_DEPLOYMENT_TARGET:-13.0}"
/usr/bin/ditto -c -k --norsrc --keepParent "$STAGE/Switch MTP.app" \
    "$PROJECT_ROOT/release-assets/mac-switch-mtp-v0.1.0-AppleSilicon.zip"
mkdir -p "$STAGE/ThirdParty-Sources"
cp release-assets/third-party-sources/* "$STAGE/ThirdParty-Sources/"
cp -R vendor/licenses "$STAGE/ThirdParty-Sources/"
cp vendor/build-libraries.sh vendor/download_sources.py "$STAGE/ThirdParty-Sources/"
cp THIRD_PARTY.md "$STAGE/ThirdParty-Sources/"
(
    cd "$STAGE/ThirdParty-Sources"
    shasum -a 256 libmtp-1.1.23.tar.gz libusb-1.0.30.tar.bz2 > SHA256SUMS.txt
)
/usr/bin/ditto -c -k --norsrc --keepParent "$STAGE/ThirdParty-Sources" \
    "$PROJECT_ROOT/release-assets/mac-switch-mtp-v0.1.0-ThirdParty-Sources.zip"
(
    cd release-assets
    shasum -a 256 mac-switch-mtp-v0.1.0-AppleSilicon.zip \
        mac-switch-mtp-v0.1.0-ThirdParty-Sources.zip > SHA256SUMS.txt
)
echo "发布文件已生成在 $PROJECT_ROOT/release-assets"
