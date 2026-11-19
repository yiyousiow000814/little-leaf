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
  check(entry.cell.x==0 and entry.outside.x==-1 and entry.direction==Vector2i.LEFT,label+": entrance opens directly to west corridor")
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
func commit_preserves_lookup_semantics():
 var m=Model.new()
 var item={"id":7,"x":1,"z":2,"rot":0,"metadata":"original"}
 var duplicate_item={"id":"7","x":8,"z":9,"rot":1}
 var guest={"id":41,"phase":"eating","ledger":12}
 var duplicate_guest={"id":"41","phase":"waiting"}
 m.items.assign([item,duplicate_item]);m.customers.assign([guest,duplicate_guest])
 var notifications=[]
 var on_changed=func():notifications.append([item.x,guest.phase,m.dining_sets.size()])
 m.changed.connect(on_changed)
 var original_revision=m.revision
 var change={"ok":true,"items":[{"id":"7","x":3,"z":4,"rot":2,"metadata":"ignore"},{"id":999,"x":5,"z":6,"rot":1},{"id":7,"x":6,"z":7,"rot":3}],"groups":[{"id":31}],"guests":[{"id":"41","phase":"checkout_wait"},{"id":777,"phase":"walking"},{"id":41,"phase":"paying"}]}
 check(Motion.commit(m,change),"accepts production commit transaction")
 check(is_same(m.items[0],item) and is_same(m.customers[0],guest),"retains original service dictionary references")
 check([item.x,item.z,item.rot,item.metadata]==[6,7,3,"original"],"last proposed coordinates win without changing other item fields")
 check(guest.phase=="paying" and guest.ledger==12,"merged guest state retains untouched live fields")
 check(duplicate_item.x==8 and duplicate_guest.phase=="waiting","duplicate live IDs keep original first-match behavior")
 check(m.items.size()==2 and m.customers.size()==2,"missing IDs are not inserted")
 check(notifications==[[6,"paying",1]] and m.revision==original_revision+1,"notify exactly once after coordinates, groups and guests commit")
 check(Motion.commit(m,{"ok":true,"noop":true}) and not Motion.commit(m,{"ok":false,"error":"blocked"}) and notifications.size()==1,"failure and no-op do not publish a partial transaction")
 m.changed.disconnect(on_changed)
func corridor_cell_index_edits():
 var m=Model.new();Minimal.apply(m)
 var initial=m.boundary_entries()
 check(initial.size()==1 and initial[0].cell==Vector2i(0,5),"starter has exactly its original western threshold")
 var entry=Vector2i(0,5)
 m.items.append({"id":999,"kind":"rug","x":entry.x,"z":entry.y,"rot":0})
 check(m.boundary_entries()==initial,"a corridor threshold rug is not a walking obstruction")
 m.items[-1].kind="plant"
 check(m.boundary_entries().is_empty(),"in-place solid item edit invalidates the navigation index")
 m.items[-1].z=0
 check(m.boundary_entries()==initial,"direct move restores the threshold in its original order")
 m.items.pop_back()
 m.wall_attachments.clear()
 check(m.boundary_entries().is_empty(),"in-place aperture deletion refreshes the geometry without requiring a revision notification")
