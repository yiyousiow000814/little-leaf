extends RefCounted
## Waiter presentation only. The service controller remains the sole clock.
## Immutable small vector contours; one reusable pose per character painter.
const ARM_LENGTH=10.5
const FINGER_REACH=2.2
const SCREEN_CONTACT=Vector2(3.0,-1.3)
# Two deliberate presses fit inside the existing order clock. The free hand
# clears the glass before the holder starts returning the device to its case.
const TAP_LIFT=.19
const TAP_WITHDRAW_START=.62
const TAP_WITHDRAW_END=.69
const STOW_START=.72
const CASE_FRONT=Vector2(-11.9,-17.0)
const CASE_BACK=Vector2(-11.0,-17.5)
static var CASE_EDGE=PackedVector2Array([Vector2(-3.6,-5.1),Vector2(2.6,-4.7),Vector2(3.7,-3.6),Vector2(3.6,5.0),Vector2(2.5,6.0),Vector2(-2.7,5.5),Vector2(-3.8,4.4),Vector2(-3.6,-5.1)])
static var CASE_PANEL=PackedVector2Array([Vector2(-2.8,-2.8),Vector2(2.7,-2.4),Vector2(2.6,4.3),Vector2(1.8,4.9),Vector2(-2.7,4.4),Vector2(-2.8,-2.8)])
static var TABLET_EDGE=PackedVector2Array([Vector2(-3.9,-8.2),Vector2(-3.2,-8.9),Vector2(3.4,-8.1),Vector2(4,-7.4),Vector2(3.9,.2),Vector2(1.1,.9),Vector2(-3.3,.1),Vector2(-4,-.6),Vector2(-3.9,-8.2)])
static var SCREEN=PackedVector2Array([Vector2(-3.1,-7.5),Vector2(3.1,-6.8),Vector2(3,-.5),Vector2(-3.2,-1.2),Vector2(-3.1,-7.5)])
static var CASE_STOWED_EDGE=PackedVector2Array([Vector2(-2.6,-5.4),Vector2(-2.2,-6.6),Vector2(2.3,-6.2),Vector2(2.9,-5.1),Vector2(-2.6,-5.4)])
var enabled=false
var ordering=false
var exposed=false
var contact=false
var tap_visible=false
var back=false
var near_hand=Vector2.ZERO
var far_hand=Vector2.ZERO
var grip=Vector2.ZERO
var tap=Vector2.ZERO
var tap_fingertip=Vector2.ZERO
var tap_surface=Vector2.ZERO
var tablet_transform=Transform2D.IDENTITY
var tap_ready=0.0
var tap_lift=0.0
var presentation=0.0
var head_attention=0.0

static func eligible(staff:bool,role:String)->bool:return staff and role=="waiter"

func update(staff:bool,role:String,action:String,payload:String,tool:String,progress:float,facing_back:bool,near:Vector2,far:Vector2):
 enabled=eligible(staff,role);back=facing_back
 # Conflicting payload/tool states keep both hands available for real work.
 ordering=enabled and action=="taking_order" and payload=="none" and tool in ["none","notepad"]
 exposed=false;contact=false;tap_visible=false
 tap_ready=0.0;tap_lift=0.0;presentation=0.0;head_attention=0.0
 if not ordering:return
 var t=clampf(progress,0.0,1.0)
 var withdrawn=smoothstep(.08,.20,t)*(1.0-smoothstep(.86,.94,t))
 var presented=smoothstep(.20,.34,t)*(1.0-smoothstep(STOW_START,.86,t))
 presentation=presented
 head_attention=smoothstep(.20,.34,t)*(1.0-smoothstep(.62,.76,t))
 # The holder changes depth with the body view; both intact arms remain10.5.
 var holder=far if back else near
 var tapping=near if back else far
 var rest=2.06 if back else 2.07
 var held=1.20 if back else .93
 var lifted=2.48 if not back else 2.42
 var holder_angle=lerp_angle(lerp_angle(rest,lifted,withdrawn),held,presented)
 grip=holder+Vector2.from_angle(holder_angle)*ARM_LENGTH
 var holder_rest=Vector2(-1,10).angle() if back else Vector2(1,10).angle()
 var grasp=smoothstep(0.0,.08,t)*(1.0-smoothstep(.94,1.0,t))
 var holder_hand=holder+Vector2.from_angle(lerp_angle(holder_rest,holder_angle,grasp))*ARM_LENGTH
 # Rear views place the device physically in front of the animal.
 # Its torso correctly occludes the central tablet; extraction shows the edge.
 var tilt=.62 if back else 0.0
 tablet_transform=Transform2D(tilt,grip)
 # Solve the wrist on its10.5 circle with the fingertip2.2 from the glass.
 # Choose the solution outside the tablet edge, so the forearm clears the screen.
 var tap_angle=(tablet_transform*Vector2(0,-3.0)-tapping).angle()
 if not back:
  var held_frame=Transform2D(tilt,holder+Vector2.from_angle(held)*ARM_LENGTH)
  var wrist_target=_edge_wrist(tapping,held_frame*SCREEN_CONTACT,held_frame)
  tap_angle=(wrist_target-tapping).angle()
 var rest_angle=Vector2(1,10).angle() if back else Vector2(-1,10).angle()
 var ready=smoothstep(.27,.34,t)*(1.0-smoothstep(TAP_WITHDRAW_START,TAP_WITHDRAW_END,t))
 var first_press=smoothstep(.35,.39,t)*(1.0-smoothstep(.435,.49,t))
 var second_press=smoothstep(.505,.545,t)*(1.0-smoothstep(.575,.62,t))
 # Both presses have a brief true contact dwell, separated by a visible lift.
 # Blend the lifted angle with the whole arm, so entry/exit remains continuous.
 var hover=TAP_LIFT*(1.0-maxf(first_press,second_press))
 tap_ready=ready;tap_lift=hover*ready
 var lifted_tap_angle=tap_angle+(hover if back else -hover)
 tap=tapping+Vector2.from_angle(lerp_angle(rest_angle,lifted_tap_angle,ready))*ARM_LENGTH
 tap_surface=tablet_transform*SCREEN_CONTACT
 tap_fingertip=tap if back else tap+(tap_surface-tap).normalized()*FINGER_REACH
 tap_visible=ready>.001
 near_hand=tap if back else holder_hand;far_hand=holder_hand if back else tap
 exposed=withdrawn>.001
 contact=ready>.999 and hover<.0000001

