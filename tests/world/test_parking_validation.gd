extends SceneTree
const M=preload("res://scripts/cafe_model.gd")
const P=preload("res://scripts/cafe_parking.gd")
const C=preload("res://scripts/cafe_runtime_codec.gd")
var checks=0
var failures=[]
func _initialize():
 var m=M.new();m.coins=100000;m.begin_decoration_session();m.buy_parking();m.finish_decoration_session()
 var samples={}
 for i in range(6000):
  m.tick(.1)
  for v in m.parking_visits:
   if not samples.has(v.phase):samples[v.phase]={"raw":C.new().encode({"format":P.FORMAT,"owned":m.parking_owned,"paid_cost":m.parking_paid_cost,"visits":m.parking_visits}),"customers":m.customers.duplicate(true),"queue":m.outside_queue.duplicate(true),"next_id":m._next_customer_id,"open":m.operating_open,"id":v.id}
  if samples.size()==6:break
 checks+=1
 if samples.size()!=6:failures.append("Did not capture all six real parking phases")
 for phase in samples:
  var sample=samples[phase]
  for key in ["id","bay","slot","phase","cancelled","car_position","car_heading","car_route","car_index","walk_origin","walk_position","walk_heading","walk_route","walk_index"]:
   for value in [null,false,true,-1,0,.5,"0","",{},[],INF,NAN]:
    var raw=sample.raw.duplicate(true)
    for v in raw.visits:
     if int(v.id)==int(sample.id):v[key]=value
    var result=P.validate(raw,sample.customers,sample.queue,sample.next_id,sample.open);checks+=1
    if not result.has("ok") or not result.ok is bool or (not result.ok and not result.has("error")):failures.append(phase+" "+key+" "+str(value))
 for phase in samples:
  var sample=samples[phase]
  for key in ["format","owned","paid_cost","visits"]:
   for value in [null,false,true,-1,0,.5,"0","",{},[],INF,NAN]:
    var raw=sample.raw.duplicate(true);raw[key]=value
    var result=P.validate(raw,sample.customers,sample.queue,sample.next_id,sample.open);checks+=1
    if not result.has("ok") or not result.ok is bool or (not result.ok and not result.has("error")):failures.append(phase+" outer-"+key+" "+str(value))
  if phase in ["dining","walking_return","car_departing"]:
   for value in [null,false,true,-1,0,.5,"0","",{},[],INF,NAN]:
    var guests=sample.customers.duplicate(true)
    for guest in guests:
     if int(guest.id)==int(sample.id):guest.parking_visit=value
    var result=P.validate(sample.raw,guests,sample.queue,sample.next_id,sample.open);checks+=1
    if not result.has("ok") or not result.ok is bool or (not result.ok and not result.has("error")):failures.append(phase+" guest-marker "+str(value))
 for phase in samples:
  var sample=samples[phase]
  for key in ["car_route","walk_route"]:
   for value in [null,false,true,-1,0,.5,"0","",{},[],INF,NAN]:
    var raw=sample.raw.duplicate(true)
    for v in raw.visits:
     if int(v.id)==int(sample.id):v[key][0]=value
    var result=P.validate(raw,sample.customers,sample.queue,sample.next_id,sample.open);checks+=1
    if not result.has("ok") or result.ok!=false:failures.append(phase+" route-element-"+key+" "+str(value))
 print("PARKING_VALIDATION_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"phases":samples.keys()}))
 quit(0 if failures.is_empty() else 1)
