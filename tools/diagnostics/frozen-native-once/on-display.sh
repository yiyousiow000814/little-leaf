#!/usr/bin/env bash
# The only call path into the original sampler; do not invoke outside the one guarded Actions step.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && ${GITHUB_RUN_ATTEMPT:-} == 1 && ${GITHUB_EVENT_NAME:-} == pull_request ]]
[[ ${GITHUB_REPOSITORY:-} == yiyousiow000814/little-leaf && ${GITHUB_HEAD_REF:-} == qa/frozen-native-integrated-once ]]
d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
e="$RUNNER_TEMP/frozen-native-evidence"; tmp="$RUNNER_TEMP/frozen-native-tmp"
[[ ${LL_DISPLAY_DRIVER:-x11} == x11 && -n ${DISPLAY:-} && ! -e "$e/sample-started.txt" && ! -e "$e/candidate" ]]
# Keep blank probe and real sampler on this one X11 server; separate their profiles.
mkdir -p "$tmp/pre/home" "$tmp/pre/config" "$tmp/pre/cache" "$tmp/pre/data" "$tmp/measurement-home"
cp -r "$d/envelope-only" "$tmp/envelope-only"
HOME="$tmp/pre/home" XDG_CONFIG_HOME="$tmp/pre/config" XDG_DATA_HOME="$tmp/pre/data" XDG_CACHE_HOME="$tmp/pre/cache" \
  LL_ENVELOPE_FILE="$e/graphics.json" timeout --kill-after=3s 30s "$GODOT_BIN" --path "$tmp/envelope-only" \
  --display-driver x11 --rendering-method gl_compatibility --resolution 1360x880 --position 30,30 \
  --script res://inspect.gd > "$e/preflight-graphics.log" 2>&1
bash "$d/host-envelope.sh" "$e/presample-host.txt"
cmp "$e/host.txt" "$e/presample-host.txt"
python3 "$d/control.py" envelope --host "$e/presample-host.txt" --graphics "$e/graphics.json" --graphics-log "$e/preflight-graphics.log"
python3 "$d/control.py" stage --repo product --stage "$tmp/staged"
# All eligibility gates must have completed. One invocation only, no loop/retry/continuation.
( set -o noclobber; printf 'native-candidate-only\nrun=%s\nattempt=%s\ndiagnostic=%s\n' "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" "$DIAGNOSTIC_SHA" > "$e/sample-started.txt" )
HOME="$tmp/measurement-home" LL_DISPLAY_DRIVER=x11 bash "$d/upstream/run-native.sh" "$tmp/staged" "$e/candidate" active-service > "$e/candidate-summary.json"
python3 "$d/audit.py" --archive "$d/frozen.zip" --helpers "$d/upstream" --candidate "$e/candidate" --binding "$d/binding.json" > "$e/comparison.json"
