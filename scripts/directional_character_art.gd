extends RefCounted
const PickupArt=preload("res://scripts/cafe_chef_pickup_art.gd")
const SinkWashArt=preload("res://scripts/cafe_sink_wash_art.gd")
## Standalone original character study. Four isometric directions rotate the
## entire body, not a front-facing paper doll with a different face.
## The production renderer now uses this reviewed directional construction.
const DiningPose=preload("res://scripts/dining_pose.gd")
const CheckoutArt=preload("res://scripts/cafe_checkout_art.gd")
const ArmOcclusion=preload("res://scripts/character_arm_occlusion.gd")
const CleaningPose=preload("res://scripts/cleaning_tool_pose.gd")
const CookingPose=preload("res://scripts/cooking_tool_pose.gd")
const WaiterTabletArt=preload("res://scripts/waiter_tablet_art.gd")
const FUR=["efe5c7","c68b46","efe5c7"]
const CLOTH=["95b9bb","c78f80","d6b16b"]
const EYE_PAIR_SIZE=Vector2(1.3,1.65)
const EYE_LINE=-40.2
const LEG_LENGTH=9.5
const SEATED_LEG_REACH=6.0
# Rounded leg caps overlap the shirt hem. Their centers may sit this far
# below the nominal socket without leaving a gap or changing limb length.
const HIP_COVER=1.25
# Comparison candidate: unladen walking only. These sub-pixel accents consume
# existing lift samples; they never advance cadence or move a stance anchor.
const WALK_CLEARANCE_ACCENT=.60
const WALK_WEIGHT_RISE=.32

static func walking_lift_accent(settings:Dictionary,walking:bool,side_profile:bool,slot:String)->float:
 if not walking or side_profile or not bool(settings.get("grounded_feet",false)):return 0.0
 if bool(settings.get("dismounting",false)) or float(settings.get("seat_mix",0.0))>0.0:return 0.0
 if str(settings.get("action","idle"))!="walking" or str(settings.get("payload","none"))!="none" or str(settings.get("tool","none"))!="none":return 0.0
 if bool(settings.get(slot+"_stance",true)) or float(settings.get("speed",0.0))<=0.0:return 0.0
 var lift=maxf(0.0,float(settings.get(slot+"_lift",0.0)))
 # Extra corner clearance is already supplied by the contact controller.
 # Fade this purely visual accent out rather than amplify those high steps.
 return WALK_CLEARANCE_ACCENT*minf(lift,1.0)*(1.0-smoothstep(1.0,2.0,lift))*clampf(float(settings.get("blend",0.0)),0.0,1.0)

static func seated_hip(near:bool,facing_back:bool)->Vector2:
 # Short figurine legs share the chair plane and project beyond its front edge.
 # The unchanged actor/body inset is subtracted to express the socket locally.
 var depth=-1.0 if facing_back else 1.0
 var along=Vector2(25,depth*12.5)
 var across=Vector2(-depth*25,12.5)
 var on_seat=along*.20+across*(.15 if near else -.15)+Vector2(0,-18)
 return on_seat-Vector2(4.68,depth*2.34)-Vector2(2,-5.5)

