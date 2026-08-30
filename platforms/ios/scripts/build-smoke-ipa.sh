#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_ROOT/../.." && pwd)"
MINIMUM_IOS="${MINIMUM_IOS:-15.0}"
MIN_FREE_KB="${MIN_FREE_KB:-10485760}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-ios-smoke}"
OUTPUT_IPA="${OUTPUT_IPA:-$REPO_ROOT/artifacts/ARMSX3-iOS-Feasibility-Smoke.ipa}"
ENTITLEMENTS="$IOS_ROOT/app/TrollStore.entitlements"

for command in cmake codesign ditto file ninja plutil shasum xcodebuild xcrun; do
    command -v "$command" >/dev/null
done

available_kb="$(df -Pk "$REPO_ROOT" | awk 'NR == 2 {print $4}')"
if (( available_kb < MIN_FREE_KB )); then
    printf 'Refusing iOS build: only %s KiB free; %s KiB required.\n' "$available_kb" "$MIN_FREE_KB" >&2
    exit 75
fi

MOLTENVK_ROOT="$($SCRIPT_DIR/fetch-moltenvk.sh)"
test -f "$MOLTENVK_ROOT/MoltenVK/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a"
test -f "$ENTITLEMENTS"

cmake \
    -S "$IOS_ROOT" \
    -B "$BUILD_DIR" \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MINIMUM_IOS" \
    -DARMSX3_MOLTENVK_ROOT="$MOLTENVK_ROOT"

xcodebuild \
    -project "$BUILD_DIR/ARMSX3iOS.xcodeproj" \
    -target ARMSX3iOS \
    -configuration Release \
    -sdk iphoneos \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' \
    COMPILER_INDEX_STORE_ENABLE=NO \
    -jobs 1 \
    build

APP="$BUILD_DIR/Release-iphoneos/ARMSX3iOS.app"
test -f "$APP/ARMSX3iOS"

binary_description="$(file "$APP/ARMSX3iOS")"
if [[ "$binary_description" != *"Mach-O 64-bit"* || "$binary_description" != *"arm64"* ]]; then
    printf 'Unexpected iOS executable: %s\n' "$binary_description" >&2
    exit 66
fi

build_version="$(xcrun vtool -show-build "$APP/ARMSX3iOS")"
if ! grep -Fq "minos $MINIMUM_IOS" <<< "$build_version"; then
    printf 'Executable does not target iOS %s.\n' "$MINIMUM_IOS" >&2
    exit 66
fi

PACKAGE_ROOT="$(mktemp -d /private/tmp/armsx3-ios-package.XXXXXX)"
cleanup() {
    case "$PACKAGE_ROOT" in
        /private/tmp/armsx3-ios-package.*) find "$PACKAGE_ROOT" -depth -delete ;;
        *) printf 'Refusing to clean unmanaged package path: %s\n' "$PACKAGE_ROOT" >&2 ;;
    esac
}
trap cleanup EXIT

mkdir -p "$PACKAGE_ROOT/Payload" "$(dirname "$OUTPUT_IPA")"
ditto "$APP" "$PACKAGE_ROOT/Payload/ARMSX3iOS.app"
PACKAGED_APP="$PACKAGE_ROOT/Payload/ARMSX3iOS.app"
if [[ -d "$PACKAGED_APP/_CodeSignature" ]]; then
    find "$PACKAGED_APP/_CodeSignature" -depth -delete
fi

codesign \
    --force \
    --sign - \
    --entitlements "$ENTITLEMENTS" \
    --generate-entitlement-der \
    "$PACKAGED_APP"
codesign --verify --strict "$PACKAGED_APP"

PACKAGED_ENTITLEMENTS="$PACKAGE_ROOT/entitlements.plist"
codesign -d --entitlements :- "$PACKAGED_APP" > "$PACKAGED_ENTITLEMENTS" 2>/dev/null
for entitlement in \
    get-task-allow \
    com.apple.security.cs.allow-jit \
    com.apple.security.cs.allow-unsigned-executable-memory \
    com.apple.developer.kernel.extended-virtual-addressing \
    com.apple.developer.kernel.increased-memory-limit; do
    if [[ "$(/usr/libexec/PlistBuddy -c "Print :$entitlement" "$PACKAGED_ENTITLEMENTS")" != "true" ]]; then
        printf 'Packaged app is missing entitlement: %s\n' "$entitlement" >&2
        exit 66
    fi
done

TEMP_IPA="$PACKAGE_ROOT/ARMSX3iOS.ipa"
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_ROOT/Payload" "$TEMP_IPA"
unzip -tq "$TEMP_IPA" >/dev/null
ditto "$TEMP_IPA" "$OUTPUT_IPA"

printf 'ARMSX3 iOS smoke IPA built.\n'
printf '  source revision: %s\n' "$(git -C "$REPO_ROOT" rev-parse HEAD)"
printf '  deployment target: iOS %s arm64\n' "$MINIMUM_IOS"
printf '  renderer probe: Vulkan through MoltenVK %s and Metal\n' "${MOLTENVK_VERSION:-1.4.2}"
printf '  output: %s\n' "$OUTPUT_IPA"
printf '  SHA-256: '
shasum -a 256 "$OUTPUT_IPA" | awk '{print $1}'
