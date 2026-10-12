# 0.1.11 street, starter and interface acceptance

Links to existing source: [editor](https://github.com/yiyousiow000814/little-leaf/pull/103), [paint/placement feedback](https://github.com/yiyousiow000814/little-leaf/pull/106), [stove pickup](https://github.com/yiyousiow000814/little-leaf/pull/104), [catalog OCR QA](https://github.com/yiyousiow000814/little-leaf/pull/99). This contract tracks outcomes that must remain visible during integration; it does not claim those existing candidates implement every item below.

## Status and evidence rules

This is an acceptance/design contract only. It does not implement the requirements below, and unchecked boxes mean acceptance has not been established here. Existing candidate source remains in its original PR; this document does not duplicate or promote it. A source-bound implementation PR, exact-head tests and visual review are required before completion. Use generated disposable profiles only. No live saves, account credentials, security settings, merge, release, tag or deployment are included.

## 10 Starter inventory, remaining outcome

- [ ] 10.03: Do not give an unnecessary trash bin in a fresh start, but retain the item for optional shop purchase; preserve already-owned items and saved value.

## 11 Outdoors and traffic

- [ ] 11.01: Hide buses and vehicles while in Decorate mode; restore correct live visibility on exit.
- [ ] 11.02: Buses arrive and depart in distinct trips.
- [ ] 11.03: Bus direction matches its lane.
- [ ] 11.04: Fix the fine white seam at the bus platform.
- [ ] 11.05: Refine bus-stop benches.
- [ ] 11.06: Refine bus-stop sign artwork.
- [ ] 11.07: Connect both road curbs and corridor grass naturally.

## 12 Menus and interface

- [ ] 12.01: Settings orders Inbox, Updates and Help in that sequence.
- [ ] 12.02: Move Log into Help.
- [ ] 12.03: Use an X inside the panel's upper-right corner for close.
- [ ] 12.04: Center the Sign in panel.
- [ ] 12.05: Keep every label/text inside its panel at supported viewport sizes.
- [ ] 12.06: Make blurry text clear without changing its meaning.
- [ ] 12.07: Rearrange the top bar after removing speed controls.
- [ ] 12.08: Show shop imagery with price below and useful, nonduplicated tooltips.

## Acceptance matrix

Check fresh and restored synthetic games, Decorate enter/exit, bus arrival/departure, interrupted panels, resize, portrait and landscape layouts. Verify keyboard/pointer/touch dismissal and repeated open/close. Screenshots and OCR must come from the actual exact-head production UI; passing OCR preprocessing does not establish visual acceptance. Fresh starter changes must not delete historic purchases or alter existing save value.
