# Table floor contact

This isolated 0.1.11 candidate ports only the table correction from PR147 `9e7429ca` onto main `50160069`. Roadmap outcome05.03 owns integrated acceptance. Chair/register/flower functions belong to the separate furniture owner. No merge or deployment is authorized here.

Cottage/refined feet and the retro bottom disk reach zero floor height. Restrained 2:1 contact patches sit behind supports at their actual anchors; basic oak retains its original supports. Tabletop silhouette/height, upper attachments, service/dining anchors, footprints and saves stay unchanged.

Run the two focused suites with `tests/run_integration_candidate.py --only test_table_ground_contact test_table_ground_capture --output NEW_DIRECTORY`. The diagnostic fixture uses only generated state and requires stable state/camera hashes and zero save calls. `tests/diagnostics/capture_table_ground_contact.py` captures four styles, four rotations, empty/occupied states and two zooms plus actual cached basic tables. It compares frozen current-main and exact candidate sources. Passing geometry tests does not accept pixels.

Basic tables use a prebaked atlas. The explicit table-cache diagnostic regenerates only its owned cell, rejects any change outside that cell, requires moving/head bytes unchanged, reimports the replacement and verifies all three real cached resources. PNG/import settings and source identity are bound by the normal atlas guard; no stale-cache bypass is allowed. The workflow stays outside ordinary PR work and runs on explicit manual dispatch or the designated qualification branch.

Retain failed fixture attempts and source-bound before/after pixels outside tracked source. Native/Web and user pixel acceptance remain distinct; this change makes no FPS or phone claim.
