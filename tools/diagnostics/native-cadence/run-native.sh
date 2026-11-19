#!/usr/bin/env bash
# Only run on the approved cloud runner, never a user's workstation.
set -euo pipefail
HELPER="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
stage="$(realpath "${1:?need staged diagnostic root}")"
out="$(realpath -m "${2:?need new evidence output directory}")"
mode="${3:?choose active-service or manual-early}"
driver="${LL_DISPLAY_DRIVER:-x11}"
binary="$(readlink -f "$(command -v "${GODOT_BIN:-godot}")")"
if [[ "$driver" = x11 && -z "${DISPLAY:-}" ]] || [[ "$driver" = wayland && -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "No permitted cloud display for $driver; completed-frame benchmark did not start" >&2
  exit 19
fi
[[ "$driver" = x11 || "$driver" = wayland ]]
project="$stage/$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["staged_project"])' "$stage/diagnostic-source.json")"
mkdir -- "$out"
export XDG_CONFIG_HOME="$out/profile/config"
export XDG_DATA_HOME="$out/profile/data"
export XDG_CACHE_HOME="$out/profile/cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
cp "$stage/diagnostic-source.json" "$out/"
sha256sum "$binary" | awk '{print $1}' > "$out/engine.sha256"
{ uname -srm; lscpu | grep -E '^(Architecture|CPU\(s\)|Model name|Thread\(s\) per core):'; grep -E 'Cpus_allowed_list|Mems_allowed_list' /proc/self/status; cat /sys/fs/cgroup/cpu.max 2>/dev/null || true; printf 'image_os=%s\nimage_version=%s\n' "${ImageOS:-local}" "${ImageVersion:-unknown}"; } > "$out/runtime-envelope.txt"
# Import is outside the measurement; the checked source was copied from git.
timeout --kill-after=5s 240s "$binary" --headless --path "$project" --editor --import >"$out/import.log" 2>&1
profile="$XDG_DATA_HOME/godot/app_userdata/Little Leaf Cafe"
mkdir -p "$profile"
probe_args=()
case "$mode" in
  active-service)
    fixture="$HELPER/synthetic-starter-21walls.json"
    printf 'ed6fcfc1e4a3396389eff71b09f60740d099de9c046eb0e37eabe900e8c1cf4f  %s\n' "$fixture" | sha256sum --check >&2
    cp "$fixture" "$profile/little_leaf_cafe_layout_motion_v15.json"
    echo ed6fcfc1e4a3396389eff71b09f60740d099de9c046eb0e37eabe900e8c1cf4f > "$out/fixture.sha256"
    probe_args=(--diagnostic-active-service)
    ;;
  manual-early)
    echo MATCHED_FRESH_VISUAL_CHECKPOINT > "$out/fixture.sha256"
    echo 'Focus the cloud game; once agreed fresh starter checkpoint is visibly matched, press F8 once.'
    ;;
  *) exit 5 ;;
esac
timeout --kill-after=5s 210s "$binary" --path "$project" --display-driver "$driver" --rendering-method gl_compatibility \
  --resolution 1360x880 --position 30,30 -- "${probe_args[@]}" > "$out/native-game.log" 2>&1
cp "$profile/diagnostic-native-draw.json" "$out/"
python3 "$HELPER/compare.py" "$out"
