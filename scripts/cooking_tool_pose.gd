extends RefCounted
## Small cooking gestures keep the existing compact arm and planted feet.
## Only presentation uses this work clock; the covered pot hides ingredients.
const BACK_REACH=10.5
const UPPER_ARM=5.5
const FOREARM=6.5
const FRONT_REACH=[8.5,8.5,12.0,9.0,10.5,9.0,8.5]
const FRY_SECONDS=2.6
const TIMES=[0.0,.15,.37,.49,.63,.82,1.0]
const TIP_Y=[.45,.45,-.35,.25,-4.8,.25,.45]
const FRONT_RISE=[.38,.38,.25,.42,.18,.28,.38]
const BACK_RISE=[.35,.35,.25,.38,-.17,.28,.35]
const BLADE_WIDTH=[1.0,1.0,.85,1.65,2.1,1.25,1.0]
const LOAD=[0.0,0.0,0.0,.75,1.0,0.0,0.0]
const WEIGHT=[Vector2.ZERO,Vector2.ZERO,Vector2(.65,.20),Vector2(.85,.35),Vector2(.30,0),Vector2(.55,.15),Vector2.ZERO]
const STAGES=["gather","push","scoop","lift","fold","settle"]
# Six persistent ingredients. The right-hand portion is actually moved by
# the working edge; there is no extra garnish fading into existence.
const FOOD_AT=[Vector2(-2.4,-.1),Vector2(-1.5,.55),Vector2(-.5,-.65),Vector2(.5,-.65),Vector2(1.5,.55),Vector2(2.4,-.1)]
const FOOD_SIZE=[Vector2(1.7,.85),Vector2(1.1,.60),Vector2(1.25,.70),Vector2(1.25,.70),Vector2(1.1,.60),Vector2(1.7,.85)]
const FOOD_COLOR=["d9a962","829760","d2a05e","d2a05e","829760","d9a962"]
const FOOD_ANGLE=[-.12,.20,.08,-.08,-.20,.12]
const PUSH_AHEAD=[.05,.45,.80]
const PUSH_SIDE=[-.35,.40,.10]
const CARRY_AT=[Vector2(-.65,-.35),Vector2(.45,-.75),Vector2(.10,.15)]

# Presentation-only gentle cycle. The real job clock remains authoritative.
static func stroke(elapsed_seconds:float,high_pan=false,remaining_seconds=-1.0,strength=1.0)->Dictionary:
 var phase=fposmod(maxf(elapsed_seconds,0.0),FRY_SECONDS)/FRY_SECONDS
 var envelope=smoothstep(0.0,.4,maxf(elapsed_seconds,0.0))*clampf(strength,0.0,1.0)
 if remaining_seconds>=0:envelope*=smoothstep(0.0,.45,remaining_seconds)
 var wave=sin(phase*TAU)*envelope
 return {"phase":phase,"tip_y":.45+wave*.28,"rise":(.35 if high_pan else .38)+wave*.018,"reach":(BACK_REACH if high_pan else FRONT_REACH[0])+wave*.20,"blade_width":1.0,"load":0.0,"body":Vector2(wave*.16,wave*wave*.10),"stage":"settle","on_food_plane":true,"finish":1.0-envelope}

static func vessel(elapsed_seconds:float,remaining_seconds=-1.0,strength=1.0)->Dictionary:
 var motion=stroke(elapsed_seconds,false,remaining_seconds,strength)
 var envelope=1.0-float(motion.finish)
 var wave=sin(float(motion.phase)*TAU)
 # One brief, soft lid hop every three cycles; never a flying ingredient.
 var hop_phase=fposmod(maxf(elapsed_seconds,0.0),FRY_SECONDS*3.0)/(FRY_SECONDS*3.0)
 var hop=pow(sin(clampf((hop_phase-.72)/.10,0.0,1.0)*PI),2)
 return {"pot":Vector2(wave*.22,-wave*wave*.35)*envelope,"lid":Vector2(-wave*.16,wave*wave*.18-hop*.85)*envelope}

static func body_weight(elapsed_seconds:float,remaining_seconds=-1.0,strength=1.0)->Vector2:
 return stroke(elapsed_seconds,false,remaining_seconds,strength).body

static func apply_body_weight(legs:Dictionary,elapsed_seconds:float,leg_length=9.5,remaining_seconds=-1.0,strength=1.0)->Dictionary:
 var weight=body_weight(elapsed_seconds,remaining_seconds,strength)
 legs.body+=weight
 for slot in ["near","far"]:
  var foot:Vector2=legs[slot+"_foot"]-weight
  var hip:Vector2=legs[slot+"_hip"]
  hip.y=foot.y-sqrt(maxf(0.0,leg_length*leg_length-pow(foot.x-hip.x,2)))
  legs[slot+"_foot"]=foot;legs[slot+"_hip"]=hip
 return legs

