#!/usr/bin/env bash
# Local review draft, not a launched workflow.
set -euo pipefail
d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
product="$(realpath -- "$1")"; recovery="$(realpath -- "$2")"
w="$RUNNER_TEMP/ll397-stock-aa-private"; out="$RUNNER_TEMP/ll397-stock-aa-public/summary.json"
fail() { python3 -B "$d/stock_preflight.py" fail "$1" "$out"; }
mkdir -m 700 "$w"
fail source_binding
[[ "$(git -C "$product" rev-parse HEAD)" == ce1435afb2329a6c1d2d77a8a19923dfd96bd205 && "$(git -C "$product" rev-parse 'HEAD^{tree}')" == 03632a0d56e4294f5664859656c8809541766d1b ]]
[[ "$(git -C "$recovery" rev-parse HEAD)" == 792f2db289cf62d76541c98e395ee002ae3f7654 && "$(git -C "$recovery" rev-parse 'HEAD^{tree}')" == 3cce6421c1f85f72823d46cc70981c9c3c5643c2 ]]
prior="$recovery/tools/diagnostics/engine-attribution-397"
(cd "$prior" && sha256sum --quiet -c "$d/recovery-stage.sha256")
python3 -B "$prior/prepare.py" "$product" "$w/stage" > "$w/stage.json" 2> "$w/stage.log"
fail display
for name in Xvfb xvfb-run xauth; do command -v "$name" >/dev/null; done
fail official_pin
export HOME="$w/stage/private/home" XDG_DATA_HOME="$w/stage/private/data" XDG_CONFIG_HOME="$w/stage/private/config" XDG_CACHE_HOME="$w/stage/private/cache"
if [[ $# == 3 ]]; then
    stock="$(realpath -- "$3")"
else
    python3 -B "$product/tools/ci/install_tools.py" godot --native-only --output "$w/tools" > "$w/install.log" 2>&1
    stock="$w/tools/godot"
fi
printf 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3  %s\n' "$stock" | sha256sum --status -c -
v="$(timeout 5s "$stock" --version)"
[[ "$v" == 4.6.3.stable.official.7d41c59c4 ]]
fail import
timeout --kill-after=5s 180s "$stock" --headless --editor --import --path "$w/stage/game" > "$w/import.log" 2>&1
! grep -Eq 'SCRIPT ERROR:|Parse Error' "$w/import.log"
fail session
timeout --kill-after=5s 360s xvfb-run -a -s '-screen 0 1600x1000x24' bash "$d/stock_measure.sh" "$w" "$stock" > "$w/sessions.log" 2>&1
fail invalid_app_receipt
python3 -B "$d/stock_preflight.py" package "$w" "$out" > "$w/validation.log" 2>&1
