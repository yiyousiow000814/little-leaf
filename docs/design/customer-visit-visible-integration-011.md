# Visible visit-local clothing candidate

The requested feature is varied customer outfits, not recurring-person identity.
Main in this isolated candidate selects CustomerVisitOutfits; this model adds only
an appearance lookup. It inherits all spawn, tick and native save/load behavior.
The renderer opts in actual guest poses, never staff or ambient pedestrians.

Recipe `customer_visit_bear_v1` is fixed and versioned. Existing saved visit IDs
reconstruct the exact digest-selected outfit across reloads and cache eviction.
Older saves need no migration. Missing/invalid visit IDs retain existing rendering.
No RNG calls, new guest fields, save fields, cloud code or gameplay changes.

Keep this recipe and catalog immutable for stable appearance. Cross-version
catalog migrations, customized customer outfits, new species artwork and platform
consumers which discard visit IDs remain gated. There is no returning-person API
in the visible candidate. The previous identity proposal is not a prerequisite.

The existing reviewed bear head, fur, pose, contact anchors and shading are retained.
Procedural clothing details are review candidates: cardigan buttons, skirt hem,
boots, socks/tights, glasses, cap, ribbon and rear bows. Pending asset contracts
remain pending; no new species art is generated or claimed approved. At seated
poses the table naturally occludes much of the clothing.

Focused synthetic checks cover real spawn, movement, queue allocation, three old
save reloads, exact save bytes and memoization eviction. Native gameplay captures
use the actual Main and Illustration with two seated visits and four settled
queued visits. Save writes by Main are suppressed, all profile paths isolated,
viewport 1360x880; normal zoom 1.0 and detail zoom 1.35 use the same paused phase.
Compatibility OpenGL on Godot 4.6.3 / RTX 3090. This is visual evidence, not an FPS
measurement. Browser/mobile/platform lifecycle acceptance has not been run.

Shared integration files changed only in the isolated candidate: main.gd selects
the model, illustrated_cafe.gd marks actual guests and merges validated options,
directional_character_art.gd draws candidate clothing using existing pose anchors.
Staff customization files and the staff checkout are untouched. Parent must
coordinate these three renderer/bootstrap files during integration.

The contextual port is based on main `93a4221b1f88ba930bdf9e6f92c976a022d57ffc`.
The frozen predecessor packet remains immutable in Library
`libfile_2a978176f8888191888ffa4e7c9dff42`. Its corrected provider is included here
with the related foundation/adapter tests; the reserved `namespace` argument is
`profile_namespace` while the persisted `namespace` key is retained.
No returning-customer model or recurring-person proposal is installed.

The patch applies cleanly against the staff candidate
`e91d34ab9da8be4ea57cb358e8546ae66dc285db`; shared file overlap is `main.gd`.
Staff adapters and its separate QA contract were not altered. Integration still
requires parent coordination if that branch or the common base advances.

Validation on the port: 14 Python contract checks; Godot 4.6.3: 33,576 wardrobe,
5,938 adapter and 36 visit checks, all with zero failures/script errors. Fresh
native gameplay capture also completed with zero script errors. There was an
offline system certificate-store warning; no networking was used by the fixture.
See [normal play capture](../qa/customer-visit-outfits/gameplay.png),
[detail play capture](../qa/customer-visit-outfits/gameplay-detail.png) and
[source-bound validation](../qa/customer-visit-outfits/validation.json).

Run the focused suite with `python tests/run_customer_wardrobe.py --suite
visit_outfits --godot GODOT_EXECUTABLE --output NEW_EXTERNAL_DIRECTORY`.
Use `--suite wardrobe` or `--suite adapter` for the related pure data checks.
Reproduce the native screenshots with `python tests/run_customer_visit_capture.py
--godot GODOT_EXECUTABLE --output NEW_EXTERNAL_DIRECTORY`.
All runners isolate profile directories; the capture suppresses Main save writes.
