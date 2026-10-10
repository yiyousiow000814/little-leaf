# WebGL handle retention candidate

The deployed 0.1.10 generated runtime increments one global handle counter and
fills each allocating WebGL table up to that counter with null entries. Deletion
clears the object but leaves the array length intact. A disposable 181-second
actual-game profile reproduced buffer/vertex-array/sync tables growing from about
143,000 to 5,268,000 entries with only about 4,200 live objects. Forced collection
on that disposable page retained another 73.83 MiB of JavaScript heap. Wasm,
audio counts and engine listeners remained stable in this workload. This is a
concrete retention mechanism; it does not identify every contributor to the
original long-lived page's OOM.

`tools/bound_web_gl_handles.py` adds separate freed-name pools to those three
tables. Existing live names stay intact. Names enter a pool only after native
deletion, object/table clearing and buffer-binding cleanup. Duplicate/nonexistent
deletion cannot append a name twice; zero stays reserved. Other tables retain
their existing allocator. Reuse follows native GL's deleted-name semantics;
stale deleted handles are not valid application references.

Both Web builders apply the candidate after the existing presenter optimization
and before hashing distribution files. The complete input SHA256 must match
`926bd39c551fc2f802ea426d37fdcfb0265b2471222af220132288e0b0e56a7b`;
all four anchors must occur exactly once. Unknown, repeated or partly patched
runtimes fail before writing. The manifest records the patch identity and full
input/output hashes. Official archives, template checks, Wasm, gameplay,
save/account behavior, original art and FPS128 source are unchanged.

Focused verification:

```sh
PYTHONPATH=tools python -m unittest tests.tooling.test_bound_web_gl_handles tests.tooling.test_optimize_web_present tests.tooling.test_crazygames.CrazyGamesVariantTests.test_flag_routes_only_copied_export_and_manifest_without_engine
node tests/tooling/webgl_handle_lifecycle.js path/to/guarded/patched/index.js
```

Seven focused Python checks pass, including unknown/missing/duplicate/already-patched
rejection and receipts. The extracted actual-runtime Node check passes 20,000
cycles with table lengths 5/6/7, three preserved live objects, binding cleanup,
cleared names and invalid-sync errors. Its GPU deletion is stubbed. Independent
read-only review found no blocking source issues in the candidate and both
builders. These checks do not replace actual browser rendering or release gates.

The exact current-main CI Web artifact (`d2910b4780bcd5321fb6dc72df1cd6300f6d2bdd`,
tree `272899608abf811b62c9d91851916c193b095dcf`, run `38064813006`) was downloaded
and every manifest file hash verified before making disposable copies. Its
checksum-pinned official Godot4.6.3/template receipt and existing FPS presenter
remain intact. Only the generated JS patch and a read-only counter probe differ
between the compared engines; PCK/Wasm and HTML are identical.

Two sequential fresh sandbox-enabled Chromium151 sessions ran the same closed
cafe/ambient traffic/music workload for 180 seconds, with explicit GC only in
these disposable sessions:

| Endpoint after GC | Before | After |
| --- | ---: | ---: |
| Global handle counter | 62,204 | 4,613 |
| Buffer slots / live | 62,200 / 2,774 | 4,612 / 2,774 |
| VAO slots / live | 62,201 / 889 | 4,613 / 889 |
| Sync slots / live | 62,204 / 9 | 3,245 / 9 |
| Retained JS heap growth | 1,073,160 bytes | 385,476 bytes |

The patched high-water marks grow when the live scene grows; they no longer
append IDs for continuous deletion/recreation. Browser errors were empty, Wasm
and audio counts stayed stable, and before/after completed frames were inspected
without a visible regression. These are bounded headless-browser observations,
not all-scene pixel parity, long-play, context-recreation or mobile acceptance.
Both browsers/servers closed and launcher processes exited successfully. Cloud
network was blocked; no original tabs, storage or saves were used.

The existing synthetic CrazyGames export test now checks presenter output →
handle patch input → final file hash for both production/preview copies. Run it
with `python -X utf8` on this Windows host. A broader 14-test file attempt using
default Windows encoding encountered pre-existing Unicode/CRLF fixture failures;
that attempt is not claimed as passing. The seven selected checks pass with UTF-8.
Complete exact-candidate CI and hosted acceptance remain pending.
No merge, release, deployment, original-save access or atlas qualification change
is authorized by these checks. Release gates still require their existing exact
source/toolchain/atlas evidence. This candidate targets 0.1.10a; hosted acceptance,
context recreation and longer-play coverage remain separate from code readiness.
