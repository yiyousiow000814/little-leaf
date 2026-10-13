# 0.1.10a / 0.1.11 additional acceptance gates

## Status

Documentation only, not implemented by this PR. These four requested outcomes are outside the 76-item 0.1.11 feature inventory. Active implementations or diagnostics must be frozen, reviewed and linked here separately; this PR does not publish them or imply acceptance.

## A. Google sign-in on itch.io

- [ ] Verify sign-in in the actual hosted itch.io embedding/top-level context, including popup/redirect success, cancellation, failure, repeat attempts and interrupted navigation.
- [ ] Treat local development, hosted game and cloud authentication origins as distinct; success at localhost does not certify the itch.io origin.
- [ ] Preserve account identity, ownership fencing and pending-save recovery before applying cloud state. Authentication success alone is not a safe-save result.
- [ ] Keep provider/security configuration unchanged in this documentation task. Any necessary allowed-origin or credential/security change needs a separate explicit approval and bounded review.

## B. Progress while hidden, but not after closing the page

- [ ] A running page may continue appropriate game progression while its app/window/tab is hidden, while preserving the existing save-owner and account fences.
- [ ] Closing or unloading the page does not authorize offline/catch-up progression or a second owner. Do not interpret elapsed wall time after a closed page as hidden-tab simulation.
- [ ] Pause/recovery/user intent and account/owner loss remain authoritative; hidden execution must not bypass them.
- [ ] Cover hide/show, focus loss, repeated transitions, browser timer throttling, two-device ownership change, account switch, recovery, close/reopen and canceled handoffs with generated profiles.
- [ ] Report browser-imposed suspension honestly. Do not claim continuous hidden execution from a timer counter alone.

## C. Actual 60 / 120 FPS behavior

- [ ] Measure actual rendered/presented cadence on appropriately refresh-capable hardware in 60 and 120 modes; a configured cap or label is insufficient.
- [ ] Separate display refresh, engine process FPS, draw/post-draw timestamps and browser callback timing. Do not equate software-renderer CI with user hardware.
- [ ] Record exact source/build, display mode, browser/graphics identity, viewport, scene load, cold/warm conditions and frame-time distribution including stalls.
- [ ] Verify normal gameplay and camera interactions as well as startup; preserve fixed simulation speed, input correctness and save ownership independently of frame rate.
- [ ] A blocked or inconclusive hardware measurement stays pending, rather than being reported as a pass.

## D. Square 64 × 64 camera overview and minimum zoom

- [ ] Treat the complete 64 × 64 world as a square playable-world extent, projected consistently through the isometric camera.
- [ ] Minimum zoom can show the complete intended overview without clipping a world edge; ordinary zoom remains useful and readable.
- [ ] Pan limits are calculated from the same extent/projection and current viewport, including wide, tall and resized windows.
- [ ] Test overview, each corner/edge, zoom-in/out near limits, mouse/touch drag and pinch, Decorate mode and modal interruptions.
- [ ] Preserve world coordinates, collision, owned-land boundaries and save data. Camera framing must not alter gameplay geometry.

## Existing 10a source and diagnostics

- [Save/session/handoff candidate #101](https://github.com/yiyousiow000814/little-leaf/pull/101) and [combined startup candidate #113](https://github.com/yiyousiow000814/little-leaf/pull/113) retain their existing responsibilities.
- [Audio QA #114](https://github.com/yiyousiow000814/little-leaf/pull/114) remains paused and tracking-only here. No audio work is resumed, changed or accepted by this document.
- [Legacy save QA #115](https://github.com/yiyousiow000814/little-leaf/pull/115) and [request-renew race QA #116](https://github.com/yiyousiow000814/little-leaf/pull/116) remain separate diagnostics; do not treat them as a release bundle.
- Final source-bound integration, compatibility and authorized release gates remain mandatory. This PR performs no merge, tag, deployment, production account access or live-save operation.
