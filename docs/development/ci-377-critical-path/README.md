# CI critical path: #377 and isolated APT retry

[Hosted run 44474276265](https://github.com/yiyousiow000814/little-leaf/actions/runs/44474276265), attempt 1, exact head `f586b7905c3a50bacd4ee82964955d67d6888699`. Full gate **failed closed in 10:21**; first guard started about 2 seconds after creation, so there was no meaningful initial queue. Build passed at +4:26; browser lanes began at +4:28. Six Curl r28/r52 transfers were rescued across lanes, three in Play.

Play passed and was the slowest required lane: 239.338 seconds for the test, of which 228.948 seconds were actual validation. Tutorial completed at 99.259 seconds and first payment at 227.602 seconds of the Play timeline. Do not add those cumulative checkpoints together or read them as individual step durations. The final gate took 23 seconds. This run did not establish stability or meet the 10-minute ceiling.

- Compatibility case A (old-opened-after-new) passed. Case B (already-open-old) reached the save check and observed revision 5 instead of expected 4; cause not established.
- WebKit: signed APT refresh and package solving succeeded; download-only timed out after 100.009 seconds, before browser recovery assertions ran. That is a separate failure from case B.
- Local follow-up: at most one restart of the same signed download-only command on GNU timeout 124. The first attempt is bounded at 65 seconds and the retry uses only the remainder of the original 100-second aggregate budget, including subprocess grace. Same private signed source/index/cache; no mirror fallback, integrity-error retry, or change to offline installation. Full local preflight passed 526 checks; no hosted evidence yet.
- Next investigation: prefetch independent, pinned inputs in parallel where dependency order permits, preserving source receipts and hashes. No savings have been measured. Keep the real tutorial, payment, and recovery checks and the fail-closed gate.
