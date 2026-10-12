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

## Game feel and animation review

Review how the existing game responds and communicates at natural speed, not just whether an action reaches its final state. This is the testing home for Game Feel & Animation; world behavior, art, depth and audio remain with their domain owners. It introduces no animation system, telemetry, economy change or permission to activate paused character work.

The concrete journey/time contract is in the [Living World contract](../design/living-world.md#time-coherence-and-bus-event-synchronization); historical mechanism confidence and product choices belong to the [gameplay-reference parity contract](../design/gameplay-reference-parity.md). These contracts do not establish accepted runtime evidence. This section supplies the generic experience/evidence method, not competing world behavior rules.

Choose one bounded session that observes the changed behavior. Reuse the existing [routing](acceptance/011-land-reception-routing.md), [contact and depth](acceptance/011-furniture-depth.md), [street and interface](acceptance/011-street-starter-interface.md) and [tutorial](interactive-tutorial.md) requirements rather than multiplying every case into a new matrix.

- Follow a relevant complete journey: arrival/wait/service/departure, or select/preview/confirm/cancel. Observe position, facing, feet, seat/hand contact, held objects and visibility through transitions; final stills cannot establish continuity. Follow the selected Living World contract for custody, clocks and bus events; do not invent door timing or customer demand for a test.
- For affected Decorate interactions, enter Decorate, select and preview, cancel, pan/zoom at human speed, interrupt with an existing panel, return and repeat once. For other interaction changes, observe the relevant repeated/interrupted flow instead; do not add unrelated Decorate steps. Observe the restored state, selection where relevant, feedback and eventual progress. Check only affected pointer, keyboard or touch paths; emulated touch is not physical-device acceptance.
- Record one uncut sequence with a short lead-in and settling period, plus normal-scale transition excerpts. Keep actual completed-frame timestamps or known recording cadence. Observe anticipation, movement/turning, easing, repetition and interruption without prescribing new poses or durations before product approval.
- Listen to the actual captured or played audio at a recorded comfortable volume: cue timing, interruption/resume, intelligibility, repetition, abrupt transitions and visual/audio comfort. A silent video, waveform, file presence or automated audio assertion does not establish listening acceptance. Protect hearing comfort; do not force maximum volume or restart paused audio QA.
- For newcomer understanding, give a goal rather than click instructions. Record what the player predicts, where help is needed and whether waiting or feedback makes sense. Automated tutorial completion is behavior evidence, not proof of understanding.

Report three distinct observations: input-to-visible/audible feedback measured with a common clock or known cadence and its uncertainty (otherwise **unmeasured**); subjective comments quoted without converting them into timing facts; and the user's keep/change/unsure decision for that candidate. A frame cap or average FPS does not establish responsiveness or stable performance. Use the existing [frame-time](rendering-performance.md) and [memory](memory-regression.md) contracts for those separate gates.

## Evidence and acceptance gates

Keep completion and ownership only in the [canonical roadmap](../roadmap.md#current-state). These gates describe what a result supports; they are not a second status ledger. Documentation completion does not mean its pilots, product behavior or user experience have passed.

| Gate | Required evidence and decision |
| --- | --- |
| Scope and design | Name the approved outcome, active owner, dependencies and unchanged save/economy/art boundaries. Distinguish a behavior-preserving optimization from an intentional visual/audio upgrade. Unanswered proposals remain unanswered. |
| Source and behavior | Pin commit/tree, affected tests and actual results. Preserve failures. Use the smallest existing checks that observe the change; required complete CI/release gates remain intact. A passing CI result establishes only its tested scope. |
| Actual presentation | Bind the real candidate/export, fixture and surface to inspected pixels, continuous motion and actual listening where affected. Optimization requires matched visual parity; intentional upgrades require user-approved output before a reference/Golden change. Atlas equality alone cannot accept actor order, motion or interaction. |
| Player decision | Show the actual candidate with its limits. Record the user's decision and exact accepted identity; concept approval, a reviewer pass, an old screenshot or silence is not candidate acceptance. Unobserved paths and subjective concerns stay explicit. |
| Integration and delivery | Verify the composed source preserves the accepted behavior/presentation and dependency deltas occur once. Merge, package qualification and actual platform publication are separate authorized actions under [release guidance](../release/README.md). A Draft, green CI or merged documentation cannot authorize deployment. |

A concise evidence record contains source/tree and relevant export hashes; deterministic fixture inputs; engine/browser/device, viewport/DPR, renderer, focus/visibility and audio route/volume; actions and observed states; original clip/frame/audio locations and timing uncertainty; test results, inspected differences, user decision and unobserved cases. Retain it outside tracked source with failures and teardown receipts, and link it from the existing owner handoff/PR. Do not add another global recording framework or commit private player evidence.

Use generated profiles and synthetic identities, block unnecessary external requests, and never inspect original saves, credentials or player sessions to manufacture acceptance. Admit runtime work through the coordinated nonblocking shared lock; stop if busy, hold it through owned-process cleanup, and report terminal release. Evidence from a different source, engine, viewport or device may explain a hypothesis but must not be relabelled as the current candidate. New asset/toolchain authoring proof belongs to the art/audio contracts; unchanged-art code work reuses valid authoring provenance and proves the affected presentation instead.
