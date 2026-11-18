#!/usr/bin/env bash
# Run from the coordinator checkout on an ephemeral GitHub runner. Never push.
set -euo pipefail
base=b92fa98eaa2cc97227d61441d7fd00db2d67e345
base_tree=99b14182675f6c323892c8f45a25d76b7bb4ada4
shadow=28f34a88b0a91d154196dac581edf7953389aeb4
shadow_tree=fb1de39fc8462ee0f4ad4ef619ecadaf255e64eb
test "$GITHUB_EVENT_NAME" = push
test "$GITHUB_REF" = refs/heads/diagnostic/preconfirm-capsule-359
test "$GITHUB_REPOSITORY" = yiyousiow000814/little-leaf
test "$GITHUB_RUN_ATTEMPT" = 1
test "$(git rev-parse HEAD)" = "$GITHUB_SHA"
test "$(git show -s --format=%P HEAD)" = "$base"
test "$(git rev-parse "$base^{tree}")" = "$base_tree"
diff -u <(printf '%s\n' 'A	.github/preconfirm-diagnostic/prepare.sh' 'A	.github/preconfirm-diagnostic/source.patch.gz.b64' 'A	.github/workflows/diagnostic-preconfirm-359.yml') <(git diff --name-status --no-renames "$base" HEAD)
test -z "$(git status --porcelain)"
case "$1" in
clean)
  git worktree add --quiet --detach "$GITHUB_WORKSPACE/clean" "$base"
  test "$(git -C "$GITHUB_WORKSPACE/clean" rev-parse HEAD)" = "$base"
  ;;
shadow)
  base64 -d .github/preconfirm-diagnostic/source.patch.gz.b64 | gzip -d > "$RUNNER_TEMP/preconfirm-source.patch"
  echo "aba397fc6bea48a94653c880c4e48ea07f253bfff241c58f7ae7583fd4816d24  $RUNNER_TEMP/preconfirm-source.patch" | sha256sum -c -
  # Private alternate index: neither coordinator nor clean checkout ever changes.
  export GIT_INDEX_FILE="$RUNNER_TEMP/preconfirm-shadow.index"
  test ! -e "$GIT_INDEX_FILE"
  git read-tree "$base"
  git apply --cached --whitespace=nowarn "$RUNNER_TEMP/preconfirm-source.patch"
  test "$(git write-tree)" = "$shadow_tree"
  export GIT_AUTHOR_NAME='Little Leaf Diagnostic' GIT_AUTHOR_EMAIL=shadow@invalid.example
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
  export GIT_AUTHOR_DATE='2026-11-18T00:00:00Z' GIT_COMMITTER_DATE='2026-11-18T00:00:00Z'
  actual=$(echo 'Nonqualifying preconfirm shadow, never publish' | git -c commit.gpgSign=false commit-tree "$shadow_tree" -p "$base")
  test "$actual" = "$shadow"
  unset GIT_INDEX_FILE
  git worktree add --quiet --detach "$GITHUB_WORKSPACE/shadow" "$shadow"
  test -z "$(git -C "$GITHUB_WORKSPACE/shadow" status --porcelain)"
  test "$(git -C "$GITHUB_WORKSPACE/shadow" rev-parse HEAD)" = "$shadow"
  ;;
*) exit 64 ;;
esac
