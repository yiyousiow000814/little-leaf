---
name: game-art-production
description: Author or revise editable Little Leaf game art, export it and integrate it into Godot using the Art Bible. Use for asset production, not general gameplay or release work.
---

# Game art production

Read the [Art Bible](../../../docs/art-audio/ART_BIBLE.md), the affected
inventory/reference rows and the [roadmap](../../../docs/roadmap.md#current-state).
The Bible is the single visual authority and remains DRAFT until the system and
Bus Stop pilot are approved. Confirm the asset owner and requested phase; keep
character/wardrobe work paused and preserve existing user authorization.

- Pin source/tree and inspect actual original pixels at normal game scale.
  Classify the work as an intentional art upgrade or behavior-preserving
  optimization; use the Bible's different approval/parity gates.
- Choose software for the asset and prove the actual editable workflow. For
  the Bus Stop, prefer Inkscape only after GUI authoring, save/reopen/edit and
  transparent export are demonstrated. Generated SVG/code is not that proof.
  Figma access limitations and the separate Blender lane remain as recorded in
  the Bible. Do not upgrade accounts or install software from this skill alone.
- Calibrate a visible unit grid, logical footprint, pivot and contacts. Keep
  named editable parts and reproducible export settings. Review design before
  integration; preserve the Bus Stop back/people/front split instead of a flat
  sprite. Do not change cameras, routes or collision to fit art.
- Follow the renderer-owned `docs/development/depth-occlusion.md` once its actual
  file/source is verified; the Bible records this pending dependency. Do not
  invent a sorting architecture, magic offsets or broad renderer rewrite.
- Retain source/export identities and follow existing
  [licenses](../../../docs/art-audio/README.md), import/atlas and
  [performance rules](../../../docs/testing/rendering-performance.md).
  Identify retained ownership, invalidation and per-frame cost before the
  smallest owner-relative integration.
- Use synthetic profiles and the minimum affected checks. Capture actual
  same-scene normal-scale Before/After and representative performance, then
  apply [game-art-review](../game-art-review/SKILL.md). Keep source, exported
  bytes and inspected captures bound together; disclose missing evidence.

Return editable source, export/integration identities, evidence and unresolved
choices. Let pilot findings refine the Bible/skills before final standards are
confirmed. Automated checks cannot approve visuals or update a Golden Reference.
This skill grants no additional publication, merge or deployment authority.
