extends SceneTree
const Model=preload("res://scripts/core/cafe_model.gd")
const Minimal=preload("res://scripts/minimal_start.gd")
const Motion=preload("res://scripts/gameplay/cafe_furniture_motion.gd")
var checks=0;var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func fresh(x=-.00000665):
 var m=Model.new();Minimal.apply(m);m.coins=100000;m._spawn_customer()
 var g=m.customers[0]
 g.phase="leaving";g.paid=true;g.seated=false;g.admitted=true;g.withdrawn=false;g.dismounting=false;g.exit_completed=false
 g.x=x;g.z=5.5;g.route=[Vector2(-.5,5.5),Vector2(-.85,5.5),Vector2(-.85,12.5)];g.route_index=0;g.checkout_cell=Vector2i(-100,-100)
 g.duration=9.5;g.elapsed=4.3;m.served=1;m.total_earned=250
 check(m.place("plant",11,7),"fixture plant places")
 return m
func state(m):return [m.items.duplicate(true),m.customers.duplicate(true),m.coins,m.served,m.total_earned,m.revision,m._next_item_id]
func public_segment(m,a:Vector2,b:Vector2)->bool:
 if not is_zero_approx(a.x-b.x) and not is_zero_approx(a.y-b.y):return false
 for step in range(1,ceili(a.distance_to(b)*20.0)+1):
  var p=a.lerp(b,float(step)/float(ceili(a.distance_to(b)*20.0)))
  if not m._public_exterior_cell(Vector2i(floori(p.x),floori(p.y))):return false
 return true
func verify_public_routes(m,label:String):
 var snapshot=state(m);var entries=m.boundary_entries()
 check(not entries.is_empty(),label+": real public access remains")
 for parcel in m.expansion_parcels():
  check(not m._public_exterior_cell(Vector2i(parcel.x,parcel.z)),label+": sale parcel is never public "+str(parcel.id))
 for entry in entries:
  check(m.is_floor_owned(entry.cell) and m._public_exterior_cell(entry.outside),label+": owned threshold/public outside")
  for arriving in [true,false]:
   var route=m._exterior_approach(entry,arriving)
   check(not route.is_empty(),label+": public approach exists")
   for index in range(1,route.size()):
    check(public_segment(m,route[index-1],route[index]),label+": whole exterior leg avoids parcels")
 var chair_id=int(m.items.filter(func(item):return item.kind=="chair")[0].id)
 for arriving in [true,false]:
  var access=m.guest_access_for(chair_id,arriving)
  check(not access.is_empty(),label+": chair journey remains connected")
  if not access.is_empty():check(m._public_exterior_cell(access.entry_outside),label+": selected entrance is public")
 check(state(m)==snapshot,label+": queries preserve customer identity, wallet and layout")
 var path="user://route-ownership-"+label+".json"
 check(m.save(path),label+": synthetic save")
 var digest=FileAccess.get_sha256(path);var loaded=Model.new()
 check(loaded.load_save(path),label+": synthetic reload")
 check(FileAccess.get_sha256(path)==digest and loaded.coins==m.coins and loaded.owned_parcels==m.owned_parcels,label+": source save and economy preserved")
 check(loaded.boundary_entries()==entries,label+": reload preserves public thresholds")
func ownership_routes():
 var m=Model.new();Minimal.apply(m);m.coins=10000000
 verify_public_routes(m,"original")
 for cell in [Vector2i(3,9),Vector2i(12,3),Vector2i(12,9)]:
  check(not m._public_exterior_cell(cell,[]),"unbought front/right/corner is not pavement")
  check(m._exterior_approach({"outside":cell,"direction":Vector2i.DOWN},true).is_empty(),"stale private approach rejected")
 check(m.buy_parcel("front_0"),"buy one front plot")
 verify_public_routes(m,"expanded")
 for id in ["right_0","right_1","right_2","right2_0"]:check(m.buy_parcel(id),"buy outer-right fixture "+id)
 verify_public_routes(m,"outer-right")
 check(m.move_wall_attachment(int(m.wall_attachments[0].id),"shell:back",3.5),"move door onto actual public back edge")
 verify_public_routes(m,"moved-door")
 var guard=0
 while not m.next_parcel().is_empty() and guard<24:
  check(m.buy_parcel(str(m.next_parcel().id)),"complete purchased map")
  guard+=1
 verify_public_routes(m,"fully-owned")
