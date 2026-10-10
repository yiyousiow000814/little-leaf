# HUD action icon proportions

In wide layouts (at least 850 logical pixels), Decorate artwork is 48 pixels wide instead of 40, and Staff artwork is 48 pixels high instead of 56. This balances the sparse brush/bucket silhouette against the denser staff portrait.

Compact dimensions, Settings scale, original artwork and aspect ratios, shared centerline, 18-pixel wide gaps, 8-pixel compact gaps, 44-pixel minimum targets and Done/Cancel dimensions are retained. The sole production change is seven lines in `scripts/cafe_hud.gd`.

## Verification

Run `python3 tests/run_hud_optical_scale.py` with Godot 4.6.3 installed. It imports and tests a disposable project/profile. The affected suites contain 937 checks: 64 optical-size checks, 838 layout/input checks and 35 cancel-centering checks. They cover both sides of the 850-pixel breakpoint, repeated resize, touch-target separation, rail containment, pointer dispatch and popup dismissal.

The same accepted HUD source also has preserved native evidence: 912 assertions across ten successive window configurations (five distinct mode/size combinations), each in play and edit mode, with three native fullscreen entries and exits. Windowed sizes include 960×540, 960×880, portrait 390×844 and landscape 844×390; fullscreen uses the actual desktop dimensions. The checks query native window mode and size and dispatch pointer events through Godot. After exiting fullscreen, the harness explicitly sets the previous dimensions; automatic previous-window-size restoration is not covered. All four prior compact toolbar comparisons are pixel-identical before and after.

`qa/check_hud_fullscreen.gd` reproduces the native window-mode sequence and refuses headless execution. Set `OUTPUT` to an existing disposable output directory, isolate the XDG data/config/cache profile, then run it with `--fresh-review --visual-qa` on a native display. `qa/capture_hud_optical_scale.gd` reproduces the matched synthetic captures. Neither harness loads player saves, and normal writes are suppressed.

Native proof was preserved before the staff-start merge; the identical HUD source is retested headlessly on that newer main. This does not establish browser Fullscreen API, physical-phone touch/safe-area or audio behavior. No private image payload or game deployment is included.
