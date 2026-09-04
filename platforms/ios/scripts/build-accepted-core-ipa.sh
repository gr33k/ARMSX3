#!/bin/zsh
set -euo pipefail

# Shell-only changes must not accidentally ship the unfinished renderer build.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ACCEPTED_IPA="$ROOT/artifacts/ARMSX3-iOS-Pre-Alpha-v0.35.0-TrollStore.ipa"
EXPECTED_CORE_SHA="a8faeb02e8b2c87af85d4b77e54bbadf149d0bc33b263e63b0b6b694e3dd1794"
STAGING="$(mktemp -d /private/tmp/armsx3-accepted-core.XXXXXX)"
trap 'find "$STAGING" -depth -delete' EXIT

unzip -p "$ACCEPTED_IPA" Payload/ARMSX3iOS.app/Frameworks/libRPCS3Core.dylib > "$STAGING/libRPCS3Core.dylib"
ACTUAL_SHA="$(shasum -a 256 "$STAGING/libRPCS3Core.dylib" | awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$EXPECTED_CORE_SHA" ]]; then
    printf 'Accepted-core identity mismatch: %s\n' "$ACTUAL_SHA" >&2
    exit 66
fi

CORE_LIBRARY="$STAGING/libRPCS3Core.dylib" \
OUTPUT_IPA="${OUTPUT_IPA:-$ROOT/artifacts/ARMSX3-iOS-Pre-Alpha-v0.36.0-TrollStore.ipa}" \
    zsh "$ROOT/platforms/ios/scripts/build-core-ipa.sh"
