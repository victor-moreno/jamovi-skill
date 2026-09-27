#!/bin/sh
# Copy the tools/ template into a module repository.
#
#   sh <skill>/scripts/add-tools.sh <repo-root> [--force]
#
# The scripts find the module (repo root, or the one subfolder with DESCRIPTION +
# jamovi/) and read Package/Version from DESCRIPTION, so they need no editing.
# The only per-module file is tools/smoke.R, which is never overwritten.
# Existing scripts that differ from the template are left alone unless --force.
set -eu
SRC="$(cd "$(dirname "$0")/../templates/tools" && pwd)"
DEST="${1:?usage: add-tools.sh <repo-root> [--force]}/tools"
FORCE="${2:-}"
mkdir -p "$DEST"
for f in "$SRC"/*; do
    b="$(basename "$f")"
    if [ "$b" = smoke.R ] && [ -f "$DEST/$b" ]; then
        echo "kept     tools/$b (module-specific)"; continue
    fi
    if [ -f "$DEST/$b" ] && ! cmp -s "$f" "$DEST/$b" && [ "$FORCE" != --force ]; then
        echo "differs  tools/$b (not replaced; rerun with --force)"; continue
    fi
    if [ -f "$DEST/$b" ] && cmp -s "$f" "$DEST/$b"; then
        echo "same     tools/$b"; continue
    fi
    cp "$f" "$DEST/$b"
    case "$b" in *.sh) chmod +x "$DEST/$b" ;; esac
    echo "copied   tools/$b"
done
echo "In git, keep the executable bit: git update-index --chmod=+x tools/*.sh"
