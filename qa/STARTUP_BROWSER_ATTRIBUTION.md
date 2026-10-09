# Browser startup attribution (QA only)

The PR105 browser fixture is ordinary Web, a disposable local HTTP origin, and
asserts the startup vault source is `fresh`. It has no Firebase shell or cloud
account bootstrap. Therefore the reproduced scheduling stall does not depend on
reading a player cloud save. It still includes local preferences, engine, scene,
resource and rendering work. The existing data does not identify their shares.

Run `tests/startup_trace_browser.js --web-build <exact-export> --output <folder>`
with the same pinned sandboxed Chrome/Playwright setup as startup timing. Run it
separately after timing: CPU profiling and WebGL wrappers change performance.
It validates every exported file and the complete production-source map.

It retains:
- CPU profile and Chrome devtools/GPU trace;
- browser GPU info, graphics flags, WebGL backend and hardware concurrency;
- actual callback execution times alongside rAF timestamps;
- MutationObserver loader-removal time;
- local vault/preferences, wasm and first-frame/engine-ready marks;
- durations/counts of shader compilation/linking, texture uploads/readback;
- every request URL, rejecting any non-local request in this generated fixture.

The wrappers preserve return values, receiver identity and native exceptions;
16 focused checks exercise those contracts. No autoplay override, progress data,
player account or gameplay source change is involved. Before attributing a long
stall, correlate its interval with trace/profile and boot markers. A frame
timestamp alone does not establish the precise time that pixels became visible.

Local status: JavaScript syntax and instrumentation contract checks pass. Actual
CDP trace has not run. The executor loopback server was unreachable from the
supported cloud browser; no network-policy workaround was attempted. CI is the
supported route. PR105 itself remains frozen and this QA branch is unpublished.
