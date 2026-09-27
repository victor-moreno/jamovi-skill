#!/usr/bin/env bash
# Build and install the module into jamovi desktop and/or a running jamovi
# Docker container, then run tools/smoke.R (if present) against the install.
#
#   bash tools/install.sh              both targets, whichever are available
#   bash tools/install.sh desktop
#   bash tools/install.sh docker [container]     (default container: jamovi)
#
# The desktop target uses whichever R `Rscript` resolves to (respecting
# ~/.Rprofile, which may append jamovi.app's bundled module library). With rig,
# pick the active R with `rig default <version>` first: it must match the R that
# jamovi.app bundles, or rlang (behind jmvcore) fails to load.
set -euo pipefail
source "$(dirname "$0")/_module.sh"

TARGET="${1:-both}"
CONTAINER="${2:-jamovi}"
ARTIFACT="$MODULE_DIR/${MODULE}_${VERSION}.jmo"
SMOKE="$ROOT/tools/smoke.R"

# R preamble for the smoke test: jamovi's base library and the installed module first
smoke_preamble() {
  printf '.libPaths(c("%s", "%s", .libPaths()))\n' "$1" "$2"
  printf 'suppressPackageStartupMessages(library("%s", character.only = TRUE))\n' "$MODULE"
}

# ── desktop ──────────────────────────────────────────────────────────────────
install_desktop() {
  local APP LOG MODDIR OLD i
  APP="${JAMOVI_CURRENT_APP:-/Applications/jamovi.app}"
  [ -d "$APP" ] || { echo "!! desktop: $APP is not installed — skipping"; return 0; }

  MODDIR="$HOME/Library/Application Support/jamovi/modules/$MODULE"
  # the Built: stamp of any copy already installed; the new one must differ
  OLD="$(grep '^Built:' "$MODDIR/R/$MODULE/DESCRIPTION" 2>/dev/null || true)"

  echo ">> desktop: building $MODULE $VERSION with $(Rscript -e 'cat(R.version.string)')"
  LOG="$(mktemp "$ROOT/.tmp/install.XXXXXX")"
  ( cd "$MODULE_DIR" && Rscript -e 'jmvtools::install()' ) 2>&1 | tee "$LOG" | grep -vE '^\s*$' || true

  # jmvtools::install() reports errors on stdout and still exits 0, and it can
  # claim success after failing to drive jamovi.app. Judge by the artifacts.
  [ -f "$ARTIFACT" ] || { echo "error: jmvtools did not produce $ARTIFACT" >&2; rm -f "$LOG"; return 1; }
  if grep -qE 'SingletonLock|sandbox initialization failed|GPU process isn.t usable' "$LOG"; then
    echo
    echo "!! jamovi.app could not be driven (already open, or a sandboxed session)."
    echo "!! The .jmo was built. Install it by hand:"
    echo "!!   jamovi -> Modules -> jamovi library -> Sideload -> $ARTIFACT"
    rm -f "$LOG"; return 0
  fi
  if ! grep -q 'Module installed successfully' "$LOG"; then
    echo "error: jmvtools::install() did not install the module (see above)" >&2
    rm -f "$LOG"; return 1
  fi
  rm -f "$LOG"

  # jamovi unpacks the module shortly AFTER jmvtools reports success. Waiting for the
  # directory is not enough when an older copy is installed: the smoke test would load
  # the old copy (measured: a new analysis "is not an exported object"). Wait for a new
  # Built: stamp instead.
  local NEW=""
  for i in $(seq 1 60); do
    NEW="$(grep '^Built:' "$MODDIR/R/$MODULE/DESCRIPTION" 2>/dev/null || true)"
    [ -n "$NEW" ] && [ "$NEW" != "$OLD" ] && break
    sleep 1
  done
  if [ -z "$NEW" ] || [ "$NEW" = "$OLD" ]; then
    echo "!! desktop: jamovi has not replaced the installed copy of $MODULE after 60 s;"
    echo "!! restart jamovi or sideload $ARTIFACT by hand"
    return 1
  fi
  echo ">> desktop: installed at $MODDIR (${NEW#Built: })"

  if [ -f "$SMOKE" ]; then
    echo ">> desktop: smoke test"
    { smoke_preamble "$APP/Contents/Resources/modules/base/R" "$MODDIR/R"; cat "$SMOKE"; } \
      | Rscript --vanilla -
  fi
}

