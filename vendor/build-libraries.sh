#!/bin/bash
# Compile both dependencies for the same deployment target as the app.
# Uses release tarballs (configure is included); no autoconf/devkit is needed.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${1:?absolute dependency prefix required}"
TARGET="${2:-13.0}"
BUILD_ARCH="$(uname -m)"
EXPECTED="libmtp=1.1.23 libusb=1.0.30 arch=$BUILD_ARCH macos=$TARGET recipe=2"
if test -f "$PREFIX/.build-info" && test "$(cat "$PREFIX/.build-info")" = "$EXPECTED" \
    && test -f "$PREFIX/lib/libmtp.9.dylib" && test -f "$PREFIX/lib/libusb-1.0.0.dylib"; then
    echo "复用兼容构建依赖：$PREFIX"
    exit 0
fi
command -v pkg-config >/dev/null || { echo "缺少 pkg-config；请先运行 brew install pkgconf" >&2; exit 1; }
python3 "$PROJECT_ROOT/vendor/download_sources.py" "$PROJECT_ROOT/.build/downloads"
WORK="$(mktemp -d /private/tmp/mac-switch-mtp-deps.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$PREFIX"
tar -xf "$PROJECT_ROOT/.build/downloads/libusb-1.0.30.tar.bz2" -C "$WORK"
tar -xf "$PROJECT_ROOT/.build/downloads/libmtp-1.1.23.tar.gz" -C "$WORK"
export MACOSX_DEPLOYMENT_TARGET="$TARGET"
export SDKROOT="$(xcrun --show-sdk-path)"
export CC="$(xcrun --find clang)"
export CXX="$(xcrun --find clang++)"
export CFLAGS="-O2 -arch $BUILD_ARCH -mmacosx-version-min=$TARGET -Werror=unguarded-availability-new"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch $BUILD_ARCH -mmacosx-version-min=$TARGET"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
# configure tests execute on the build host. macOS 27 added pipe2(), which is
# absent on the deployment target; select libusb's existing pipe()+fcntl() path.
export ac_cv_func_pipe2=no
JOBS="$(sysctl -n hw.logicalcpu)"
(
    cd "$WORK/libusb-1.0.30"
    ./configure --prefix="$PREFIX" --disable-dependency-tracking --disable-static
    make -j "$JOBS"
    make install
)
(
    cd "$WORK/libmtp-1.1.23"
    ./configure --prefix="$PREFIX" --disable-mtpz --disable-silent-rules \
        --disable-dependency-tracking --disable-static --with-udev="$PREFIX/lib/udev"
    make -j "$JOBS"
    make install
)
printf '%s\n' "$EXPECTED" > "$PREFIX/.build-info"
echo "兼容动态库构建完成：macOS $TARGET / $BUILD_ARCH"
