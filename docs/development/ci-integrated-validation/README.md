# Integrated ordinary Web validation

Exact local code: `1d73bad631657c5a3ee955208a618c2103d1863a` / tree `64650412571a41f4b01e5aabff8306c3ede32acf`. [Mermaid](integrated.mmd) · [Excel](integrated.xlsx).

The two #394 siblings (walls #396 `22c591d0` and furniture #395 `35a01aa7`) are combined with #391 `94f694d` and the signed WebKit refresh patch `3beee897f9ff1274339ccccb9a8be5cdd482fa04bf7482057e1c209779fd1e94`. Retry GNU timeout 124 only: first 50 s, one bounded retry, 75 s aggregate including grace. The existing 300 s step is unchanged. Signed full refresh must pass before solving; no package, signature, browser, assertion or harness relaxation.

Local composite preflight passed 532 Python tests plus JS and atlas guards in 24.15 s; atlas scope is 85 sources/three families. Focused Mail/Storage passed 22. Earlier #391 green in 8:52 applies only to its old stack; #393 was red on signed refresh and the real Save B assertion. Hosted CI must still run once in a fresh, complete ordinary main-target PR and report wall time against the five-minute target and ten-minute maximum. Main-push, release and 60 FPS remain unqualified.

## Hosted receipts and non-PR gate

- [Ordinary PR run 44510115110](https://github.com/yiyousiow000814/little-leaf/actions/runs/44510115110) passed in 9m 56s at `ce1435afb2329a6c1d2d77a8a19923dfd96bd205` against `8c415d94fdb86e68dd0ce90d3482f9e668e8805d`. Real Play, Recovery, CrazyGames, both old-save cases and the final aggregate passed. It passed the 10-minute ceiling, not the five-minute target. This is a prior exact run, not the requalified head.
- [Main run 44460244371](https://github.com/yiyousiow000814/little-leaf/actions/runs/44460244371) recorded skipped browser jobs after optional PR preflight was skipped, and the gate correctly failed. Adopt the narrow [#367](https://github.com/yiyousiow000814/little-leaf/pull/367) guards in the integrated flow: require no cancellation and successful direct needs for Play, Recovery, compatibility and Firebase. Preserve the Firebase preview flag and the final evidence gate. [Isolated non-PR run 44461860270](https://github.com/yiyousiow000814/little-leaf/actions/runs/44461860270) passed for #367; it is not validation of the integrated head.
- Fresh final-head ordinary CI and a no-deploy non-PR qualification are pending. No release, measured FPS improvement, or 60 FPS acceptance follows from these checks.
