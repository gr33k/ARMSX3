#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FETCH_SCRIPT="$SCRIPT_DIR/fetch-spirv-cross.sh"
TEST_SOURCE="$REPO_ROOT/rpcs3/ios/tests/metal-shader-host"
VERTEX_SPIRV="$REPO_ROOT/3rdparty/GPUOpen/VulkanMemoryAllocator/bin/Shader.vert.spv"
FRAGMENT_SPIRV="$REPO_ROOT/3rdparty/GPUOpen/VulkanMemoryAllocator/bin/Shader.frag.spv"
TEMP_ROOT=""

cleanup() {
    if [[ -n "$TEMP_ROOT" && -e "$TEMP_ROOT" ]]; then
        find "$TEMP_ROOT" -depth -delete
    fi
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

for command_name in cmake find mktemp ninja zsh; do
    command -v "$command_name" >/dev/null
done

test -f "$VERTEX_SPIRV"
test -f "$FRAGMENT_SPIRV"
spirv_cross_source="$($FETCH_SCRIPT)"
TEMP_ROOT="$(mktemp -d /private/tmp/armsx3-metal-shader-test.XXXXXX)"

cmake \
    -S "$TEST_SOURCE" \
    -B "$TEMP_ROOT/build" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DARMSX3_SPIRV_CROSS_SOURCE_DIR="$spirv_cross_source"

cmake --build "$TEMP_ROOT/build" \
    --target ARMSX3MetalShaderKeyTests ARMSX3MetalShaderTranslationTests \
    --parallel 2

"$TEMP_ROOT/build/ARMSX3MetalShaderKeyTests"
"$TEMP_ROOT/build/ARMSX3MetalShaderTranslationTests" \
    "$VERTEX_SPIRV" \
    "$FRAGMENT_SPIRV"
