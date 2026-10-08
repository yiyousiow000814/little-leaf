# Branded startup (0.1.10 candidate)

Native boot and the ordinary Web / CrazyGames HTML loaders use the existing approved `assets/branding/little_leaf_approved_v3.png`. The project icon also uses that artwork so exported tab/window icons do not fall back to the engine logo. No artwork, audio, licenses, save formats, game version, publication gate or platform gameplay behavior changed.

## Presentation and handoff

- Native boot uses the intro's `Color(0.8, 0.89, 0.91, 1)` sky, the approved PNG, linear filtering and zero minimum display time. Godot 4.6.3's `boot_splash/stretch_mode=0` means the native splash retains its original size; the default 1360 × 880 native window contains the 783 × 518 art. The HTML shell controls responsive web sizing separately.
- Both shells are visible before any engine or SDK download and have matching sky, quiet clouds, the approved wordmark, and “Welcome to”. The logo's responsive dimensions and center match the start of `cafe_intro.gd`, including short landscape viewports. The CrazyGames SDK retains its official URL and executes before vault boot, but after the branded markup is available to paint.
- Loading starts with an honest “Preparing your café…” status. Known engine byte totals use a styled native progress element; unknown or invalid totals stay indeterminate. Download completion says “Opening your café…” and does not claim the scene is ready. No invented percentage, CSS motion, crossfade or minimum wait is added. Reduced-motion mode hides any browser-supplied indeterminate animation while preserving the live status label.
- Engine startup success and a real `RenderingServer.frame_post_draw` signal must both arrive before the overlay is removed. Either event may arrive first. The web-only, one-shot hook in `main.gd` does not alter the intro timeline or platform gameplay events. Duplicate signals and late events after failure do nothing.
- If the engine resolves but a first frame does not arrive during 45 visible seconds, the loader displays an actionable error instead of revealing an empty canvas. This is only a failure watchdog, never a forced wait or automatic successful handoff. Hidden tabs suspend it; returning to a visible tab starts a new observation window.

## Error and data boundaries

The loader has live status text, meaningful image/canvas/progress labels, literal-text errors, keyboard-focusable Reload, touch-scrollable errors, a text logo fallback and a JavaScript-disabled fallback. Missing engine scripts, constructor errors, feature detection errors, engine startup rejection, unsupported features and the existing service-worker recovery rejection produce a branded error.

The presentation bridge never reads or writes storage, audio, gameplay, account or SDK state. Reload only reloads the page. All embedded inbox, diagnostic, vault, preference and CrazyGames adapter bytes were checked unchanged against the frozen source `0dd4db11`.

Startup order remains vault → preferences → engine, with Godot IDBFS mounting disabled. Ordinary Web still passes failed vault/preferences boot results into the existing protected in-game recovery flow. CrazyGames still rejects failed platform progress or preferences before engine startup, with no local fallback. The loader does not call `loadingStop`, `gameplayStart` or `gameplayStop`; their existing platform conditions remain authoritative.

## Focused checks

Run from the repository root:

```sh
node tests/boot_presentation.js
node tests/crazygames_storage.js
node tests/legacy_byte_storage.js
node tests/compensation_inbox_storage.js
node tests/save_log_privacy.js
node tests/save_log_observers.js
node tests/web_performance_lifecycle.js
```

The loader test executes the exact two shell presentation/startup scripts against a synthetic DOM, including both readiness orders, download totals, duplicate and late signals, missing artwork, literal errors, reload, hidden-tab and stalled-frame handling, missing engine, synchronous constructor/feature errors, engine failure, ordinary Web recovery and CrazyGames fail-closed boot. It does not execute a browser or real player storage.

The pinned Godot 4.6.3 executable also checked the splash configuration and `RenderingServer.SPLASH_STRETCH_MODE_DISABLED` constant in a disposable headless project. This validates configuration support, not native pixels. See the [Godot 4.6 boot settings](https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html#class-projectsettings-property-application-boot-splash-stretch-mode) and [stretch modes](https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html#enum-renderingserver-splashstretchmode).

The combined candidate still needs its final aggregate, both exports, and exported splash-image verification. Real browser/native rendering, precise frame-to-frame visual continuity, warm/cold-cache visual startup, reduced-motion rendering, missing-asset visuals and real CrazyGames hosting remain unverified here: this cloud's browser sockets and graphical renderer are unavailable. No browser security restrictions were disabled, no user desktop was used, and no fabricated screenshot substitutes for that missing evidence.

See [entry motion](entry-motion-010.md) for the coordinated camera-descent change and its separate validation scope.
