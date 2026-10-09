extends RefCounted
## Presentation-only stove handoff. Ownership still changes in service contact.
const Layout=preload("res://scripts/cafe_stove_layout.gd")
const Geometry=preload("res://scripts/kitchen_worktop_geometry.gd")
const Pickup=preload("res://scripts/cafe_chef_pickup.gd")
const INSET=.32
const UPPER=5.5
const LOWER=6.5
static func work_offset(rotation:int)->Vector2:
 return Vector2(Layout.PICKUP_LATERAL,-INSET).rotated(posmod(rotation,4)*PI/2)
static func grip(rotation:int)->Vector2:
 return Geometry.surface(Layout.OUTPUT_GRIP,31.0,rotation)
static func pose(near:Vector2,far:Vector2,carry:Vector2,target:Vector2,plate_target:Vector2,progress:float,picking_up:bool,use_near_hint:int=-1)->Dictionary:
 var use_near=bool(use_near_hint) if use_near_hint>=0 else near.distance_to(target)<=far.distance_to(target)
 var shoulder=near if use_near else far
 var contact=smoothstep(.08,.65,progress) if progress<=.65 else 1.0-smoothstep(.65,1.0,progress)
 var hand=carry.lerp(target,contact)
 var axis=(hand-shoulder).normalized()
 var distance=clampf(shoulder.distance_to(hand),absf(UPPER-LOWER)+.00001,UPPER+LOWER-.00001)
 hand=shoulder+axis*distance
 var along=(UPPER*UPPER-LOWER*LOWER+distance*distance)/(2.0*distance)
 var bend=sqrt(maxf(0.0,UPPER*UPPER-along*along))
 var side=axis.orthogonal()
 if side.y<0:side=-side
 var elbow=shoulder+axis*along+side*bend
 # Held plate converges to the exact worktop anchor at the same .65 event.
 # Contact is held for the single transition; no second decorative plate.
 var plate=(carry+Vector2(4,-2)).lerp(plate_target,contact)
 return {"use_near":use_near,"shoulder":shoulder,"elbow":elbow,"hand":hand,"plate":plate,"target":target,"plate_target":plate_target,"contact_error":hand.distance_to(target),"plate_error":plate.distance_to(plate_target),"contact":contact,"picking_up":picking_up}
