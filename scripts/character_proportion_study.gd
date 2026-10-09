extends RefCounted
## Opt-in QA hypotheses only. No saved setting or production default change.
static func values(variant:String,seat_mix=0.0)->Dictionary:
 var torso=2.0 if variant=="A" else (3.0 if variant=="B" else 0.0)
 var leg=1.0 if variant=="A" else (2.0 if variant=="B" else 0.0)
 leg*=1.0-clampf(seat_mix,0.0,1.0)
 return {"variant":variant,"torso":torso,"leg":leg,"head_shift":torso+leg}
static func point(p:Vector2,body:Dictionary)->Vector2:
 if body.is_empty() or float(body.get("head_shift",0.0))==0.0:return p
 # Extend the shirt between hem and shoulders; the intact head only translates.
 var weight=clampf((-p.y-11.5)/12.5,0.0,1.0)
 return p-Vector2(0,float(body.leg)+float(body.torso)*weight)
static func points(source:Array,body:Dictionary)->Array:
 var result=[]
 for p in source:result.append(point(p,body))
 return result
