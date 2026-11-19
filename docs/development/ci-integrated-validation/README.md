# Integrated ordinary Web validation

Exact local code: `1d73bad631657c5a3ee955208a618c2103d1863a` / tree `64650412571a41f4b01e5aabff8306c3ede32acf`. [Mermaid](integrated.mmd) · [Excel](integrated.xlsx).

The two #394 siblings (walls #396 `22c591d0` and furniture #395 `35a01aa7`) are combined with #391 `94f694d` and the signed WebKit refresh patch `3beee897f9ff1274339ccccb9a8be5cdd482fa04bf7482057e1c209779fd1e94`. Retry GNU timeout 124 only: first 50 s, one bounded retry, 75 s aggregate including grace. The existing 300 s step is unchanged. Signed full refresh must pass before solving; no package, signature, browser, assertion or harness relaxation.

Local composite preflight passed 532 Python tests plus JS and atlas guards in 24.15 s; atlas scope is 85 sources/three families. Focused Mail/Storage passed 22. Earlier #391 green in 8:52 applies only to its old stack; #393 was red on signed refresh and the real Save B assertion. Hosted CI must still run once in a fresh, complete ordinary main-target PR and report wall time against the five-minute target and ten-minute maximum. Main-push, release and 60 FPS remain unqualified.
