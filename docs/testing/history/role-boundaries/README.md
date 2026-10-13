# Waiter and cleaner responsibilities

Waiters collect dishes, wash them and wipe tables (cleanup stages 0–2). Cleaners sweep litter, empty it into the bin and mop spills (stages 3–6). Completing either role's work never clears the other role's unfinished tasks. The existing serialized stage indices and staff identities are retained.

Legacy cleaners already carrying dishes or partway through a table gesture finish that commitment safely. Unstarted table work is released for a waiter; no new table task is assigned to a cleaner. The runtime codec accepts waiter table work and rejects waiter ownership of floor stages.

## Verification

Run `python3 tests/run_role_boundaries_native.py` with Godot 4.6.3 installed. The runner imports an isolated disposable project and generates every runtime save itself. No pre-existing runtime JSON or player data is included.

`tests/fixtures/before_main.gd` overrides only the two changed scheduling methods and legacy role list, copied from public baseline 5658420983244c7b5799f599934809ca72532338. A small fresh-model fixture drives those original role rules through actual movement to eight legacy cleanup stages. The surrounding scene and model remain current. The new runtime loads those generated saves and checks carried ownership, position, stage, elapsed work, payroll and final completion. Additional checks cover new role assignments, unavailable workers, sink-free floor cleanup, save/reload during waiter work, and exactly-once guest release.

Native role comparisons were reviewed separately. No image payload is included here. Browser behavior remains unverified. Saves containing waiter cleanup work require this updated codec; older builds reject that new assignment, so keep an original backup before any future deployment or rollback.
