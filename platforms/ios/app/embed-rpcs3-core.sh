#!/bin/sh
set -eu

source_core="$1"
: "${TARGET_BUILD_DIR:?Xcode TARGET_BUILD_DIR is required}"
: "${FRAMEWORKS_FOLDER_PATH:?Xcode FRAMEWORKS_FOLDER_PATH is required}"

frameworks_dir="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
embedded_core="${frameworks_dir}/libRPCS3Core.dylib"

mkdir -p "${frameworks_dir}"
if ! cmp -s "${source_core}" "${embedded_core}"; then
    cp "${source_core}" "${embedded_core}"
fi
