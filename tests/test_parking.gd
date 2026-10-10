extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Parking=preload("res://scripts/cafe_parking.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
var failures=[]
var checks=0
var phases={}
func _initialize():call_deferred("run")
func check(value:bool,label:String):
 checks+=1
 if not value:failures.append(label);push_error(label)
func encoded(value):return Codec.new().encode(value)
func same(a,b)->bool:
 if (a is int or a is float) and (b is int or b is float):return absf(float(a)-float(b))<1e-8
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not same(a[key],b[key]):return false
  return true
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for i in range(a.size()):
   if not same(a[i],b[i]):return false
  return true
 return a==b
func owned():
 var m=Model.new();m.coins=10000;m.begin_decoration_session();check(m.buy_parking(),"buy fixed parking");m.finish_decoration_session();return m
func step(m,seconds:float):
 for frame in range(ceili(seconds/.1)):
  m._arrival_elapsed=0.0;m._tick_step(.1)
  for visit in m.parking_visits:phases[visit.phase]=true
func parking_step(m,seconds:float):
 for frame in range(ceili(seconds/.1)):
  Parking.advance(m,.1);m.OutsideQueue.advance(m,.1)
  for visit in m.parking_visits:phases[visit.phase]=true
func snapshot(m):
 var state={}
 for key in ["parking_visits","parking_owned","parking_paid_cost","customers","outside_queue","coins","items","dining_sets","built_walls","wall_attachments","shell_products","shell_segment_products","floor_finishes","floor_style","owned_parcels","expanded","width","depth","cooks","waiters","cleaners","cashiers","included_bin_pending","included_checkout_pending","operating_open","duty_targets","duty_counts","served","total_earned","total_cleaned","payroll_elapsed","payroll_accrued","wages_due","total_wages_paid","_next_customer_id","_next_item_id","_next_wall_id","_next_attachment_id","next_checkout_ticket","_arrival_elapsed","_walking_customer_id","service_snapshot"]:state[key]=m.get(key)
 return encoded(state)
func roundtrip(m,label:String):
 var path="user://parking-"+label+".json"
 check(m.save(path),label+" save: "+m.last_error)
 if not FileAccess.file_exists(path):return null
 var hash=FileAccess.get_sha256(path);var copy=Model.new();check(copy.load_save(path),label+" load: "+copy.last_error)
 check(same(snapshot(m),snapshot(copy)),label+" exact snapshot preserved")
 check(FileAccess.get_sha256(path)==hash,label+" source bytes unchanged")
 return copy
func invalid(m,raw:Dictionary,label:String):
 var path="user://parking-invalid-"+label+".json";var f=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(raw));f.close()
 var before=snapshot(m);var hash=FileAccess.get_sha256(path)
 check(not m.load_save(path),label+" rejected")
 check(same(before,snapshot(m)),label+" rejected atomically")
 check(hash==FileAccess.get_sha256(path),label+" rejected bytes unchanged")
func run():
 check(OS.get_environment("XDG_DATA_HOME")!="" and OS.get_user_data_dir().begins_with(OS.get_environment("XDG_DATA_HOME")),"disposable generated save profile")
 var m=Model.new();var wallet=m.coins
 check(not m.parking_owned and m.parking_visits.is_empty(),"new parking unowned/empty")
 check(not m.buy_parking() and m.coins==wallet,"normal-play insufficient funds atomic")
 m.begin_decoration_session();check(not m.buy_parking() and m.coins==wallet,"insufficient funds atomic")
 m.coins=10000;check(m.buy_parking() and m.coins==8000 and m.parking_paid_cost==2000,"one-time configured purchase")
 check(not m.buy_parking() and m.coins==8000,"repeat purchase cannot charge")
 roundtrip(m,"session-owned")
 check(m.parking_refund()==2000,"saving retains same-session receipt")
 check(m.sell_parking() and m.coins==10000,"same-session sale full refund")
 check(not m.sell_parking() and m.coins==10000,"repeat sale cannot mint money")
 check(m.buy_parking(),"repurchase after cancellation");m.finish_decoration_session();m.begin_decoration_session()
 check(m.parking_refund()==1000 and m.sell_parking() and m.coins==9000,"Done ends full refund")
 check(m.buy_parking(),"buy before load");var loaded=roundtrip(m,"owned")
 loaded.begin_decoration_session();check(loaded.parking_refund()==1000,"load ends full refund entitlement")
 # Old saves migrate without retroactive ownership, charge, or rewrite.
 var legacy=Model.new();check(legacy.save("user://parking-legacy-source.json"),"legacy source")
 var raw=JSON.parse_string(FileAccess.get_file_as_string("user://parking-legacy-source.json"));raw.erase("parking")
 var f=FileAccess.open("user://parking-legacy.json",FileAccess.WRITE);f.store_string(JSON.stringify(raw));f.close()
 var old_hash=FileAccess.get_sha256("user://parking-legacy.json")
 check(m.load_save("user://parking-legacy.json") and not m.parking_owned and m.parking_visits.is_empty() and m.coins==Model.INITIAL_COINS,"missing parking migrates empty, wallet preserved")
 check(old_hash==FileAccess.get_sha256("user://parking-legacy.json"),"migration never rewrites source")
 # Actual member custody, full-room FIFO, timeout and interruption.
 m=owned();check(Parking.reserve(m,1),"reserve stable single-member compatibility fixture")
 var member=m.parking_visits[0].members[0];var id=int(member.id)
 roundtrip(m,"car-arriving")
 for i in range(400):
  parking_step(m,.1)
  if m.parking_visits[0].phase=="parked":break
 check(member.phase=="walking_in","member appears after car physically parks")
 roundtrip(m,"walking-in")
 parking_step(m,15);check(m.customers.size()==1 and m.customers[0].id==id and m.customers[0].parking_visit,"admission transfers exact original member")
 roundtrip(m,"dining-arrival")
 m=owned();m._spawn_walkers(2);Parking.reserve(m,1);parking_step(m,55)
 member=m.parking_visits[0].members[0]
 check(member.phase=="queued","full restaurant retains original party member in queue")
 roundtrip(m,"queued")
 var q=m.outside_queue.filter(func(v):return int(v.id)==int(member.id))[0]
 q.wait_seconds=m.OutsideQueue.WAIT_SECONDS-.05
 var at=Vector2(q.x,q.z);m.OutsideQueue.advance(m,.1)
 check(member.phase=="walking_return" and member.walk_position==at and not m.outside_queue.has(q),"timeout transfers exact position/member to own car")
 roundtrip(m,"timeout")
 parking_step(m,75);check(m.parking_visits.is_empty() and m.served==0,"timed-out party returns and exits without reward")
 m=owned();Parking.reserve(m,4);parking_step(m,29);m.set_operating_open(false)
 roundtrip(m,"closed-party")
 parking_step(m,75);check(m.parking_visits.is_empty() and m.outside_queue.is_empty(),"interrupted original members all return before bay release")
 print("PARKING_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"phases":phases.keys(),"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
