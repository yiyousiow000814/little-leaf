extends RefCounted
## Original-art, one-piece limb geometry. Props own their transfer paths, so a
## station farther away changes the prop handoff, never a character's anatomy.
const ARM_LENGTH := 10.5
const LEG_LENGTH := 9.5
const CARRY := Vector2(16.0, -24.0)
const SHOULDER := Vector2(8.0, -24.0)
const TRANSFER_BEAT := 0.65

static func limb(target:Vector2, pivot:Vector2, length:float) -> Dictionary:
	var direction := (target-pivot).normalized()
	if direction.length_squared()<.01:direction=Vector2.DOWN
	var tip := pivot+direction*length
	return {"pivot":pivot,"tip":tip,"length":length,"target_error":tip.distance_to(target)}

static func gesture(action:String,t:float,swing:float,seated:bool,payload:String,carry:Vector2=CARRY) -> Dictionary:
	var hand := Vector2(9.0+swing, -15.0)
	var other := Vector2(-9.0-swing,-15.0)
	var nod := 0.0
	if seated:hand=Vector2(15,-22);other=Vector2(-10,-18)
	if payload!="none":hand=carry;other=Vector2(-10,-19)
	if action in ["serving","placing_plate","dropping_dishes","collecting","collecting_plate","collecting_drink","plating","disposing_trash","collecting_trash","picking_up_trash","picking_litter"]:
		var beat := smoothstep(.10,.65,t)*(1.0-smoothstep(.65,1.0,t))
		hand=Vector2(11,-18).lerp(Vector2(19,-26),beat)
		nod=beat*.7
	elif action in ["cooking","preparing_food","preparing_drink","washing"]:
		hand=Vector2(18+sin(t*TAU*2)*1.2,-24+cos(t*TAU*2)*.65)
		other=Vector2(-11,-21)
		nod=sin(t*TAU*2)*.25
	elif action=="wiping":
		hand=carry if payload!="none" else Vector2(10,-18)
		other=Vector2(-14+sin(t*TAU*2)*2,-23)
	elif action in ["sweeping","mopping"]:
		other=Vector2(-14+sin(t*TAU*2)*1.4,-24)
		hand=carry if payload!="none" else Vector2(12,-23)
		nod=sin(t*TAU*2)*.45
	elif action=="standby":
		hand=Vector2(10+sin(t*TAU)*.6,-21);other=Vector2(-10,-20)
		nod=sin(t*TAU)*.12
	elif action=="taking_order":hand=Vector2(13,-23);other=Vector2(-10,-22)
	elif seated and action in ["eating","drinking"]:
		var beat=sin(t*TAU*2)
		hand=Vector2(13,-22)+Vector2(0,beat*.6);other=Vector2(-10,-20)
		nod=beat*.4
	elif action=="blocked":
		other=Vector2(-8,-22)
		if payload=="none":hand=Vector2(10,-22)
	return {"right":limb(hand,SHOULDER,ARM_LENGTH),"left":limb(other,Vector2(-8,-24),ARM_LENGTH),"nod":nod}

static func prop_offset(_action:String,_t:float,_reach:Vector2,carry:Vector2,_payload:String) -> Vector2:
	# A small symbolic gesture is enough. The authoritative ownership beat
	# switches hand OFF and surface ON in one frame; no flying prop or reach.
	return carry