func ownership_routes():
 var m=Model.new();Minimal.apply(m);m.coins=10000000
 verify_public_routes(m,"original")
 for cell in [Vector2i(3,9),Vector2i(12,3),Vector2i(12,9),Vector2i(3,-1),Vector2i(18,3),Vector2i(3,18)]:
  check(not m._public_exterior_cell(cell,[]),"unbought front/right/corner is not pavement")
  check(m._exterior_approach({"outside":cell,"direction":Vector2i.DOWN},true).is_empty(),"stale private approach rejected")
 check(m.buy_parcel("front_0"),"buy one front plot")
 verify_public_routes(m,"expanded")
 check(m.buy_parcel("right_0"),"buy land elsewhere without authorizing a new public approach")
 verify_public_routes(m,"right-owned")
 check(m.move_wall_attachment(int(m.wall_attachments[0].id),"wall:16",.5),"move door within real corridor edge")
 verify_public_routes(m,"moved-corridor-door")
 for z in range(Model.BASE_DEPTH,Model.BASE_DEPTH+Model.PARCEL_DEPTH):check(m.place_wall("z",0,z),"wall purchased corridor-side plot")
 check(not m.boundary_entries().any(func(entry):return entry.cell.y>=Model.BASE_DEPTH),"walled side land creates no side entrance")
 verify_public_routes(m,"side-owned-walled")
 var snapshot=state(m);var openings=m.wall_attachments.duplicate(true)
 check(m.move_wall_attachment(int(m.wall_attachments[0].id),"wall:4",.5),"valid rear-only door remains editable without admitting customers")
 check(m.wall_attachments[0].id==openings[0].id and m.coins==snapshot[2] and m.items==snapshot[0],"door edit preserves identity, inventory and money")
 check(m.boundary_entries().is_empty() and m.guest_access_for(7).is_empty(),"walled side plot plus rear-only door has no corridor admission")
 var path="user://corridor-rear-only.json"
 check(m.save(path),"valid rear-only layout still saves")
 var digest=FileAccess.get_sha256(path);var loaded=Model.new()
 check(loaded.load_save(path) and FileAccess.get_sha256(path)==digest,"rear-only save loads without rewriting its source bytes")
 check(loaded.wall_attachments==m.wall_attachments and loaded.coins==m.coins and loaded.items==m.items,"rear-only load preserves door, wallet and inventory")
 var sealed=Model.new();Minimal.apply(sealed);sealed.coins=10000000
 check(sealed.buy_parcel("right_0"),"synthetic disconnected-side fixture buys land elsewhere")
 sealed.wall_attachments[0].wall_ids=["wall:4"];sealed.wall_attachments[0].offset=.5
 snapshot=state(sealed)
 check(sealed.boundary_entries().is_empty() and sealed.guest_access_for(7).is_empty(),"purchased elsewhere plus sole back opening has no corridor access")
 check(state(sealed)==snapshot,"inaccessible synthetic route queries are read-only")
 sealed._spawn_customer()
 check(sealed.customers.is_empty() and sealed.outside_queue.size()==2,"no legal corridor access queues real requests instead of admitting guests")
 check(sealed.outside_queue.all(func(visitor):return visitor.x<0 and visitor.table_id==-1 and visitor.chair_id==-1),"queued visitors stay on corridor and claim no dining place")
func public_reroutes():
 for expanded in [false,true]:
  var m=Model.new();Minimal.apply(m);m.coins=10000000
  if expanded:check(m.buy_parcel("front_0"),"reroute fixture buys corridor-connected side land")
  m._spawn_customer();var guest=m.customers[0]
  for position in [Vector2(-2.76,3.5),Vector2(-2.76,12.0),Vector2(-.85,19.4)]:
   guest.x=position.x;guest.z=position.y
   var original=guest.duplicate(true);var snapshot=state(m)
   check(m.reroute_guest(guest),"actual corridor arrival replans "+str(position))
   var previous=position
   for point in guest.route:
    var cell=Vector2i(floori(point.x),floori(point.y))
    if m.is_floor_owned(cell):break
    check(public_segment(m,previous,point),"entire replan prefix avoids private parcels")
    previous=point
   var retained=guest.duplicate(true)
   for key in ["route","route_index","entry_cell","entry_direction","entry_outside","service_cell","waiting","departure_blocked"]:
    retained.erase(key);original.erase(key)
   check(retained==original,"replan preserves guest identity, position, claims and payment")
   check(m.items==snapshot[0] and m.coins==snapshot[2] and m.served==snapshot[3] and m.total_earned==snapshot[4],"replan preserves layout and economy")
  for position in [Vector2(12.5,10.5),Vector2(19.76,3.5),Vector2(3.5,-.5),Vector2(3.5,19.4)]:
   guest.x=position.x;guest.z=position.y
   var before=guest.duplicate(true)
   check(not m.reroute_guest(guest) and guest==before,"non-corridor origin refuses without rewriting guest "+str(position))
func _initialize():
 commit_preserves_lookup_semantics()
 corridor_cell_index_edits()
 ownership_routes()
 public_reroutes()
 arrival_shared_search()
 arrival_held_seat()
 legacy_departure_distances()
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

class ArrivalGrid extends "res://scripts/core/cafe_model.gd":
 var extent:=8
 var checks:=0
 var barriers:Dictionary={}
 func is_floor_owned(cell:Vector2i)->bool:
  return cell.x>=0 and cell.y>=0 and cell.x<extent and cell.y<extent
 func edge_blocked(a:Vector2i,b:Vector2i)->bool:
  checks+=1
  return barriers.has([a,b]) or barriers.has([b,a])
 func boundary_entries()->Array[Dictionary]:
  var result:Array[Dictionary]=[]
  for z in range(extent):
   result.append({"cell":Vector2i(0,z),"outside":Vector2i(-1,z),"direction":Vector2i.LEFT})
  return result
 func _wall_reachable(_walls:Array,_layout:Array,_ownership:Array,_openings=null,_known_keys=null)->Dictionary:
  var result={}
  for x in range(extent):
   for z in range(extent):
    result[Vector2i(x,z)]=true
  return result

