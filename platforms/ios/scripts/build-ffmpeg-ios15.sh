#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
VERSION="${FFMPEG_VERSION:-8.1.1}"
EXPECTED_SHA256="${FFMPEG_SHA256:-b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3}"
MINIMUM_IOS="${MINIMUM_IOS:-15.0}"
JOBS="${JOBS:-2}"
DEPS_ROOT="${ARMSX3_DEPS_ROOT:-$REPO_ROOT/.deps}"
ARCHIVE="$DEPS_ROOT/downloads/ffmpeg-$VERSION.tar.xz"
SOURCE_ROOT="$DEPS_ROOT/ffmpeg-source"
SOURCE="$SOURCE_ROOT/ffmpeg-$VERSION"
BUILD_ROOT="$DEPS_ROOT/ffmpeg-build-ios15"
PREFIX="$DEPS_ROOT/ffmpeg-ios15"
URL="https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
BUILD_CONTRACT="ios-prefix-map-v1:$VERSION:$MINIMUM_IOS"

for command in curl make shasum tar xcrun; do
    command -v "$command" >/dev/null
done

required_libraries=(libavformat.a libavcodec.a libswscale.a libswresample.a libavutil.a)
complete=1
for library in "${required_libraries[@]}"; do
    [[ -f "$PREFIX/lib/$library" ]] || complete=0
done
if (( complete )) && grep -Fq '#define FFMPEG_VERSION "8.1.1"' "$PREFIX/include/libavutil/ffversion.h" && \
    [[ "$(cat "$PREFIX/.armsx3-build-contract" 2>/dev/null || true)" == "$BUILD_CONTRACT" ]]; then
    printf '%s\n' "$PREFIX"
    exit 0
fi

mkdir -p "$DEPS_ROOT/downloads" "$SOURCE_ROOT"
if [[ ! -f "$ARCHIVE" ]]; then
    curl -fL --retry 3 --output "$ARCHIVE.partial" "$URL"
    mv "$ARCHIVE.partial" "$ARCHIVE"
fi

actual_sha256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$actual_sha256" != "$EXPECTED_SHA256" ]]; then
    printf 'FFmpeg archive hash mismatch: expected %s, got %s\n' "$EXPECTED_SHA256" "$actual_sha256" >&2
    exit 66
fi

if [[ ! -x "$SOURCE/configure" ]]; then
    tar -xf "$ARCHIVE" -C "$SOURCE_ROOT"
fi
if [[ -d "$BUILD_ROOT" ]]; then
    find "$BUILD_ROOT" -depth -delete
fi
if [[ -d "$PREFIX" ]]; then
    find "$PREFIX" -depth -delete
fi
mkdir -p "$BUILD_ROOT" "$PREFIX"

SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos --find clang)"
CXX="$(xcrun --sdk iphoneos --find clang++)"

cd "$BUILD_ROOT"
"$SOURCE/configure" \
    --prefix="$PREFIX" \
    --target-os=darwin \
    --arch=arm64 \
    --cpu=armv8-a \
    --enable-cross-compile \
    --cc="$CC" \
    --cxx="$CXX" \
    --sysroot="$SDKROOT" \
    --extra-cflags="-arch arm64 -miphoneos-version-min=$MINIMUM_IOS -ffile-prefix-map=$REPO_ROOT=/src/ARMSX3 -fdebug-prefix-map=$REPO_ROOT=/src/ARMSX3 -fmacro-prefix-map=$REPO_ROOT=/src/ARMSX3" \
    --extra-cxxflags="-arch arm64 -miphoneos-version-min=$MINIMUM_IOS -ffile-prefix-map=$REPO_ROOT=/src/ARMSX3 -fdebug-prefix-map=$REPO_ROOT=/src/ARMSX3 -fmacro-prefix-map=$REPO_ROOT=/src/ARMSX3" \
    --extra-ldflags="-arch arm64 -miphoneos-version-min=$MINIMUM_IOS" \
    --enable-pic \
    --enable-static \
    --disable-shared \
    --disable-programs \
    --disable-doc \
    --disable-debug \
    --disable-avdevice \
    --disable-avfilter \
    --disable-network \
    --disable-autodetect \
    --disable-iconv \
    --disable-bzlib \
    --disable-lzma \
    --disable-zlib \
    --disable-audiotoolbox \
    --disable-videotoolbox \
    --disable-securetransport \
    --enable-pthreads >&2
make -j"$JOBS" >&2
make install >&2

for library in "${required_libraries[@]}"; do
    test -f "$PREFIX/lib/$library"
done
printf '%s\n' "$BUILD_CONTRACT" > "$PREFIX/.armsx3-build-contract"
printf '%s\n' "$PREFIX"
