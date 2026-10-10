extends RefCounted
## Presentation only. Four bites share the existing normalized meal clock.
## No timers, saved fields, service transitions, or ownership changes live here.
const BITES=4
const PICKUP=.26
const MOUTH=.54
const RETURN=.78
const ARM_LENGTH=10.5

static func beat(progress:float)->Dictionary:
 var clock=clampf(progress,0.0,1.0)*BITES
 var index=mini(int(clock),BITES-1)
 var phase=clock-float(index)
 var picked=mini(index+(1 if phase>=PICKUP else 0),BITES)
 return {"index":index,"phase":phase,"picked":picked,"remaining":1.0-float(picked)/BITES,"loaded":phase>=PICKUP and phase<MOUTH}

static func remaining(progress:float)->float:return float(beat(progress).remaining)

const TOOL_LENGTH=8.0
const FOOD_CONTACTS=[Vector2(3.8,1.8),Vector2(-.8,-4),Vector2(3,-2),Vector2(-4,-1.6)]

static func grip(shoulder:Vector2,target:Vector2)->Dictionary:
 var delta=target-shoulder
 var distance=clampf(delta.length(),absf(ARM_LENGTH-TOOL_LENGTH)+.00001,ARM_LENGTH+TOOL_LENGTH-.00001)
 var direction=delta.normalized() if delta.length_squared()>.0001 else Vector2.RIGHT
 var tip=shoulder+direction*distance
 var along=(ARM_LENGTH*ARM_LENGTH-TOOL_LENGTH*TOOL_LENGTH+distance*distance)/(2.0*distance)
 var across=sqrt(maxf(0.0,ARM_LENGTH*ARM_LENGTH-along*along))
 var first=shoulder+direction*along+direction.orthogonal()*across
 var second=shoulder+direction*along-direction.orthogonal()*across
 # The exposed grip remains beside the cheek, never on the hidden torso side.
 var hand=first if first.x>=second.x else second
 return {"hand":hand,"axis":(tip-hand).normalized(),"tip":tip,"target_error":tip.distance_to(target)}

static func reach_ease(value:float)->float:
 # A short acceleration/coast/deceleration profile avoids a rushed reach when
 # a close plate requires a larger wrist/arm arc; contact timing stays fixed.
 var u=clampf(value,0.0,1.0);var edge=.18;var speed=1.0/(1.0-edge)
 if u<edge:return .5*speed*u*u/edge
 if u>1.0-edge:return 1.0-.5*speed*(1.0-u)*(1.0-u)/edge
 return speed*(u-edge*.5)

static func pose(near:Vector2,far:Vector2,plate:Vector2,progress:float,back:bool,rest_hand:Vector2=Vector2.INF,plate_mirror=1.0)->Dictionary:
 var timing=beat(progress);var phase=float(timing.phase)
 var use_near=back;var shoulder=near if use_near else far
 var rest=rest_hand if rest_hand!=Vector2.INF else shoulder+Vector2(1 if use_near else -1,10).normalized()*ARM_LENGTH
 var presence=smoothstep(0.0,.035,progress)*(1.0-smoothstep(.97,1.0,progress))
 if not use_near:rest=shoulder+Vector2.from_angle((rest-shoulder).angle()-.65*presence)*ARM_LENGTH
 var rest_axis=Vector2.UP
 var plate_contact=plate+FOOD_CONTACTS[int(timing.index)]*Vector2(plate_mirror,1)
 var at_plate=grip(shoulder,plate_contact)
 var mouth=Vector2(10,-32) if back else Vector2(8.5,-32.5)
 var stage="reach";var chew=0.0
 if phase>=MOUTH and phase<RETURN:
  stage="chew";chew=sin((phase-MOUTH)/(RETURN-MOUTH)*TAU*2)*.30;mouth.y+=chew
 var at_mouth=grip(shoulder,mouth)
 var start_hand=rest;var finish_hand:Vector2=at_plate.hand
 var start_axis=rest_axis;var finish_axis:Vector2=at_plate.axis
 var blend=reach_ease(phase/.20)
 if phase>=PICKUP and phase<MOUTH:
  stage="lift";start_hand=at_plate.hand;finish_hand=at_mouth.hand;start_axis=at_plate.axis;finish_axis=at_mouth.axis;blend=smoothstep(PICKUP,MOUTH,phase)
 elif phase>=MOUTH and phase<RETURN:
  start_hand=at_mouth.hand;finish_hand=at_mouth.hand;start_axis=at_mouth.axis;finish_axis=at_mouth.axis;blend=1.0
 elif phase>=RETURN:
  stage="return";start_hand=at_mouth.hand;finish_hand=rest;start_axis=at_mouth.axis;finish_axis=rest_axis;blend=smoothstep(RETURN,1.0,phase)
 # The arm and spoon retain their exact short lengths throughout the cycle.
 # The wrist rotates the spoon; no telescoping shaft bridges a remote plate.
 var hand=shoulder+Vector2.from_angle(lerp_angle((start_hand-shoulder).angle(),(finish_hand-shoulder).angle(),blend))*ARM_LENGTH
 var axis=Vector2.from_angle(lerp_angle(start_axis.angle(),finish_axis.angle(),blend))
 var tip=hand+axis*TOOL_LENGTH
 return {"use_near":use_near,"shoulder":shoulder,"hand":hand,"tip":tip,"plate_contact":plate_contact,"mouth":mouth,"stage":stage,"presence":presence,"loaded":bool(timing.loaded),"bite":int(timing.index),"head_offset":Vector2(0,chew),"phase":phase,"back":back,"rest_hand":rest,"over_table":back or hand.y<=plate.y-1.0,"tool_length":TOOL_LENGTH,"plate_reach_error":at_plate.target_error}

static func draw(artist,origin:Vector2,p:Dictionary,fur,shadow):
 var hand:Vector2=origin+p.hand
 var tip:Vector2=origin+p.tip
 var axis=(tip-hand).normalized()
 # A small, warm wooden spoon is quiet against the existing ceramic palette.
 # Keep the actual grip attached to the same short arm throughout the cycle.
 if float(p.presence)>.01:
  var handle=Color("a68c5d");handle.a=float(p.presence)
  artist.line(hand-axis*1.4,tip-axis*1.1,handle,1.15)
  var bowl=Color("d3bb85");bowl.a=float(p.presence)
  artist.ellipse(tip,Vector2(1.7,.85),bowl)
  if p.loaded:artist.ellipse(tip+Vector2(0,-.6),Vector2(1.5,.9),["dca15e","8aa268","d4a161","fff0cd"][int(p.bite)])
 var hand_color=Color(fur if p.use_near else shadow)
 if not p.use_near:hand_color.a*=float(p.presence)
 artist.ellipse(hand,Vector2(2.05,2.05),hand_color)
