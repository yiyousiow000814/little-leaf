extends RefCounted
## A compact forearm ends in a wrap grip, separate from the head silhouette.
## The hand follows the forearm; the utensil is held across the palm rather
## than forcing the wrist to point exactly along the steep cooking shaft.
const ARM_LENGTH=10.5
const SWEEP=Vector2(2.0,.40)
const MAX_ARM_RISE=.12
static func pose(shoulder:Vector2,pan:Vector2,phase:float)->Dictionary:
 var beat=sin(phase*TAU*2)
 var contact=pan+Vector2(beat*SWEEP.x,cos(phase*TAU*2)*SWEEP.y)
 var aim=(pan-shoulder).normalized()
 # Raising the whole straight arm toward the pot put the grip under the
 # chef's cheek. Keep the short forearm at worktop level and stir at the hand.
 var rise=maxf(aim.y,-MAX_ARM_RISE)+beat*.012
 var arm_axis=Vector2(sqrt(maxf(0.0,1.0-rise*rise))*signf(aim.x),rise)
 var hand=shoulder+arm_axis*ARM_LENGTH
 var axis=(contact-hand).normalized()
 var across=Vector2(-axis.y,axis.x)
 var wrist=hand-arm_axis*2.0
 return {"shoulder":shoulder,"hand":hand,"wrist":wrist,"arm_axis":arm_axis,"contact":contact,"pan":pan,"axis":axis,"across":across,"butt":hand-axis*3.2,"neck":contact-axis*1.8,"thumb":hand+axis*.55-across*.95}

static func draw(artist:Node2D,origin:Vector2,p:Dictionary,fur,shadow):
 var hand:Vector2=origin+p.hand;var tip:Vector2=origin+p.contact
 var arm:Vector2=p.arm_axis;var side=Vector2(-arm.y,arm.x)
 var axis:Vector2=p.axis;var across:Vector2=p.across
 # This action owns exactly one forearm. Its narrow wrist joins the palm
 # on the same axis; no second generic capsule can become a pale crescent.
 artist._round_limb(origin+p.shoulder,origin+p.wrist,fur,3.7)
 artist.rounded_poly([hand-arm*2.3-side*1.6,hand+arm*1.9-side*1.6,hand+arm*2.15+side*.8,hand+arm*.6+side*1.7,hand-arm*2.0+side*1.5],1.1,fur)
 artist.line(hand-arm*1.1+side*1.6,hand+arm*.5+side*1.7,shadow,.6)
 # Dark handle is visible both below and above the wrap; the small fingers
 # cover only its middle. The blade stays at the actual food plane.
 artist.line(origin+p.butt,origin+p.neck,"9a7c48",1.55)
 artist.line(origin+p.butt,hand+axis*1.2,"866b3e",2.0)
 artist.rounded_poly([tip-axis*1.8-across*.75,tip-axis*1.8+across*.75,tip+axis*.6+across*1.45,tip+axis*.6-across*1.45],.55,"c4ad79")
 artist.line(tip+axis*.55-across*1.1,tip+axis*.55+across*1.1,"e0ca92",.55)
 # One continuous finger wrap, plus a thumb on the opposite side. Avoid a
 # round palm stamped over the shaft: that made the grip look like a bend.
 artist._round_limb(hand-across*1.05-axis*.55,hand+across*.9-axis*.55,fur,1.25)
 artist._round_limb(hand-across*.95+axis*.4,hand+across*.65+axis*.4,fur,1.05)
 artist.ellipse(origin+p.thumb,Vector2(1.05,1.15),fur)
