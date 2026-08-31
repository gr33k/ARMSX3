#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FETCH_SCRIPT="$SCRIPT_DIR/fetch-spirv-cross.sh"
METADATA_TEST="$REPO_ROOT/rpcs3/ios/tests/SPIRVCrossDependencyMetadataTests.cmake"
SMOKE_SOURCE="$REPO_ROOT/rpcs3/ios/tests/spirv-cross-cmake-smoke"
TEMP_ROOT=""

cleanup() {
    if [[ -n "$TEMP_ROOT" && -e "$TEMP_ROOT" ]]; then
        find "$TEMP_ROOT" -depth -delete
    fi
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

for command_name in awk cmake find mkdir mktemp ninja shasum xcrun zsh; do
    command -v "$command_name" >/dev/null
done

zsh -n "$FETCH_SCRIPT"
metadata="$($FETCH_SCRIPT --print-metadata)"
revision="$(printf '%s\n' "$metadata" | awk -F= '$1 == "revision" { print $2 }')"
[[ -n "$revision" ]]

TEMP_ROOT="$(mktemp -d /private/tmp/armsx3-spirv-cross-contract.XXXXXX)"
good_deps="$TEMP_ROOT/good/.deps"
bad_deps="$TEMP_ROOT/bad/.deps"
mkdir -p "$bad_deps/downloads"
printf 'deliberately invalid archive\n' > "$bad_deps/downloads/SPIRV-Cross-$revision.tar.gz"

if ARMSX3_DEPS_ROOT="$bad_deps" "$FETCH_SCRIPT" >/dev/null 2>&1; then
    printf 'hash rejection contract failed\n' >&2
    exit 1
fi

first_source="$(ARMSX3_DEPS_ROOT="$good_deps" "$FETCH_SCRIPT")"
second_source="$(ARMSX3_DEPS_ROOT="$good_deps" "$FETCH_SCRIPT")"
[[ "$first_source" == "$second_source" ]]
[[ -f "$first_source/LICENSE" ]]

cmake \
    -DARMSX3_DEPS_ROOT="$good_deps" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -P "$METADATA_TEST"

sdkroot="$(xcrun --sdk iphoneos --show-sdk-path)"
cmake \
    -S "$SMOKE_SOURCE" \
    -B "$TEMP_ROOT/cmake-build" \
    -G Ninja \
    -DARMSX3_DEPS_ROOT="$good_deps" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DCMAKE_OSX_SYSROOT="$sdkroot" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY

cmake --build "$TEMP_ROOT/cmake-build" \
    --target ARMSX3IOSMetalShaderCompiler ARMSX3IOSMetalRuntimeScaffold \
    --parallel 2

printf 'SPIRV-Cross dependency and iOS Metal runtime/compiler contracts passed.\n'
