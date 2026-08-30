#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
VERSION="${MOLTENVK_VERSION:-1.4.2}"
EXPECTED_SHA256="${MOLTENVK_SHA256:-b5d947b1660e6e9fed40b9cd2387e160aaab9e80b775c0cef7e14059405178c1}"
DEPS_ROOT="${ARMSX3_DEPS_ROOT:-$REPO_ROOT/.deps}"
ARCHIVE="$DEPS_ROOT/downloads/MoltenVK-ios-v$VERSION.tar"
DESTINATION="$DEPS_ROOT/MoltenVK-$VERSION"
URL="https://github.com/KhronosGroup/MoltenVK/releases/download/v$VERSION/MoltenVK-ios.tar"

for command in curl shasum tar; do
    command -v "$command" >/dev/null
done

if [[ -f "$DESTINATION/MoltenVK/MoltenVK/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a" ]]; then
    printf '%s\n' "$DESTINATION/MoltenVK"
    exit 0
fi

mkdir -p "$DEPS_ROOT/downloads"
if [[ ! -f "$ARCHIVE" ]]; then
    curl -fL --retry 3 --output "$ARCHIVE.partial" "$URL"
    mv "$ARCHIVE.partial" "$ARCHIVE"
fi

actual_sha256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$actual_sha256" != "$EXPECTED_SHA256" ]]; then
    printf 'MoltenVK archive hash mismatch: expected %s, got %s\n' "$EXPECTED_SHA256" "$actual_sha256" >&2
    exit 66
fi

if [[ -d "$DESTINATION" ]]; then
    find "$DESTINATION" -depth -delete
fi
mkdir -p "$DESTINATION"
tar -xf "$ARCHIVE" -C "$DESTINATION"

test -f "$DESTINATION/MoltenVK/MoltenVK/include/vulkan/vulkan.h"
test -f "$DESTINATION/MoltenVK/MoltenVK/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a"
printf '%s\n' "$DESTINATION/MoltenVK"
