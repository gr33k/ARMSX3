#!/bin/sh
set -eu

source_core="$1"
icon_2x="$2"
icon_3x="$3"
: "${TARGET_BUILD_DIR:?Xcode TARGET_BUILD_DIR is required}"
: "${FRAMEWORKS_FOLDER_PATH:?Xcode FRAMEWORKS_FOLDER_PATH is required}"
: "${WRAPPER_NAME:?Xcode WRAPPER_NAME is required}"

frameworks_dir="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
embedded_core="${frameworks_dir}/libRPCS3Core.dylib"
app_bundle="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"

mkdir -p "${frameworks_dir}"
if ! cmp -s "${source_core}" "${embedded_core}"; then
    cp "${source_core}" "${embedded_core}"
fi

for icon in "${icon_2x}" "${icon_3x}"; do
    destination="${app_bundle}/$(basename "${icon}")"
    if ! cmp -s "${icon}" "${destination}"; then
        cp "${icon}" "${destination}"
    fi
done