static func leg_pose(settings:Dictionary,walking:bool,phase:float,facing_back:bool,side_profile=false)->Dictionary:
 var seated=clampf(float(settings.get("seat_mix",0.0)),0,1)
 var far_hip=Vector2(-1.8,-12) if side_profile else (Vector2(-3.7,-12) if facing_back else Vector2(3.7,-12))
 var near_hip=Vector2(1.4,-10.8) if side_profile else (Vector2(3.7,-10.5) if facing_back else Vector2(-3.7,-10.5))
 var near_rest=near_hip;var far_rest=far_hip
 var near_axis=Vector2.RIGHT if side_profile else Vector2(1,-.48 if facing_back else .48).normalized()
 var far_axis=near_axis
 var body=Vector2.ZERO
 var near_angle=0.0
 var far_angle=0.0
 var near_slot=""
 var far_slot=""
 if bool(settings.get("grounded_feet",false)) and not bool(settings.get("dismounting",false)) and not side_profile:
  var mirror=float(settings.get("mirror",1.0))
  near_slot="left" if near_hip.x*mirror<0.0 else "right"
  far_slot="right" if near_slot=="left" else "left"
  # The floor's near/far depth turns continuously, even when the intact
  # torso selects another of its four drawings. Keep sockets at that depth
  # so a facing change alone cannot make the body hop by 1.5 pixels.
  var rest_axis:Vector2=settings.rest_axis
  near_hip.y=(settings[near_slot+"_rest"] as Vector2).y-rest_axis.y*1.5-LEG_LENGTH
  far_hip.y=(settings[far_slot+"_rest"] as Vector2).y-rest_axis.y*1.5-LEG_LENGTH
  var near_center:Vector2=settings[near_slot+"_foot"]
  var far_center:Vector2=settings[far_slot+"_foot"]
  var near_accent=walking_lift_accent(settings,walking,side_profile,near_slot)
  var far_accent=walking_lift_accent(settings,walking,side_profile,far_slot)
  near_center.y-=near_accent;far_center.y-=far_accent
  near_axis=settings[near_slot+"_axis"];far_axis=settings[far_slot+"_axis"]
  near_center.x*=mirror;far_center.x*=mirror;near_axis.x*=mirror;far_axis.x*=mirror
  var near_ankle=near_center-near_axis*1.5
  var far_ankle=far_center-far_axis*1.5
  # Move the intact torso only if a turning contact needs lateral room. Feet
  # remain exact world targets; no foot clamp or stretched leg hides slipping.
  # A socket can tuck two pixels across beneath the shirt during a turn.
  # Combined with the small torso translation, this keeps the one-piece leg
  # compact instead of making a nearly horizontal leg lower the whole body.
  var low=maxf(near_ankle.x-near_hip.x-7.5,far_ankle.x-far_hip.x-7.5)
  var high=minf(near_ankle.x-near_hip.x+7.5,far_ankle.x-far_hip.x+7.5)
  body.x=clampf(0.0,low,high) if low<=high else (low+high)*.5
  near_hip.x+=clampf(near_ankle.x-near_hip.x-body.x,-2.0,2.0)
  far_hip.x+=clampf(far_ankle.x-far_hip.x-body.x,-2.0,2.0)
  var near_dx=near_ankle.x-near_hip.x-body.x
  var far_dx=far_ankle.x-far_hip.x-body.x
  var near_y=near_ankle.y-sqrt(maxf(0.0,LEG_LENGTH*LEG_LENGTH-near_dx*near_dx))
  var far_y=far_ankle.y-sqrt(maxf(0.0,LEG_LENGTH*LEG_LENGTH-far_dx*far_dx))
  var support_floor=maxf(near_y-near_hip.y,far_y-far_hip.y)-HIP_COVER
  var weight_rise=WALK_WEIGHT_RISE*maxf(near_accent,far_accent)/WALK_CLEARANCE_ACCENT
  # Lift the intact shirt/head very slightly over mid-step. The exact leg
  # solution clamps this rise before a socket could uncover under the hem.
  body.y=maxf(-weight_rise,support_floor)
  # Each full-length leg disappears naturally under the unchanged shirt hem.
  # The raised leg's hip can tuck upward; there are no articulated knees.
  var tucked_near=Vector2(near_hip.x,near_y-body.y)
  var tucked_far=Vector2(far_hip.x,far_y-body.y)
  near_angle=atan2(near_dx,near_ankle.y-near_y)
  far_angle=atan2(far_dx,far_ankle.y-far_y)
  near_hip=tucked_near.lerp(near_rest,seated)
  far_hip=tucked_far.lerp(far_rest,seated)
 else:
  var blend=0.0 if bool(settings.get("dismounting",false)) else clampf(float(settings.get("blend",1.0 if walking else 0.0)),0,1)
  var angle=sin(phase*TAU)*.18*blend if walking else 0.0
  near_angle=-angle;far_angle=angle
  body.y=-absf(sin(phase*TAU))*.40*blend if walking else 0.0
 body=body.lerp(Vector2(2,-5.5),seated)
 near_hip=near_hip.lerp(seated_hip(true,facing_back),seated)
 far_hip=far_hip.lerp(seated_hip(false,facing_back),seated)
 # Two short legs project along the seat perspective, as in the figure's
 # annotated pose. Feet remain suspended; no extra knee/shin anatomy is added.
 var seat_axis=Vector2(1,-.5 if facing_back else .5).normalized()
 near_axis=near_axis.lerp(seat_axis,seated).normalized();far_axis=far_axis.lerp(seat_axis,seated).normalized()
 var near_foot=near_hip+Vector2(sin(near_angle),cos(near_angle))*LEG_LENGTH
 var far_foot=far_hip+Vector2(sin(far_angle),cos(far_angle))*LEG_LENGTH
 near_foot=near_foot.lerp(near_hip+seat_axis*SEATED_LEG_REACH,seated)
 far_foot=far_foot.lerp(far_hip+seat_axis*SEATED_LEG_REACH,seated)
 return {"body":body,"near_hip":near_hip,"far_hip":far_hip,"near_foot":near_foot,"far_foot":far_foot,"near_axis":near_axis,"far_axis":far_axis,"near_slot":near_slot,"far_slot":far_slot}

static func body_offset(settings:Dictionary,walking:bool,phase:float) -> Vector2:
 return leg_pose(settings,walking,phase,bool(settings.get("view_back",false))).body

static func head_bounds(species:int,side_profile=false,with_hat=false) -> Rect2:
 # The outer ear/skull extents used by head() and profile_head(), including hat.
 var top=[-73.0 if side_profile else -72.0,-59.0 if side_profile else -60.0,-53.7 if side_profile else -54.4][posmod(species,3)]
 if with_hat:top=minf(top,-63.5)
 return Rect2(Vector2(-14.5,top),Vector2(29.0,-25.0-top))

var a
var origin=Vector2.ZERO
var back=false
var profile=false
var swing=0.0
var blink=false
var chef_hat=false
var blocked=false
var head_attention=0.0
var waiter_tablet=WaiterTabletArt.new()
func dot(p:Vector2,r:Vector2,c):a._face_ellipse(origin+p,r,c)
func line(p:Vector2,q:Vector2,c,w=1.0):a.line(origin+p,origin+q,c,w)
func shape(points:Array,c,r=2.0):
 var world=[]
 for p in points:world.append(origin+p)
 a.rounded_poly(world,r,c)
func ellipse(p:Vector2,r:Vector2,c):a.ellipse(origin+p,r,c)
func paw(start:Vector2,tip:Vector2,c,width=4.7):
 var finish=start+(tip-start).normalized()*10.5
 a._round_limb(origin+start,origin+finish,c,width)
 return finish
func far_overlay_paw(start:Vector2,tip:Vector2,color,width:float,species:int,head_offset=Vector2.ZERO):
 for part in ArmOcclusion.visible_far_arm(start,tip,width,back,profile,species,head_offset):
  var world=[]
  for point in part:world.append(origin+point)
  a.poly(world,color)
static func shoe_outline(ankle:Vector2,axis:Vector2)->Array:
 var center=ankle+axis*1.5;var across=axis.orthogonal();var outline=[]
 for q in [Vector2(-3.9,-1.25),Vector2(-2.8,-2.0),Vector2(1.4,-2.2),Vector2(3.5,-1.6),Vector2(4.1,-.3),Vector2(3.5,1.45),Vector2(1.4,2.15),Vector2(-2.8,1.9),Vector2(-3.9,.95)]:outline.append(center+axis*q.x+across*q.y)
 return outline

static func tail_outline(rear:bool)->Array:
 return [Vector2(-1,-13),Vector2(-6,-11),Vector2(-15,-14),Vector2(-20,-21),Vector2(-18,-27),Vector2(-13,-22),Vector2(-9,-18),Vector2(-1,-18)] if rear else [Vector2(-6,-15),Vector2(-12,-12),Vector2(-21,-17),Vector2(-23,-24),Vector2(-18,-25),Vector2(-14,-20),Vector2(-6,-20)]

