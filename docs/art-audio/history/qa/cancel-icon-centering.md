# Center the cancel symbol

The cancel artwork is a plus rotated 45 degrees. Its default pivot remained at the upper-left corner, so rotation moved the visible X left and below the center of its button. Set the pivot to half the current artwork size after each layout.

This is a one-line presentation fix. It does not change the button bounds, enabled state, input handler, edit behavior, or any other HUD dimensions. The broader HUD/settings proportions change is separate.

Run with Godot 4.6.3 and a disposable profile:

```
godot --headless --path . --script tests/test_cancel_icon.gd -- --fresh-review --visual-qa
```

The test checks transformed glyph/button centers in enabled and disabled states at 1360×880, 960×540, 800×600, 640×480 and 390×844, preserves the artwork's 45-degree rotation and disabled state, and dispatches clicks that cancel an active selection. The fixed version passes all 35 assertions; the baseline fails the 10 center assertions.

Native GL Compatibility before/after edit-state captures use identical 1360×880 and 960×540 viewports, with baseline HUD proportions on both sides so this evidence isolates the cancel symbol.
