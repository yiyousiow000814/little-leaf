#!/usr/bin/env bash
set -euo pipefail
d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[[ ${GITHUB_ACTIONS:-} == true && ${GITHUB_REPOSITORY:-} == yiyousiow000814/little-leaf && ${GITHUB_EVENT_NAME:-} == push && ${GITHUB_REF:-} == refs/heads/qa/render-mechanism-397 && ${GITHUB_RUN_ATTEMPT:-} == 1 ]]
private="$RUNNER_TEMP/ll-render-mechanism-397-private"
out="$RUNNER_TEMP/ll-render-mechanism-397-public/summary.json"
mkdir -m 700 "$private"
fail() { python3 -B "$d/guard.py" fail "$out" "$1"; }
fail source_binding
python3 -B "$d/guard.py" event . >"$private/event.log" 2>&1
fail source_stage
python3 -B "$d/prepare.py" product "$private/stage" >"$private/bind.log" 2>&1
fail official_tool
python3 product/tools/ci/install_tools.py godot --native-only --output "$private/tools" >"$private/tool.log" 2>&1
bin="$private/tools/godot"
fail official_engine_identity
printf 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3  %s\n' "$bin" | sha256sum --status -c -
export HOME="$private/home" XDG_DATA_HOME="$private/data" XDG_CONFIG_HOME="$private/config" XDG_CACHE_HOME="$private/cache"
mkdir -m 700 "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
export LIBGL_ALWAYS_SOFTWARE=1
fail static_import
timeout --kill-after=5s 180s "$bin" --headless --path "$private/stage/game" --editor --import >"$private/import.log" 2>&1
if grep -E 'SCRIPT ERROR:|Parse Error:|Compile Error:' "$private/import.log" >/dev/null; then exit 10; fi
fail x11_prereq
command -v xvfb-run >/dev/null && command -v Xvfb >/dev/null && command -v xauth >/dev/null || exit 11
fail setup_or_render_inconclusive
( set -o noclobber; printf 'one native fixture only\n' >"$private/fixture-started" )
set +e
timeout --kill-after=5s 180s xvfb-run -a -s '-screen 0 1600x1000x24' "$bin" --path "$private/stage/game" --audio-driver Dummy --display-driver x11 --rendering-method gl_compatibility --resolution 1360x880 --position 30,30 --script res://mechanism.gd -- "$private/stage/walls.json" 55abd21e9305293539b88327c9cd1b3dbc46d5a38fe44f77664243851cb42490 "$private/raw.json" >"$private/fixture.log" 2>&1
rc=$?
set -e
if [[ "$rc" != 0 ]] || grep -E 'SCRIPT ERROR:|Parse Error:|Compile Error:|Assertion failed' "$private/fixture.log" >/dev/null; then
  python3 -B "$d/guard.py" fixture-fail "$out" "$private/raw.json"
  exit 12
fi
fail bounded_report_rejected
# No stdout, raw timings, host records, original assets or pixels leave runner scratch.
set +e
python3 -B "$d/report.py" "$private/raw.json" "$private/validated.json" --wall-sha256 55abd21e9305293539b88327c9cd1b3dbc46d5a38fe44f77664243851cb42490 --fixture-sha256 "$(sha256sum "$d/mechanism.gd" | cut -d' ' -f1)" >"$private/report.log" 2>&1
rc=$?
set -e
[[ -f "$private/validated.json" && $(stat -c %s "$private/validated.json") -le 32768 ]]
install -m 600 "$private/validated.json" "$out"
exit "$rc"
