#!/usr/bin/env bash
# Reuse the validated Play prerequisites probe on the recovery/compatibility runners.
set -euo pipefail
d=${1:?expected package receipt directory}
ldd /opt/google/chrome/chrome > "$d/chrome-ldd.txt"
ldd /usr/bin/tesseract > "$d/ocr-ldd.txt"
if grep -F 'not found' "$d/chrome-ldd.txt" "$d/ocr-ldd.txt"; then exit 1; fi
tesseract --version > "$d/tesseract-version.txt"
tesseract --list-langs > "$d/tesseract-languages.txt"
grep -Fx eng "$d/tesseract-languages.txt"
fc-match sans-serif > "$d/font-default.txt"
xvfb-run -a node tools/ci/play_canary.cjs > "$d/browser-canary.json"
