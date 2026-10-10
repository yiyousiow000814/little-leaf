# Testing

Start with [tests/README.md](../../tests/README.md) for existing runners, synthetic fixtures and disposable diagnostics. Choose the smallest check that observes the changed behavior. Required release gates remain separate; passing a test does not accept rendered pixels or authorize publication.

## Product acceptance

Read the [canonical roadmap](../roadmap.md) for current state before these source/date-bound contracts:

- [Characters and wardrobes](acceptance/011-characters-wardrobes.md)
- [Furniture, depth and grounding](acceptance/011-furniture-depth.md)
- [Land, reception and routing](acceptance/011-land-reception-routing.md)
- [Street, starter inventory and interface](acceptance/011-street-starter-interface.md)
- [Separate 10a gates](acceptance/10a-011-additional-gates.md)
- [Original 76-outcome review index](acceptance/10a-011-pr-coverage.md): historical coverage, not current completion status

## Focused verification

- [Routing synthetic cases](rc-inspired-routing-011-qa.md)
- [Fresh tutorial browser gate](fresh-tutorial-browser-gate.md)
- [Actual Web wall-save compatibility](wall-web-compatibility.md)
- [Interactive tutorial](interactive-tutorial.md), [compensation Inbox regression](compensation-inbox.md)
- [Historical evidence directory](history/README.md): retain its source/date and limitations when citing a result

Protect original saves, browser storage and live Firebase rules. Follow [development boundaries](../development/README.md) and [AGENTS.md](../../AGENTS.md).

## Rendering and frame time

Use the [rendering and performance contract](rendering-performance.md) for retained resources, first-frame visual regression checks, normal-speed camera gestures and exact-build Web timelines. Current acceptance remains in the [roadmap](../roadmap.md#current-state).
