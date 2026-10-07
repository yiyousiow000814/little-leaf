# 0.1.10 integration candidate

This branch is a combined validation candidate, not visual acceptance, a release,
or permission to merge. Baseline v0.1.9 is exactly
`11c1f8d904b0c4c9a2565cbd557d1552b4ba9401`. Main observed at integration start:
`e9fcf09fe5a975de73b0749e4b3e8484e5e3b2ae`.

## Source binding

- PR #57: `ef7f47feb7c499b63165bc672cd29bd850c4dbc3`
- PR #58: `aa0bb270931188c5cb4cdd1fa160de62531682a7`
- PR #59: `ff14aa5bd022c202a2fbbc009d2f37b3a75393b3`
- PR #60: `5791bf389b0d9499f8f555bf79bc82ba4f9d358c`
- PR #61: `f68a425f642c71ab891db150feb82c1cdd953bba`
- PR #62: `58172e27469b281c466748a41cbfead26d04c58d`
- PR #63: `790b059cdcaba0f051990c00f14b7b5440b4ea34`
- PR #64: `fc3ad12c5d050a51cb76ef7d39317a21b3191f1e`, extending checkpoint
  `bf7cfaf45882dc1fb6412981993929aeed6e2f0f`
- PR #65: `7e473d96977843b6389f1a6b79aa549af43fc588`

Merge ancestry includes #60 through #63 and #59 through #65 once each. The
v0.1.9 baseline already contains the 54–56 stack; none is retargeted or remotely
merged. #57 pauses only the itch publisher. No remote PR is merged by this work.

## Conflict resolution

The 57+58+59 stage retains 76 registered suites plus five startup cases (81
test processes). The full combination retains every suite from each source:
83 registered suites plus five startup cases (88 processes). The exporter
continues to require the exact complete manifest, with no entries removed.

Renderer conflict resolution preserves queue-aware pedestrian advance and
ambient traffic advance. Staff body depth includes cleaning stance offsets.
The original rear tree draws before the shell; the original corner tree and
new environment trees share depth sorting with props and people using one
position/scale schema. Final PR64 greenery retains each TREE_VARIANTS identity
and its precomputed authored contours; the original corner remains oak and the
rear tree remains before the shell. Shelter construction/roof-ground ordering
and deterministic three-form lawn geometry are retained. Beverage ordering remains rotation-specific across
source, cache and foreground rendering. Cleaning cache invalidates on model
identity, revision, position, contact and stance; live shell cache preserves
the explicit-proposal bypass. Queue ledger is separate from customers and
seated patience remains 70/120 seconds. Refund session resets and Done remain.

## Open review gaps

- Pan/cup visual rejections remain unresolved: the annotated image returned 403.
- Environment review is pending. Parking purchase and customer car arrival are
  unimplemented/disabled; static parked cars are scenery, not arrivals.
- Local Windows exports using --local-tools are smoke artifacts and cannot
  qualify as checksum-pinned release exports. Mandatory Linux CI remains.
- Synthetic CPU profiles measure update work, not physical phone temperature.
- Original player saves and other worker checkouts are never test inputs.

## Restore

Clone this repository, fetch the draft integration branch, and check out its
exact recorded commit. Restore v0.1.9 by checking out the immutable baseline
hash above in another fresh directory. Never restore over a player save.
Use tests/run_integration_candidate.py with a fresh output path and isolated
engine/log/userdata directories. The checked-in suite runner creates disposable
synthetic profiles. Run ci/build_web.py only with complete exact-commit evidence,
then ci/build_crazygames.py against that Web build; all browser gates in
.github/workflows/build-web.yml remain mandatory. Do not invoke publishers.