func _initialize():
 ownership_routes()
 for x in [-.5,-.00000665,-.0000001,0.0,.0000001,.2]:
  var m=fresh(x);var before=state(m);var id=int(m.items[-1].id);var g=m.customers[0].duplicate(true)
  var plan=Motion.plan(m,id,2,0,0)
  check(plan.ok,"safe plant move at west-exit epsilon "+str(x))
  check(state(m)==before,"preview never changes money, layout or guests "+str(x))
  if plan.ok:
   check(Motion.commit(m,plan),"safe transaction commits "+str(x))
   check(m.get_item(id).x==2 and m.get_item(id).z==0,"only requested plant position changes")
   check(m.coins==before[2] and m.served==before[3] and m.total_earned==before[4],"no price or payment duplication")
   check(m.customers[0].x==g.x and m.customers[0].z==g.z and m.customers[0].paid==g.paid,"guest body/payment identity preserved")
   if x<0:check(m.customers[0]==g,"already-exterior route, clock and index preserved exactly")
 var m=fresh();var g=m.customers[0];var before=g.duplicate(true)
 g.route.insert(0,Vector2(5.5,5.5));g.route_index=1;before=g.duplicate(true)
 check(m.reroute_guest(g) and g==before,"already-consumed route prefix is not replayed or validated")
 m=fresh();g=m.customers[0];g.route=[Vector2(-.5,4.5),Vector2(1.5,4.5)]
 # Reach the wall at z4.5 along two orthogonal legs.
 g.route=[Vector2(g.x,4.5),Vector2(1.5,4.5)];before=g.duplicate(true)
 check(not m.reroute_guest(g) and g==before,"remaining wall crossing is rejected without mutation")
 m=fresh();g=m.customers[0];g.route=[Vector2(2.5,5.5),Vector2(2.5,12.5)]
 m.items.append({"id":999,"kind":"plant","x":1,"z":5,"rot":0});before=g.duplicate(true)
 check(not m.reroute_guest(g) and g==before,"remaining furniture crossing is rejected without mutation")
 var id=int(m.items[-2].id);var snapshot=state(m)
 check(not Motion.commit(m,Motion.plan(m,id,2,0,0)) and state(m)==snapshot,"invalid remaining route cannot partially commit a furnishing")
 m=fresh();g=m.customers[0];g.x=.5;g.z=9.0000001;g.route=[Vector2(.5,10.5),Vector2(.5,12.5)]
 id=int(m.items[-1].id);snapshot=state(m)
 check(not Motion.commit(m,Motion.plan(m,id,0,8,0)) and state(m)==snapshot,"edge furniture cannot clip a guest whose center just left owned floor")
 m=fresh();g=m.customers[0];g.x=-.5;g.z=8.5;g.route=[Vector2(-.5,9.1),Vector2(2.5,9.1),Vector2(2.5,12.5)]
 m.items.append({"id":999,"kind":"plant","x":1,"z":8,"rot":0});before=g.duplicate(true)
 check(not m.reroute_guest(g) and g==before,"future body sweep cannot graze new furniture beside an outside route")
 m=fresh();g=m.customers[0];g.route=[Vector2(-.85,12.5)];before=g.duplicate(true)
 check(not m.reroute_guest(g) and g==before,"diagonal shortcut is not invented")
 m=fresh();g=m.customers[0];g.route=[];before=g.duplicate(true)
 check(not m.reroute_guest(g) and g==before,"missing remaining route remains invalid")
 m=fresh();g=m.customers[0];g.chair_id=999;before=g.duplicate(true)
 check(not m.reroute_guest(g) and g==before,"missing assigned chair remains invalid")
 m=fresh();g=m.customers[0];g.route_index=-1;before=g.duplicate(true)
 check(not m.reroute_guest(g) and g==before,"invalid route index remains invalid")
 m=fresh();g=m.customers[0];var start=Vector2(g.x,g.z)
 check(m.reroute_guest(g),"exterior departure remains valid before advancing")
 m._advance_walk(g,1.0/30.0)
 check(Vector2(g.x,g.z).distance_to(start)<=m.WALK_SPEED/30.0+.0001 and float(g.x)<start.x,"first post-edit step is continuous and outbound")
 print("DEPARTING_ROUTE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
