#!/usr/bin/env bash
# Called once inside a single private Xvfb display after an approved full build.
set -euo pipefail
w="$1"; official="$2"; rebuilt="$3"
export LIBGL_ALWAYS_SOFTWARE=1
unset LL397_ENGINE_ARM LL397_ENGINE_TRACE
for id in stock-before rebuilt stock-after; do
    slot="$w/$id"; mkdir -m700 "$slot"
    cp -a "$w/stage/private/." "$slot/"
    export HOME="$slot/home" XDG_DATA_HOME="$slot/data" XDG_CONFIG_HOME="$slot/config" XDG_CACHE_HOME="$slot/cache"
    export LL397_APP_RAW="$slot/app.json"
    if [[ $id == rebuilt ]]; then
        bin="$rebuilt"; export LL397_APP_MODE=rebuilt LL397_ENGINE_TRACE="$slot/engine.tsv"
    else
        bin="$official"; export LL397_APP_MODE=stock
        unset LL397_ENGINE_TRACE
    fi
    timeout --kill-after=5s 210s "$bin" --path "$w/stage/game" --display-driver x11 --rendering-method gl_compatibility --render-thread safe --resolution 1360x880 --position 30,30 -- --engine-attribution-397 > "$slot/display.log" 2>&1
    ! grep -Eq 'SCRIPT ERROR:|Parse Error' "$slot/display.log"
    test -s "$LL397_APP_RAW"
done
