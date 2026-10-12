# UI/UX design system

This is the UI foundation of the Game Production Framework: a reuse and review
contract for the existing game, not a new runtime framework. The
[roadmap](../roadmap.md#current-state) owns product decisions and completion;
document approval does not approve every existing screen or a new visual candidate.
Preserve the original 2D presentation, cream theme and
[art sources and licenses](../art-audio/README.md). Historical
[HUD spacing](../art-audio/history/qa/hud-spacing.md) and
[optical proportions](../art-audio/history/qa/hud-optical-scale.md) are references
with their own acceptance limits, not blanket UI Golden images.

## Reuse-first components and surface roles

Start with the nearest accepted peer and
[`CafeHud`](../../game/scripts/ui/cafe_hud.gd), not a new palette or control toolkit.
Its `theme_panel`, `theme_button`, `theme_panel_contents` and `theme_scroll`
already provide painted surfaces, typography, states and scroll styling.
[`UpdateNotes`](../../game/scripts/ui/cafe_update_notes.gd) demonstrates a panel
that themes itself; generic `Main.button` and `CompactUI._small_button` alone
do not provide that HUD theme.

| Surface | Intended use | Reuse and behavior boundary |
| --- | --- | --- |
| HUD / inline control | Persistent information and frequent actions | Retain the HUD's artwork, optical alignment, native hit targets and existing layout modes. |
| Panel | A bounded settings, information or management task | Reuse the appropriate cream or framed `theme_panel` variant and themed contents; select its input/dismissal policy explicitly. A painted frame alone does not make it modal. |
| Nonmodal notice | Optional availability or contextual status | Use a restrained cream surface and clear actions without stealing focus or blocking unrelated play. Do not add it to the modal wrapper merely to obtain styling. |
| Modal / blocking recovery | A decision whose controller must prevent conflicting actions | Use the existing popup/input lifecycle and entry-aware close/back path. Styling must not weaken save, ownership or transaction fences. |

For each surface, name its owner, opening action, primary action, dismissal route,
return destination and blocking policy. Reuse existing callbacks, sounds and
transaction entrypoints. Any changed policy is a behavior change requiring its
own explicit scope, even when introduced during visual cleanup.

## Typography, spacing and states

- Choose typography by semantic role. Equivalent settings rows, buttons and
  descriptions should use their peers' treatment, not vary because one happens
  to be an `OptionButton`. Existing body text uses Noto Sans; HUD themed actions
  and headings use the existing Nunito bold resource. `theme_panel_contents`
  applies heading styling at 18px and above; it is not a universal text-size fix.
- Keep title, explanation/status and actions visually distinct. Existing panels
  such as Update Notes provide a 22px title / 14px body reference; choose the
  appropriate peer for a compact notice rather than globally scaling all text.
  Measure after fonts and theme padding are applied; never solve overflow by
  silently shrinking important copy or clipping an action label.
- Reuse HUD INK/CREAM/GREEN and `cream_face` / `green_face` materials. Give the
  principal progression action the accent treatment and secondary dismissal a
  quieter treatment. Disabled, hover, pressed and keyboard focus must remain
  distinguishable; color alone must not communicate failure or availability.
- Call `theme_button(primary, true)` before recursive generic theming:
  its `soft_panel_button` guard deliberately prevents re-theming. Review this
  order when composing controls dynamically or after a parent's theme pass.
- Use existing surface padding and peer gaps; `theme_panel` defaults to 16px,
  with explicit framed-panel adjustments. Align painted edges as well as control
  rectangles. Do not apply one spacing number indiscriminately to every surface.
- Preserve at least 44 logical pixels in both dimensions for actionable touch
  targets, including icon-only close controls, and keep adjacent targets distinct.
  Small artwork may sit inside a larger native hit target. Text must fit with
  breathing room, including longer status messages.

## Responsive layout and accessible interaction

Use `CafeHud._safe_insets()` and the existing layout helpers for the surface's
actual role. Its optical edge helpers can align a panel to the HUD; modal
centering/height helpers must not silently change a notice's placement policy.
Check portrait, short landscape and desktop against the affected layout branches.
After resize or content changes, keep titles, close controls and actions inside
the safe viewport. Use a bounded scroll/content fallback where needed, with
critical navigation still reachable; a tall panel is not proof that all content fits.

Preserve readable text wrapping and live glyphs rather than baking text into art.
Keep useful accessible names, purpose and affordability/failure information;
do not replace meaningful status with a decorative tooltip. Essential information
must be discoverable on touch, not only hover. An intentional disabled action needs
a comprehensible reason when that reason is not otherwise apparent.

Verify pointer and touch-target dispatch, Tab/Shift+Tab order, visible focus and
Enter/Space activation. Optional notices must not grab focus on arrival. Closing
a panel should return focus to its initiating control or a valid fallback if that
control no longer exists. Escape, outside click, X and Back follow the surface's
declared policy; blocking operations may legitimately defer them. A screenshot,
emitted signal or synthetic touch event does not establish physical-device or
screen-reader acceptance.

## World-space text and scale readability

Classify scene text by the information it carries: required prices, quantities,
road/navigation labels and interaction instructions must be readable where the
player makes the decision; decorative lettering must not carry their only copy.
Inventory essential text and its source of truth before changing a sign. Keep
the price/count and action purpose available through an existing themed details
surface, with touch and keyboard discovery, rather than relying only on hover.
If a physical sign cannot hold the necessary information, simplify its world
copy and expose the detail there while preserving the object's proportions.
Making every object larger or every label bold is not a readability fix.

Check actual text at minimum, normal and maximum supported zoom. Evaluate font
size/weight, contrast, hierarchy, spacing, edge clarity and background together.
Visual scale and rendering diagnosis follow the
[Art Bible scale/readability standard](../art-audio/ART_BIBLE.md#world-space-text-and-scale-readability).
Distinguish a design problem
from font rendering, texture filtering, cache or zoom-path faults before choosing
the smallest fix; preserve existing theme and interaction semantics.

The first audit case is the parking sign's "FOR SALE" / "4 parking bays" copy,
followed by the scoped inventory of other essential scene text. Establish the
screenshot's build/source and exact draw path first; an unbound screenshot is
an observed example, not proof about a particular commit. A proposed repair needs
actual Godot before/after frames with matched camera/state at normal and enlarged
zoom, minimum-scale QA, and affected Web text-clarity/performance evidence. These
are acceptance gates for that repair, not authorization to edit or recapture the
whole scene. The current standards addition approves no new game pixels.

## Repeated and interrupted actions

Describe ready, busy, success, failure and unavailable states before changing the
layout. Show progress/status without implying success before the controller
confirms it. Preserve disabled controls and required input fences while busy;
expose retry or dismissal only when the underlying state permits them.

Check repeated open/close and activation, resize while open, navigation away,
interruption and return, and late callbacks for the affected flow. Do not duplicate
purchases, saves or reloads; restore focus and state without reviving stale actions.
Closing a visual surface must not commit a preview, discard durable progress or
release an ownership guard. Reuse the existing controller's cancellation and
generation/identity checks. Keep signal connections and retained UI resources
bounded; follow [code health](../development/README.md#code-health-review),
[performance](../testing/rendering-performance.md) and
[memory ownership](../testing/memory-regression.md), rather than adding another
timer, cache or UI lifecycle framework.

## Update Available: concrete reuse failure

The read-only audit pinned main
[`50dd65f`](https://github.com/yiyousiow000814/little-leaf/commit/50dd65f5de1d476019497966206f88cf38cd9c96).
At [`cafe_update_notice.gd:22–30`](https://github.com/yiyousiow000814/little-leaf/blob/50dd65f5de1d476019497966206f88cf38cd9c96/game/scripts/cafe_update_notice.gd#L22),
the notice creates a flat panel, 15px heading, 12px status and two unaccented
`_small_button` actions. It never calls the HUD theme helpers. It is also created
after the one-time popup theme pass in `CompactUI.setup`. These are confirmed
source causes of the theme bypass, not speculation about a developer's intention.

On 2026-10-11 the user explicitly rejected the supplied
`image(20261011-095200).png`. Inspection of that 545x352 crop confirms a
plain pale panel and two equally gray actions beside the illustrated HUD. Its
build/viewport identity is not embedded in the crop, so it is a concrete rejected
visual example, not an exact-build regression capture or an approved Golden.

Actual historical desktop and landscape frames from
[paired run 37926321021](https://github.com/yiyousiow000814/little-leaf/actions/runs/37926321021)
(artifact 11613444512, after `6caa8af4`) show the flat pale surface and equally
gray/beige actions beside the illustrated HUD. That notice's source bytes match
the audited main. The complete historical scene is not current-main proof, and
the receipt says `rendered_pending_pixel_review`; its before desktop view has no
notice. Do not claim there were no screenshots or infer who accepted them.

[`test_update_notice.gd`](../../tests/test_update_notice.gd) checks geometry,
44px targets, repeated actions and safe update behavior. It does not check shared
material/font reuse or primary/secondary visual hierarchy. **Review expectation:**
inspect every dynamically created surface's theme path and actual appearance
beside its HUD peer; passing geometry and producing captures are insufficient.
Treat very long text, focus behavior and short-height fallback as cases to verify,
not defects proven by source inspection alone.

A compact themed notice with “Save and update” as primary and “Later” as secondary
is now the user-authorized first UI pilot, following the foundation. Implementation
and paired desktop/mobile-landscape visual approval remain separate. This document
does not implement or approve its pixels, change
PR135/178, or authorize changes to
[`CafeWebSave`](../../game/scripts/cafe_web_save.gd) cloud-confirmation,
revision/generation, freeze or reload fences. PR176 release ordering and PR188
refresh/session ownership are separate from this visual finding.

## Actual visual acceptance

For a UI change, record the exact base/candidate commits, affected surface and
state, renderer/export, viewport/safe insets and generated fixture. Run the smallest
existing behavior checks that observe the change, then inspect matched actual
game frames at normal zoom. Preserve the same camera, content and interaction
state across each pair; differences must come from the declared candidate.

Select representative affected views and states, not a blanket matrix. For the
notice proposal these would include ready on desktop/portrait/landscape, saving
and a long failure message on short landscape, and visible keyboard focus; also
verify unavailable hides. Inspect visual hierarchy, HUD material/type consistency,
optical alignment, text insets, wrapping, close/action reachability and state cues.
Observe actual input and repeated/interrupted behavior alongside the frames.

Report source inspection, behavior checks, rendered frames, user acceptance,
merge and release separately. Native evidence does not establish Web or physical
touch; browser evidence does not establish a phone's safe areas. A Golden image
must have explicit approval and source/state identity: never promote a convenient
capture automatically. Preserve failed evidence and state remaining limitations.
Use the existing [acceptance entrypoint](../testing/README.md) and required release
gates; documentation or CI completion alone is not user approval of new pixels.
