#!/usr/bin/env bash
set -euo pipefail
root=$PWD
tool="$root/tools/diagnostics/active-service"
run_trial() {
  local variant=$1 label=$2 commit artifact
  case "$variant" in
    base) commit=$BASE_COMMIT;;
    candidate) commit=$CANDIDATE_COMMIT;;
    *) return 1;;
  esac
  artifact="$RUNNER_TEMP/cadence-artifact-$variant"
  timeout --kill-after=5s 250s node "$tool/active-service.cjs" \
    --repo "$root/source-$variant" --expected-commit "$commit" \
    --web-build "$artifact/web-build/web" \
    --layout-report "$artifact/engine-evidence/test_interactive_tutorial-result.json" \
    --engine-report "$artifact/engine-evidence/summary.json" \
    --output "$RUNNER_TEMP/cadence-results/$label" \
    --seed-fixture "$tool/synthetic-starter-21walls.json"
}
failures=0
for pair in 'base A1' 'candidate B1' 'candidate B2' 'base A2'; do
  read -r variant label <<<"$pair"
  if ! run_trial "$variant" "$label"; then
    printf '%s failed\n' "$label" | tee -a "$RUNNER_TEMP/cadence-results/trial-failures.txt"
    failures=$(( failures + 1 ))
  fi
done
node "$tool/summarize.cjs" "$RUNNER_TEMP/cadence-results"
(( failures == 0 ))
