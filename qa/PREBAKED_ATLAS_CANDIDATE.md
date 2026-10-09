# Lossless pre-generated atlas startup candidate

This independent candidate does not include the rejected FIFO scheduler. It loads
exact original 4x native atlas output from lossless imported resources. Geometry,
regions, sampling scale, alpha, filtering, gameplay, audio, welcome and saves stay
unchanged. If a resource is unavailable or has wrong dimensions, the existing
procedural bake is retained. `--runtime-atlases` forces that comparison path.
The first-gesture welcome patch and bounded fallback readiness gate are separate.

## Source and pixels

PNG producer: native run37895899863, commit ae5fc2d23681eb8e03bdce928e5d9e015b7e1428.
Artifact SHA256 a66fc771bbce7bdf7e9a9a496c5dcafdcc262333b6450a513fbecf71677ad5a0.
Its three original concurrent bakes and three serialized bakes produced identical
RGBA hashes, also matching the preceding run. Combined PNG size:715,730 bytes.
Combined level-zero RGBA size:33,824,768 bytes. This replaces the existing texture
set; it does not keep a second set. Peak GPU memory/load time still require actual
renderer measurements. Imported pixels are not alpha-repaired a second time,
rescaled, mipmapped or lossy-compressed.

`ci/verify_prebaked_atlases.py` binds PNG/import hashes and the recursive static
procedural dependency closure in `data/prebaked_atlas_manifest.json`. Changed
inputs fail the normal Web CI gate. The native job is triggered for source/cache
changes and regenerates all three atlases from original primitives, then compares
actual RGBA bytes with the imported resources. Updating a manifest alone is not
pixel acceptance. The headless test independently verifies imported RGBA hashes.

## Acceptance

- Preserve exact rendered RGBA parity and ten frozen actual-main screenshots.
- Compare two same-runner baseline/candidate cold and retained-warm pairs, total
  first draw, visible welcome/descent gaps, atlas load calls and peak memory.
- Cold state is sampled before scene creation so synchronously loaded pre-generated
  resources are not mislabeled as previously warm objects.
- The ordinary full Web CI additionally records fresh-origin cold/warm HTTP rAF
  scheduling, actual loader-removal time, resource transfer/decode sizes and JS
  heap observations. These are browser scheduling observations, not device FPS,
  isolated GPU timings, audible output or exact intro-phase timestamps.
- No timed screenshots or readback. Native frozen screenshots and atlas parity
  are separate from timing. No real player profiles or deployment are used.

Initial local validation:3,245 headless checks passed (16 imported-pixel/selection,
983 background,732 shell,1,514 intro), plus6 source-guard adversarial tests. Import
had no diagnostics. Browser timing and candidate native improvement remain unrun.