# ── docker ───────────────────────────────────────────────────────────────────
install_docker() {
  # A sandbox that cannot read ~/.docker/config.json makes the CLI print a
  # warning and list nothing, which looks like "no container". Use a writable config.
  if [ -z "${DOCKER_CONFIG:-}" ] && ! [ -r "$HOME/.docker/config.json" ]; then
    export DOCKER_CONFIG="$ROOT/.tmp/dockercfg"; mkdir -p "$DOCKER_CONFIG"
  fi
  command -v docker >/dev/null || { echo "!! docker: no docker CLI — skipping"; return 0; }
  if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"; then
    echo "!! docker: container '$CONTAINER' is not running — skipping"
    return 0
  fi
  if ! docker exec "$CONTAINER" sh -c 'command -v jmc >/dev/null 2>&1'; then
    echo "!! docker: jmc is not in the container." >&2
    echo "!! Install the jamovi compiler in the image before using this target." >&2
    return 1
  fi

  echo ">> docker: copying source into $CONTAINER"
  local PARTS=(DESCRIPTION NAMESPACE R jamovi)
  [ -d "$MODULE_DIR/data" ] && PARTS+=(data)
  [ -d "$MODULE_DIR/inst" ] && PARTS+=(inst)
  # --no-mac-metadata/--no-xattrs: AppleDouble ._ files otherwise land in the
  # container and jmc tries to compile them.
  tar --no-mac-metadata --no-xattrs -C "$MODULE_DIR" -cf - "${PARTS[@]}" \
    | docker exec -i "$CONTAINER" sh -c \
        "rm -rf /tmp/$MODULE-src && mkdir -p /tmp/$MODULE-src && tar -C /tmp/$MODULE-src -xf -"

  echo ">> docker: jmc --install"
  # --skip-deps: dependencies must already resolve from jamovi's base library;
  # set JMC_SKIP_DEPS=no for a module that needs packages jamovi does not bundle.
  docker exec -i -e MODULE="$MODULE" -e SKIP="${JMC_SKIP_DEPS:-yes}" "$CONTAINER" bash -s <<'INCONTAINER'
set -euo pipefail
source /usr/lib/jamovi/bin/env.conf 2>/dev/null || true
RHOME="${R_HOME:-$(R RHOME 2>/dev/null || true)}"
[ -n "$RHOME" ] || { echo "   error: no R in the container" >&2; exit 1; }
FLAGS=(--to /usr/lib/jamovi/modules --rhome "$RHOME" --rlibs /usr/lib/jamovi/modules/base/R --patch-version)
[ "$SKIP" = yes ] && FLAGS+=(--skip-deps)
jmc --install "/tmp/$MODULE-src" "${FLAGS[@]}"
[ -f "/usr/lib/jamovi/modules/$MODULE/jamovi.yaml" ] || {
  echo "   error: jmc did not install $MODULE" >&2; exit 1; }
INCONTAINER

  echo ">> docker: restarting $CONTAINER to load the module"
  docker restart "$CONTAINER" >/dev/null
  if [ -f "$SMOKE" ]; then
    echo ">> docker: smoke test"
    { smoke_preamble /usr/lib/jamovi/modules/base/R "/usr/lib/jamovi/modules/$MODULE/R"; cat "$SMOKE"; } \
      | docker exec -i "$CONTAINER" bash -c 'source /usr/lib/jamovi/bin/env.conf 2>/dev/null || true; Rscript --vanilla -'
  fi
  echo ">> docker: installed $MODULE $VERSION"
}

case "$TARGET" in
  desktop) install_desktop ;;
  docker)  install_docker ;;
  both)    install_desktop || true; echo; install_docker || true ;;
  *)       echo "usage: install.sh [desktop|docker|both] [container]" >&2; exit 1 ;;
esac
