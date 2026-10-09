# Whole-character scale study for 0.1.11

This is an opt-in comparison, not a selected production default. The earlier torso/leg-only A/B study was rejected and is not included.

The three factors are 1.00, 1.25 and 1.40. Head, ears, clothes, body, limbs and shoes use one uniform renderer transform. Standing actors scale about the rendered floor root; seated actors use their actual averaged hip support anchor. Shared renderer geometry drives screen bounds. World furniture contact targets are inverse-transformed into pose space. Plate and cup artwork keeps its world size and support point when held.

The first fixture contains one real cooking job, explicitly staged idle fox/bear observers and a rabbit beside the door. All variants share furniture, camera, model state, clock and the corrected .32 stove-job approach. Normal, medium and doorway frames are actual native renders. Private reference-game images are not published.

## Common comparison fixture and known limits

The full-cell stove top and pot are unchanged. All three variants explicitly enable the same QA-only .66-cell toe plinth with grounded corner supports: .09 furniture-art-unit square posts, centered at plus/minus (full-cell art span/2 minus .07), height0 to6.1. A small contact shadow is under each support. This avoids presenting large shoes intersecting a solid near-full-cell lower cabinet. Other cabinets are unchanged; their separate normalization study is not silently combined. The fixture uses uncached furniture drawing to ensure the opt-in support geometry is actually rendered.

A 1.40 rabbit silhouette is100.8 art units against the existing97-unit door; that is a known clearance failure, not a ready-to-ship ratio. The comparison tests stationary cooking contacts, exact shoe polygons, support bounds, seated hip anchoring and plate/cup world-size transforms. Continuous scaled walking, full seated/dismounting interactions, every job/tool, street/bus actors, and combined production UI acceptance remain unqualified. In particular, changing a whole render transform does not by itself requalify persistent planted gait contacts during travel.

Sources: the shared geometry API is composed from the manual-input owner's d59918d commit; grounded stove work is104d693 (published7c09163d). The capture receipt records the exact final study tree and every original PNG hash. No player saves, simulation timing, routing footprint, production default, merge or deployment is changed by this study.