static func pose(shoulder:Vector2,pan:Vector2,elapsed_seconds:float,remaining_seconds=-1.0,strength=1.0)->Dictionary:
 var high_pan=pan.y<shoulder.y-6.0
 var motion=stroke(elapsed_seconds,high_pan,remaining_seconds,strength)
 var neutral_pan:Vector2=pan+motion.body
 var aim=(neutral_pan-shoulder).normalized()
 var facing=signf(aim.x)
 var neutral_rise=.35 if high_pan else .38
 var neutral_reach=BACK_REACH if high_pan else FRONT_REACH[0]
 var neutral_hand=shoulder+Vector2(sqrt(1.0-neutral_rise*neutral_rise)*facing,neutral_rise)*neutral_reach
 # The physical-looking handle no longer grows and shrinks with the tip.
 # A rigid projected spatula pivots from the attached hand; the working edge
 # scrapes the food plane, lifts a small fold, and returns to the same pan.
 var tool_length=neutral_hand.distance_to(neutral_pan+Vector2(0,.45))
 var rise=float(motion.rise)
 var arm_axis=Vector2(sqrt(maxf(0.0,1.0-rise*rise))*facing,rise)
 var reach=float(motion.reach)
 var hand=shoulder+arm_axis*reach
 # A compact bent arm extends for the scrape rather than stretching a rigid
 # rod-like limb. Both anatomical segments keep fixed lengths throughout.
 var along=(UPPER_ARM*UPPER_ARM-FOREARM*FOREARM+reach*reach)/(2.0*reach)
 var bend=sqrt(maxf(0.0,UPPER_ARM*UPPER_ARM-along*along))
 var below=Vector2(-arm_axis.y*facing,absf(arm_axis.x))
 var elbow=shoulder+arm_axis*along+below*bend
 arm_axis=(hand-elbow).normalized()
 var dy=pan.y+float(motion.tip_y)-hand.y
 var contact=hand+Vector2(sqrt(maxf(0.0,tool_length*tool_length-dy*dy))*facing,dy)
 var axis=(contact-hand).normalized()
 var across=Vector2(-axis.y,axis.x)
 var wrist=hand-arm_axis*2.0
 return {"shoulder":shoulder,"elbow":elbow,"hand":hand,"wrist":wrist,"arm_axis":arm_axis,"contact":contact,"pan":pan,"axis":axis,"across":across,"butt":hand-axis*3.2,"neck":contact-axis*2.1,"thumb":hand+axis*.55-across*.95,"motion":motion,"tool_length":tool_length,"neutral_pan":neutral_pan,"high_pan":high_pan}

static func blade_under_food(p:Dictionary)->bool:
 return float(p.motion.tip_y)>=-1.0

static func _phase_pose(p:Dictionary,phase:float)->Dictionary:
 var seconds=phase*FRY_SECONDS
 return pose(p.shoulder,p.neutral_pan-body_weight(seconds),seconds)

static func _push_food(index:int,tip:Vector2)->Vector2:
 var base:Vector2=FOOD_AT[index+3]
 var x=maxf(base.x,tip.x+PUSH_AHEAD[index])
 var reached=smoothstep(0.0,.8,x-base.x)
 return Vector2(x,lerpf(base.y,tip.y+PUSH_SIDE[index],reached))

static func _carried_food(index:int,p:Dictionary)->Vector2:
 return p.contact-p.pan-p.axis*.4+CARRY_AT[index]

static func food_parts(p:Dictionary)->Array:
 var phase=float(p.motion.phase)
 var parts=[]
 var push_end=_phase_pose(p,.37)
 var peak=_phase_pose(p,.63)
 for id in range(6):
  var at:Vector2=FOOD_AT[id]
  var angle=float(FOOD_ANGLE[id])
  var carried=false
  if id>=3:
   var index=id-3
   if phase>.15 and phase<=.37:
    # Nothing moves until the blade reaches that ingredient's support point.
    at=_push_food(index,p.contact-p.pan)
   elif phase>.37 and phase<=.49:
    var start_offset=_push_food(index,push_end.contact-push_end.pan)-(push_end.contact-push_end.pan)
    var carry_offset=-p.axis*.4+CARRY_AT[index]
    at=p.contact-p.pan+start_offset.lerp(carry_offset,smoothstep(.37,.49,phase))
    carried=true
   elif phase>.49 and phase<=.63:
    at=_carried_food(index,p);carried=true
   elif phase>.63 and phase<.82:
    # Release the same pieces. Their fall accelerates into the pan while the
    # blade withdraws underneath, rather than staying glued above the food.
    var t=(phase-.63)/(.82-.63)
    var from=_carried_food(index,peak)
    at=Vector2(lerpf(from.x,at.x,smoothstep(0.0,1.0,t)),lerpf(from.y,at.y,t*t))
    angle+=sin(t*PI)*(.32+index*.06)
  at=FOOD_AT[id] if float(p.motion.finish)>=1.0 else at.lerp(FOOD_AT[id],float(p.motion.finish))
  angle=lerpf(angle,FOOD_ANGLE[id],float(p.motion.finish))
  parts.append({"id":id,"at":at,"angle":angle,"carried":carried and float(p.motion.finish)<1.0})
 return parts