static func character_bounds(geometry:Dictionary,at:Vector2,legs:Dictionary,species:int,side_profile:bool,with_hat:bool,back_view:bool)->Rect2:
 var bounds=head_bounds(species,side_profile,with_hat)
 bounds.position+=geometry.head_origin
 var points=ArmOcclusion.torso_points(back_view,side_profile)
 points.append_array(shoe_outline(legs.near_foot,legs.near_axis));points.append_array(shoe_outline(legs.far_foot,legs.far_axis))
 if species==1:points.append_array(tail_outline(back_view))
 for point in points:bounds=bounds.expand(at+point)
 for key in ["near_shoulder","near_hand","far_shoulder","far_hand","near_hip","far_hip","near_foot","far_foot"]:bounds=bounds.expand(geometry[key])
 var cooking:Dictionary=geometry.get("cooking_pose",{})
 for key in ["shoulder","elbow","wrist","hand","thumb"]:
  if cooking.has(key):bounds=bounds.expand(at+cooking[key])
 # Covers the painter's widest 4.8px limb capsule plus its antialias fringe.
 return bounds.grow(3.1)

func shoe(ankle:Vector2,near:bool,axis_override=Vector2.ZERO):
 var axis:Vector2=axis_override if axis_override.length_squared()>.01 else (Vector2.RIGHT if profile else Vector2(1,-.48 if back else .48).normalized())
 var center=ankle+axis*1.5;var across=axis.orthogonal()
 # A narrow heel and rounded toe make forward direction legible. The same
 # ground center and bounds are retained for the planted-foot controller.
 var outline=shoe_outline(ankle,axis)
 shape(outline,"80785b",.45)
 var heel=center-axis*2.9
 if back:
  # Rear views expose the heel band, not the front-facing toe highlight.
  line(heel-across*1.1,heel+across*1.1,"68694f",1.1)
  line(heel-axis*.25-across*.8,heel-axis*.25+across*.8,"a99f7b",.45)
 else:
  var vamp=center+axis*.65-Vector2(0,.55)
  line(vamp-across*1.15,vamp+across*1.15,"b1a782",.7)
func leg(hip:Vector2,ankle:Vector2,color,width:float,_seat_mix:float,_axis:Vector2):
 a._round_limb(origin+hip,origin+ankle,color,width)

