extends RefCounted
## One-tile physical worktop layout. Pot and full-size plate occupy opposite
## corners; all consumers rotate the same local coordinates, with no z boost.
const POT_CENTER=Vector2(-.22,-.22)
const HANDLE_GRIP=Vector2(0,.48) # Sub-pixel inward clearance for the AA cap.
const OUTPUT_CENTER=Vector2(.27,.27)
const OUTPUT_GRIP=Vector2(.27,.54)
const PICKUP_LATERAL=.12
