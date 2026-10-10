# 0.1.10b metadata repair

The published `v0.1.10a` remains bound to `0cc0f9ede67ca8b930966f1d705309476119fd6b`. GitHub source Release succeeded; itch run38072050242 failed before building or uploading because release-note metadata changed after the atlas dependency manifest was produced.

This repair advances both version fields to0.1.10b, keeps0.1.10a and the exact0.1.10 major-update notes as history, then binds the final release-note bytes in the unchanged atlas guard. No notes edits may follow that binding without revalidation.

Of121 recursively discovered dependencies, only `data/release_notes.json` differs from the current manifest. All other120 sources, PNG bytes, import settings, dimensions and three decoded RGBA hashes match the existing canonical native-rendered provenance from run38069841730 (receipt24222be1ce393c56ff99428e9b8fae67c8c978edd90b60deb89ec405929e02b3). That original provenance is retained. This is a non-rendering metadata rebind, not a new procedural rendering or visual acceptance claim. No art, camera or runtime logic changes.

The original atlas dependency guard remains mandatory and unchanged; changed painter inputs, PNGs or import settings must still fail. Exact final-commit metadata and atlas checks plus the tag workflow's native/export/browser gates remain required. Production Firebase rules, Auth/IAM, player saves and live Hosting remain untouched by this repair. Firebase automatic delivery wiring is separate and must retain the security-sensitive cutover gate.
