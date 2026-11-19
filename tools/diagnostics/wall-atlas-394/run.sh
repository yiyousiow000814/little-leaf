#!/usr/bin/env bash
set -euo pipefail
guide="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
private="$(mktemp -d "$RUNNER_TEMP/wall-atlas-394-private.XXXXXXXX")"
public="$RUNNER_TEMP/wall-atlas-394-public"
# Only this wrapper's fixed failure is printed; everything else stays in runner temp.
set +e
bash -euo pipefail -s -- "$guide" "$private" "$public" >"$private/console.log" 2>&1 <<'PRIVATE'
guide=$1; private=$2; public=$3
  python3 -B "$guide/gate.py" event .
  python3 -B "$guide/gate.py" stage candidate
  python3 -B "$guide/qualify.py" --repo candidate --bind "$guide/binding.json" --lane atlas --verify-only
  python3 -B candidate/tools/ci/install_tools.py godot --native-only --output "$private/engine"
  bin="$private/engine/godot"
  printf 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3  %s\n' "$bin" | sha256sum --status -c -
  command -v xvfb-run && command -v Xvfb && command -v xauth || exit 12
  export LIBGL_ALWAYS_SOFTWARE=1
  xvfb-run -a -s '-screen 0 1600x1000x24' python3 -B "$guide/qualify.py" --repo candidate --bind "$guide/binding.json" --lane atlas --godot "$bin" --output "$private/native"
  python3 -B "$guide/receipt.py" "$private/native/summary.json" > "$private/bounded-receipt.json"
  mkdir -m 700 "$public"
  cp "$private/bounded-receipt.json" "$public/summary.json"
PRIVATE
rc=$?
set -e
if (( rc != 0 )); then
  echo 'Exact original-three wall atlas qualification did not complete. No private evidence published.' >&2
  exit 1
fi
