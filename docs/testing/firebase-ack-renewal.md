# Acknowledgment racing a lease renewal

A browser Firestore transaction can receive `permission-denied` when the owner
renews its lease after the acknowledgment transaction reads, even when the
final save and Google-account fixture are correct. The acknowledgment rules
require the original request and the *current* lease timestamp. The controlled
browser/emulator reproduction also returned the ancillary denied save-read
message seen in staging run38079858293. That message alone does not prove an
account or fixture mismatch. The failed compiled run did not retain the exact
transaction inputs, so its precise interleaving remains unproven.

The client recovers only after an independent server read proves a newer lease
timestamp for the same schema, owner, epoch, device and complete request, with
no acknowledgment. It makes one fresh acknowledgment transaction. That
transaction must still match the independently observed timestamp and recheck
the final save digest, revision, writer ID and writer epoch. Timestamp comparison
retains seconds and nanoseconds. A second race, changed request/save/account,
read failure or uncertain outcome remains a failure; the durable journal is
retained. This path neither transfers ownership nor writes a save. Server rules,
the ordinary60-second lease and explicit force-takeover behavior remain unchanged.

`node tests/firebase_session.js` includes the36 bounded-ACK checks and existing
session/request/update regressions. The actual SDK browser regression is a
separate focused emulator check. From `platform/firebase`, with the pinned
dependencies and Playwright available:

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node session_ack.browser.test.mjs /tmp/ack-receipt.json
```

Start a disposable Firestore emulator with the checked-in rules first.
`FIREBASE_TEST_PROJECT` may select another `demo-little-leaf-*` project, and
`PLAYWRIGHT_MODULE`/`PLAYWRIGHT_EXECUTABLE_PATH` may select installed test tools.
The test permits only localhost emulator traffic and locally supplied SDK
modules, uses generated UIDs, and closes its browser and SDK clients. It checks
normal acknowledgment/takeover, one renewal race recovered, two renewal races
remaining paused, and server rejection of the old writer after takeover.

These checks use synthetic authentication. They do not establish real Google
sign-in or release qualification. A separate local complete compiled-flow run
passed all30 checks in103.33seconds with adapter `cb1090c39f3178ab495355a72ba551de922bda44`
and unchanged c runtime `a5dd2b2b3a0cfee9c79fcd75eb870a9892afbf27`. All291 game
inputs matched the immutable ordinary export; the session JS was the only
changed production input. The diagnostic-only report records headless Chrome,
synthetic accounts, fresh disposable native geometry and local Windows4.6.3
tools separately from original CI runtime/native evidence. It covers handoff,
stale writers, local/cloud choice, cancellation, offline pending retention and
update timeout/reload. It does not replace exact-source release qualification.

The [Draft PR160](https://github.com/yiyousiow000814/little-leaf/pull/160) repair is
new source and cannot be represented as unchanged released `a5dd2b2b` bytes.
Fresh source-bound qualification and coordinated approval remain prerequisites
for publication or Firebase activation; do not rerun or bypass the retained
failed staging intent.