func draw(artist:Node2D,at:Vector2,species:int,facing_back:bool,walking=false,phase=0.0,staff=false,side_profile=false,settings:Dictionary={}):
 a=artist;origin=at;back=facing_back;profile=side_profile;swing=sin(phase*TAU)*2.0 if walking else 0.0
 var fur=FUR[species];var shadow="b77d42" if species==1 else "ded2b0";var cloth=str(settings.get("shirt",CLOTH[species]))
 var action=str(settings.get("action","idle"));var t=float(settings.get("progress",0));var payload=str(settings.get("payload","none"));var tool=str(settings.get("tool","none"))
 # Defensive presentation boundary: an old/direct caller can still pass a
 # kitchen phase. A customer waiting for food has empty hands, never a spatula.
 if not staff and action=="cooking":action="waiting_meal";tool="none"
 var overlay=bool(settings.get("reach_overlay",false));var hide=bool(settings.get("hide_reach",false))
 var geometry_only=bool(settings.get("geometry_only",false))
 blink=bool(settings.get("blink",false));chef_hat=bool(settings.get("chef_hat",false));blocked=action=="blocked"
 var seat_mix=clampf(float(settings.get("seat_mix",0.0)),0,1)
 var blend=0.0 if bool(settings.get("dismounting",false)) else clampf(float(settings.get("blend",1.0 if walking else 0.0)),0,1)*(1.0-seat_mix)
 swing*=blend
 var legs=leg_pose(settings,walking,phase,back,profile)
 if staff and action=="cooking":
  # A small upper-body weight transfer drives the scoop while the shoes stay
  # planted. Solve the short legs back to their original ground anchors.
  legs=CookingPose.apply_body_weight(legs,float(settings.get("cooking_elapsed",0.0)),LEG_LENGTH,float(settings.get("cooking_remaining",-1.0)),float(settings.get("cooking_strength",1.0)))
 origin+=legs.body
 if not overlay and not geometry_only:ellipse(Vector2(2*seat_mix,2)-legs.body,Vector2(10,3.1),Color(.37,.42,.29,.12))
 # Far arm and far leg are behind the torso; near parts are in front.
 var far_shoulder=Vector2(-1,-25.5) if profile else (Vector2(-6,-26.5) if back else Vector2(6,-26.5))
 var near_shoulder=Vector2(1,-23.5) if profile else (Vector2(7,-24) if back else Vector2(-7,-24))
 var relaxed=not walking and seat_mix<.01 and payload=="none" and tool=="none" and action in ["idle","standby","blocked"]
 var far_tip=far_shoulder+(Vector2.DOWN if relaxed else Vector2(-1-swing,10).normalized())*10.5
 var carry:Vector2=settings.get("carry_hand",carry_anchor(back))
 var near_target=near_shoulder+Vector2(1+swing,10)
 if payload!="none":near_target=carry
 elif action in ["cooking","preparing_food","preparing_drink","washing"]:near_target=near_shoulder+Vector2(8,1+sin(t*TAU*2)*.6)
 elif action in ["serving","placing_plate","dropping_dishes","collecting","collecting_plate","collecting_drink","plating","taking_order"]:near_target=near_shoulder+Vector2(7,3)
 elif action in ["drinking","standby"]:near_target=near_shoulder+Vector2(3,8+sin(t*TAU)*.4)
 elif action in ["mopping","sweeping"]:near_target=near_shoulder+Vector2(7,4+sin(t*TAU*2))
 if relaxed:near_target=near_shoulder+Vector2.DOWN
 var near_tip=near_shoulder+(near_target-near_shoulder).normalized()*10.5
 waiter_tablet.update(staff,str(settings.get("role","")),action,payload,tool,t,back,near_shoulder,far_shoulder)
 if waiter_tablet.ordering:
  near_tip=waiter_tablet.near_hand;far_tip=waiter_tablet.far_hand
 var pickup_pose={}
 if staff and action in ["placing_plate","collecting_plate"] and settings.has("pickup_grip"):
  pickup_pose=PickupArt.pose(near_shoulder,far_shoulder,carry,settings.pickup_grip-origin,settings.pickup_plate-origin,t,action=="collecting_plate",1 if back else 0)
  if pickup_pose.use_near:near_tip=pickup_pose.hand
  else:far_tip=pickup_pose.hand
 var dining_pose={}
 if not staff and action=="eating" and seat_mix>.99 and payload=="none":
  dining_pose=DiningPose.pose(near_shoulder,far_shoulder,settings.get("reach",Vector2(30,-40))-origin,t,back,near_tip if back else far_tip,float(settings.get("mirror",1.0)))
  if dining_pose.use_near:near_tip=dining_pose.hand
  else:far_tip=dining_pose.hand
 var cooking_pose={}
 if staff and action=="cooking":
  if bool(settings.get("cooking_grip",false)):
   cooking_pose=CookingPose.grip_pose(near_shoulder,far_shoulder,settings.get("reach",Vector2(18,-36))-origin,float(settings.get("cooking_elapsed",0.0)),float(settings.get("cooking_remaining",-1.0)),float(settings.get("cooking_strength",1.0)))
   if cooking_pose.use_near:near_tip=cooking_pose.hand
   else:
    far_tip=cooking_pose.hand
    near_tip=near_shoulder+Vector2.DOWN*10.5
  else:
   cooking_pose=CookingPose.pose(near_shoulder,settings.get("reach",Vector2(18,-36))-origin,float(settings.get("cooking_elapsed",0.0)),float(settings.get("cooking_remaining",-1.0)),float(settings.get("cooking_strength",1.0)))
   cooking_pose["use_near"]=true
   near_tip=cooking_pose.hand
 var washing_pose={}
 if action=="washing" and settings.has("washing_basis"):
  var reference:Dictionary=settings.get("washing_grip_reference",{}).duplicate()
  if not reference.is_empty():reference.center-=origin
  washing_pose=SinkWashArt.pose(near_shoulder,far_shoulder,settings.get("reach",Vector2(10,-24))-origin,settings.washing_basis,float(settings.get("washing_seconds",0.0)),reference)
  near_tip=washing_pose.near.hand;far_tip=washing_pose.far.hand
 var cleaning_pose={}
 var disposal_pose={}
 var wiping_pose={}
 var payment_pose={}
 if action in ["paying","taking_payment"]:
  payment_pose=CheckoutArt.payment_pose(near_shoulder,far_shoulder,settings.get("reach",Vector2(18,-31))-origin,t,action=="taking_payment")
  if payment_pose.use_near:near_tip=payment_pose.hand
  else:far_tip=payment_pose.hand
 if action=="wiping" and tool=="cloth":
  wiping_pose=CleaningPose.table_pose(near_shoulder,far_shoulder,settings.get("reach",Vector2(18,-34))-origin,t)
  if wiping_pose.use_near:near_tip=wiping_pose.hand
  else:far_tip=wiping_pose.hand
 if action in ["sweeping","mopping"]:
  var ground:Vector2=settings.get("reach",Vector2(22,2))-origin+Vector2(3,-3)
  cleaning_pose=CleaningPose.floor_pose(near_shoulder,far_shoulder,ground,back,t,action=="sweeping")
  near_tip=cleaning_pose.near_hand
  if action=="sweeping":far_tip=cleaning_pose.far_hand
 if action=="disposing_trash":
  var bin_rim:Vector2=settings.get("reach",Vector2(18,-32))-origin+Vector2(3,-3)
  disposal_pose=CleaningPose.disposal_pose(near_shoulder,near_tip,bin_rim,back,t)
  near_tip=disposal_pose.hand
 var geometry={"near_shoulder":origin+near_shoulder,"near_hand":origin+near_tip,"far_shoulder":origin+far_shoulder,"far_hand":origin+far_tip,"pickup_pose":pickup_pose,"washing_pose":washing_pose,"dining_pose":dining_pose,"cooking_pose":cooking_pose,"cleaning_pose":cleaning_pose,"wiping_pose":wiping_pose,"payment_pose":payment_pose,"carry":origin+carry,"far_hip":origin+legs.far_hip,"far_foot":origin+legs.far_foot,"near_hip":origin+legs.near_hip,"near_foot":origin+legs.near_foot,"body":legs.body,"near_slot":legs.near_slot,"far_slot":legs.far_slot,"near_shoe":origin+legs.near_foot+legs.near_axis*1.5,"far_shoe":origin+legs.far_foot+legs.far_axis*1.5}
 var bounds_head_origin=origin+(Vector2(-.25,.85)*waiter_tablet.head_attention if waiter_tablet.head_attention>.0001 else (dining_pose.head_offset if not dining_pose.is_empty() else Vector2.ZERO))
 geometry["head_origin"]=bounds_head_origin
 if geometry_only:
  var near_outline=[];var far_outline=[]
  for point in shoe_outline(legs.near_foot,legs.near_axis):near_outline.append(origin+point)
  for point in shoe_outline(legs.far_foot,legs.far_axis):far_outline.append(origin+point)
  geometry["near_shoe_polygon"]=near_outline;geometry["far_shoe_polygon"]=far_outline
  geometry["occlusion_bounds"]=character_bounds(geometry,origin,legs,species,profile,chef_hat,back)
  return geometry
 if not overlay and waiter_tablet.enabled and back:
  waiter_tablet.draw_tablet(a,origin)
  waiter_tablet.draw_case(a,origin)
  waiter_tablet.draw_hands(a,origin,fur,shadow)
  if waiter_tablet.ordering and not hide:paw(near_shoulder,near_tip,fur,4.8)
 if not overlay:
  if back and not hide and not cleaning_pose.is_empty():
   # Floor work faces away from the viewer. Shafts, floor heads and the far
   # grip must be behind the intact torso/head, not painted across its back.
   a._draw_floor_tools(origin,cleaning_pose,action,payload)
   if action=="sweeping":ellipse(far_tip,Vector2(2.0,2.0),shadow)
  if not pickup_pose.is_empty() and not pickup_pose.use_near:
   paw(pickup_pose.shoulder,pickup_pose.elbow,shadow,3.7);paw(pickup_pose.elbow,pickup_pose.hand,shadow,3.7)
  elif not cooking_pose.is_empty() and not cooking_pose.use_near:CookingPose.draw(a,origin,cooking_pose,shadow,shadow)
  elif not washing_pose.is_empty():washing_arm(washing_pose.far,shadow,4.4,species,false)
  else:paw(far_shoulder,far_tip,shadow,4.4)
 var far_hip:Vector2=legs.far_hip;var near_hip:Vector2=legs.near_hip
 var far_foot:Vector2=legs.far_foot;var near_foot:Vector2=legs.near_foot
 if not overlay:
  leg(far_hip,far_foot,"938b6c",3.8,seat_mix,legs.far_axis);shoe(far_foot,false,legs.far_axis)
  leg(near_hip,near_foot,"a19774",4.1,seat_mix,legs.near_axis)
 if not overlay:
  if not back and species==1:tail(false)
  if not back and species==0:ellipse(Vector2(-9,-13),Vector2(3.4,3.3),"f6ebce")
  # The same intact outline also masks far-arm worktop overlays.
  shape(ArmOcclusion.torso_points(back,profile),cloth,3.5)
  # Three-quarter torso: shoulder line, side panel and hem all share the view.
  if profile:
   shape([Vector2(-5.5,-28),Vector2(-2.5,-25),Vector2(-3,-12),Vector2(-6,-11.5),Vector2(-8,-20)],Color(cloth).darkened(.075),1.8)
   line(Vector2(-4.5,-13.4),Vector2(5.6,-13),Color(cloth).lightened(.23),.75)
  elif back:
   shape([Vector2(5.3,-29),Vector2(9,-23),Vector2(8.2,-11.5),Vector2(4.6,-12),Vector2(5,-23)],Color(cloth).darkened(.075),1.8)
   line(Vector2(-6,-12),Vector2(6,-13.2),Color(cloth).lightened(.23),.75)
  else:
   shape([Vector2(-7.5,-28.2),Vector2(-4.8,-25),Vector2(-4,-12),Vector2(-7,-12.2),Vector2(-10,-20)],Color(cloth).darkened(.075),1.7)
   line(Vector2(-5,-14),Vector2(7,-12.8),Color(cloth).lightened(.23),.75)
  shoe(near_foot,true,legs.near_axis)
  if staff:
   if back:
    line(Vector2(-7,-18),Vector2(7,-19),"eadfc0",1.6)
    line(Vector2(0,-19),Vector2(-2,-13),"eadfc0",1.0)
   else:
    shape([Vector2(-3,-25.5),Vector2(5.5,-24.5),Vector2(7,-13),Vector2(-4.5,-14)],"eee3c4",1.7)
    line(Vector2(-3,-26),Vector2(-2,-21),"e0d6b9",1.3)
    line(Vector2(4,-25),Vector2(4.7,-20),"e0d6b9",1.3)
  if back:
   if species==1:tail(true)
   else:ellipse(Vector2(-2,-12.5),Vector2(3.7,3.6),"f6ebce")
 if not overlay and waiter_tablet.enabled:
  waiter_tablet.draw_strap(a,origin)
  if not back:
   if waiter_tablet.ordering and not hide:paw(near_shoulder,near_tip,fur,4.8)
   waiter_tablet.draw_tablet(a,origin)
   waiter_tablet.draw_case(a,origin)
 var far_work=(not pickup_pose.is_empty() and not pickup_pose.use_near) or (not cooking_pose.is_empty() and not cooking_pose.use_near) or (not dining_pose.is_empty() and not dining_pose.use_near) or (not payment_pose.is_empty() and not payment_pose.use_near) or (not wiping_pose.is_empty() and not wiping_pose.use_near)
 if hide and not overlay and far_work:paw(near_shoulder,near_tip,fur,4.8)
 if not hide:
  if not waiter_tablet.ordering and (cooking_pose.is_empty() or not cooking_pose.use_near) and not (overlay and far_work) and washing_pose.is_empty() and (pickup_pose.is_empty() or not pickup_pose.use_near) and (dining_pose.is_empty() or not dining_pose.use_near):paw(near_shoulder,near_tip,fur,4.8)
  var work_hand=far_tip if payload!="none" and tool in ["cloth","mop","broom"] else near_tip
  var floor:Vector2=settings.get("reach",Vector2(22,2))-origin+Vector2(3,-3) if tool in ["mop","broom"] else Vector2(22,2)
  if waiter_tablet.enabled and action=="taking_order":
   if not waiter_tablet.ordering:a._action_prop(origin,carry,"idle",t,payload,tool,work_hand,near_tip,floor)
   elif not back:
    # The far arm remains behind the torso; only fingers cover the device.
    waiter_tablet.draw_hands(a,origin,fur,shadow)
  elif not pickup_pose.is_empty():
   if pickup_pose.use_near:
    paw(pickup_pose.shoulder,pickup_pose.elbow,fur,3.7);paw(pickup_pose.elbow,pickup_pose.hand,fur,3.7)
   elif overlay:
    far_overlay_paw(pickup_pose.shoulder,pickup_pose.elbow,shadow,3.7,species);far_overlay_paw(pickup_pose.elbow,pickup_pose.hand,shadow,3.7,species)
   if payload=="plate":a._plate(origin+pickup_pose.plate,1.0,false)
   ellipse(pickup_pose.hand,Vector2(1.8,1.8),fur if pickup_pose.use_near else shadow)
  elif not dining_pose.is_empty():
   if not overlay or dining_pose.over_table:
    if dining_pose.use_near:paw(dining_pose.shoulder,dining_pose.hand,fur,4.8)
    elif overlay:far_overlay_paw(dining_pose.shoulder,dining_pose.hand,shadow,4.4,species,dining_pose.head_offset)
    if back or overlay:DiningPose.draw(a,origin,dining_pose,fur,shadow)
  elif not washing_pose.is_empty():
   washing_arm(washing_pose.near,fur,4.8,species,false)
   if overlay:washing_arm(washing_pose.far,shadow,4.4,species,true)
   var contact:Vector2=washing_pose.work.hand
   if washing_pose.contact:
    a.rounded_poly([origin+contact+Vector2(-2,-.8),origin+contact+Vector2(1.8,-1.3),origin+contact+Vector2(2.2,.7),origin+contact+Vector2(-1.8,1.1)],.5,"c3d2b6")
   ellipse(washing_pose.support.hand,Vector2(1.7,1.6),shadow if washing_pose.use_near else fur)
   ellipse(contact+Vector2(0,-.5),Vector2(1.7,1.6),fur if washing_pose.use_near else shadow)
  elif not cooking_pose.is_empty():
   if cooking_pose.use_near:CookingPose.draw(a,origin,cooking_pose,fur,shadow)
   elif overlay:
    # Reveal only distal segments above the cabinet; never repaint through
    # the intact torso or head when the far hand owns the pot grip.
    far_overlay_paw(cooking_pose.shoulder,cooking_pose.elbow,shadow,3.7,species)
    far_overlay_paw(cooking_pose.elbow,cooking_pose.hand,shadow,3.7,species)
    ellipse(cooking_pose.hand,Vector2(1.6,1.6),fur)
  elif not wiping_pose.is_empty():
   if overlay and not wiping_pose.use_near:far_overlay_paw(far_shoulder,far_tip,shadow,4.4,species)
   if wiping_pose.contact:
    a._action_prop(origin,carry,action,t,payload,tool,wiping_pose.hand,wiping_pose.hand,floor)
    ellipse(wiping_pose.hand,Vector2(2.1,2.1),fur if wiping_pose.use_near else shadow)
  elif not payment_pose.is_empty():
   if overlay and not payment_pose.use_near:far_overlay_paw(far_shoulder,far_tip,shadow,4.4,species)
   CheckoutArt.hand_prop(a,origin+payment_pose.hand,t,action=="taking_payment")
   ellipse(payment_pose.hand,Vector2(1.8,1.8),fur if payment_pose.use_near else shadow)
  elif not cleaning_pose.is_empty():
   if not back:
    a._draw_floor_tools(origin,cleaning_pose,action,payload)
    if action=="sweeping":ellipse(far_tip,Vector2(2.0,2.0),shadow)
   # Only the near grip is in front; the far grip was masked by the body.
   ellipse(near_tip,Vector2(2.1,2.1),fur)
  elif payload=="trash" or tool=="dustpan":
   var carried=disposal_pose if not disposal_pose.is_empty() else CleaningPose.carried_pan(near_tip,back,0.0,false)
   a._dustpan(origin+carried.pan,origin+carried.hand,carried.axis,payload=="trash")
   ellipse(near_tip,Vector2(2.1,2.1),fur)
  else:a._action_prop(origin,carry,action,t,payload,tool,work_hand,near_tip,floor)
 if not overlay:
  head_attention=waiter_tablet.head_attention
  if head_attention>.0001:
   # A small downward nod and eye shift follows the display, then returns to
   # the guest. Only this moving head uses source geometry; idle stays cached.
   var head_origin=origin
   origin+=Vector2(-.25,.85)*head_attention
   head(species)
   origin=head_origin
  else:a._draw_head(origin+(dining_pose.head_offset if not dining_pose.is_empty() else Vector2.ZERO),species,back,blink,chef_hat,blocked,2 if profile else (3 if back else 0))
  if not dining_pose.is_empty() and not back and (not hide or not dining_pose.over_table):DiningPose.draw(a,origin,dining_pose,fur,shadow)
  head_attention=0.0
 return geometry
