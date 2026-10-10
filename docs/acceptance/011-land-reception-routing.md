# 0.1.11 land, reception and routing acceptance

The detailed routing and reception design remains in [PR #112](https://github.com/yiyousiow000814/little-leaf/pull/112); editor transactions remain in [PR #103](https://github.com/yiyousiow000814/little-leaf/pull/103). This document adds a complete outcome checklist and makes the remaining historical-door and discovery gaps explicit. It contains no new routing implementation.

## Status and evidence rules

This is an acceptance/design contract only. It does not implement the requirements below, and unchecked boxes mean acceptance has not been established here. Existing candidate source remains in its original PR; this document does not duplicate or promote it. A source-bound implementation PR, exact-head tests and visual review are required before completion. Use generated disposable profiles only. No live saves, account credentials, security settings, merge, release, tag or deployment are included.

## 07 Doors, windows, walls and land

- [ ] 07.01: Original and newly purchased doors/windows/walls support consistent buy, sell and move actions with correct ownership/payment provenance.
- [ ] 07.02: Doors have consistent one-grid-cell width and visual size. Existing 0.76-width historical doors are not already normalized by PR #103; compatibility and visual migration remain explicit gates.
- [ ] 07.03: Customers and staff enter/exit through actual doors or missing-wall openings.
- [ ] 07.04: Never route through unpurchased land.
- [ ] 07.05: Make door movement and the parking/land purchase entry point easier to discover.

## 08 Reception and waiting

- [ ] 08.01: Customers enter the restaurant first to look for a dining seat.
- [ ] 08.02: When no dining place is available, customers wait near the entrance.
- [ ] 08.03: Unpaired chairs may serve as waiting chairs.
- [ ] 08.04: Customers may sit at dirty tables and wait for cleaning without receiving invalid service.
- [ ] 08.05: Handle vacancy refill, failure to enter and physical clearance after departure without stranded claims.

## 09 Eight-direction navigation

- [ ] 09.01: Use consistent eight-direction routing for customers, staff and cashier flows.
- [ ] 09.02: Disallow diagonal corner cutting through walls, furniture or door frames.
- [ ] 09.03: Replan correctly after layout changes without stale reservations.
- [ ] 09.04: Use bounded soft person avoidance rather than hard mutual blocking.
- [ ] 09.05: Resolve chair/equipment task endpoints and seat ownership correctly.

## Compatibility and acceptance

Preserve cardinal historical saves. New diagonal or reception persistence needs coordinated native, Firebase, ordinary Web and CrazyGames validation; no new version is assigned here. Test explicit supported legacy reception variants and reject malformed input without mutation. Cover full/split dining layouts, dirty-seat claims, waiting-chair promotion, departure clearance, layout changes mid-task, blocked doors, missing walls and unowned land. The previously documented 50 routing cases are a QA plan, not 50 features and not a completed test run.
