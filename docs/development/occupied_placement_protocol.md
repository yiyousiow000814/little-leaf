# Explicit occupied placement protocol

This isolated candidate continues PR157 from 1f0e7a5. It implements physical footprint placement while guests exist through explicit model APIs; default startup and historical save callers remain unchanged. PR125 staff routing is a separate dependency and must be composed through reviewed relative hunks.

`enable_footprint_placement()` enables owned-floor, object, opening and actual body checks while allowing inaccessible future guest routes. Purchases and moves build an isolated plan and publish items, wallet and guest dictionaries together; existing dictionary identity remains authoritative for Main service records. Selling occupied dining identities remains prohibited.

A blocked guest uses an exact six-field mobility envelope: `kind`, `format`, `goal`, frozen `position`, bounded historical furnishing `anchors`, and nonrecursive `previous`. The codec validates the original cardinal route/index/pose against referenced historical anchors. Historical geometry grants no exemption for current body, floor, walls or doors. Unknown fields, contradictory anchors and capability mixing reject atomically.

Blocked guests do not step, accrue phase clocks, cross service contacts or reach meal departure deadlines. Existing job, service, payload, FIFO ticket and cashier token remain authoritative. Pending historical checkout cells are dormant physical claims; the active payment token is retained. A retry publishes a complete legal cardinal route and available current checkout cell together, preserving actual coordinates until the next tick. Claims held by another live guest prevent partial reacquisition. Explicit cafe close can cancel an unadmitted exterior arrival through its existing withdrawal route without losing identity.

`save_placement` and `load_placement` require the explicit version17 envelope `little_leaf.footprint_placement.v1` and default `user://little_leaf_cafe_footprint_placement_v17.json`. Historical/default/private navigation filenames are protected. Ordinary v15 APIs reject pending envelopes; placement APIs reject navigation state. Failed validation or writes leave the previous destination and live state unchanged. No original profile is modified by fixtures.

Per-frame work stays in the existing model and Main ticks. Retry caches are bounded by live guest IDs and invalidated by layout revision or current claim changes; successful retries and explicit cancellation release their entries. No timers, staff scheduler, assets or renderer behavior are added. Route geometry is evaluated on invalidation, not rebuilt for already validated movement every frame.

Focused fixtures: `test_occupied_placement_protocol` covers seated/arriving/checkout histories, two pending guests plus a live claim competitor, exterior cancellation and atomic rejected saves/loads. `test_occupied_placement_service` uses actual Main cooking, plating and carried ownership, positive unrelated diner/floor/wash controls, full runtime reload and exactly-once continuation. Its optional native capture uses a synthetic profile only.

Remaining acceptance: reviewed PR125 composition preserving the v16 namespace; reviewed explicit trial startup/save caller; source-bound native and Web qualification on that composite; user playable acceptance and merge. This contract does not promote v17 by default or certify Web publication.