func washing_arm(part:Dictionary,color,width:float,species:int,masked:bool):
 if masked:
  far_overlay_paw(part.shoulder,part.elbow,color,width,species)
  # The elbow emerges beside the torso, then the bent forearm comes forward
  # over the plate. Masking it by the apron severs the wrist from the hand.
  # Keep the head in front while preserving ordinary far-arm body masking.
  for piece in washing_forearm_parts(part,width,species):
   var world=[]
   for point in piece:world.append(origin+point)
   a.poly(world,color)
 else:
  # These are already solved half-arm endpoints. paw() is reserved for one
  # complete 10.5-pixel arm and would double each segment past the joint.
  a._round_limb(origin+part.shoulder,origin+part.elbow,color,width)
  for piece in washing_forearm_parts(part,width,species,false):
   var world=[]
   for point in piece:world.append(origin+point)
   a.poly(world,color)

func washing_forearm_parts(part:Dictionary,width:float,species:int,mask_head=true)->Array[PackedVector2Array]:
 var axis:Vector2=(part.hand-part.elbow).normalized();var angle=axis.angle();var side=Vector2(-axis.y,axis.x)
 var middle:Vector2=part.elbow.lerp(part.hand,.4);var outline=PackedVector2Array()
 # Keep the rounded elbow but narrow the visible forearm itself, not only
 # its tip. The wrist is slimmer than the palm, so both read separately.
 for k in range(13):outline.append(part.hand+Vector2.from_angle(angle-PI*.5+PI*float(k)/12)*1.45)
 outline.append(middle+side*width*.38)
 for k in range(13):outline.append(part.elbow+Vector2.from_angle(angle+PI*.5+PI*float(k)/12)*width*.5)
 outline.append(middle-side*width*.38)
 var pieces:Array[PackedVector2Array]=[outline]
 if not mask_head:return pieces
 for mask in ArmOcclusion.head_masks(back,profile,species,Vector2.ZERO):
  for cover in Geometry2D.offset_polygon(mask,.7):
   var visible:Array[PackedVector2Array]=[]
   for piece in pieces:visible.append_array(Geometry2D.clip_polygons(piece,cover))
   pieces=visible
 return pieces

