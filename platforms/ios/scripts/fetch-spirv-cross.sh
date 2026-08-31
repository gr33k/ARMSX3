#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# MoltenVK v1.4.2 records this exact commit in
# ExternalRevisions/SPIRV-Cross_repo_revision.
readonly MOLTENVK_VERSION="1.4.2"
readonly MOLTENVK_TAG_COMMIT="db66022459ffb663aa2b50f6b018bc2e124f5edf"
readonly REVISION="6c09849fe88c48eaed08413aa022aaa136a3a057"
readonly EXPECTED_SHA256="b81b9956289950570953738e666a031ca32ff64e4fc925eba89f227c42109518"
readonly ARCHIVE_NAME="SPIRV-Cross-$REVISION.tar.gz"
readonly SOURCE_ROOT_NAME="SPIRV-Cross-$REVISION"
readonly URL="https://codeload.github.com/KhronosGroup/SPIRV-Cross/tar.gz/$REVISION"

DEPS_ROOT="${ARMSX3_DEPS_ROOT:-$REPO_ROOT/.deps}"
ARCHIVE=""
DESTINATION=""
STAGING_DIR=""
PARTIAL_ARCHIVE=""

usage() {
    printf 'usage: %s [--print-metadata]\n' "$0" >&2
}

fail() {
    printf 'SPIRV-Cross dependency error: %s\n' "$1" >&2
    exit "${2:-1}"
}

cleanup() {
    if [[ -n "$PARTIAL_ARCHIVE" && -e "$PARTIAL_ARCHIVE" ]]; then
        find "$PARTIAL_ARCHIVE" -depth -delete
    fi
    if [[ -n "$STAGING_DIR" && -e "$STAGING_DIR" ]]; then
        find "$STAGING_DIR" -depth -delete
    fi
}

if (( $# > 1 )); then
    usage
    exit 64
fi

if [[ "${1:-}" == "--print-metadata" ]]; then
    printf 'moltenvk_version=%s\n' "$MOLTENVK_VERSION"
    printf 'moltenvk_tag_commit=%s\n' "$MOLTENVK_TAG_COMMIT"
    printf 'revision=%s\n' "$REVISION"
    printf 'archive_sha256=%s\n' "$EXPECTED_SHA256"
    printf 'archive_url=%s\n' "$URL"
    printf 'license=Apache-2.0\n'
    exit 0
elif (( $# == 1 )); then
    usage
    exit 64
fi

for command_name in awk curl find grep mkdir mktemp mv shasum tar; do
    command -v "$command_name" >/dev/null || fail "required command not found: $command_name" 69
done

mkdir -p "$DEPS_ROOT"
DEPS_ROOT="$(cd "$DEPS_ROOT" && pwd -P)"

# Dependencies may live in the repository-level ignored .deps directory or in
# an external cache, but never inside tracked source directories.
if [[ "$DEPS_ROOT" == "$REPO_ROOT" ||
      "$DEPS_ROOT" == "$REPO_ROOT/platforms" || "$DEPS_ROOT" == "$REPO_ROOT/platforms/"* ||
      "$DEPS_ROOT" == "$REPO_ROOT/rpcs3" || "$DEPS_ROOT" == "$REPO_ROOT/rpcs3/"* ||
      "$DEPS_ROOT" == "$REPO_ROOT/3rdparty" || "$DEPS_ROOT" == "$REPO_ROOT/3rdparty/"* ]]; then
    fail "ARMSX3_DEPS_ROOT must be an out-of-source .deps/cache directory" 64
fi

ARCHIVE="$DEPS_ROOT/downloads/$ARCHIVE_NAME"
DESTINATION="$DEPS_ROOT/$SOURCE_ROOT_NAME"
readonly STAMP_NAME=".armsx3-spirv-cross-dependency"
readonly STAMP_REVISION="revision=$REVISION"
readonly STAMP_SHA256="archive_sha256=$EXPECTED_SHA256"

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

mkdir -p "$DEPS_ROOT/downloads"
if [[ ! -f "$ARCHIVE" ]]; then
    PARTIAL_ARCHIVE="$ARCHIVE.partial.$$"
    curl --proto '=https' --tlsv1.2 -fL --retry 3 --retry-all-errors \
        --connect-timeout 15 --output "$PARTIAL_ARCHIVE" "$URL"
    mv "$PARTIAL_ARCHIVE" "$ARCHIVE"
    PARTIAL_ARCHIVE=""
fi

actual_sha256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$actual_sha256" != "$EXPECTED_SHA256" ]]; then
    fail "archive hash mismatch for $ARCHIVE: expected $EXPECTED_SHA256, got $actual_sha256" 66
fi

if [[ -f "$DESTINATION/$STAMP_NAME" &&
      -f "$DESTINATION/CMakeLists.txt" &&
      -f "$DESTINATION/LICENSE" &&
      -f "$DESTINATION/spirv_cross.hpp" &&
      -f "$DESTINATION/spirv_msl.hpp" ]] &&
   grep -Fqx "$STAMP_REVISION" "$DESTINATION/$STAMP_NAME" &&
   grep -Fqx "$STAMP_SHA256" "$DESTINATION/$STAMP_NAME"; then
    printf '%s\n' "$DESTINATION"
    exit 0
fi

STAGING_DIR="$(mktemp -d "$DEPS_ROOT/.spirv-cross-stage.XXXXXX")"
tar -xzf "$ARCHIVE" -C "$STAGING_DIR"
staged_source="$STAGING_DIR/$SOURCE_ROOT_NAME"

for required_file in CMakeLists.txt LICENSE spirv_cross.hpp spirv_msl.hpp; do
    [[ -f "$staged_source/$required_file" ]] || fail "archive is missing $required_file" 65
done
grep -Fq "Apache License" "$staged_source/LICENSE" || fail "unexpected SPIRV-Cross license payload" 65

printf '%s\n%s\n%s\n%s\n' \
    "$STAMP_REVISION" \
    "$STAMP_SHA256" \
    "moltenvk_version=$MOLTENVK_VERSION" \
    "moltenvk_tag_commit=$MOLTENVK_TAG_COMMIT" \
    > "$staged_source/$STAMP_NAME"

if [[ -e "$DESTINATION" ]]; then
    find "$DESTINATION" -depth -delete
fi
mv "$staged_source" "$DESTINATION"
find "$STAGING_DIR" -depth -delete
STAGING_DIR=""

printf '%s\n' "$DESTINATION"
