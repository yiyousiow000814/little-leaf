# Background-only welcome cache candidate

This is a performance experiment, not accepted smoothness or a release.

## Runtime boundary

Only `CafeBackgroundCache` changes. While the intro is active, a separate retained canvas holds the unchanged world commands covering the remaining finite descent. The screen fill remains fixed. Camera translation is applied to the retained canvas. At intro completion, the ordinary background cache is rebuilt once and resumes its original behavior. An unexpected pan outside the coverage, changed projection, viewport, opacity, resource, or ownership invalidates the cache. Unsupported drawing states fall back. Both canvases are freed with the cache.

The parent shell code is unchanged. No first-gesture/audio, HUD setter, gameplay, save or artwork change is included. The source-hash manifest was regenerated after actual native procedural/pre-generated atlas RGBA equality (three of three).

## Local evidence, not browser acceptance

Godot 4.6.3 official, X11, Mesa llvmpipe LLVM 19.1.7, 1360×880 SubViewport. Eight warm-process trials, four configurations then reverse order; every accepted trial completed the full 6.5-second intro. No UI interaction or screenshot occurred during the accepted measurement. Newly generated model per trial; save writes suppressed.

Original descent medians: 34.682 / 31.243 ms. Background-only: 27.796 / 28.772 ms. Original p95: 48.884 / 47.597 ms. Background-only: 43.563 / 45.370 ms. Background rebuilds: 162 / 167 versus 2. Restaurant medians remained approximately 36–38 ms. Shared shader/atlas cache history and small sample size limit interpretation. Shell-only did not show a consistent extra benefit and is excluded.

Expanded fixed-position raster comparisons, 29 positions at two sizes, ABBA order:
- 32 / 58 pairs are exact RGBA in both directions.
- Other pairs differ by no more than 1 / 255 per channel, maximum 213 pixels (0.0178% of the worst frame).
- Original repetitions and candidate repetitions are each 58 / 58 exact.
- Both final settled frames are exact.
- Inspected difference masks trace original antialiased pavement/curb boundaries, without a perceptible shape or contact change.

Strict byte/pixel equality is not claimed for moving frames. CI may accept explicitly requested intro-only antialias rounding bounded to one channel step and 0.025% changed pixels. Settled frames and all regenerated atlas pixels must remain exact. The report always preserves exact status and observed counts.

Focused independent-source checks passed 12,646 assertions before the manifest-only refresh. Python guards, source closure and diagnostic JavaScript hooks are separately tested.

## CI comparison contract

The native workflow uses the immutable pre-generated-atlas parent `df115a085437633e3538ef5462401f57739fc935` as control, with fresh per-run source archives and profiles.

For the focused `perf/background-cache-startup-10a` draft, the Web workflow freshly tests and exports that control in a parallel job. It compares the existing full-gate candidate export and the same-run control export on one runner, in baseline/candidate/candidate/baseline order. Each launch contains cold and warm HTTP-cache trials with disposable fresh game storage. No historical artifact is substituted. Source maps and export hashes must match each checked-out product.

Separate traces collect CPU sampling, loader/boot/Wasm markers, slow WebGL calls, renderer identity and graphics flags; tracing overhead is excluded from timing. Timing also retains callback execution timestamps alongside browser-supplied rAF timestamps, DOM loader removal, and per-process RSS/high-water RSS for the disposable browser processes. Shared pages prevent interpreting a sum of process RSS as unique physical memory.

No merge, deployment, production Firebase operation, real player save, audible-audio claim or smooth-60-fps claim is authorized by a passing diagnostic run. Review actual cold startup, post-loader gaps, transition/restaurant distributions, memory and renderer comparability first.
