#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
typeset -a paths

while read -r _ module_path; do
    if [[ "$module_path" != "3rdparty/llvm/llvm" ]]; then
        paths+=("$module_path")
    fi
done < <(git -C "$REPO_ROOT" config --file .gitmodules --get-regexp path)

git -C "$REPO_ROOT" submodule sync --recursive
git -C "$REPO_ROOT" submodule update --init --depth 1 --recursive -- "${paths[@]}"
