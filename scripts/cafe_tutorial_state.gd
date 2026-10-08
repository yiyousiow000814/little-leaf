extends RefCounted
## Optional, additive save metadata. Missing/unknown metadata never enrolls an
## existing cafe, invalidates a good save, or changes its economy/runtime.
const FORMAT=1
const OPEN=0
const STAFF=1
const STAFF_DONE=2
const DECORATE=3
const DONE=4
const ORDER=5
const PAYMENT=6
const COMPLETE=7
static func begin(served:int)->Dictionary:
 return {"format":FORMAT,"status":"active","step":OPEN,"baseline_served":served}
static func read(value)->Dictionary:
 if not value is Dictionary or value.get("format")!=FORMAT:return {}
 if value.get("status") not in ["active","skipped","completed"]:return {}
 for key in ["step","baseline_served"]:
  var number=value.get(key)
  if not (number is int or number is float) or not is_finite(float(number)) or float(number)!=floor(float(number)):return {}
 if int(value.step)<OPEN or int(value.step)>COMPLETE or int(value.baseline_served)<0:return {}
 return {"format":FORMAT,"status":str(value.status),"step":int(value.step),"baseline_served":int(value.baseline_served)}
