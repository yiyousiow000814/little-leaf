# Save reachability and wall-edge preparation

[Flow](save-topology.mmd) · [Measurement ledger](save-topology.xlsx) ·
[Architecture and performance contract draft](https://github.com/yiyousiow000814/little-leaf/pull/355)

Save preflight reuses reachability only within one model and one preflight. The
original checkout, chair, motion, and egress checks remain in place. Checkout
only requests reachability if a reservation needs it. If the save codec
normalizes openings to a different value, the checked openings get their own
map. Decorate Apply preflights the draft; a concurrent save serializes the
previously applied copy. The two never share a reachability map.

A reachability pass indexes wall IDs and starts with the set of blocked unit
edges. It resolves each door once in support order and checks the same midpoint
clearance before opening an edge. The flood fill, save format, legacy resolver,
and art/render paths are unchanged. The gameplay reachability helper is outside
the unchanged 83-input atlas-producer closure. The original three atlas PNGs,
imports, and provenance are unchanged; the canonical atlas verifier passes. For the indexed canonical branch, this
replaces W(W+1)/2 edge-search comparisons plus repeated support lookups with
work proportional to walls, attachment/support references and overlapped
unit edges. Legacy door records still use their original resolver once per
door; do not ascribe the same bound to those lookups or the entire save.

Nine focused native suites and the new edge-parity cases passed 4,258 distinct
checks. The three-minute synthetic starter case retained 36/36 exact save
payloads. Native timings in the ledger cover two distinct scopes: full
synchronous starter preparation and isolated synthetic blocked-edge
construction. They are not additive and do not establish browser FPS, frame
headroom, or Web root cause. Next: matched Web traces during active service,
including save work, wall preparation and frame intervals.
