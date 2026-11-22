# Batch 12: current Main UI qualification

This is a supplemental native check for the exact Main postimage in #394, not a replacement for the historical Mail or Storage captures. The current-only expected SHA-256 in their tooling tests changes from `ce5e31dabaa771689227275ab60fc38e66fd0df294a93077c4aa3543922f0473` to `8c61d1056fc19d206d1bfbfeed6d1f746c94cd32d847ca8c66b0ed84e06b847f`. Historical source/atlas pins, acceptance checks and workflow refs remain unchanged.

| Role | Exact source commit | Exact tree |
| --- | --- | --- |
| #392 control | `0f04d4c196b48b7f6f41462801477a3accbbf510` | `737ef9445cc9462cd56b692c5fc9fe5af27e865f` |
| #394 candidate (direct child) | `bcf98740388339c8be25112d0cbc4b06dd0220a3` | `af80122978a453a01a13312a2c9512a4a818a3f7` |
| Diagnostic only (direct child of candidate) | `686bc546ddf415ac732332f8d0611fa0c1ea9656` | `a571ff4765669a0795e3b06463075ca3fa6eee0a` |

[Hosted native run 44502161978](https://github.com/yiyousiow000814/little-leaf/actions/runs/44502161978), attempt 1, [paired-native job 135484441488](https://github.com/yiyousiow000814/little-leaf/actions/runs/44502161978/job/135484441488). The bounded [artifact 14518275937](https://github.com/yiyousiow000814/little-leaf/actions/runs/44502161978/artifacts/14518275937) ZIP SHA-256 is `699cc3f75c067da2b10a08573c7c08520a2b60740ae5e020d1e4031b7bc311c2`; its sole `summary.json` SHA-256 is `c9d6d0295d8c71a50137ef927b743b75b51cbe863b079febe21d64ae25b1840c`. Archive SHA-256 bindings: control `787f6bb760bf67e299cc12b155531631d58294af44c48166c925b2f4d31eb72f`, candidate `a349072173e33e307200d8b1c87e359a430dd990010cfae68d0c3b75a57ea820`.

| Synthetic fixture | Exact decoded RGBA pairs | Passed assertions per revision |
| --- | ---: | ---: |
| Mail composer | 3 | 162 |
| Parking boundary | 2 | 103 |
| Short Storage panel | 6 | 334 |
| Total | 11 | 599 |

Official Godot 4.6.3, X11/Xvfb and software compatibility renderer on one native runner. No player data writes, raw images or raw logs were published. Unchanged 85-source/three-atlas closure and exact fixture inputs were verified by the diagnostic. These cases pause live game processing; this receipt does not measure order-assignment performance, FPS, Web/save compatibility, or release readiness.
