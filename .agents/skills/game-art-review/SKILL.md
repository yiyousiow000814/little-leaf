---
name: game-art-review
description: Review Little Leaf art changes using actual same-scene normal-scale Before/After, the Art Bible and representative performance evidence. Use for visual assessment, not a generic code review.
---

# Game art review

Read the [Art Bible](../../../docs/art-audio/ART_BIBLE.md) and its relevant
[reference decisions](../../../docs/art-audio/ART_BIBLE.md#reference-and-evidence-registry).
Respect each reference's recorded scope: rejected examples are not approved
baselines, direction images are not paired Before/After, and acceptance of one
screen or asset does not approve others. Missing inspection stays explicit.

Verify source/tree, editable/export/import identities and actual capture files.
Require matching scene, normal play scale, camera, viewport, fixture and relevant
animation/state. Inspect those images first, then explanatory close-ups. A
concept, crop or successful geometry/atlas check does not replace game pixels.

Assess structure/joins, silhouette and proportion, material palette/planes,
detail and visible glyph ink, ground/service contact, occlusion and neighboring
interactions. Check relevant rotations, empty/occupied states and first frames
after motion/zoom. Preserve the asset's layered relationships and current
roadmap boundaries. Retain unresolved source-versus-pixel discrepancies as gaps;
a review does not authorize unrelated repairs.

For Occlusion QA, follow the renderer-owned depth contract through the Bible's
[maintained contracts](../../../docs/art-audio/ART_BIBLE.md#authority-and-existing-contracts).
Check actual-order/continuous-frame evidence and explicit open cases, including
relevant actor/prop crossings and affected Decorate rotations. A bounded
observation is not all-scene or user acceptance. Art approval cannot waive a
depth regression.

Apply the [performance contract](../../../docs/testing/rendering-performance.md)
to a representative candidate/control sample. Check the measured surface,
hardware/load, completed-frame timings, per-frame work and retained-resource
invalidation; use the [memory contract](../../../docs/testing/memory-regression.md)
when lifecycle changes warrant it. Missing measurements remain Pending; a cap or
high average does not prove stable60 or a phone result.

For optimization, enforce retained-control Pixel Parity and investigate
differences. For an intentional upgrade, judge the declared visual change and
remaining regressions; do not demand old pixels or bless new ones automatically.
Report exact evidence, specific findings, smallest next action and a bounded
reviewer recommendation. Keep that recommendation separate from user approval.

Update Approved/Rejected/Pending reference decisions only from actual user
decisions with scope and source. Follow the Bible's current pilot/refinement and
Golden gates before recording a new standard. Automated checks never grant
visual approval. This skill grants no additional merge, deployment, account or
asset-editing authority.
