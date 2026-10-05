extends RefCounted
## A compact forearm ends in a wrap grip, separate from the head silhouette.
## The hand follows the forearm; the utensil is held across the palm rather
## than forcing the wrist to point exactly along the steep cooking shaft.
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

static func stroke(elapsed_seconds:float,high_pan=false,remaining_seconds=-1.0)->Dictionary:
 # The real work clock supplies a deliberate gather/pause, scrape, scoop,
 # short lift and fold, then a soft settle. This never advances service.
 var phase=fposmod(maxf(elapsed_seconds,0.0),FRY_SECONDS)/FRY_SECONDS
 var segment=0
 while segment<TIMES.size()-2 and phase>=TIMES[segment+1]:segment+=1
 var weight=smoothstep(TIMES[segment],TIMES[segment+1],phase)
 var rises=BACK_RISE if high_pan else FRONT_RISE
 var result={"phase":phase,"tip_y":lerpf(TIP_Y[segment],TIP_Y[segment+1],weight),"rise":lerpf(rises[segment],rises[segment+1],weight),"reach":BACK_REACH if high_pan else lerpf(FRONT_REACH[segment],FRONT_REACH[segment+1],weight),"blade_width":lerpf(BLADE_WIDTH[segment],BLADE_WIDTH[segment+1],weight),"load":lerpf(LOAD[segment],LOAD[segment+1],weight),"body":WEIGHT[segment].lerp(WEIGHT[segment+1],weight),"stage":STAGES[segment],"on_food_plane":segment in [0,1,2,5]}
 var finish=0.0 if remaining_seconds<0 else 1.0-smoothstep(0.0,.45,remaining_seconds)
 result["finish"]=finish
 result.rise=lerpf(result.rise,BACK_RISE[0] if high_pan else FRONT_RISE[0],finish)
 result.reach=lerpf(result.reach,BACK_REACH if high_pan else FRONT_REACH[0],finish)
 result.tip_y=lerpf(result.tip_y,TIP_Y[0],finish)
 result.blade_width=lerpf(result.blade_width,BLADE_WIDTH[0],finish)
 result.body=(result.body as Vector2).lerp(Vector2.ZERO,finish)
 return result

static func body_weight(elapsed_seconds:float,remaining_seconds=-1.0)->Vector2:
 return stroke(elapsed_seconds,false,remaining_seconds).body

static func apply_body_weight(legs:Dictionary,elapsed_seconds:float,leg_length=9.5,remaining_seconds=-1.0)->Dictionary:
 var weight=body_weight(elapsed_seconds,remaining_seconds)
 legs.body+=weight
 for slot in ["near","far"]:
  var foot:Vector2=legs[slot+"_foot"]-weight
  var hip:Vector2=legs[slot+"_hip"]
  hip.y=foot.y-sqrt(maxf(0.0,leg_length*leg_length-pow(foot.x-hip.x,2)))
  legs[slot+"_foot"]=foot;legs[slot+"_hip"]=hip
 return legs

static func pose(shoulder:Vector2,pan:Vector2,elapsed_seconds:float,remaining_seconds=-1.0)->Dictionary:
 var high_pan=pan.y<shoulder.y-6.0
 var motion=stroke(elapsed_seconds,high_pan,remaining_seconds)
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
 var pan:Vector2=origin+p.pan
 var parts=food_parts(p)
 _food_foundation(artist,pan)
 # Surface food covers an inserted blade. Only a raised blade crosses in
 # front of the resting pile. The carried portion always sits ON the blade.
 var under=blade_under_food(p)
 if not under:_draw_parts(artist,pan,parts,0,3)
 artist.line(origin+p.butt,origin+p.neck,"9a7c48",1.55)
 artist.line(origin+p.butt,hand+axis*1.2,"866b3e",2.0)
 var blade_width=float(p.motion.blade_width)
 artist.rounded_poly([tip-axis*2.1-across*.7,tip-axis*2.1+across*.7,tip+axis*.7+across*blade_width,tip+axis*.7-across*blade_width],.35,"c4ad79")
 artist.line(tip+axis*.65-across*blade_width*.85,tip+axis*.65+across*blade_width*.85,"ead6a0",.65)
 if under:_draw_parts(artist,pan,parts,0,3)
 _draw_parts(artist,pan,parts,3,6)
 artist._round_limb(hand-across*1.05-axis*.55,hand+across*.9-axis*.55,fur,1.25)
 artist._round_limb(hand-across*.95+axis*.4,hand+across*.65+axis*.4,fur,1.05)
 artist.ellipse(origin+p.thumb,Vector2(1.05,1.15),fur)
