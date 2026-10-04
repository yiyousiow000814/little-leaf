# Equal spacing for the right-hand HUD actions

The visible Decorate, Staff and Settings artwork shares an optical centerline and equal painted gaps: 18 pixels in wide layouts and 8 pixels in compact layouts. Play mode no longer reserves an invisible Cancel slot. Edit mode expands the rail for the actual Done/Cancel pair. Existing icon proportions, 44-pixel minimum targets and the wooden end inset are retained.

Wallet and business-sign proportions remain stable when only viewport height changes. The already-merged cancel-symbol pivot remains centered. No assets, save data or gameplay rules change.

## Verification

With Godot 4.6.3 and disposable user directories, import the project, then run `godot --headless --path . --script tests/test_hud_layout.gd -- --fresh-review --visual-qa` and the existing `tests/test_cancel_icon.gd`.

The HUD suite checks eight declared viewport sizes from 390×844 through 1360×880 in play and edit states, painted spacing, optical centers, target separation, viewport/rail containment, resize stability and pointer dispatch for pause, speeds, Decorate, Cancel, Staff and Settings. Preserved native comparisons were reviewed separately. Browser and Fullscreen API behavior remain unverified.
