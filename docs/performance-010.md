# 0.1.10 performance investigation

Baseline: `11c1f8d904b0c4c9a2565cbd557d1552b4ba9401` (v0.1.9).
The candidate changes only hidden legacy customer synchronization and live shell-edge lookup. Illustrated animation, frame cap, service clocks, path selection, proposed-layout checks and save formats remain unchanged.

## Reproduce

Use Godot 4.6.3, GL Compatibility, a disposable checkout and matching non-threaded Web template. Never run this fixture against an original player profile. `ProfileMain` intercepts startup and saves and uses generated state. Do not overlap graphical benchmarks, exports or heavy tests.

```
python qa/prepare_performance_profile.py --source BASELINE --output NEW_NATIVE_COPY
godot --headless --path NEW_NATIVE_COPY --editor --import
python qa/run_profile_native.py --project NEW_NATIVE_COPY --output NEW_EVIDENCE --godot GODOT_EXE

python qa/prepare_performance_profile.py --source BASELINE --output NEW_WEB_COPY --web-template WEB_TEMPLATE_ZIP
godot --headless --path NEW_WEB_COPY --editor --import
godot --headless --path NEW_WEB_COPY --export-release Web NEW_EXPORT/index.html
python qa/run_profile_web.py --web NEW_EXPORT --output NEW_WEB_EVIDENCE
```

Repeat against the candidate with the same fixture. The native/browser launch helpers currently target Windows and installed Chrome. A `PAUSE_BENCHMARKS` file in the evidence parent prevents further native launches. All created browsers, servers and engine processes are owned and closed by their runner; unrelated processes are never stopped.

Scene: generated minimal café with one guest moved to its first route waypoint and four deployed staff. Fixed seed 1337, 1360×880, DPR 1, target frame cap 60, 120 warmup frames, 600 measured frames and fixed simulation step 1/60. Music is disabled in both fixtures. The cap is a maximum, not an achieved frame rate. The additional edge batch performs 21,000 repeated boundary queries outside the frame samples.

## Observed results, 2026-10-07

Windows desktop: Godot 4.6.3, NVIDIA RTX 3090, driver 595.97. Web: Chrome 151.0.7922.138, ANGLE Direct3D11 on the same GPU. One complete serial native pair and one complete serial Web pair are retained, alongside initial native exploratory runs.

| Metric | Native before | Native after | Web before | Web after |
| --- | ---: | ---: | ---: | ---: |
| 21,000 shell-edge queries, ms | 328.657 | 20.112 | 279.100 | 27.400 |
| Customer/staff sync over 600 frames, ms | 32.205 | 11.103 | 40.400 | 8.300 |
| Sync calls | 1,200 | 600 | 1,200 | 600 |
| Controller mean, ms/frame | 1.285 | 1.781 | 1.524 | 1.468 |
| Frame interval mean, ms | 18.067 | 24.319 | 38.079 | 38.087 |

The isolated shell batch improved by 93.9% native and 90.2% Web. Hidden-customer synchronization improved by 65.5% native and 79.5% Web. The native whole-frame result is slower and inconclusive under shared desktop conditions; it is not presented as an improvement. Web controller savings are small and Web frame cadence is essentially unchanged. Other desktop processes existed, and subsequent repeated pairs were paused after a separate Godot GUI crash report at 05:23 UTC. A clean repeated whole-game comparison remains outstanding. No physical iPhone, power or thermal improvement has been measured.

Customer and staff state signatures match exactly in both pairs. Native before/after PNGs are byte-identical (SHA256 `99717b1e905c31cc92f88af4f7f2a0757ab0581acf2737c1e49053b557236236` in the original pair), as are Web pair screenshots. These establish parity at the sampled scene/time, not universal visual equivalence.

## Decisions and remaining work

The hidden 3D customer meshes were updated twice each active frame although the viewport explicitly disables 3D. The candidate retains staff roster synchronization and the legacy customer path when 3D is enabled, but skips those invisible mesh and dialogue updates in the illustrated game.

Shell-edge navigation repeatedly resolves the same opening cuts. Live queries now cache both open and closed edges by the existing conservative model revision. Explicit proposed-wall/opening inputs bypass the cache. Regression coverage checks both directions, preview isolation, door removal, reset and shortened shells.

The unconditional 2D redraw includes animated street traffic, pose blends and live service. Lowering its cadence would affect presentation, so this patch retains it. Static/dynamic rendering separation and richer active-scene profiling need separate investigation. PR59's floor-cleaning approach scans are investigated on a separate integration branch; they are not included in the v0.1.9 baseline measurements above.

Focused engine validation: eight suites, 2,506 checks passed. Full disposable engine run: 77 test processes, 654,515 checks passed. The report records the tested source hashes because production changes were uncommitted at execution; exact-head hosted CI remains required. Local CI unit discovery had 53 passes and one Windows symlink-privilege error. Seven Node suites passed when run against exact repository blob bytes; default Windows checkout line conversion initially broke embedded-source equality checks. No source change was made to those Web adapters.
