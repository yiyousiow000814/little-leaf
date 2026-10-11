---
name: game-art-review
description: Review Little Leaf art changes using actual same-scene normal-scale Before/After, the Art Bible and representative performance evidence. Use for visual assessment, not a generic code review.
---

# Game art review

Read the [Art Bible](../../../docs/art-audio/ART_BIBLE.md) and relevant
reference/inventory rows. Respect each reference's scope: rejected45f7cd3 is not
an approved baseline; the shelter-style image and road annotation are not paired
Before/After; Settings approval is bounded. Missing inspection stays explicit.

Verify source/tree, editable/export/import identities and actual capture files.
Require matching scene, normal play scale, camera, viewport, fixture and relevant
animation/state. Inspect those images first, then explanatory close-ups. A
concept, crop or successful geometry/atlas check does not replace game pixels.

Assess structure/joins, silhouette and proportion, material palette/planes,
detail and visible glyph ink, ground/service contact, occlusion and neighboring
interactions. Check relevant rotations, empty/occupied states and first frames
after motion/zoom. Preserve shelter back/people/front layering and existing
character pauses. Record the basic-chair source discrepancy as Pending actual
pixel audit unless that scoped audit has been performed; do not repair it here.

For Occlusion QA, use the renderer-owned [depth contract](https://github.com/yiyousiow000814/little-leaf/blob/e3a71b24ca220bc27bb4abbd13fbdaee88e9ecfe/docs/development/depth-occlusion.md).
Its canonical home `docs/development/depth-occlusion.md` awaits main integration.
Check its actual-order/continuous-frame evidence and explicit open cases, including
relevant actor/tree crossings and Decorate rotations. Existing bounded observations
are not all-scene acceptance or PR189 user approval. Art approval cannot waive a
depth regression; the Bible retains the source reference and approval limits.

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
decisions with scope and source. The Bus Stop pilot must refine the draft system
before the user approves both and a Golden Reference is recorded. Automated
checks never grant visual approval. This skill grants no additional merge,
deployment, account or asset-editing authority.
