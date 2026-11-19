#!/usr/bin/env bash
set -euo pipefail
d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
priv="$RUNNER_TEMP/wall-quad-private"
mkdir -m 700 "$priv"
cleanup() { rc=$?; if [[ $rc != 0 ]]; then "${py:-python3}" "$d/failure.py" "$priv" > "$priv/failure-detail.log" 2>&1 || true; fi; return "$rc"; }
trap cleanup EXIT
unset WALL_CAPTURE_HEADLESS_SMOKE PYTHONOPTIMIZE
fail() { python3 "$d/receipt.py" "$1"; }
python3 "$d/guard.py" event
fail source_staging
python3 "$d/guard.py" stage product "$priv/staged" > "$priv/source.log" 2>&1
fail tool_provision
python3 product/tools/ci/install_tools.py godot --native-only --output "$priv/tools" > "$priv/tool.log" 2>&1
bin="$priv/tools/godot"
fail engine_digest
printf 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3  %s\n' "$bin" | sha256sum --status -c -
fail display_or_decoder
command -v Xvfb >/dev/null && command -v xvfb-run >/dev/null && command -v xauth >/dev/null
# Do not install unpinned decoder packages. Stock Ubuntu image or installed runner Python supplies Pillow.
py=""
for p in /usr/bin/python3 "$(command -v python3)"; do
  if "$p" -c 'from PIL import Image' >/dev/null 2>&1; then py="$p"; break; fi
done
test -n "$py"
export LIBGL_ALWAYS_SOFTWARE=1
for arm in control candidate; do
 r="$priv/$arm"; project="$priv/staged/$arm/game"; mkdir -p "$r/output"
 export HOME="$r/saveguard/home" XDG_DATA_HOME="$r/saveguard/data" XDG_CACHE_HOME="$r/saveguard/cache" XDG_CONFIG_HOME="$r/saveguard/config" XDG_STATE_HOME="$r/saveguard/state"
 mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
 fail "${arm}_import"
 timeout --kill-after=5s 125s "$bin" --headless --path "$project" --editor --import > "$r/import.log" 2>&1
 if grep -Eq 'SCRIPT ERROR:|^ERROR:' "$r/import.log"; then exit 12; fi
 fail "${arm}_stills"
 OUTPUT="$r/output" WALL_EXPECT_ARM="$arm" timeout --kill-after=5s 100s xvfb-run -a -s '-screen 0 1600x1000x24' "$bin" --path "$project" --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --resolution 1360x880 --fixed-fps 60 --script res://capture_wall_quad_parity.gd -- --skip-tutorial > "$r/capture.log" 2>&1
 if grep -Eq 'SCRIPT ERROR:|^ERROR:' "$r/capture.log" || ! grep -q '^WALL_RETENTION_CAPTURE ' "$r/capture.log"; then exit 13; fi
done
fail pixel_qualification
"$py" "$d/receipt.py" verify "$priv" > "$priv/compare.log" 2>&1
# OPTIONAL_COUNTER_BODY
# Image parity has already been sealed. This separate canvas receives original
# submitted triangle streams only; it is not a second normal-game performance run.
scratch="$priv/counter"
mkdir "$scratch"
cp "$d/counter-project.godot" "$scratch/project.godot"; cp "$d/counter.gd" "$scratch/counter.gd"
base64 --decode "$d/counter-scenes.gz.b64" | gzip -cd > "$scratch/scenes.json"
printf '388527b937e67df65e55cbee3b6f88c56b42d2aae9d6b82584d64a3a2825e273  %s\n' "$scratch/scenes.json" | sha256sum --status -c -
export GALLIUM_DRIVER=llvmpipe HOME="$scratch/home" XDG_DATA_HOME="$scratch/data" XDG_CONFIG_HOME="$scratch/config" XDG_CACHE_HOME="$scratch/cache" XDG_STATE_HOME="$scratch/state"
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
timeout --kill-after=5s 60s xvfb-run -a -s '-screen 0 1600x1000x24' "$bin" --path "$scratch" --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --script res://counter.gd --quit-after 120 -- "$scratch/scenes.json" "$scratch/raw.json" > "$scratch/counter.log" 2>&1
if grep -Eq 'SCRIPT ERROR:|^ERROR:' "$scratch/counter.log"; then exit 15; fi
"$py" "$d/finalize.py" "$scratch/raw.json" > "$scratch/verification.log" 2>&1