static func _food_piece(artist:Node2D,at:Vector2,id:int,angle:float,scale=1.0,mirror=1.0):
 var size:Vector2=FOOD_SIZE[id]*scale
 var corners=[]
 for q in [Vector2(-1,-.65),Vector2(.6,-1),Vector2(1,.2),Vector2(.55,.85),Vector2(-.8,.7)]:
  corners.append(at+(q*size).rotated(angle)*Vector2(mirror,1))
 artist.ellipse(at+Vector2(0,.3)*scale,size*Vector2(.92,.60),Color(.44,.31,.16,.26))
 artist.rounded_poly(corners,.30*scale,FOOD_COLOR[id])
 artist.line(at+Vector2(-.45*mirror,-.30)*scale,at+Vector2(.30*mirror,-.38)*scale,Color(FOOD_COLOR[id]).lightened(.14),.40*scale)

static func _food_foundation(artist:Node2D,pan:Vector2,scale=1.0):
 # A faint pan/oil shadow leaves clear empty space when a portion is lifted.
 artist.ellipse(pan+Vector2(0,.55)*scale,Vector2(4.8,1.25)*scale,Color(.48,.35,.18,.14))

static func draw_rest_food(artist:Node2D,pan:Vector2,remaining:float,mirror=1.0):
 _food_foundation(artist,pan,remaining)
 for id in range(6):_food_piece(artist,pan+FOOD_AT[id]*Vector2(mirror,1)*remaining,id,FOOD_ANGLE[id],remaining,mirror)

static func _draw_parts(artist:Node2D,pan:Vector2,parts:Array,first:int,last:int):
 for i in range(first,last):
  var part=parts[i]
  _food_piece(artist,pan+part.at,part.id,part.angle)

static func draw(artist:Node2D,origin:Vector2,p:Dictionary,fur,shadow):
 var hand:Vector2=origin+p.hand;var tip:Vector2=origin+p.contact
 var arm:Vector2=p.arm_axis;var side=Vector2(-arm.y,arm.x)
 var axis:Vector2=p.axis;var across:Vector2=p.across
 artist.art_polyline(PackedVector2Array([origin+p.shoulder,origin+p.elbow,origin+p.wrist]),artist.col(fur),3.7)
 artist.ellipse(origin+p.shoulder,Vector2.ONE*1.85,fur)
 artist.ellipse(origin+p.elbow,Vector2.ONE*1.85,fur)
 artist.rounded_poly([hand-arm*2.3-side*1.6,hand+arm*1.9-side*1.6,hand+arm*2.15+side*.8,hand+arm*.6+side*1.7,hand-arm*2.0+side*1.5],1.1,fur)
 artist.line(hand-arm*1.1+side*1.6,hand+arm*.5+side*1.7,shadow,.6)
 # A relaxed grip beside the covered pot; no utensil or food crosses its lid.
 artist._round_limb(hand-across*1.05-axis*.55,hand+across*.9-axis*.55,fur,1.25)
 artist._round_limb(hand-across*.95+axis*.4,hand+across*.65+axis*.4,fur,1.05)
 artist.ellipse(origin+p.thumb,Vector2(1.05,1.15),fur)

const WORK_INSET=.32
static func grip_pose(near_shoulder:Vector2,far_shoulder:Vector2,target:Vector2,elapsed_seconds:float,remaining_seconds=-1.0,strength=1.0)->Dictionary:
 # Choose the anatomically nearer arm instead of stretching across the torso.
 var use_near=near_shoulder.distance_squared_to(target)<=far_shoulder.distance_squared_to(target)
 var shoulder=near_shoulder if use_near else far_shoulder
 var offset=target-shoulder
 var reach=clampf(offset.length(),absf(UPPER_ARM-FOREARM)+.001,UPPER_ARM+FOREARM-.001)
 var axis=offset.normalized() if offset.length_squared()>.000001 else Vector2.RIGHT
 var hand=shoulder+axis*reach
 var along=(UPPER_ARM*UPPER_ARM-FOREARM*FOREARM+reach*reach)/(2.0*reach)
 var bend=sqrt(maxf(0.0,UPPER_ARM*UPPER_ARM-along*along))
 var side=Vector2(-axis.y,axis.x)
 if side.y<0:side=-side
 var elbow=shoulder+axis*along+side*bend
 var arm_axis=(hand-elbow).normalized()
 var across=Vector2(-arm_axis.y,arm_axis.x)
 return {"use_near":use_near,"shoulder":shoulder,"elbow":elbow,"hand":hand,"wrist":hand-arm_axis*2.0,"arm_axis":arm_axis,"contact":hand,"pan":target,"axis":arm_axis,"across":across,"thumb":hand+arm_axis*.55-across*.95,"motion":stroke(elapsed_seconds,false,remaining_seconds,strength),"grip_target":target,"grip_error":hand.distance_to(target)}