func legacy_arrival(m,chair_id:int,table_id:int,start:Vector2)->Dictionary:
 var chair=m.get_item(chair_id)
 var chair_cell=Vector2i(int(chair.x),int(chair.z))
 var forward=m._chair_table_direction(chair_id,table_id)
 var best={};var best_rank=4;var best_length=INF
 for entry in m.boundary_entries():
  for approach in m.chair_egress_cells(chair_id,table_id):
   var indoor=m.Checkout.path(m,entry.cell,approach)
   if indoor.is_empty():continue
   var direction=approach-chair_cell
   var rank=0 if direction.x*forward.x+direction.y*forward.y==0 else 1
   var route=m._exterior_approach(entry,true)
   for cell in indoor:route.append(m.cell_center(cell))
   route.append(m.cell_center(chair_cell))
   var length=m._route_length(start,route)
   if rank<best_rank or (rank==best_rank and length+.000001<best_length):
    best_rank=rank;best_length=length
    best={"entry_cell":entry.cell,"entry_direction":entry.direction,"entry_outside":entry.outside,
      "approach":approach,"route":route,"length":length,"chair_approach":"side" if rank==0 else "rear_fallback"}
 return best

func arrival_shared_search():
 var m=ArrivalGrid.new()
 for size in [8,16,24]:
  m.extent=size;m.items.clear();m.barriers.clear()
  for z in range(1,size-1,2):
   m.items.append({"id":z*2,"kind":"chair","x":size-3,"z":z,"rot":0})
   m.items.append({"id":z*2+1,"kind":"table","x":size-2,"z":z,"rot":0})
  for z in range(size):
   if z!=size/2:m.barriers[[Vector2i(1,z),Vector2i(2,z)]]=true
  var start:=Vector2(-.85,12.319)
  m.checks=0
  var old:Array=[]
  for z in range(1,size-1,2):old.append(legacy_arrival(m,z*2,z*2+1,start))
  var before=m.checks
  m.checks=0
  var index:Dictionary={}
  var current:Array=[]
  for z in range(1,size-1,2):current.append(m._arrival_access(z*2,start,z*2+1,index))
  var after=m.checks
  print("ARRIVAL_TREE_WORK ",size," ",before," ",after)
  check(current==old and not current[0].is_empty(),"exact route/float length and west-entry or side ties, grid %s"%size)
  check(after<=size*size*size and after*3<before,"entry searches expand at most one grid per admission and reuse across chair pairs, grid %s"%size)
  var different_start:=Vector2(-.85,-2.49)
  check(m._arrival_access(2,different_start,3,index)==legacy_arrival(m,2,3,different_start),"different street start does not reuse prior continuous costs")
  m.items.append({"id":1000,"kind":"plant","x":size-3,"z":0,"rot":0})
  m.items.append({"id":1001,"kind":"plant","x":size-3,"z":2,"rot":0})
  var rerouted=m.guest_access_for(2,true,start,12.5,3)
  check(rerouted==legacy_arrival(m,2,3,start) and rerouted!=current[0] and rerouted.get("chair_approach","")=="rear_fallback","fresh scan sees in-place furniture changes and preserves rear fallback")

func arrival_held_seat():
 var m=Model.new()
 m._spawn_walkers(1)
 check(m.customers.size()==1,"first direct admission reserves a real dining pair")
 if m.customers.is_empty():return
 var held=m.customers[0]
 held.phase="ordering"
 m.service_snapshot={"layout_hold":{"guests":[{"id":held.id}]}}
 var unchanged=held.duplicate(true)
 m._spawn_walkers(1)
 check(m.layout_held("guests",int(held.id)) and m.customers.size()==2 and held==unchanged,"arrival leaves held guest and its job untouched")
 if m.customers.size()<2:return
 var admitted=m.customers[1]
 check(admitted.table_id!=held.table_id and admitted.chair_id!=held.chair_id,"new guest never takes occupied held table or chair")

class LegacyDepartureGrid extends ArrivalGrid:
 var ports:Array[int]=[]
 var directed:Dictionary={}
 var occupied:Dictionary={}
 func edge_blocked(a:Vector2i,b:Vector2i)->bool:
  return super.edge_blocked(a,b) or directed.has([a,b])
 func boundary_entries()->Array[Dictionary]:
  if ports.is_empty():return super.boundary_entries()
  var result:Array[Dictionary]=[]
  for z in ports:result.append({"cell":Vector2i(0,z),"outside":Vector2i(-1,z),"direction":Vector2i.LEFT})
  return result
 func _egress_occupied(_id:int,cell:Vector2i)->bool:return occupied.has(cell)

