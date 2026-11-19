#!/usr/bin/env bash
set -euo pipefail
d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
private="$RUNNER_TEMP/ll-stock397-private"
public="$RUNNER_TEMP/ll-stock397-public/summary.json"
fail() { python3 -B "$d/guard.py" fail "$public" "$1"; }
mkdir -m 700 "$private"
fail source_binding
python3 -B "$d/guard.py" event . > "$private/event.log" 2>&1
fail sparse_source
python3 -B "$d/guard.py" source product > "$private/sparse.log" 2>&1
fail stage_binding
python3 -B "$d/prepare.py" product "$private/stage" > "$private/stage.json" 2>"$private/stage.log"
python3 -B "$d/guard.py" stage "$private/stage" "$private/stage.json"
fail engine_acquisition
python3 -B product/tools/ci/install_tools.py godot --native-only --output "$private/tools" > "$private/install.log" 2>&1
bin="$private/tools/godot"
fail engine_sha
printf 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3  %s\n' "$bin" | sha256sum --status -c -
export HOME="$private/stage/private/home" XDG_DATA_HOME="$private/stage/private/data" XDG_CONFIG_HOME="$private/stage/private/config" XDG_CACHE_HOME="$private/stage/private/cache"
fail import
timeout --kill-after=5s 180s "$bin" --headless --editor --import --path "$private/stage/game" > "$private/import.log" 2>&1
! grep -Eq 'SCRIPT ERROR:|Parse Error' "$private/import.log"
fail display
command -v xvfb-run >/dev/null && command -v Xvfb >/dev/null && command -v xauth >/dev/null
export LIBGL_ALWAYS_SOFTWARE=1 LL397_STOCK_RAW="$private/raw.json"
fail session
( set -o noclobber; printf 'once\n' > "$private/started" )
set +e
timeout --kill-after=5s 220s xvfb-run -a -s '-screen 0 1600x1000x24' "$bin" --path "$private/stage/game" --display-driver x11 --rendering-method gl_compatibility --render-thread safe --resolution 1360x880 --position 30,30 -- --stock-residual-397 > "$private/session.log" 2>&1
rc=$?
set -e
case "$rc" in
 0) ;;
 4|8) fail scene_or_phase; exit "$rc" ;;
 7) fail unsupported_renderer; exit "$rc" ;;
 124|137) fail session_timeout; exit "$rc" ;;
 *) exit "$rc" ;;
esac
! grep -Eq 'SCRIPT ERROR:|Parse Error' "$private/session.log"
fail invalid_summary
python3 -B "$d/guard.py" package "$LL397_STOCK_RAW" "$public"
# A prep-only receipt is useful partial evidence, not a fully qualified comparison.
python3 -B - "$public" <<'PY'
import json,sys
if json.load(open(sys.argv[1]))["status"]!="prep_plus_stationary_viewport_body":raise SystemExit(18)
PY