static func _edge_wrist(shoulder:Vector2,surface:Vector2,frame:Transform2D)->Vector2:
 var offset=surface-shoulder
 var distance=offset.length()
 if distance<.0001:return shoulder+Vector2.DOWN*ARM_LENGTH
 var axis=offset/distance
 var along=(ARM_LENGTH*ARM_LENGTH-FINGER_REACH*FINGER_REACH+distance*distance)/(2.0*distance)
 var height_squared=ARM_LENGTH*ARM_LENGTH-along*along
 if height_squared<0:return shoulder+axis*ARM_LENGTH
 var middle=shoulder+axis*along
 var side=axis.orthogonal()*sqrt(height_squared)
 var first=middle+side;var second=middle-side
 var inverse=frame.affine_inverse()
 return first if (inverse*first).x>(inverse*second).x else second

func _polygon(a,origin:Vector2,points:PackedVector2Array,tint,edge="",width=.6,transform=Transform2D.IDENTITY):
 var world:PackedVector2Array=Transform2D(0,origin)*transform*points
 preload("res://scripts/cafe_canvas_draw.gd").draw_colored_polygon(a,world,a.col(tint))
 if edge!="":a.art_polyline(world,a.col(edge),width)

func draw_case(a,origin:Vector2):
 if not enabled:return
 var at=origin+(CASE_BACK if back else CASE_FRONT)
 _polygon(a,at,CASE_EDGE,"a78968","806f56",.65)
 _polygon(a,at,CASE_PANEL,"bea17d")
 a.line(at+Vector2(-2.6,-3.9),at+Vector2(2.7,-3.5),"765f4b",.8)
 a.line(at+Vector2(-2.5,3.7),at+Vector2(1.9,4.2),"d4bb97",.55)
 if not ordering:
  _polygon(a,at,CASE_STOWED_EDGE,"8caa9e","657f73",.55)
  a.line(at+Vector2(-1.5,-5.9),at+Vector2(1.7,-5.6),"d8e0c6",.45)

func draw_strap(a,origin:Vector2):
 if not enabled:return
 var top=Vector2(4.6,-28.1) if back else Vector2(5.8,-26.1)
 var rim=(CASE_BACK if back else CASE_FRONT)+Vector2(2.5,1.3)
 a.line(origin+top,origin+rim,"846e54",2.4)
 a.line(origin+top+Vector2(-.15,-.3),origin+rim+Vector2(-.15,-.3),"c9af87",1.0)
 var buckle=top.lerp(rim,.66)
 a.line(origin+buckle+Vector2(-1.0,-.8),origin+buckle+Vector2(1.0,.8),"e0caa1",1.5)

func draw_tablet(a,origin:Vector2):
 if not ordering:return
 _polygon(a,origin,TABLET_EDGE,"7d9b8e","5f7a6e",.6,tablet_transform)
 if back:
  a.line(origin+tablet_transform*Vector2(-1.9,-5.2),origin+tablet_transform*Vector2(1.2,-4.8),"aec2ae",.7)
 else:
  _polygon(a,origin,SCREEN,"d0dfc7","bed0b5",.45,tablet_transform)
  a.line(origin+tablet_transform*Vector2(-2.1,-6.4),origin+tablet_transform*Vector2(2.0,-5.9),"8ba68d",.65)
  a.line(origin+tablet_transform*Vector2(-2.1,-4.8),origin+tablet_transform*Vector2(1.1,-4.4),"b0bf9f",.55)
  a.line(origin+tablet_transform*Vector2(-2.1,-3.3),origin+tablet_transform*Vector2(.4,-3.0),"b0bf9f",.55)

func draw_hands(a,origin:Vector2,fur,shadow):
 if not exposed:return
 # Repaint only the fingertips over the device: no detached grip or stylus.
 a.ellipse(origin+grip,Vector2(1.65,1.5),shadow if back else fur)
 if back:
  a.ellipse(origin+tap,Vector2(1.45,1.4),fur)
 elif tap_visible:
  var finger_color=shadow
  a.ellipse(origin+tap,Vector2(1.45,1.4),finger_color)
  a.line(origin+tap,origin+tap_fingertip,finger_color,.85)
  a.ellipse(origin+tap_fingertip,Vector2(.6,.6),finger_color)
