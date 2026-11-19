#!/usr/bin/env bash
# Only the current candidate runs; no host/driver dump, original re-run, or baseline arithmetic.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && ${GITHUB_REPOSITORY:-} == yiyousiow000814/little-leaf && ${GITHUB_RUN_ATTEMPT:-} == 1 && ${GITHUB_REF:-} == refs/heads/qa/current-native-389-once && ${GITHUB_EVENT_NAME:-} == push ]]
d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
private="$RUNNER_TEMP/ll-current-389-private"; public="$RUNNER_TEMP/ll-current-389-public"
evidence="$public/summary.json"
fail() { python3 "$d/guard.py" fail "$evidence" "$1"; }
mkdir -p "$public"; mkdir -m 700 "$private"
fail source_binding
python3 "$d/guard.py" event . > "$private/event-gate.log" 2>&1
[[ "$(git -C product rev-parse HEAD)" == 1556f2ad1e9985c723f7f3634a3f48535cc411a2 && "$(git -C product rev-parse 'HEAD^{tree}')" == f449331e7ae64da7f19fa62b3554062381cb887c ]]
mkdir "$private/stager"; cp "$d/stage.py" "$private/stager/stage.py"; cp "$d/probe.gd" "$private/stager/native_draw_probe.gd"
python3 "$private/stager/stage.py" --repo product --commit 1556f2ad1e9985c723f7f3634a3f48535cc411a2 --tree f449331e7ae64da7f19fa62b3554062381cb887c --output "$private/stage" > "$private/stage.log" 2>&1
fail fixture_or_sampler_hash
python3 "$d/guard.py" staged "$private/stage" > "$private/binding.log" 2>&1
fail native_tool_install
python3 product/tools/ci/install_tools.py godot --native-only --output "$private/tools" > "$private/install.log" 2>&1
bin="$private/tools/godot"
fail native_tool_hash
printf 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3  %s\n' "$bin" | sha256sum --status -c -
export HOME="$private/home" XDG_DATA_HOME="$private/data" XDG_CONFIG_HOME="$private/config" XDG_CACHE_HOME="$private/cache"
mkdir "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
fail headless_editor_import
timeout --kill-after=5s 240s "$bin" --headless --path "$private/stage/game" --editor --import > "$private/import.log" 2>&1
! grep -q 'SCRIPT ERROR:' "$private/import.log" || exit 11
profile="$XDG_DATA_HOME/godot/app_userdata/Little Leaf Cafe"; mkdir -p "$profile"
cp "$d/fixture.json" "$profile/little_leaf_cafe_layout_motion_v15.json"
export LL_CADENCE_RAW="$private/raw.json"
fail display_startup
command -v xvfb-run >/dev/null && command -v Xvfb >/dev/null && command -v xauth >/dev/null || exit 12
fail candidate_session
# No second game invocation. This shell stamp is private; no raw logs/diagnostic scene IDs are uploaded.
( set -o noclobber; printf 'once\n' > "$private/game-started" )
set +e
timeout --kill-after=5s 225s xvfb-run -a -s '-screen 0 1600x1000x24' "$bin" --path "$private/stage/game" --display-driver x11 --rendering-method gl_compatibility --resolution 1360x880 --position 30,30 -- --diagnostic-active-service > "$private/game.log" 2>&1
rc=$?
set -e
stop_later() {
  fail "$1"
  if [[ -s "$LL_CADENCE_RAW.capped" ]]; then python3 "$d/report.py" --checkpoint "$LL_CADENCE_RAW.capped" "$evidence" "$1" > "$private/checkpoint.log" 2>&1; fi
  exit 17
}
case "$rc" in 0) ;; 2) fail display_or_output_unavailable; exit 2 ;; 3) stop_later probe_output_failed ;; 5) fail initial_cap_not_60; exit 5 ;; 4) fail natural_cooking_not_reached; exit 4 ;; 124|137) stop_later candidate_timeout ;; *) stop_later candidate_session ;; esac
if grep -q "SCRIPT ERROR:" "$private/game.log"; then stop_later engine_script_error; fi
if [[ ! -s "$LL_CADENCE_RAW" ]]; then stop_later missing_measurement; fi
fail capped_window_invalid
python3 "$d/report.py" "$LL_CADENCE_RAW" "$evidence" > "$private/report.log" 2>&1
