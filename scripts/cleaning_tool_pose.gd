extends RefCounted
## Compact paws grip the handles; long handles bridge the distance to the floor.
## All points use the same mirrored character-local ground plane.
const ARM_LENGTH=10.5
const TABLE_TOP_RADII=Vector2(26,11.5)
static func table_inset(heading:Vector2)->float:
 # The back-facing worker is in front of the table and steps up to its rim.
 # From behind the table the raised far paw already reaches at the aisle
 # stance; moving that body farther forward would hide its face in the top.
 return .55 if heading.x+heading.y<0 else .12
static func short_hand(shoulder:Vector2,target:Vector2)->Vector2:
 return shoulder+(target-shoulder).normalized()*ARM_LENGTH
static func table_pose(near_shoulder:Vector2,far_shoulder:Vector2,table_top:Vector2,phase:float)->Dictionary:
 # The reach is the tabletop centre in mirrored character space. Choose the
 # table-facing paw, then sweep its rigid arm across the near part of the top.
 # A cloth appears only once that paw has reached the surface during docking.
 var use_near=near_shoulder.distance_squared_to(table_top)<=far_shoulder.distance_squared_to(table_top)
 var shoulder=near_shoulder if use_near else far_shoulder
 var hand=short_hand(shoulder,table_top+Vector2(sin(phase*TAU*2)*4,0))
 var surface_distance=(hand-table_top)/TABLE_TOP_RADII
 return {"use_near":use_near,"hand":hand,"contact":surface_distance.length_squared()<=1.0}
static func floor_pose(near_shoulder:Vector2,far_shoulder:Vector2,ground:Vector2,back:bool,phase:float,sweeping:bool)->Dictionary:
 var axis=Vector2(1,-.45 if back else .45).normalized()
 var pan=ground+axis*5.0
 # Each stroke finishes at the pan's lip. The last stroke stays at the lip
 # for the single floor -> pan ownership switch at completion.
 var stroke=sin(clampf(phase,0,1)*PI*2.0)
 var brush=pan-axis*(5.0+maxf(0.0,stroke)*5.0) if sweeping else ground+axis*stroke*2.5
 var near_hand=short_hand(near_shoulder,Vector2(brush.x*.45+5,-17))
 var far_hand=short_hand(far_shoulder,Vector2(pan.x,-16))
 return {"axis":axis,"pan":pan,"brush":brush,"near_hand":near_hand,"far_hand":far_hand,"shaft_top":near_hand+(near_hand-brush).normalized()*6.0}
static func relaxed_pan_hand(back:bool)->Vector2:
 var shoulder=Vector2(7,-24) if back else Vector2(-7,-24)
 return short_hand(shoulder,shoulder+Vector2(3,10))
static func carried_pan(hand:Vector2,back:bool,_phase:float,_disposing:bool)->Dictionary:
 # Travelling keeps the tray level and the arm down; disposal owns the tip.
 return {"axis":Vector2.RIGHT,"pan":hand+Vector2(6 if back else 10,7),"hand":hand}

static func disposal_pose(shoulder:Vector2,carrying_hand:Vector2,rim:Vector2,back:bool,phase:float)->Dictionary:
 # Lift the long-handled pan to the real rim before the existing .65 transfer.
 # The paw always remains one fixed short arm from its shoulder.
 var t=clampf(phase,0.0,1.0)
 var lift=smoothstep(.08,.55,t)*(1.0-smoothstep(.70,1.0,t))
 var carry=carried_pan(carrying_hand,back,0.0,false)
 var pour_axis=Vector2(1,-.45 if back else .45).normalized().rotated(-.45 if back else .45)
 var axis=(carry.axis as Vector2).slerp(pour_axis,lift)
 var pan=(carry.pan as Vector2).lerp(rim+pour_axis*3.5,lift)
 var raised_hand=short_hand(shoulder,rim+Vector2(-4,9))
 var hand=short_hand(shoulder,(carrying_hand as Vector2).lerp(raised_hand,lift))
 return {"axis":axis,"pan":pan,"hand":hand,"mouth":pan-axis*3.5,"lift":lift}
