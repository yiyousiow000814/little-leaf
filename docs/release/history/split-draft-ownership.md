# Draft release metadata split

Base: f2f1e8ae. Source: 08af6a1, unchanged for these files through 83d6f4f.

Exact source files: data/release_notes.json, data/release_notes.schema.json, scripts/cafe_update_notes.gd, tests/test_update_notes.gd. Owns only project.godot config/version=0.1.10, leaving startup branding and performance FPS changes to their owners. Adds exactly one update-notes runner registration and the source ReleaseNotesContractTests schema/draft rejection methods in ci/test_release.py.

The source draft remains Developer preview with review_pending, not a published release. Runtime suppression keeps draft/pending version, dates, label, bullets, internal review notes, unread badges and persisted seen-version updates hidden. Released documents continue normal behavior. No tags, publishing, or release-complete claim.

Diagnostic tag, promotion and artifact tests are in the separate QA infrastructure slice. The historical itch manual-disabled assertion is deliberately excluded: separate Firebase entry bootstrap297a1c2 supersedes that platform policy. Main #67 release separation remains unchanged. No historical QA evidence or Firebase CI lock/provenance payload is imported. Historical screenshots/profilers remain recoverable at the reference, never claimed as fresh tests.

Compose runner registration and ci/test_release.py additively; do not replace either shared file wholesale. Final source coverage and all-owner aggregate remain integration responsibilities.
