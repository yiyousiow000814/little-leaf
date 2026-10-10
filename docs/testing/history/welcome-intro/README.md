# Welcome intro

Integrates the accepted Welcome v3 title and the original 6.5-second sky-to-café
introduction onto current main, preserving the natural new-game staff start,
accepted HUD scale, expansion, worker roles and save retry behavior.

The title artwork is the same accepted alpha-only crop. Its RGB pixels, lettering,
cup, leaves and colours are unchanged. The greeting and skip instruction remain
live UI elements. Original timing, fades, presentation-only camera offset,
skip-gesture ownership, interruption behavior and once-per-session guard remain
unchanged.

## Focused source boundary

Existing source changes are confined to the original intro hooks in `main.gd`
and `illustrated_cafe.gd`. The current fresh-staff hook remains intact. New files
are the intro script, title artwork/provenance and generated-fixture tests.
Private source identifiers are omitted from publication metadata; artwork and
executable source are byte-identical to the accepted integration.

## Reproduce engine checks

Use Godot 4.6.3 and Python 3:

    python3 tests/run_welcome_intro.py

The runner imports a disposable project with isolated HOME, XDG and APPDATA
directories. Normal saves are suppressed and no player save is loaded.

Legacy non-intro runners explicitly use `--skip-intro` so the startup overlay cannot consume their unrelated HUD/input interactions. This does not weaken the separate intro lifecycle checks.

The two focused suites contain 443 assertions covering the timeline, full title,
greeting and skip bounds, aspect ratio, portrait/landscape/desktop projection,
skip press/release ownership, repeated recreation, focus and mode interruptions,
CLI bypass, pause/music flags and startup-recovery visibility. This is headless
scene/logic evidence, not browser rendering, Web storage, audio output or phone
verification. Final combined-build visual QA is tracked separately.

The asset SHA-256 is
`b75415fdf74e98904348264e4851b21401fe2f1ae09a6a277f10849f81564478`.
Existing asset licenses and save storage logic remain unchanged.
