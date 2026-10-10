# 10a atlas provenance preparation

Scope is migrated-main control, PR123 camera and PR126 background only. No FPS128 or 11 candidates. Earlier four-candidate route remains held and is not run.

Current migrated control af61a3f3 has the same108 atlas source hashes and retained assets as originalf690. Exact camera migration final commit374aa2c5/tree0de56386 is frozen from the owner's published handoff. The preinstall and runner checks reject any missing camera lock. PR126e55 is the currently observed exact PR head; refresh only on an exact owner source handoff. Never substitute a later branch ref silently.

Official Godot4.6.3/7d41c59c4, X11 GL Compatibility, Ubuntu24.04, Mesa25.2.8-0ubuntu0.24.04.4 and llvmpipeLLVM20.1.2(256bits) must reproduce successful reference run37898956030. Fail on fingerprint/baseline mismatch. All three generated/imported RGBA pairs and decoded saved PNGs must exactly equal the retained references. Any changed pixel stops qualification; there is no intentional-art exception or asset replacement path.

Source inventories bind full Git commit/tree and all tracked hashes. The runner supports migrated `game/project.godot` and historical root `project.godot`; res://scripts names stay unchanged. Helpers are placed only in disposable project copies. APPDATA equivalent XDG profiles are synthetic, no game instance/save operations/renderer performance measurement or broad game suite occurs.

Only after successful actual native receipts and inspection may the existing receipt-bound source-manifest writer be used in separate isolated source copies. Keep existing PNG/import bytes unchanged; provenance must bind exact producing run/commit/tree/receipt hash. Verify existing guard afterward and return manifest-only changes to the corresponding candidate owner. No guard relaxation, blind hash refresh, general-purpose art generation or live publication.

Publication of this diagnostic branch and one standard-environment native run remain subject to direct local user approval because earlier attempts were denied. Once source locks and permission are complete, dispatch the existing registered startup-profile workflow exactly once; no default-branch registration/security edits or alternate route if denied. Existing PR105 renderer assets/actions/checksums are reused.
