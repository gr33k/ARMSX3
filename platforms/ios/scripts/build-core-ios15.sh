#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
MINIMUM_IOS="${MINIMUM_IOS:-15.0}"
JOBS="${JOBS:-2}"
MIN_FREE_KB="${MIN_FREE_KB:-10485760}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-ios-core}"

for command in cmake file git ninja nm otool xcrun; do
    command -v "$command" >/dev/null
done

available_kb="$(df -Pk "$REPO_ROOT" | awk 'NR == 2 {print $4}')"
if (( available_kb < MIN_FREE_KB )); then
    printf 'Refusing RPCS3 core build: only %s KiB free; %s KiB required.\n' "$available_kb" "$MIN_FREE_KB" >&2
    exit 75
fi

"$SCRIPT_DIR/init-submodules.sh"
MOLTENVK_ROOT="$("$SCRIPT_DIR/fetch-moltenvk.sh")"
LLVM_ROOT="$("$SCRIPT_DIR/fetch-llvm-ios15.sh")"
FFMPEG_ROOT="$("$SCRIPT_DIR/build-ffmpeg-ios15.sh")"
SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
PREFIX_MAP_FLAGS="-ffile-prefix-map=$REPO_ROOT=/src/ARMSX3 -fdebug-prefix-map=$REPO_ROOT=/src/ARMSX3 -fmacro-prefix-map=$REPO_ROOT=/src/ARMSX3"

cmake \
    -S "$REPO_ROOT" \
    -B "$BUILD_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$SDKROOT" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MINIMUM_IOS" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    "-DCMAKE_C_FLAGS=$PREFIX_MAP_FLAGS" \
    "-DCMAKE_CXX_FLAGS=$PREFIX_MAP_FLAGS" \
    "-DCMAKE_OBJC_FLAGS=$PREFIX_MAP_FLAGS" \
    "-DCMAKE_OBJCXX_FLAGS=$PREFIX_MAP_FLAGS" \
    -DRPCS3_FRONTEND=IOS \
    -DRPCS3_MOLTENVK_ROOT="$MOLTENVK_ROOT" \
    -DRPCS3_FFMPEG_ROOT="$FFMPEG_ROOT" \
    -DWITH_LLVM=ON \
    -DBUILD_LLVM=OFF \
    -DSTATIC_LINK_LLVM=ON \
    -DLLVM_DIR="$LLVM_ROOT/lib/cmake/llvm" \
    -DUSE_LTO=OFF \
    -DUSE_PRECOMPILED_HEADERS=OFF \
    -DBUILD_RPCS3_TESTS=OFF \
    -DRUN_RPCS3_TESTS=OFF

ninja -C "$BUILD_DIR" -j"$JOBS" RPCS3Core

CORE="$BUILD_DIR/rpcs3/libRPCS3Core.dylib"
test -f "$CORE"
file "$CORE" | grep -Fq 'Mach-O 64-bit dynamically linked shared library arm64'
xcrun vtool -show-build "$CORE" | grep -Fq "minos $MINIMUM_IOS"
nm -gU "$CORE" | grep -Fq '_rpcs3_ios_initialize'
if nm -u "$CORE" | grep -Eq 'os_sync_(wait|wake)'; then
    printf 'Core imports APIs unavailable before iOS 17.4.\n' >&2
    exit 66
fi
printf '%s\n' "$CORE"