static func carry_anchor(away:bool)->Vector2:return Vector2(13,-17) if away else Vector2(2,-18)
func eye(at:Vector2,size:Vector2):
 at+=Vector2(-.65,1.0)*head_attention
 if blink:
  a._face_line(origin+at+Vector2(-size.x,0),origin+at+Vector2(0,-.5),"4e624b",.8)
  a._face_line(origin+at+Vector2(0,-.5),origin+at+Vector2(size.x,0),"4e624b",.8)
 else:
  dot(at,size,"4e624b");dot(at+Vector2(.2,-.5),Vector2(.25,.28),"f8f0d9")
 if blocked:a._face_line(origin+at+Vector2(-1,-2.6),origin+at+Vector2(1,-2),"758061",.7)
func hat(species:int):
 # Fitted toque: the crown is an asymmetric soft volume; the band wraps the
 # skull instead of ending as a flat white bar. All marks share the head's
 # authored view, so profile/rear are not front art pasted on another face.
 var cream="fff5dd"
 var shade="e5d8b9"
 var edge="d6c6a3"
 if profile:
  shape([Vector2(-10.6,-50.5),Vector2(-12.3,-54.7),Vector2(-10.7,-59.4),Vector2(-6.2,-61.7),Vector2(-2.8,-60.7),Vector2(1.2,-63),Vector2(6,-61.6),Vector2(9.3,-57.3),Vector2(8.6,-51.8)],cream,2.1)
  shape([Vector2(-10.6,-53),Vector2(-8.6,-51.4),Vector2(-7.7,-48.1),Vector2(-10.2,-48.9)],shade,.7)
  # A curved contact edge anchors the band to the sloping forehead.
  a._face_line(origin+Vector2(-10,-48.5),origin+Vector2(7.8,-47.1),"c9bb99",1.15)
  shape([Vector2(-10.3,-52.3),Vector2(-2.5,-52.7),Vector2(8.6,-51.4),Vector2(8,-47.8),Vector2(-2.2,-48.2),Vector2(-9.9,-49.4)],cream,1.2)
  line(Vector2(-9,-50.1),Vector2(-2.5,-49.1),edge,.55)
  line(Vector2(-2.5,-49.1),Vector2(7.4,-48.7),edge,.55)
  line(Vector2(3.3,-57.8),Vector2(4.4,-54),shade,.65)
 elif back:
  shape([Vector2(-11.1,-51.7),Vector2(-13,-55.7),Vector2(-10.7,-60.3),Vector2(-5.4,-61.3),Vector2(-1.4,-59.9),Vector2(3,-63),Vector2(8.4,-61.8),Vector2(11.5,-57.4),Vector2(10.3,-52.3)],cream,2.2)
  a._face_line(origin+Vector2(-9.4,-47.5),origin+Vector2(9.3,-48.9),"c9bb99",1.15)
  shape([Vector2(-10.8,-52.7),Vector2(-1,-52),Vector2(10.4,-54),Vector2(9.7,-49.3),Vector2(-.5,-47.9),Vector2(-10.1,-48.8)],cream,1.25)
  line(Vector2(-9.3,-49.8),Vector2(-.5,-49),edge,.6)
  line(Vector2(-.5,-49),Vector2(8.8,-50.3),edge,.6)
  line(Vector2(5.8,-53),Vector2(5.3,-50),shade,.7)
  line(Vector2(-7.5,-57.6),Vector2(-6.6,-54.6),shade,.65)
 else:
  shape([Vector2(-11.4,-52),Vector2(-13,-56.1),Vector2(-10.6,-60.4),Vector2(-6.2,-61.9),Vector2(-1.7,-60.5),Vector2(2.6,-63),Vector2(7.8,-61.9),Vector2(11.5,-58),Vector2(10.3,-52)],cream,2.2)
  shape([Vector2(-11.2,-53.2),Vector2(-7.6,-52.6),Vector2(-7.2,-48.2),Vector2(-10.3,-49.4)],shade,.7)
  a._face_line(origin+Vector2(-9.8,-48.3),origin+Vector2(9.3,-47.9),"c9bb99",1.15)
  shape([Vector2(-10.7,-53),Vector2(-1,-53.5),Vector2(10.4,-52.3),Vector2(9.7,-48.1),Vector2(.2,-47.7),Vector2(-10.1,-49)],cream,1.25)
  line(Vector2(-9.1,-50),Vector2(.3,-48.8),edge,.6)
  line(Vector2(.3,-48.8),Vector2(8.8,-49.1),edge,.6)
  line(Vector2(6.9,-58.8),Vector2(7.1,-54.4),shade,.65)
 if species==0:
  # The two long ears are retained at their original tips. They emerge from
  # tailored oval ports, with an inset shadow and a foreground fabric lip.
  # Only the exposed upper ear is repainted, never a complete ear over fabric.
  if profile:
   hat_ear_port([Vector2(-8,-61.4),Vector2(-9,-63),Vector2(-7,-68),Vector2(-4,-65),Vector2(-3.8,-61.1)],Vector2(-5.8,-61.2),Vector2(3.4,1.4),"dfd4b5",Vector2.ZERO,Vector2.ZERO)
   hat_ear_port([Vector2(-3,-60.6),Vector2(-3,-69),Vector2(0,-73),Vector2(3,-69),Vector2(3.6,-60.2)],Vector2(.3,-60.4),Vector2(3.7,1.45),FUR[0],Vector2(.2,-66),Vector2(.4,-61.4))
  else:
   hat_ear_port([Vector2(-9.6,-60),Vector2(-10,-63),Vector2(-8,-67),Vector2(-5,-65),Vector2(-4.3,-59.7)],Vector2(-7,-59.8),Vector2(3.5,1.45),FUR[0],Vector2.ZERO if back else Vector2(-7,-62),Vector2.ZERO if back else Vector2(-6.5,-60.8))
   hat_ear_port([Vector2(.4,-61.4),Vector2(0,-68),Vector2(3,-72),Vector2(6,-69),Vector2(6.4,-61.2)],Vector2(3.3,-61.2),Vector2(3.7,1.45),FUR[0],Vector2.ZERO if back else Vector2(3,-66),Vector2.ZERO if back else Vector2(3.3,-62.2))

