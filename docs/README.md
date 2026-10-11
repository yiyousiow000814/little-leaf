# Little Leaf documentation

Start with the [repository README](../README.md) to open the game. Read the [canonical roadmap](roadmap.md) before choosing work: it is the single current editing plan, with original requirements through 0.3.2, dependencies, ownership and acceptance gates. Library master v3 is a historical snapshot, not a synchronized editing copy.

Choose the guide for what you want to do:

| Purpose | Start here | What it covers |
| --- | --- | --- |
| Design | [Design](design/README.md) | Player outcomes, character and building contracts, routing rules |
| Development | [Development](development/README.md) | Open/build the project, implementation and save boundaries |
| Art and audio | [Art and audio](art-audio/README.md) | Asset permissions, provenance and source-bound visual records |
| Testing | [Testing](testing/README.md) | Acceptance criteria, browser gates, focused regression and visual evidence |
| Release | [Release](release/README.md) | Checked builds, platform previews, publication and recovery |

For agent work, [AGENTS.md](../AGENTS.md) links the canonical rules and developer commands. Generated profiles, screenshots, logs and private operational handoffs stay outside tracked source.

## Game Production Framework

Use the relevant pillars through the [Feature Design Quality Gate](design/README.md#feature-design-quality-gate).
This is a navigation map, not another roadmap or completion ledger. The
[roadmap](roadmap.md#current-state) alone owns product scope, priority and status.
The source links below identify accessible foundation drafts while their canonical
homes await main integration; they do not imply merge or runtime acceptance.
Replace a source link with its canonical relative link only after that file lands.

| Pillar | Canonical home and current source reference | Responsibility |
| --- | --- | --- |
| Art Direction / Art Bible | `docs/art-audio/ART_BIBLE.md`: [Art Bible](https://github.com/yiyousiow000814/little-leaf/blob/fdd0ab798e2298eff58e19a48aade497a482e401/docs/art-audio/ART_BIBLE.md); [production skill](https://github.com/yiyousiow000814/little-leaf/blob/fdd0ab798e2298eff58e19a48aade497a482e401/.agents/skills/game-art-production/SKILL.md), [review skill](https://github.com/yiyousiow000814/little-leaf/blob/fdd0ab798e2298eff58e19a48aade497a482e401/.agents/skills/game-art-review/SKILL.md) | Original identity, editable authoring, calibration and scoped reference decisions; genuine game pixels before Golden approval. |
| Technical Art / Occlusion | `docs/development/depth-occlusion.md`: [depth contract](https://github.com/yiyousiow000814/little-leaf/blob/e3a71b24ca220bc27bb4abbd13fbdaee88e9ecfe/docs/development/depth-occlusion.md) | Ground anchors, footprints/parts, pass order, native/cache ownership and continuous Occlusion QA. |
| Audio Direction / Audio Bible | `docs/art-audio/AUDIO_BIBLE.md`: [Audio Bible](https://github.com/yiyousiow000814/little-leaf/blob/41c341c70f503f3fb845d857f7b1a0f1c9270500/docs/art-audio/AUDIO_BIBLE.md) | Production/source/licensing and mix/playback review; measured signals and actual listening remain distinct. |
| Living World Design | `docs/design/living-world.md`: [Living World](https://github.com/yiyousiow000814/little-leaf/blob/e69263f0fc8ffea66afa6fb6742064846ce19ce4/docs/design/living-world.md) | Spatial/causal/identity coherence, clocks, offscreen and bus events, custody and complete journeys. |
| Game Feel & Animation | `docs/testing/README.md#game-feel-and-animation-review`: [experience review](https://github.com/yiyousiow000814/little-leaf/blob/8c6ca6d571a7ac54a9da4e6503ef191555f491b9/docs/testing/README.md#game-feel-and-animation-review) | Natural-speed animation, feedback, repetition/interruption, listening comfort and newcomer understanding. |
| UI/UX Design System | `docs/design/ui-ux-design-system.md`: [UI/UX](https://github.com/yiyousiow000814/little-leaf/blob/63262f0fc27996be2807c09974e3874c4348b636/docs/design/ui-ux-design-system.md) | Reuse-first theme/components, typography/states, responsive surfaces, focus/touch and actual interaction review. |
| Gameplay Reference & Parity | `docs/design/gameplay-reference-parity.md`: [reference and parity](https://github.com/yiyousiow000814/little-leaf/blob/22a4152f9e02671f6795f28821eab6f9786f29cc/docs/design/gameplay-reference-parity.md) | Historical era/confidence, strategic loops, intentional adaptations and explicit unresolved product decisions. |
| Quality Assurance / Acceptance Gates | `docs/testing/README.md#evidence-and-acceptance-gates`: [acceptance gates](https://github.com/yiyousiow000814/little-leaf/blob/8c6ca6d571a7ac54a9da4e6503ef191555f491b9/docs/testing/README.md#evidence-and-acceptance-gates) | Separate source/tests, actual presentation, player decision, integration and delivery; retain scoped failures and gaps. |

The implementer owns the proposed change, relevant production evidence and
unchanged boundaries. The reviewer checks the exact source and actual required
pixels, motion or listening evidence rather than granting approval from CI.
The user decides new visual/audio Golden standards and substantive product-policy
choices; integration and release owners retain their existing separate gates.
A recorded mandatory review process can be complete while its pilot or creative
standard is still unvalidated. Do not turn an unapproved proposal into a rule.

### Task entry examples

- **New furniture:** use Art production, Technical Art and Art review; preserve
  footprint/contact/part relationships and select the affected continuous depth
  and interaction checks. An unchanged-art optimization reuses existing authoring
  proof and calibration with Pixel Parity instead of making a new GUI sample.
- **UI notification:** start with UI/UX reuse and the Feature Design Quality Gate;
  review actual affected layouts, input/focus, repeat/interruption and visual
  feedback through Game Feel/QA. Keep its save, update or Auth action owner intact.
- **Vehicle/customer behavior:** start with Living World and its complete journey;
  involve Technical Art for overlap/render handoffs and Gameplay Reference for
  changed strategic rules. Demand, economics and persistence need their own approval.
- **Audio:** use the Audio Bible's production/source package and review gates,
  then affected Game Feel/QA listening and platform checks. A decoded waveform or
  successful test is not listening approval. No separate per-pillar skill is needed.

Existing [rendering/performance](testing/rendering-performance.md),
[memory](testing/memory-regression.md), [asset permissions](art-audio/README.md),
[development](development/README.md) and [release](release/README.md) rules remain
in force. Apply them proportionately; this index starts no runtime run, asset
migration, character activation, merge or publication.

## Reading historical evidence

An area's `history/` preserves dated approvals, reviews, failed evidence and recovery records. Their statements describe the source and date recorded there; they do not establish current implementation, merge, release or pixel acceptance. Use the roadmap's current-state section first.

The [historical evidence directory](testing/history/README.md) links original reviews across these areas. [Source recovery records](development/history/repository-notes.md) and the [original manifest](development/history/SOURCE_MANIFEST.json) retain original hashes and paths. Commands and JSON inside historical records refer to their original repository or capture environment.

Distribution notices live under `art-audio/third-party/`; the retained QA output placeholders live under `testing/litter-remnants-visibility/` and `testing/role-boundaries/`. Their build and diagnostic consumers use these category paths.