func original_seated_departure(m,chair_id:int,table_id:int,exit_z:float,guest_id:int)->Dictionary:
 var chair=m.get_item(chair_id)
 var chair_cell=Vector2i(int(chair.x),int(chair.z))
 var forward=m._chair_table_direction(chair_id,table_id)
 var approaches=m.chair_egress_cells(chair_id,table_id)
 var best={};var best_rank=4;var best_length=INF
 for entry in m.boundary_entries():
  for approach in approaches:
   var direction=approach-chair_cell
   var rank=(0 if direction.x*forward.x+direction.y*forward.y==0 else 1)+(2 if m._egress_occupied(guest_id,approach) else 0)
   var indoor=m.Checkout.path(m,entry.cell,approach)
   if indoor.is_empty():continue
   indoor.reverse()
   var route:Array[Vector2]=[]
   for cell in indoor:route.append(m.cell_center(cell))
   route.append_array(m._exterior_approach(entry,false,exit_z))
   var length=m._route_length(m.cell_center(chair_cell),route)
   if rank<best_rank or (rank==best_rank and length+.000001<best_length):
    best_rank=rank;best_length=length
    best={"entry_cell":entry.cell,"entry_direction":entry.direction,"entry_outside":entry.outside,
      "approach":approach,"route":route,"length":length,"chair_approach":"side" if rank%2==0 else "rear_fallback"}
 return best

func legacy_departure_distances():
 var m=LegacyDepartureGrid.new()
 m.ports.assign([0,2])
 m.items.assign([
  {"id":1,"kind":"chair","x":4,"z":2,"rot":0},{"id":2,"kind":"table","x":5,"z":2,"rot":0},
  {"id":3,"kind":"plant","x":3,"z":2},{"id":4,"kind":"plant","x":4,"z":3}])
 var expected=original_seated_departure(m,1,2,1.5,3)
 var current=m.guest_access_for(1,false,Vector2.ZERO,1.5,2,3)
 check(current==expected and current.entry_cell==Vector2i(0,0),"exact equal-length exterior tie keeps first west entry")
 check(current.route[0]==Vector2(4.5,1.5) and current.route[1]==Vector2(4.5,.5),"equal indoor route uses old forward direction tie, then reverses it")
 m.directed[[Vector2i(3,0),Vector2i(4,0)]]=true
 current=m.guest_access_for(1,false,Vector2.ZERO,1.5,2,3)
 check(current==original_seated_departure(m,1,2,1.5,3) and current.route[1]==Vector2(3.5,1.5),"one-way transition tests forward edge orientation, not reverse traversal permission")
 m.items.resize(2);m.occupied[Vector2i(4,1)]=true
 current=m.guest_access_for(1,false,Vector2.ZERO,1.5,2,3)
 check(current==original_seated_departure(m,1,2,1.5,3) and current.approach==Vector2i(4,3),"occupied side ranks after clear side, exact whole route retained")
 var real=Model.new();Minimal.apply(real)
 var chair_id=int(real.items.filter(func(item):return item.kind=="chair")[0].id)
 var attached=real.wall_attachments.duplicate(true)
 var public_route=real.guest_access_for(chair_id,false,Vector2.ZERO,-2.5)
 check(not public_route.is_empty() and public_route==original_seated_departure(real,chair_id,-1,-2.5,-1),"real authored door cut and exit tail match old route")
 real.wall_attachments.clear()
 check(real.guest_access_for(chair_id,false,Vector2.ZERO,-2.5).is_empty(),"closing real authored door cut blocks departure")
 real.wall_attachments.assign(attached)
 check(real.guest_access_for(chair_id,false,Vector2.ZERO,-2.5)==public_route,"reopening real door observes current geometry, not a previous search")
 m.ports.clear();m.directed.clear();m.occupied.clear()
 for size in [8,16,24]:
  m.extent=size;m.barriers.clear()
  m.items.assign([{"id":1,"kind":"chair","x":size-3,"z":size/2,"rot":0},{"id":2,"kind":"table","x":size-2,"z":size/2,"rot":0}])
  for z in size:
   if z!=size/2:m.barriers[[Vector2i(1,z),Vector2i(2,z)]]=true
  m.checks=0;expected=original_seated_departure(m,1,2,-2.5,4);var before=m.checks
  m.checks=0;current=m.guest_access_for(1,false,Vector2.ZERO,-2.5,2,4);var after=m.checks
  print("LEGACY_DEPARTURE_WORK ",size," ",before," ",after)
  check(current==expected and not current.is_empty(),"scaled route, exact length, and exterior tail match, grid %s"%size)
  check(after<=4*size*size and after*2<before,"expanded cells independent of entry count, grid %s"%size)
