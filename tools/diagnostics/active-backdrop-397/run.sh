#!/usr/bin/env bash
set -euo pipefail
d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
private="$RUNNER_TEMP/ll-active397-private"
out="$RUNNER_TEMP/ll-active397-public/summary.json"
fail() { python3 -B "$d/guard.py" fail "$out" "$1"; }
mkdir -m 700 "$private"
fail source_binding
python3 -B "$d/guard.py" event . >"$private/event.log" 2>&1
fail sparse_source
python3 -B "$d/guard.py" source product >"$private/source.log" 2>&1
fail stage_binding
python3 -B "$d/prepare.py" product "$private/stage" >"$private/stage.json" 2>"$private/prepare.log"
python3 -B "$d/guard.py" stage "$private/stage" "$private/stage.json"
fail engine_acquisition
python3 -B product/tools/ci/install_tools.py godot --native-only --output "$private/tools" >"$private/tool.log" 2>&1
bin="$private/tools/godot"
fail engine_sha
printf 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3  %s\n' "$bin" | sha256sum --status -c -
export HOME="$private/stage/private/home" XDG_DATA_HOME="$private/stage/private/data" XDG_CONFIG_HOME="$private/stage/private/config" XDG_CACHE_HOME="$private/stage/private/cache"
fail import
timeout --kill-after=5s 180s "$bin" --headless --editor --import --path "$private/stage/game" >"$private/import.log" 2>&1
if grep -Eq 'SCRIPT ERROR:|Parse Error:|Compile Error:' "$private/import.log"; then exit 11; fi
fail display
command -v xvfb-run >/dev/null && command -v Xvfb >/dev/null && command -v xauth >/dev/null || exit 12
export LIBGL_ALWAYS_SOFTWARE=1 LL_ACTIVE_BACKDROP_RAW="$private/raw.json"
fail session
( set -o noclobber; printf 'one diagnostic process only\n' >"$private/sampled" )
set +e
timeout --kill-after=5s 260s xvfb-run -a -s '-screen 0 1600x1000x24' "$bin" --path "$private/stage/game" --audio-driver Dummy --display-driver x11 --rendering-method gl_compatibility --render-thread safe --resolution 1360x880 --position 30,30 -- --diagnostic-active-backdrop >"$private/game.log" 2>&1
rc=$?
set -e
if [[ "$rc" == 124 || "$rc" == 137 ]];then fail session_timeout;exit 14;fi
if [[ "$rc" != 0 && "$rc" != 2 ]];then exit 16;fi
if grep -Eq 'SCRIPT ERROR:|Parse Error:|Compile Error:' "$private/game.log";then exit 15;fi
fail invalid_summary
python3 -B "$d/report.py" "$LL_ACTIVE_BACKDROP_RAW" "$private/validated.json" --expected-commit ce1435afb2329a6c1d2d77a8a19923dfd96bd205 --expected-tree 03632a0d56e4294f5664859656c8809541766d1b --engine-sha256 f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3 --probe-sha256 "$(sha256sum "$d/probe.gd" | cut -d' ' -f1)" --adapter-sha256 "$(sha256sum "$d/ll397_active_backdrop.gd" | cut -d' ' -f1)" || [[ -s "$private/validated.json" ]] || exit 17
[[ $(stat -c %s "$private/validated.json") -lt 16384 ]]
install -m 600 "$private/validated.json" "$out"
python3 -B - "$out" "$rc" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]));assert x.get('status')=='valid' and sys.argv[2]=='0'
PY
