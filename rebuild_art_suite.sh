#!/bin/bash
# rebuild_art_suite.sh — build the FNAL art-suite conda packages in dependency
# order into the local rattler-build output channel, feeding each product's
# output back as a channel for the next.
#
# Usage (from conda/):
#   ./rebuild_art_suite.sh [--fresh] [--upto <pkg>]
#     --fresh        wipe ./art-suite-output before building (clean channel)
#     --upto <pkg>   stop after building <pkg> (default: build all in ORDER)
#
# Does NOT touch the rattler package cache — that is a separate, deliberate
# action (see the "pristine reset" commands in the project notes). Re-running
# this without --fresh just rebuilds/overwrites into the existing channel.
set -euo pipefail

# --- cache on nvme/local (mirrors .claude/settings.json; keep self-contained) ---
export RATTLER_CACHE_DIR="${RATTLER_CACHE_DIR:-/nfs/data/1/calcuttj/.cache/rattler}"
export PIXI_CACHE_DIR="${PIXI_CACHE_DIR:-/nfs/data/1/calcuttj/.cache/rattler}"

RB="$HOME/.pixi/bin/rattler-build"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

CHANNEL="./art-suite-output"
LOGDIR="$HERE/rebuild-logs"

# Dependency-ordered build list (#0 -> #7). See ART_BUILD_PLAN.md.
ORDER=(cetmodules cetlib_except hep_concurrency cetlib fhiclcpp messagefacility canvas canvas_root_io)

FRESH=0
UPTO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fresh) FRESH=1; shift;;
    --upto)  UPTO="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

if [ "$FRESH" = "1" ]; then
  echo ">>> --fresh: removing $CHANNEL"
  # A prior failed canvas_root_io build can leave a corrupted host_env whose
  # README/ dir lost its +x bit (ROOT/README collision), which blocks rm from
  # traversing it. Restore traversal on our own scratch before removing.
  chmod -R u+rwX "$CHANNEL" 2>/dev/null || true
  rm -rf "$CHANNEL"
fi
mkdir -p "$CHANNEL" "$LOGDIR"

echo ">>> rattler-build: $("$RB" --version)"
echo ">>> cache: $RATTLER_CACHE_DIR"
echo ">>> channel: $CHANNEL"
echo ">>> order: ${ORDER[*]}"
echo

for pkg in "${ORDER[@]}"; do
  recipe="recipes/art-suite/$pkg/recipe.yaml"
  log="$LOGDIR/$pkg.log"
  if [ ! -f "$recipe" ]; then
    echo "!!! missing recipe: $recipe" >&2; exit 1
  fi
  echo "=== building #$pkg ==="
  # Capture rattler's real exit code INTO the log (a piped tail would mask it).
  set +e
  "$RB" build --recipe "$recipe" \
    --output-dir "$CHANNEL" \
    -c "$CHANNEL" -c conda-forge \
    --allow-symlinks-on-windows > "$log" 2>&1
  rc=$?
  set -e
  echo "RATTLER_EXIT:$rc" >> "$log"
  if [ "$rc" -ne 0 ]; then
    echo "!!! FAILED at #$pkg (exit $rc). Last lines of $log:" >&2
    tail -n 25 "$log" >&2
    exit "$rc"
  fi
  echo "    OK -> $log"
  [ -n "$UPTO" ] && [ "$pkg" = "$UPTO" ] && { echo ">>> stopping after $UPTO (--upto)"; break; }
done

echo
echo ">>> DONE. Channel contents:"
ls -1 "$CHANNEL"/noarch/*.conda "$CHANNEL"/linux-64/*.conda 2>/dev/null || true
