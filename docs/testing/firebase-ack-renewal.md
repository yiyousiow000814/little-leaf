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
sign-in, compiled full-flow acceptance or release qualification. The repair is
new source and cannot be represented as unchanged released `a5dd2b2b` bytes.
Fresh source-bound qualification and coordinated approval remain prerequisites
for publication or Firebase activation; do not rerun or bypass the retained
failed staging intent.
