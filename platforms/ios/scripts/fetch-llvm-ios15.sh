#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REVISION="${LLVM_IOS_REVISION:-ca7933e47d3a3451-ec81b2304bcb}"
EXPECTED_SHA256="${LLVM_IOS_SHA256:-138446dbbd497f1c18a741aab85b27982ec62099f13e39f81abfbdc901160583}"
DEPS_ROOT="${ARMSX3_DEPS_ROOT:-$REPO_ROOT/.deps}"
ARCHIVE_NAME="LLVM-iOS15-arm64-$REVISION.tar.xz"
ARCHIVE="$DEPS_ROOT/downloads/$ARCHIVE_NAME"
DESTINATION="$DEPS_ROOT/llvm-ios15-sdk"
LLVM_ROOT="$DESTINATION/LLVM-iOS15-arm64"
URL="https://github.com/XITRIX/LLVM-On-iOS/releases/download/llvm-ios15-$REVISION/$ARCHIVE_NAME"

for command in curl shasum tar; do
    command -v "$command" >/dev/null
done

if [[ -f "$LLVM_ROOT/lib/cmake/llvm/LLVMConfig.cmake" ]]; then
    printf '%s\n' "$LLVM_ROOT"
    exit 0
fi

mkdir -p "$DEPS_ROOT/downloads"
if [[ ! -f "$ARCHIVE" ]]; then
    curl -fL --retry 3 --output "$ARCHIVE.partial" "$URL"
    mv "$ARCHIVE.partial" "$ARCHIVE"
fi

actual_sha256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$actual_sha256" != "$EXPECTED_SHA256" ]]; then
    printf 'LLVM iOS archive hash mismatch: expected %s, got %s\n' "$EXPECTED_SHA256" "$actual_sha256" >&2
    exit 66
fi

if [[ -d "$DESTINATION" ]]; then
    find "$DESTINATION" -depth -delete
fi
mkdir -p "$DESTINATION"
tar -xf "$ARCHIVE" -C "$DESTINATION"

test -f "$LLVM_ROOT/lib/cmake/llvm/LLVMConfig.cmake"
printf '%s\n' "$LLVM_ROOT"
