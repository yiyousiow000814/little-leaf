# Assets and licenses

No repository-wide open-source license has been selected. Individual asset permissions do not grant a blanket license for the game.

Keep the relevant notices when redistributing code or assets:

- **Godot anti-aliased line code:** [MIT license and source attribution](third-party/GODOT-AA-LICENSE.txt)
- **Noto Sans:** [SIL Open Font License 1.1](../../game/assets/fonts/NOTICE.txt)
- **Nunito:** [SIL Open Font License 1.1](../../game/assets/fonts/Nunito-OFL.txt)
- **Tabler icons:** [MIT license](../../game/assets/ui/wood_hud/icons/LICENSE)
- **Project artwork:** [HUD provenance](../../game/assets/ui/wood_hud/PROVENANCE.json), its accompanying prompt records, and [wordmark provenance](../../game/assets/branding/PROVENANCE.json)
- **Music:** [release notice](../../game/assets/audio/NEW_RELEASE_MUSIC_NOTICE.txt), [GeneralUser GS license](../../game/assets/audio/GeneralUser-GS-LICENSE.txt), and [provenance addendum](../../game/assets/audio/MUSIC_PROVENANCE_ADDENDUM.json)

The music records document supplier permission for the included recordings and uncertainty about some historical sample origins. The SoundFont and original composition source are not included.

The source attribution comment in `scripts/retained_aa_strokes.gd` retains its historical notice path because the script is part of the qualified atlas source hashes. The linked notice above is its current location; build helpers copy that same unchanged license from `docs/art-audio/third-party/`.

## Authoring and visual references

Preserve the original 2D isometric presentation. [Character authoring](../design/cute-staff-accessories-011.md) defines the shared source contract; use the [roadmap](../roadmap.md) for current owner and acceptance state. [Audio source records](../../game/assets/audio/README.md) remain with their assets.

Historical visual studies retain their original source, approval and evidence limits:

- [Environment source history](history/environment-010-source-history.md), [environment review](history/environment-010.md), [capture evidence](history/environment-010)
- [Chair ground contact](history/chair-ground-contact.md), [chef hat](history/CHEF_HAT_CANDIDATE_REVIEW.md), [chef/food contact](history/chef-food-contact/REVIEW.md)
- [Pan proportions](history/pan-burner-proportions/REVIEW_PENDING.md), [pan handle](history/pan-handle-workface/REVIEW_PENDING.md), [register edge](history/register-edge/README.md)
- [HUD optical scale](history/qa/hud-optical-scale.md), [HUD spacing](history/qa/hud-spacing.md), [cancel icon](history/qa/cancel-icon-centering.md)
- [Camera-range record](history/shared-play-camera-range.md), [zoom clarity](history/zoom-clarity/README.md)

These dated records are not a second current plan. Actual game pixels need source-bound visual acceptance in addition to tests.
