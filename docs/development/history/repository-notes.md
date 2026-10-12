# Source baseline and development notes

These notes preserve the original source-baseline and early-fix documentation. Later fixes are documented in their own folders under `docs/`.

Editable Godot source for Little Leaf Cafe, baseline **0.1.5-dev.1**.

This repository preserves the reviewed 0.1.5 baseline, including the category-arrow repair, and adds the separately scoped [browser startup retry](../../testing/history/startup-retry/README.md) and [starter wall/floor geometry](../../testing/history/starter-geometry/README.md) fixes. Retry addresses transient loading failures; the actual reported player failure remains unknown. Geometry completes the starter west wall and fills only missing, unmarked legacy starter-row tiles. Other 0.1.6 work, including the welcome intro, requires separate review. Publishing this source repository does not deploy the game or change its itch.io visibility.

## Run

Use Godot **4.6.3** with the GL Compatibility renderer. Import the root `project.godot`, allow its local asset import, then run the main scene (`main.tscn`). Alternatively, use `godot --path .` with Godot 4.6.3 installed.

Launching the game can read/write its normal local save profile. For inspection or experiments, use a disposable operating-system profile and copied saves; keep real player data outside this repository. There is no automated browser preview or QA window resizing in this repository.

The original `assets/` inputs, `.import` settings and script `.uid` files are tracked. Some HUD/font files intentionally use `importer="keep"`; retain those settings. Godot's generated `.godot/` directory and compiled exports are excluded. No Git LFS is required for the current assets: the production inputs total about 16.84 MiB and the largest individual file is about 2.93 MiB.

## Restore and verify

The baseline tag is `0.1.5-dev.1`. Restore into a new directory to preserve any current working changes:

```sh
git clone --branch 0.1.5-dev.1 https://github.com/yiyousiow000814/little-leaf.git little-leaf-baseline
```

`SOURCE_MANIFEST.json` records SHA-256 values for all 203 original production files and the published counterparts. Eight provenance/prompt documents have private Library references and absolute workspace paths redacted for public publication; their original checksums are retained. At that baseline tag, all other production files, including executable source, images, fonts, music and license text, are byte-identical to the frozen baseline. The scoped fixes add focused synthetic tests and sanitized evidence captures. No real player saves, tokens, QA archives or generated export binaries are included.

## Assets and licenses

Preserve these notices when redistributing the relevant assets:

- Noto Sans: `assets/fonts/NOTICE.txt` (SIL Open Font License 1.1).
- Nunito: `assets/fonts/Nunito-OFL.txt` (SIL Open Font License 1.1).
- Tabler SVG icons: `assets/ui/wood_hud/icons/LICENSE` (MIT).
- HUD artwork provenance: `assets/ui/wood_hud/PROVENANCE.json` and the original prompt records; the artwork was generated for this project.
- Music: `assets/audio/GeneralUser-GS-LICENSE.txt`, `NEW_RELEASE_MUSIC_NOTICE.txt` and `MUSIC_PROVENANCE_ADDENDUM.json` document the original recordings and supplier permissions. The supplier's disclosed uncertainty about some historical sample origins remains; the SoundFont and original composition source are not included.

Asset-specific permissions do not establish a blanket open-source license for the game code or all artwork. No repository-wide open-source license has been selected or added.