func hat_ear_port(points:Array,center:Vector2,radius:Vector2,fur,inner_start:Vector2,inner_end:Vector2):
 ellipse(center,radius,"c3b28d")
 shape(points,fur,1.65)
 if inner_start!=Vector2.ZERO:line(inner_start,inner_end,"d9bca7",1.5)
 # The front rim hides the very bottom of the ear and gives the opening
 # visible thickness. This is a fabric cutout, not an accidental intersection.
 var points_lip=[]
 for index in range(9):
  var angle=PI*float(index)/8.0
  points_lip.append(center+Vector2(cos(angle)*radius.x,sin(angle)*radius.y*.66))
 for index in range(points_lip.size()-1):line(points_lip[index],points_lip[index+1],"f5e9ca",1.05)
func tail(rear:bool):
 if rear:
  shape(tail_outline(true),"c68b46",3.0)
  shape([Vector2(-20,-21),Vector2(-18,-27),Vector2(-14,-23),Vector2(-15,-18)],"f3e5c7",2.2)
 else:
  shape(tail_outline(false),"bd8343",3.0)
  shape([Vector2(-21,-17),Vector2(-23,-24),Vector2(-18,-25),Vector2(-17,-20)],"f3e5c7",2.0)
func head(species:int):
 var fur=FUR[species]
 if profile:
  profile_head(species)
  return
 # The far ear is narrower and lower; near ear overlaps the back of the skull.
 if species==2:
  ellipse(Vector2(-9,-47),Vector2(5.5,5.8),fur);ellipse(Vector2(7,-49),Vector2(5.0,5.4),fur)
  if not back:ellipse(Vector2(-9,-47),Vector2(2.7,3.0),"d6c19f");ellipse(Vector2(7,-49),Vector2(2.5,2.8),"d6c19f")
 elif species==0:
  shape([Vector2(-8,-45),Vector2(-10,-63),Vector2(-8,-67),Vector2(-5,-65),Vector2(-3,-46)],fur,2.8)
  shape([Vector2(1,-46),Vector2(0,-68),Vector2(3,-72),Vector2(6,-69),Vector2(7,-46)],fur,3.0)
  if not back:
   line(Vector2(-7,-62),Vector2(-5.8,-51),"d9bca7",1.55)
   line(Vector2(3,-66),Vector2(3.6,-51),"d9bca7",1.7)
 else:
  shape([Vector2(-12,-42),Vector2(-12,-56),Vector2(-2,-49)],fur,2.0)
  shape([Vector2(1,-49),Vector2(9,-60),Vector2(12,-42)],fur,2.0)
  if not back:
   shape([Vector2(-9,-47),Vector2(-10,-53),Vector2(-5,-49)],"af794b",1)
   shape([Vector2(5,-49),Vector2(8,-55),Vector2(9,-46)],"af794b",1)
 ellipse(Vector2(-.5 if back else 0,-38),Vector2(13.1,12.7),fur)
 if back:
  if chef_hat:hat(species)
  return
 if species==1:
  shape([Vector2(-10,-36),Vector2(-4,-34),Vector2(4,-36),Vector2(12,-34),Vector2(8,-28),Vector2(0,-26),Vector2(-8,-29)],"f4e8cd",3.3)
 else:ellipse(Vector2(4.5,-33),Vector2(8.5,5.4),"f5ebd0")
 # Cute readability: both three-quarter eyes share exactly one size and line.
 eye(Vector2(.8,EYE_LINE),EYE_PAIR_SIZE);eye(Vector2(8.0,EYE_LINE),EYE_PAIR_SIZE)
 dot(Vector2(9.1,-34.8),Vector2(1.5,1.0),"b28b77" if species==0 else "6c654e")
 a._face_line(origin+Vector2(9,-33.8),origin+Vector2(8.5,-32.5),"99866b",.65)
 a._face_line(origin+Vector2(8.5,-32.5),origin+Vector2(6.4,-32.0),"99866b",.65)
 dot(Vector2(1,-33.5),Vector2(1.8,1.0),Color(.81,.52,.42,.16))
 if chef_hat:hat(species)
