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
- PR #64: `c3069e296044d7d2553c42faecccea8edf6de8f6`, extending
  `cf89cda4db6183d4aa77f0b21322dbfd3bf7ba28` and previously integrated
  `07e9ab194a26c03f941b21663eacbe9393cfc576`.
- Cloud-only kerb refinement: `e58d9eb6de6ea6e02c8729b2fb6a8f90b5e65128`
  from the isolated environment branch (locally reapplied as `033b240`).
- PR #65: `7e473d96977843b6389f1a6b79aa549af43fc588`

Merge ancestry includes #60 through #63 and #59 through #65 once each. The
v0.1.9 baseline already contains the 54-56 stack; none is retargeted or remotely
merged. #57 pauses only the itch publisher. No remote PR is merged by this work.

## Conflict resolution

The 57+58+59 stage retains 76 registered suites plus five startup cases (81
test processes). The full combination retains every suite from each source:
85 registered suites plus five startup cases (90 processes), including ordinary mouse/touch environment camera access. The exporter
continues to require the exact complete manifest, with no entries removed.

Renderer conflict resolution preserves queue-aware pedestrian advance and
ambient traffic advance. Bus-stop presentation advances exactly once with the
same active-game delta, while street pedestrians retain queue-aware advance.
The fixed three bus visitors use connected sidewalk/pad/curb-door routes and
never enter the authoritative cafe queue, customer, economy or save state. Staff body depth includes cleaning stance offsets.
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

- Pan reference images are now available. Actual local before/after renders
  have been delivered for the bounded `2c993eda` source plus the pan-handle,
  outside-queue bubble and single-control stove corrections through `c66fa72`.
  These are not renders of the full cloud performance candidate; full-candidate,
  cup and environment visual acceptance remains open.
- Environment and parking visual review is pending. The four-bay fixed Decorate
  purchase and same-ID customer car/queue/dining/return lifecycle are implemented;
  see [parking](parking.md). Focused engine checks are not rendered acceptance.
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

## Environment camera follow-up

The previous combined head 6dd49dadfd5ee8f22c96722b4ed1673578587cf1
clamped panning to cafe land: close views could not reach the bus stop or lot
edge. The follow-up widens traversal only to bounded authored stop/parking
geometry. Cafe-only Home/Fit and camera stability on Decorate/Done remain.
The regression exercises real input dispatch, minimum/maximum zoom, supported
portrait/landscape/desktop layouts and safe insets with synthetic state.
This does not resolve frying-pan/cup visual rejection or accept environment art.

## New cloud candidate, October 7 2026

This candidate starts from remote PR66 `2ce3b2b`, imports the verified curve/grid
changes above, and adds the cloud-only road-facing kerb refinement. It does not
restore or overwrite the newer Windows-only `2c993eda` source or native media.
That checkpoint has no confirmed cloud-readable source handoff; its exact
unpushed diff remains unknown. The historical 55,202,137-byte recovery archive
is bound to `2ce3b2b`, not `2c993eda`.

The kerb adds continuous filled top/road-facing planes, with tapered dropped
shoulders and a flush boarding opening. Fixed square paving, original palette,
presentation visitors were retained in that earlier geometry checkpoint. The
subsequent [parking integration](parking.md) adds separate customer authority.

Independent integration regressions add both edges of both curved approach
ends to ordinary min/max zoom, safe-inset, mouse pan, two-finger pan and pinch
coverage. At `ea3d328`, these produced 15 reach failures. The new repair projects
the actual cached pavement vertices into inspection bounds; `15df60b` passes
all 1,228 checks. Cafe-only Fit, Decorate/Done camera stability and model
authority are still asserted. This is newly implemented cloud source, not an
assertion that it is byte-identical to the Windows repair.

The untouched cloud baseline passed all 90 engine processes / 1,213,052 checks.
Final candidate aggregate/export receipts must be bound to this new candidate;
prior remote CI is not inherited evidence. New cloud graphical capture remains
unverified because the available display/browser launch is blocked. The
checked-in curve/grid images are historical feature evidence, not pictures of
the new kerb. See the October 8 update below for later bounded local captures;
full cloud-candidate visual acceptance remains open.

No remote push, merge, release or deployment is part of this cloud checkpoint.

## Bounded local visual follow-up, October 8 2026

Checkpoint `c66fa723a789628fb61ac2ae041cf2dc93f03a4b` preserves the earlier
rear-handle placement, removes outside-waiting queue bubbles, stops repainting
the rear metal collar over the pan/wood grip, and uses one centered stove control.
The checkpoint records 98 passing headless engine processes / 1,228,339 checks
and 54 passing Python CI guards on that commit. This is historical evidence
for `c66fa72`, not validation of later edits.

Eight actual local synthetic before/after images were delivered for the bounded
`2c993eda` source plus the prior handle correction and new three-fix production
delta. The pan references are no longer blocked by the earlier HTTP 403. These
images do not establish a full-source handoff of `2c993eda`, render the entire
cloud performance candidate, or grant user acceptance of cups, environment art
or the full candidate. Graphical performance and physical phone heat remain
unverified. Release notes stay draft, and itch publication stays paused.
