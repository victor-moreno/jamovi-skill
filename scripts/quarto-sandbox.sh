#!/bin/sh
# Run Quarto where $HOME/Library is not writable (a sandboxed agent session).
#
#   sh /path/to/jamovi-skill/scripts/quarto-sandbox.sh render            # from the Quarto project
#   sh /path/to/jamovi-skill/scripts/quarto-sandbox.sh render page.qmd
#
# On macOS Quarto puts its cache in "$HOME/Library/Caches/quarto" and dies with
# "PermissionDenied ... stat '.../Library/Caches/quarto'" before rendering anything;
# the XDG_* variables are ignored on darwin (quarto.js: darwinUserCacheDir builds
# the path from HOME alone). So HOME is pointed at a scratch directory. R derives
# its user library and ~/.Rprofile from HOME too, so both are captured first and
# passed on explicitly. Scratch space: $QUARTO_SCRATCH, default ./.tmp/qhome.
set -eu

# a quarto on PATH, else the copies bundled with RStudio or Positron
QUARTO="${QUARTO:-}"
for q in "$QUARTO" "$(command -v quarto 2>/dev/null || true)" \
         /Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto \
         /Applications/Positron.app/Contents/Resources/app/quarto/bin/quarto; do
    if [ -n "$q" ] && [ -x "$q" ]; then QUARTO="$q"; break; fi
done
[ -x "${QUARTO:-}" ] || { echo "quarto-sandbox: no quarto found (set QUARTO=...)" >&2; exit 1; }

# the real user library and profile, resolved while HOME is still the real one
if [ -z "${R_LIBS_USER:-}" ] && command -v Rscript >/dev/null 2>&1; then
    R_LIBS_USER="$(Rscript --vanilla -e 'cat(path.expand(Sys.getenv("R_LIBS_USER")))')"
    export R_LIBS_USER
fi
if [ -z "${R_PROFILE_USER:-}" ] && [ -f "$HOME/.Rprofile" ]; then
    R_PROFILE_USER="$HOME/.Rprofile"
    export R_PROFILE_USER
fi

SCRATCH="${QUARTO_SCRATCH:-$PWD/.tmp/qhome}"
mkdir -p "$SCRATCH"
HOME="$SCRATCH" exec "$QUARTO" "$@"