func profile_head(species:int):
 var fur=FUR[species]
 if species==2:
  ellipse(Vector2(-8,-47),Vector2(4,5.5),"ded2b0");ellipse(Vector2(-1,-48),Vector2(4.7,5.7),fur);ellipse(Vector2(-1,-48),Vector2(2.5,3),"d6c19f")
 elif species==0:
  # True side: two ears overlap in depth instead of maintaining frontal spacing.
  shape([Vector2(-7,-46),Vector2(-9,-63),Vector2(-7,-68),Vector2(-4,-65),Vector2(-2,-46)],"dfd4b5",2.6)
  shape([Vector2(-3,-46),Vector2(-3,-69),Vector2(0,-73),Vector2(3,-69),Vector2(4,-46)],fur,3.0)
  line(Vector2(.2,-66),Vector2(.4,-51),"d9bca7",1.6)
 else:
  shape([Vector2(-12,-44),Vector2(-11,-55),Vector2(-3,-49)],"b87e43",1.7)
  shape([Vector2(-3,-48),Vector2(3,-59),Vector2(7,-44)],fur,2.0)
  shape([Vector2(0,-48),Vector2(3,-55),Vector2(5,-46)],"af794b",1.0)
 # The forehead, short muzzle, nose tip and chin are one outer head silhouette.
 shape([Vector2(-12,-44),Vector2(-9,-50),Vector2(-1,-52),Vector2(7,-49),Vector2(10,-43),Vector2(9,-38),Vector2(13,-36),Vector2(14,-33),Vector2(9,-29),Vector2(1,-27),Vector2(-9,-30),Vector2(-13,-37)],fur,4.0)
 shape([Vector2(-7,-36),Vector2(0,-34.5),Vector2(6,-37),Vector2(13,-35.5),Vector2(14,-33),Vector2(9,-29),Vector2(1,-27),Vector2(-8,-30)],"f4e8cd" if species==1 else "f5ebd0",3.5)
 eye(Vector2(5.7,-40.7),Vector2(1.25,1.7))
 dot(Vector2(12.5,-34.6),Vector2(1.30,.95),"b28b77" if species==0 else "6c654e")
 a._face_line(origin+Vector2(11.8,-33.5),origin+Vector2(10.3,-31.8),"99866b",.65)
 a._face_line(origin+Vector2(10.3,-31.8),origin+Vector2(7.7,-31.5),"99866b",.65)
 dot(Vector2(2.5,-33.5),Vector2(1.7,1.0),Color(.81,.52,.42,.16))

 if chef_hat:hat(species)
