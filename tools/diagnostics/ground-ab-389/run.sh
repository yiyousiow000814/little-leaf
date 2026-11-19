#!/usr/bin/env bash
set -euo pipefail
d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
private="$RUNNER_TEMP/ll-ground-ab-389-private"
out="$RUNNER_TEMP/ll-ground-ab-389-public/summary.json"
fail() { python3 "$d/guard.py" fail "$out" "$1"; }
mkdir -m 700 "$private"
fail source_binding
python3 "$d/guard.py" event . > "$private/event.log" 2>&1
commit=1556f2ad1e9985c723f7f3634a3f48535cc411a2
tree=f449331e7ae64da7f19fa62b3554062381cb887c
[[ $(git -C product rev-parse HEAD) == "$commit" && $(git -C product rev-parse 'HEAD^{tree}') == "$tree" ]]
fail source_stage
printf '61040500cf917bc1d16946707bf8415f11a56f28528ff56cc4077e8523652615  %s\n' "$d/probe.gd" | sha256sum --status -c -
printf '2f90bb334d2e3e6799ad024e62b87f9e0e88512d981291c567ce8a08705cd437  %s\n' "$d/report.py" | sha256sum --status -c -
mkdir "$private/stage"
git -C product archive -o "$private/project.tar" "$commit" game
printf '959cb8b47173be82ea921d96144fb6cd91870adccac1191141ddd41ac1ed8229  %s\n' "$private/project.tar" | sha256sum --status -c -
tar --no-same-owner --no-same-permissions -xf "$private/project.tar" -C "$private/stage"
rm "$private/project.tar"
printf '2325055b6ad989c576abddce28d5df9f96b81f90d6fd50bf307aa212a0d24cc5  %s\n' "$d/background.patch" | sha256sum --status -c -
git -C "$private/stage" -c core.whitespace=cr-at-eol apply --check "$d/background.patch"
git -C "$private/stage" -c core.whitespace=cr-at-eol apply "$d/background.patch"
cp "$d/probe.gd" "$private/stage/game/ll_ground_ab.gd"
fail native_tool
python3 product/tools/ci/install_tools.py godot --native-only --output "$private/tools" > "$private/install.log" 2>&1
bin="$private/tools/godot"
printf 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3  %s\n' "$bin" | sha256sum --status -c -
export HOME="$private/home" XDG_DATA_HOME="$private/data" XDG_CONFIG_HOME="$private/config" XDG_CACHE_HOME="$private/cache"
mkdir "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
fail headless_import
timeout --kill-after=5s 180s "$bin" --headless --path "$private/stage/game" --editor --import > "$private/import.log" 2>&1
! grep -q 'SCRIPT ERROR:' "$private/import.log" || exit 11
fail display
command -v xvfb-run >/dev/null && command -v Xvfb >/dev/null && command -v xauth >/dev/null
export LL_GROUND_AB_RAW="$private/raw.json"
fail probe_rgba_or_capture
timeout --kill-after=5s 140s xvfb-run -a -s '-screen 0 1600x1000x24' "$bin" --path "$private/stage/game" --display-driver x11 --rendering-method gl_compatibility --resolution 1360x880 --position 30,30 --script res://ll_ground_ab.gd > "$private/probe.log" 2>&1
! grep -q 'SCRIPT ERROR:' "$private/probe.log" || exit 12
fail report_rejected
python3 "$d/report.py" "$LL_GROUND_AB_RAW" "$out" > "$private/report.log" 2>&1
