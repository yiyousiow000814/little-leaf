# Private native routing/reception persistence

This additive review capability depends on PR165. Default version15 and the
separate reception18 reader keep their existing formats and cardinal rules.
It does not activate Web/cloud persistence or import an original player profile.

Main must already be fresh and save-suppressed. Activation requires all five
native flags: `--fresh-review`, `--navigation-candidate`,
`--guest-navigation-candidate`, `--reception-candidate`, and
`--routing-reception-persistence-candidate`. `LL_RECEPTION_REVIEW_ROOT` must be
absolute and contain the dedicated generated application userdata, with no
ordinary application-name component, link or junction ancestor. Private16/18
persistence and placement17 flags are mutually excluded.

The explicit APIs are `enable_routing_reception_review`,
`save_routing_reception_review`, and `load_routing_reception_review`. Main's
save/load APIs capture and restore its actual service ledger; model-only APIs
operate on a standalone model. Live Main callers must use Main's APIs, so model
and controller state publish together. Main refuses a standalone empty service
ledger before publication; that ledger remains valid only for model-only APIs.
There is no automatic save/load caller.

The dedicated file is
`user://little_leaf_cafe_routing_reception_review_v19.json`. The existing schema
requires exact version19 and
`routing_reception_review_format: little_leaf.routing_reception_review.v1`, with
the validated `little_leaf.reception.v2` ledger and service version5. Only staff
rows may carry the reviewed `navigation_phase: follow|replan`. The reader refuses
copied historical/16/17/18 envelopes, unknown/nested capability markers and
placement17 blocked intent. Default and18 APIs protect the new filename and its
temporary name before I/O in this successor; already frozen executables retain
their own version/header refusals and are not retroactively modified.

Actual purchased layout data is included independently of movement capability:
furniture IDs/positions/rotations/levels, dining groups, walls/openings and their
paid values, floor finishes, owned parcels, parking ownership/value and wallet
retain the existing validated fields. Rejecting blocked17 movement intent does
not discard or reset any purchased item. A blocked17 snapshot cannot be imported
through19; such a combined movement capability remains a separate contract.

The existing geometry/runtime reader prepares a complete shadow model before
publication. Main verifies its consumer references before cancelling old
requests. A successful restore publishes synchronously, recreates service
state with its saved identities/tokens/payloads/clocks, invalidates old ground
and follower generations, and issues fresh requests. Rejection or abandoning
the prepared shadow preserves the live model, service state, generations and
input bytes. The existing scoped safe replacement mechanism protects the old
target if finalization fails.

Indoor diagonals retain both orthogonal-cell and wall/body-sweep clearance.
Guest chair/workface contact and exterior transit remain cardinal. Admitted
guests retain their selected south/right/west exit; waiting reception visitors
retain their distinct west-corridor authority. Consumed route history cannot
grant a new current leg, and endpoint ownership remains with the existing
checkout/table/service contracts. The reader resolves each work step from its
authoritative service record (including chef pass-counter custody), rather than
using a retained station ID as a universal endpoint. Guest/token ownership stays
exclusive even when no physical waypoint has been claimed. An exhausted guest
route requires the actual body at its final waypoint. A save attempted during a
stage transition before its next target is reserved/replanned can be refused;
the explicit caller must wait for a coherent safe anchor.

Run only the named synthetic cases in a new output directory:

```sh
python tests/run_reception_review.py --godot /path/to/godot \
  --output /tmp/private19-protocol \
  --only test_routing_reception_persistence test_reception_private_contract \
         test_routing_reception_scope
```

The runner owns the shared engine lock and generated profile, including literal
junction/symlink refusal cases. The persistence case uses actual Main admission,
fractional guest/staff routes, payment and original dirty-chair cleanup. It also
tests interrupted/repeated restore, purchased-layout retention, wrong envelopes,
body/route/ownership failures and protected targets. Headless checks establish
reader behavior, not rendered-pixel acceptance. Native capture requires a fresh
exact-source atlas qualification; no previous PR165 proof is transferred.

The ordinary Main `_service_save_snapshot()` signature remains unchanged for
existing subclasses and save consumers. Private review export uses the separate
pure `_service_snapshot_ledger()` helper so refusal probes do not mutate live
service ownership while taking a snapshot.

Private19 staff rows accept only fields emitted by the explicit serializer.
Unsupported runtime objects and malformed optional headings, block metadata or
job identities refuse during shadow validation, before Main stops or publishes.
Historical reader policies remain unchanged.
