#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_ROOT/../.." && pwd)"
MINIMUM_IOS="${MINIMUM_IOS:-15.0}"
MIN_FREE_KB="${MIN_FREE_KB:-5242880}"
CORE_LIBRARY="${CORE_LIBRARY:-$REPO_ROOT/build-ios-core/rpcs3/libRPCS3Core.dylib}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-ios-app}"
OUTPUT_IPA="${OUTPUT_IPA:-$REPO_ROOT/artifacts/ARMSX3-iOS-Core-Test.ipa}"
ENTITLEMENTS="$IOS_ROOT/app/TrollStore.entitlements"
PREFIX_MAP_FLAGS="-ffile-prefix-map=$REPO_ROOT=/src/ARMSX3 -fdebug-prefix-map=$REPO_ROOT=/src/ARMSX3 -fmacro-prefix-map=$REPO_ROOT=/src/ARMSX3"
PRIVATE_BINARY_PATTERN="${PRIVATE_BINARY_PATTERN:-/Users/[^/]+|/NAS/}"

for command in cmake codesign ditto file ninja plutil shasum strings xcodebuild xcrun; do
    command -v "$command" >/dev/null
done

available_kb="$(df -Pk "$REPO_ROOT" | awk 'NR == 2 {print $4}')"
if (( available_kb < MIN_FREE_KB )); then
    printf 'Refusing iOS app build: only %s KiB free; %s KiB required.\n' "$available_kb" "$MIN_FREE_KB" >&2
    exit 75
fi

test -f "$CORE_LIBRARY"
test -f "$ENTITLEMENTS"

cmake \
    -S "$IOS_ROOT" \
    -B "$BUILD_DIR" \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MINIMUM_IOS" \
    "-DCMAKE_C_FLAGS=$PREFIX_MAP_FLAGS" \
    "-DCMAKE_CXX_FLAGS=$PREFIX_MAP_FLAGS" \
    "-DCMAKE_OBJC_FLAGS=$PREFIX_MAP_FLAGS" \
    "-DCMAKE_OBJCXX_FLAGS=$PREFIX_MAP_FLAGS" \
    -DARMSX3_CORE_LIBRARY="$CORE_LIBRARY"

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
mkdir -p "$APP/Frameworks"
ditto "$CORE_LIBRARY" "$APP/Frameworks/libRPCS3Core.dylib"

for binary in "$APP/ARMSX3iOS" "$APP/Frameworks/libRPCS3Core.dylib"; do
    description="$(file "$binary")"
    if [[ "$description" != *"Mach-O 64-bit"* || "$description" != *"arm64"* ]]; then
        printf 'Unexpected iOS binary: %s\n' "$description" >&2
        exit 66
    fi
    if ! xcrun vtool -show-build "$binary" | grep -Fq "minos $MINIMUM_IOS"; then
        printf '%s does not target iOS %s.\n' "$binary" "$MINIMUM_IOS" >&2
        exit 66
    fi
done

if nm -u "$APP/Frameworks/libRPCS3Core.dylib" | grep -Eq 'os_sync_(wait|wake)'; then
    printf 'Core imports iOS 17.4 os_sync symbols.\n' >&2
    exit 66
fi
if ! otool -L "$APP/ARMSX3iOS" | grep -Fq '@rpath/libRPCS3Core.dylib'; then
    printf 'App does not load RPCS3Core through @rpath.\n' >&2
    exit 66
fi

PACKAGE_ROOT="$(mktemp -d /private/tmp/armsx3-ios-core-package.XXXXXX)"
cleanup() {
    case "$PACKAGE_ROOT" in
        /private/tmp/armsx3-ios-core-package.*) find "$PACKAGE_ROOT" -depth -delete ;;
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

codesign --force --sign - "$PACKAGED_APP/Frameworks/libRPCS3Core.dylib"
codesign \
    --force \
    --sign - \
    --entitlements "$ENTITLEMENTS" \
    --generate-entitlement-der \
    "$PACKAGED_APP"
codesign --verify --deep --strict "$PACKAGED_APP"

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

for binary in "$PACKAGED_APP/ARMSX3iOS" "$PACKAGED_APP/Frameworks/libRPCS3Core.dylib"; do
    if strings "$binary" | grep -Eq "$PRIVATE_BINARY_PATTERN"; then
        printf 'Packaged binary contains a private local path or configured address: %s\n' "$binary" >&2
        exit 66
    fi
done

TEMP_IPA="$PACKAGE_ROOT/ARMSX3iOS.ipa"
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_ROOT/Payload" "$TEMP_IPA"
unzip -tq "$TEMP_IPA" >/dev/null
ditto "$TEMP_IPA" "$OUTPUT_IPA"

printf 'ARMSX3 iOS real-core IPA built.\n'
printf '  source revision: %s\n' "$(git -C "$REPO_ROOT" rev-parse HEAD)"
printf '  deployment target: iOS %s arm64\n' "$MINIMUM_IOS"
printf '  core ABI: %s\n' "$(nm -gU "$CORE_LIBRARY" | grep -c '_rpcs3_ios_abi_version')"
printf '  output: %s\n' "$OUTPUT_IPA"
printf '  SHA-256: '
shasum -a 256 "$OUTPUT_IPA" | awk '{print $1}'
