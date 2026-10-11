# Manual Firebase reuse of a completed release

This candidate removes the second ordinary engine/export/browser matrix from
manual Firebase qualification. It does not deploy or apply security rules.
The existing automatic `released_run_id` contract remains
`qualified-release-staged-not-deployable`; its activation flags remain false.

After a completed exact-source itch publication, an approved main dispatch of
`stage-firebase.yml` may select `released_live_run_id` alone. This selects the
original immutable main CI runtime and evidence through the existing coordinator.
It preserves all ten focused Firebase gates, packed startup verification, source
geometry preparation and compiled Web/UI flows against disposable Firestore rules.
It does not run another full native suite, ordinary export or ordinary browser
matrix. Fresh staging and trusted previews retain their existing paths.

The distinct output status is `manual-released-live-qualified`. It retains exact
original manifest bytes, native/export/browser receipts, completed publication
order, current focused/compiled receipts, runtime hashes and public config. The
released transformer executes from the exact released checkout. Coordinator SHA
and tree remain separate from runtime/source SHA and tree; an older release may
be reused only when it is an ancestor of that exact coordinator. No byte or version
relabeling is permitted.

The existing `deploy-firebase.yml` live route requires the selected manifest hash
and immutable artifact origin. Before WIF it freshly checks successful same-repo
main attempt-1 staging, the original successful main qualification and mandatory
jobs, its unexpired artifact digest, successful completed itch publication and
unchanged tag, coordinator/source hashes and ancestry. The packet validator binds
the complete evidence, config, loaded marker and runtime. Network execution repeats
local validation using the authenticated origin receipt. Existing WIF identity,
Hosting scope, complete config preservation, mutation journal and no automatic
rollback policy remain unchanged. This qualification does not substitute for
review, production rules approval or real Google/device acceptance.

There is no safe current shortcut from a PR artifact to a squash-merged main SHA:
the projected version inside the packed runtime contains the export source SHA
prefix, and trusted reuse rejects PR workflow events. Main still needs its own
exact-source qualification. For SHA releases, live qualification requires a
completed Butler channel-order receipt; Hosting cannot run in parallel with that
publication. No new parallel delivery design is introduced for the roughly one
minute itch step.

Recent reference durations supplied for planning were main CI 9m45, fresh Firebase
15m28, canonical atlas checks 54s, itch 1m06 and Hosting 32s. The removed work is the
ordinary matrix duplicated within fresh Firebase, not canonical/main qualification,
itch or Hosting. New manual focused/compiled duration and end-to-end savings have
not been measured. Synthetic protocol tests establish contracts, not runtime or
production performance.
