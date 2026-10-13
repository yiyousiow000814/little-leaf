# Bounded Google/cloud-save cutover preparation

This preparation aligns PR124 with main `d2910b4780bcd5321fb6dc72df1cd6300f6d2bdd`
and adds permission-refusal protection. It does not publish rules or Hosting,
upload itch, change credentials/IAM/Auth configuration, or read player data.
The elapsed-business interval-certificate proposal is excluded: it needs a
separate protocol/rules review and must not alter this packet's rules identity.

## Client protection

The frozen released `b8b80ee` adapter is retained as an exact synthetic test
fixture, SHA256 `04774d3495b891c95e00a5525b6d74fab93aa6eb2b84199e065a82369d0fa6bc`.
After a rejected upload it stops further commits, keeps pending payload, digest,
profile and revision in the account journal, and never reports cloud confirmation.
Its existing UI has a generic conflict/reload notice, not the new export panel.
Do not claim the old UI changes remotely or that a Hosting update evicts open tabs.

The compatible client latches a refused-write state, pauses the native game through
the existing ownership bridge, and offers explicit Export pending progress and
Reload updated game buttons. Export rereads the account journal, rejects changed
accounts or another tab's changed entry, and includes the latest final native
snapshot. It neither uploads nor replaces progress. Reload stays on the same
origin; it does not migrate itch-origin local saves or browser storage partitions.

Focused evidence covers frozen legacy refusal, real IndexedDB persistence across
navigation, a same-origin upgrade preserving the exact pending cafe, and a real
SDK/rules fenced acknowledgment. Synthetic Google claims are not real SSO proof.
The existing compiled nine-check proof and seven-rule proof keep their original
source identities; new compiled evidence must bind the new engine and runtime.

## Exact preparation and proposed order

Freeze source/tree, all public files and ZIP digests, candidate rules and original
public/rules recovery bytes. Pin current Hosting version/config and compare public
hashes again immediately before execution; reject unexpected changes. A local
review packet is not automatically eligible for the existing fresh-CI deployment
validator, and fixed auth-pause updater digests must never be repurposed.

1. Review the exact client/rules pair and rollback records; approve the concrete
   destination and maintenance window. Fresh full staging qualification remains
   a distinct claim from bounded synthetic cutover evidence.
2. Tell old clients to stop play and reload the upgraded game at the same address,
   retain pending progress and recovery files, and never clear browser storage.
   Cached/open legacy pages will still be denied after the rule switch.
3. An already authorized operator publishes only the reviewed Firestore rules for
   `little-leaf-41e5d` / `(default)`, then enables the separately approved compatible
   client. Rules and Hosting are not atomic. The saving interruption and stop-on-
   failure condition must be part of the user's action-time approval. Do not
   grant rule permissions to the Hosting-only WIF identity.
4. Verify public inventory/markers and run the user-approved Google/cloud test
   only with a designated disposable account/profile. Abort if it has existing
   cafe progress. Do not seed, overwrite, migrate or clear a real player's save.
5. On failure, pause new clients first. Before any new fenced save, a reviewed
   paired restoration can return the original client/rules. After a new save,
   restoring old rules/clients can permit stale writers and overwrite newer
   progress; stop and review recovery instead of automatic rollback. Rules
   restoration does not undo document writes or restore lost local progress.

The reviewed rule change permits same-UID Google get/create/update at
`players/{uid}/session/owner`, requires an active owner/epoch/lease fence for writes
at `players/{uid}/saves/cafe`, keeps list/delete and other UIDs/paths denied, and
does not itself mutate player documents. Hosting preview and live use the same
database; a production rule change is project-wide, not preview-only.

## Standing two-platform release requirement

After official itch launch, Firebase and itch must share the release version,
reviewed runtime source, compiled game content, and Google/cloud-save backend.
Essential platform wrappers may differ. For every release, compare both public
version/source markers and the `index.js`, `index.wasm`, `index.pck` hashes, and
verify the account branch targets the same Firebase project/save path. Publish
the matching pair or explicitly stop the release; do not silently leave a version
drift. Current test-preview differences are historical evidence, not permission
for future drift. Preparing this requirement authorizes no immediate deployment.
