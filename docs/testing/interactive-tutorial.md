# Interactive tutorial (developer preview)

This guide is part of the developer candidate. It is not publication or platform-submission evidence.

## Player flow

1. On a genuinely new profile, the cafe starts closed with the real Open sign highlighted.
2. Open the cafe, then open Staff. Close Staff with its real Done button.
3. Open Decorate, browse the catalogue and return with Done. No purchase is required and no service wait gates this lesson.
4. Watch a naturally arriving guest sit and place an order.
5. Follow cooking, serving, eating and checkout. The guide waits for a real completed payment.
6. Dismiss the completion card and continue playing.

The guide is non-modal. Pause, camera movement, other menus and ordinary controls remain available. Interruption prompts point to the actual Resume, Reopen or Done control; they do not change the player's state automatically. Skipping while closed explicitly offers **Skip & open cafe**. Help & Updates offers Resume or Replay, plus Restart for an unfinished guide.

There are no tutorial guests, accelerated service timers, hidden payments, free purchases or camera-range changes. A long offscreen approach in the underlying arrival system remains observable and must be tested separately from the guide.

## Persistence

Optional `tutorial` metadata stores format, status, step and the served-count baseline. It uses the existing save path, schema version and save/CAS/recovery mechanisms. Existing saves without this metadata are not auto-enrolled, closed or reset. Invalid optional metadata is ignored without discarding a valid cafe. Replay does not reset the layout, roster, wallet or service runtime.

## Verification

Run the focused fixture using the disposable regression runner:

```sh
python3 tests/run_integration_candidate.py --output /tmp/little-leaf-tutorial-qa --only test_interactive_tutorial
```

The fixture dispatches mouse/touch events to the real controls, uses ordinary main-loop service ticks, and observes actual order/eating/checkout phases. It covers interrupted scene reloads, completed/skipped state, replay baseline, existing saves, recovery-safe optional metadata and supported mobile/desktop layouts. These are accelerated engine checks, not real-time first-impression measurements.

Other regression fixtures use `--skip-tutorial` to retain their explicit preexisting scope. The dedicated tutorial fixture does not bypass onboarding.

For rendered evidence, prepare an isolated project, import it with Godot 4.6.3, then run that project through the cloud-native Godot window:

```sh
python3 tests/prepare_tutorial_native.py --output /tmp/tutorial-native-saveguard
```

The generated project has a unique saveguard profile and automatically writes screenshots plus `native-result.json`. Preparation alone is not a render pass. Inspect the actual screenshots before accepting visual QA. All preparation/engine jobs must respect the shared Godot lock and native UI work must be coordinated with other running checks.
