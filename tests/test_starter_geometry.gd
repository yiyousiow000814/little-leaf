extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Openings=preload("res://scripts/cafe_wall_openings.gd")
const Ground=preload("res://scripts/illustrated_ground.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
const OUT="user://geometry-fixtures"
var checks=0
var failures=[]

func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func read(path:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path))
func write(path:String,data:Dictionary):
	var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data,"\t",true,true));file.close()
func same(a,b)->bool:
	# JSON reads all numbers as floats. Compare numeric values exactly without
	# confusing representation changes with saved-data changes.
	if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
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
func signature(model)->String:
	var state={}
	for prop in model.get_property_list():
		if int(prop.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE and str(prop.name)!="last_error":state[str(prop.name)]=model.get(str(prop.name))
	return JSON.stringify(Codec.new().encode(state),"",true,true)
func reject(live,data:Dictionary,label:String):
	var path=OUT+"/bad.json";write(path,data)
	var hash=FileAccess.get_sha256(path);var before=signature(live)
	check(not live.load_save(path),label+" rejected")
	check(signature(live)==before,label+" preserves live state")
	check(FileAccess.get_sha256(path)==hash,label+" preserves source bytes")

func _init():
	if not "geometry-saveguard" in OS.get_user_data_dir():printerr("SAVEGUARD FAILED");quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var model=Model.new();model.coins=4567
	check(model.width==12 and model.depth==9 and model.owned_floor_count()==108,"fresh footprint is exactly 12x9")
	check(model.floor_finishes.size()==108,"fresh floor has 108 installed tiles")
	var ground=Ground.new();ground.prepare(model)
	check(ground.floor_cells.size()==108,"retained renderer draws every starter tile")
	for x in range(12):check(ground.floor_cells.has(Vector2i(x,8)),"ninth-row rendered tile "+str(x))
	var shell=Openings.shell_hosts(model.shell_products)
	check(shell[0].b==Vector2(12,0) and shell[1].b==Vector2(0,9),"rendered shell ends match footprint")
	check(model.edge_blocked(Vector2i(0,8),Vector2i(-1,8)),"new west edge blocks grid travel")
	check(model.edge_blocked(Vector2i(-1,8),Vector2i(0,8)),"new west edge blocks reverse travel")
	check(model.segment_blocked(Vector2(-.5,8.5),Vector2(.5,8.5)),"new west edge blocks continuous travel")
	check(not model.segment_blocked(Vector2(-.5,9.2),Vector2(.5,9.2)),"wall stops at depth 9")
	check(not model.edge_blocked(Vector2i(-1,5),Vector2i(0,5)),"included entrance remains open")
	check(not model.segment_blocked(Vector2(-.5,5.5),Vector2(.5,5.5)),"included doorway remains traversable")
	check(not model.can_place_wall("z",0,8),"duplicate extension wall is rejected")
	check(model.can_place_wall("x",0,9),"front edge remains available")
	check(model.save(OUT+"/fresh.json"),"fresh save: "+model.last_error)
	var fresh=read(OUT+"/fresh.json")
	check(fresh.starter_geometry_version==1,"save records completed geometry revision")
	var reload=Model.new();check(reload.load_save(OUT+"/fresh.json"),"fresh reload")
	check(reload.floor_finishes==model.floor_finishes,"fresh floors round trip exactly")
	check(model.replace_wall("shell:west","full","sage_panels"),"replacement uses full nine-tile shell")
	check(model.shell_products["shell:west"].paid_cost==9*model.wall_price("full"),"replacement charges actual shell length")
	check(model.save(OUT+"/nine-tile-shell.json") and reload.load_save(OUT+"/nine-tile-shell.json"),"nine-tile shell paid value saves and reloads")
	# Pre-v12 fixtures exercise real save loading, including the older parcel
	# coordinates. They do not read or write any player file.
	for version in [1,5,6,11,12,13,15]:
		var old=fresh.duplicate(true);old.erase("starter_geometry_version");old.version=version
		for x in range(12):old.floor_finishes.erase("%d,8"%x)
		if version<15:old.erase("layout_motion_format");old.runtime.erase("layout_motion_format")
		if version<13:
			old.duty_counts.erase("cashier");old.duty_targets.erase("cashier");old.runtime.erase("checkout_format");old.runtime.erase("next_checkout_ticket")
		var path=OUT+"/old-%d.json"%version;write(path,old);var before=FileAccess.get_sha256(path)
		var migrated=Model.new()
		check(migrated.load_save(path),"legacy %d loads: "%version+migrated.last_error)
		check(migrated.floor_finishes.size()==108 and migrated.starter_floor_gap_cells().is_empty(),"legacy %d gains only missing starter row"%version)
		check(migrated.coins==4567 and migrated.owned_parcels.is_empty(),"legacy %d preserves wallet and ownership"%version)
		check(FileAccess.get_sha256(path)==before,"legacy %d source file unchanged"%version)
		check(migrated.save(OUT+"/migrated.json"),"legacy %d migrated save"%version)
		var again=Model.new();check(again.load_save(OUT+"/migrated.json"),"legacy %d second load"%version)
		check(again.floor_finishes==migrated.floor_finishes,"legacy %d repair is idempotent"%version)
	var custom=fresh.duplicate(true);custom.erase("starter_geometry_version")
	custom.owned_parcels=["front_0","right_0"]
	for x in range(12):custom.floor_finishes.erase("%d,8"%x)
	custom.floor_finishes["3,8"]={"style":"sage_tile","paid_cost":model.floor_price("sage_tile")}
	custom.floor_finishes["2,9"]={"style":"cream_tile","paid_cost":model.floor_price("cream_tile")}
	custom.built_walls=[{"id":1,"axis":"z","x":0,"z":8,"height":"full","material":"leaf_print"}];custom.next_wall_id=2
	custom.wall_attachments.append({"id":2,"kind":"window","host_id":"wall:1","offset":.5,"width":.70,"paid_cost":30});custom.next_attachment_id=3
	custom.shell_products["shell:west"]={"height":"full","material":"cream_stripe","paid_cost":8*model.wall_price("full")}
	write(OUT+"/custom.json",custom);var custom_hash=FileAccess.get_sha256(OUT+"/custom.json")
	var preserved=Model.new();check(preserved.load_save(OUT+"/custom.json"),"custom legacy load: "+preserved.last_error)
	check(preserved.floor_finishes["3,8"]==custom.floor_finishes["3,8"],"custom ninth-row tile and paid cost preserved")
	check(preserved.floor_finishes["2,9"]==custom.floor_finishes["2,9"],"expansion flooring stays at exact saved coordinate")
	check(preserved.owned_parcels==custom.owned_parcels and preserved.coins==custom.coins,"expanded ownership and wallet unchanged")
	check(same(preserved.built_walls,custom.built_walls) and same(preserved.wall_attachments,custom.wall_attachments),"custom wall identity finish and window unchanged")
	check(same(preserved.shell_products,custom.shell_products),"old paid shell value unchanged")
	check(preserved.get_wall_host("shell:west").b==Vector2(0,8),"default shell does not overlap preserved custom extension")
	check(preserved.get_wall_host("wall:1").b==Vector2(0,9),"preserved custom wall completes west edge")
	check(preserved.segment_blocked(Vector2(-.5,8.5),Vector2(.5,8.5)),"custom window still blocks travel")
	check(preserved.wall_replacement_quote("z:0:8","full","sage_panels").valid,"preserved wall remains editable")
	check(preserved.save(OUT+"/custom-roundtrip.json"),"custom legacy save: "+preserved.last_error)
	check(reload.load_save(OUT+"/custom-roundtrip.json"),"custom legacy reload: "+reload.last_error)
	check(reload.built_walls==preserved.built_walls and reload.floor_finishes==preserved.floor_finishes and reload.shell_products==preserved.shell_products,"custom geometry round trip exact")
	check(FileAccess.get_sha256(OUT+"/custom.json")==custom_hash,"custom import source bytes unchanged")
	# A hosted door in a retained extension must not be sealed by default shell.
	custom.wall_attachments[1]={"id":2,"kind":"door","host_id":"wall:1","offset":.5,"width":.76,"paid_cost":40}
	write(OUT+"/custom-door.json",custom)
	check(preserved.load_save(OUT+"/custom-door.json"),"custom extension door loads")
	check(not preserved.edge_blocked(Vector2i(-1,8),Vector2i(0,8)),"custom extension door grid passage preserved")
	check(not preserved.segment_blocked(Vector2(-.5,8.5),Vector2(.5,8.5)),"custom extension door continuous passage preserved")
	# New revision must not silently refill an intentionally absent tile later.
	var marked=fresh.duplicate(true);marked.floor_finishes.erase("4,8");write(OUT+"/marked.json",marked)
	check(reload.load_save(OUT+"/marked.json") and not reload.floor_finishes.has("4,8"),"completed revision skips future migration")
	for value in [0,2,"1",true]:
		var bad=fresh.duplicate(true);bad.starter_geometry_version=value;reject(reload,bad,"invalid geometry marker "+str(value))
	var bad=fresh.duplicate(true);bad.floor_finishes["2,8"]={"style":"unknown","paid_cost":0};reject(reload,bad,"invalid finish")
	bad=custom.duplicate(true);bad.built_walls.append(custom.built_walls[0].duplicate());reject(reload,bad,"duplicate saved extension wall")
	bad=custom.duplicate(true);bad.shell_products["shell:west"].paid_cost=449;reject(reload,bad,"invalid paid shell value")
	var report={"checks":checks,"failures":failures,"save_root":OS.get_user_data_dir()}
	write(OUT+"/REPORT.json",report);print("STARTER_GEOMETRY_RESULT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
