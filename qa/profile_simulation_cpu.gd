extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Main=preload("res://scripts/main.gd")
const Walls=preload("res://scripts/cafe_walls.gd")
class Indexed extends "res://scripts/cafe_model.gd":
 var cells={}
 var ids={}
 func index_items():
  for item in items:cells[Vector2i(item.x,item.z)]=item;ids[int(item.id)]=item
 func item_at(x:int,z:int)->Dictionary:return cells.get(Vector2i(x,z),{})
 func get_item(id:int)->Dictionary:return ids.get(id,{})
func _initialize():run.call_deferred()
func fixture(n:int,indexed=false):
 var m=Indexed.new() if indexed else Model.new()
 m.items.clear();m.customers.clear();m.dining_sets.clear();m.built_walls.clear();m.wall_attachments.clear()
 m.owned_parcels.assign(Model.PARCEL_IDS);m._sync_floor_bounds()
 for i in n:m.items.append({"id":i+1,"kind":"rug","x":i%18,"z":i/18,"rot":0})
 if indexed:m.index_items()
 m.revision+=1
 return m
func sample(label:String,count:int,call:Callable)->Dictionary:
 for i in 5:call.call()
 var batches=[]
 for repeat in 3:
  var t=Time.get_ticks_usec()
  for i in count:call.call()
  batches.append((Time.get_ticks_usec()-t)/float(count))
 return {"label":label,"iterations_per_batch":count,"microseconds_per_call":batches}
func validate_route(m,route):
 var point=Vector2(1.5,.5)
 for cell in route:
  var next=Vector2(cell)+Vector2(.5,.5)
  if not m._walkable(cell) or m.segment_blocked(point,next):return false
  point=next
 return true
func run():
 var results=[]
 for n in [12,72,216]:
  for indexed in [false,true]:
   var m=fixture(n,indexed)
   results.append(sample("bfs_items_%s_indexed_%s"%[n,indexed],30,func():return m.path_between(Vector2i(1,0),Vector2i(17,17))))
 var game=Main.new()
 for walls in [0,36,108]:
  var m=fixture(72)
  for i in walls:
   var wall=Walls.make("x",10+i%7,i/7);wall.id=i+1;m.built_walls.append(wall)
  m.revision+=1
  for length in [1,16,32]:
   var route=[]
   for i in length:route.append(Vector2i(1+(i%2 if (i/2)%2==0 else 1-i%2),i/2))
   results.append(sample("route_validation_walls_%s_legs_%s"%[walls,length],100,func():return validate_route(m,route)))
   game.model=m
   var staff={"pos":Vector2(1.5,.5),"path":route,"index":0}
   if game.has_method("_staff_route_invalid"):
    results.append(sample("controller_route_walls_%s_legs_%s"%[walls,length],100,func():m.navigation_cells();return game._staff_route_invalid(staff,m.navigation_signature())))
   else:results.append(sample("controller_route_walls_%s_legs_%s"%[walls,length],100,func():return validate_route(m,route)))
 for tables in [4,16,48]:
  for indexed in [false,true]:
   var m=fixture(0,indexed)
   for i in tables:
    var x=2+(i%8)*2;var z=1+(i/8)*2
    m.items.append({"id":i*2+1,"kind":"table","x":x,"z":z,"rot":0})
    m.items.append({"id":i*2+2,"kind":"chair","x":x,"z":z+1,"rot":0})
    m.dining_sets.append({"table_id":i*2+1,"seat_id":i*2+2})
    m.customers.append({"id":i+1,"table_id":i*2+1,"chair_id":i*2+2,"phase":"eating"})
   if indexed:m.index_items()
   results.append(sample("full_cafe_admission_tables_%s_indexed_%s"%[tables,indexed],100,func():return m._admit_queued_visitor({"id":100,"x":-1.6,"z":7.5})))
 for n in [12,72,216]:
  var m=fixture(n)
  for i in range(m.items.size()-1,-1,-1):
   if int(m.items[i].x)==4 and int(m.items[i].z)==3:m.items.remove_at(i)
  m.items.append({"id":1000,"kind":"register","x":4,"z":3,"rot":0})
  m.revision+=1
  results.append(sample("checkout_empty_items_%s"%n,100,func():m.Checkout.advance(m,1.0/60)))
  m.customers.append({"id":1,"phase":"paying","paid":false,"settlement_mode":"register","checkout_ticket":1,"checkout_cell":Vector2i(4,4),"mobility":{}})
  results.append(sample("checkout_paying_items_%s"%n,100,func():m.Checkout.advance(m,1.0/60)))
 for node in [game.world,game.furnishings,game.people,game.camera,game.ui]:node.free()
 game.free()
 var report={"source_label":OS.get_environment("SOURCE_LABEL"),"engine":Engine.get_version_info().string,"mode":"headless synthetic CPU microbenchmarks, not frame/thermal evidence","results":results}
 FileAccess.open(OS.get_environment("OUTPUT")+"/profile.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print(JSON.stringify(report));quit()
