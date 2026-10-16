extends SceneTree
## Generated-only contract for the coherent unified-building candidate.
const Model=preload("res://scripts/core/cafe_model.gd")
const Minimal=preload("res://scripts/minimal_start.gd")
const Walls=preload("res://scripts/gameplay/cafe_walls.gd")
const Openings=preload("res://scripts/gameplay/cafe_wall_openings.gd")
const Codec=preload("res://scripts/persistence/cafe_building_codec.gd")
const Segments=preload("res://scripts/gameplay/cafe_shell_segments.gd")
var checks=0
var failures=[]

func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)

func same(a,b)->bool:
	if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for index in a.size():
			if not same(a[index],b[index]):return false
		return true
	return a==b

func _initialize():
	if not "saveguard" in OS.get_user_data_dir():printerr("Use an isolated saveguard profile");quit(2);return
	for axis in ["x","z"]:
		var shape=Walls.make(axis,3,4,"full","original")
		var included=Walls.installed("wall:1",shape,0,0)
		var bought=Walls.installed("wall:2",shape,55,27)
		check(Walls.physical_rect(included)==Walls.physical_rect(bought),axis+" preset and purchase share physical geometry")
		check(Walls.visual_front(included)==Walls.visual_front(bought) and Walls.visual_back(included)==Walls.visual_back(bought),axis+" preset and purchase share accepted visible geometry")
		check(Walls.visual_front(bought).is_equal_approx(Walls.normal(shape)*.13),axis+" centered front anchor")
		check(Walls.visual_back(bought).is_equal_approx(Walls.normal(shape)*-.13),axis+" centered back anchor")
		check(is_equal_approx(Walls.visual_front(bought).distance_to(Walls.visual_back(bought)),.26),axis+" visible width remains .26")
		check(included.paid_cost==0 and included.refund_credit==0 and bought.paid_cost==55 and bought.refund_credit==27,axis+" receipt data does not select a geometry path")
		var placement={"physical_back":-.26,"physical_front":0.0,"visual_back":-.26,"visual_front":0.0,"pattern_offset":4.0}
		var imported=Walls.installed("shell:west#4",shape,0,0,placement)
		var direction=Vector2.RIGHT if axis=="x" else Vector2.DOWN
		var anchor=Vector2(3,4)
		check(Walls.physical_rect(imported).is_equal_approx(Rect2(anchor-Walls.normal(shape)*.08,direction+Walls.normal(shape)*.16)),axis+" imported body centers on the unchanged edge datum")
		check(Walls.visual_front(imported).is_equal_approx(Walls.normal(shape)*.13) and Walls.visual_back(imported).is_equal_approx(Walls.normal(shape)*-.13),axis+" imported visible profile centers on the unchanged edge datum")
		check(Walls.pattern_origin(imported)==anchor-direction*4,axis+" imported wallpaper phase survives")
		placement.physical_back=-1.0
		check(is_equal_approx(Walls.placement_value(imported,"physical_back"),-.08),axis+" normalized placement metadata is independently owned")
		shape.x=9
		check(included.x==3 and bought.x==3 and imported.x==3,axis+" installed records do not alias constructor input")
	check("original" in Walls.MATERIALS,"Original room is an ordinary catalog material")
	var row=[]
	for x in range(3):row.append(Walls.installed("wall:%d"%(x+1),Walls.make("x",x,0),55,27))
	var ids=["wall:1","wall:2","wall:3"]
	var host=Openings.resolve_ids(ids,row)
	check(not host.is_empty() and host.a==Vector2.ZERO and host.b==Vector2(3,0),"one modern host can cover all three supporting edges")
	var opening={"id":9,"kind":"door","wall_ids":ids,"offset":1.5,"width":2.8,"paid_cost":0}
	var aperture=Openings.aperture(opening,row)
	check(not aperture.is_empty() and aperture.a.is_equal_approx(Vector2(.1,0)) and aperture.b.is_equal_approx(Vector2(2.9,0)),"wide opening keeps its full aperture without a starter root")
	check(Openings.resolve_ids(["wall:1","wall:3"],row).is_empty(),"missing middle support cannot become an implicit wall")
	check(Openings.resolve_ids(["wall:2","wall:1"],row).is_empty(),"unordered support identities are rejected")
	check(Openings.resolve_ids(["wall:1","wall:1"],row).is_empty(),"duplicate support identities are rejected")
	row[1].height="half"
	check(Openings.resolve_ids(ids,row).is_empty(),"multi-edge opening needs full-height support")
	row[1].height="full";row[1].placement={"physical_front":0.0,"physical_back":-.26,"visual_front":0.0,"visual_back":-.26,"pattern_offset":0.0}
	check(Openings.resolve_ids(ids,row).is_empty(),"new spans cannot silently flatten incompatible imported offsets")
	var products=Openings.initial_shell_products()
	var legacy={"products":products,"segments":Segments.migrate(products,[]).segments,"attachments":Openings.initial_attachments()}
	var original=JSON.stringify(legacy)
	var migrated=Codec.import_validated(legacy.products,legacy.segments,[],legacy.attachments)
	check(migrated.ok,"validated legacy building imports into the common object schema")
	check(JSON.stringify(legacy)==original,"candidate migration never edits original legacy records")
	if migrated.ok:
		var data={"version":15,"building_format":Codec.FORMAT,"wall_format":Codec.WALL_FORMAT,"wall_attachment_format":2,"starter_geometry_version":1,
			"built_walls":migrated.walls,"floor_style":"warm_oak","next_wall_id":1,"wall_attachments":migrated.attachments,"next_attachment_id":2}
		var owns=func(cell):return cell.x>=0 and cell.x<12 and cell.y>=0 and cell.y<9
		var parsed=Codec.read_walls(data,18,18,owns,["warm_oak","cream_tile","sage_tile"])
		check(parsed.ok,"new wall codec reads the preserved legacy import")
		if parsed.ok:check(Codec.read_openings(data,parsed.walls).ok,"new opening codec reads the complete imported aperture")
		var roundtrip=JSON.parse_string(JSON.stringify(data))
		check(Codec.read_walls(roundtrip,18,18,owns,["warm_oak"]).ok,"JSON scalar roundtrip preserves modern wall geometry and identity")
		var invalid=data.duplicate(true);invalid.built_walls.append(invalid.built_walls[0].duplicate(true))
		check(not Codec.read_walls(invalid,18,18,owns,["warm_oak"]).ok,"codec rejects duplicate active edges instead of layering")
		invalid=data.duplicate(true);invalid.erase("starter_geometry_version")
		check(not Codec.read_walls(invalid,18,18,owns,["warm_oak"]).ok,"new format cannot trigger the missing legacy-floor marker repair")
		invalid=data.duplicate(true);invalid.shell_products=legacy.products
		check(not Codec.read_walls(invalid,18,18,owns,["warm_oak"]).ok,"new format rejects a second hidden shell authority")
		invalid=data.duplicate(true);invalid.built_walls[0].refund_credit=100
		check(not Codec.read_walls(invalid,18,18,owns,["warm_oak"]).ok,"codec rejects invented refund credit")
	var model=Model.new();Minimal.apply(model);model.set_operating_open(false)
	check(model.built_walls.size()==21 and model.collision_wall_hosts().size()==21,"fresh preset has one installed wall authority")
	check(model._next_wall_id==22 and model.get_wall_host("wall:18").height=="full","fresh preset uses the same public wall identities")
	check(model.save("user://modern.json"),"modern model saves: "+model.last_error)
	var restored=Model.new()
	check(restored.load_save("user://modern.json"),"modern model reloads: "+restored.last_error)
	check(restored.built_walls==model.built_walls and restored.wall_attachments==model.wall_attachments,"modern model exact building roundtrip")
	var fixtures=OS.get_environment("UNIFIED_LEGACY_FIXTURE_DIR")
	if fixtures=="":fixtures="res://tests/fixtures/unified_building"
	# Independent expected road seed for the existing empty v1 parking fixtures.
	var expected_road_cars=[]
	for index in 8:
		var position=Vector2(-4.65 if index%2==0 else -7.35,-65.0+index*19.0)
		expected_road_cars.append({"id":index,"position":{"$vector2":[position.x,position.y]},"direction":1 if index%2==0 else -1,"color":"a2b3b3" if index%3==0 else "ddcdb0"})
	var expected_initial_traffic={"elapsed":0.0,"cars":expected_road_cars}
	if fixtures!="":
		for name in ["historical","public_closed","owned_custom","intentionally_bare_grass","removed_structure","progress_and_payroll","inherited_extension_full","inherited_extension_half"]:
			var path=fixtures.path_join(name+".json");var digest=FileAccess.get_sha256(path)
			var original_save=JSON.parse_string(FileAccess.get_file_as_string(path))
			var imported_model=Model.new()
			var loaded=imported_model.load_save(path)
			check(loaded,name+" actual old-client payload loads: "+imported_model.last_error)
			check(FileAccess.get_sha256(path)==digest,name+" original bytes unchanged")
			if not loaded:continue
			check(imported_model.coins==int(original_save.coins) and imported_model.owned_parcels==original_save.owned_parcels,name+" wallet and ownership preserved")
			if name=="intentionally_bare_grass":check(imported_model.floor_finishes.is_empty(),"deliberate grass does not repaint during import")
			check(imported_model.save("user://imported.json"),name+" migrated save: "+imported_model.last_error)
			var new_save=JSON.parse_string(FileAccess.get_file_as_string("user://imported.json"))
			for field in original_save:
				if field in ["wall_format","shell_segment_format","shell_segment_products","shell_products","shell_material","built_walls","wall_attachment_format","wall_attachments"]:continue
				var expected=original_save[field]
				if field=="parking":
					check(same(expected,{"format":"little_leaf.parking.v1","owned":false,"paid_cost":0,"visits":[]}),name+" legacy parking fixture remains empty and unowned")
					expected=expected.duplicate(true)
					expected.format="little_leaf.parking.v2";expected["traffic"]=expected_initial_traffic
				check(new_save.has(field) and same(new_save[field],expected),name+" preserves "+field)
			check(FileAccess.get_sha256("user://imported.json.pre-grid-"+digest+".json")==digest,name+" original recovery copy is exact")
			var again=Model.new();check(again.load_save("user://imported.json"),name+" migrated reload: "+again.last_error)
			check(again.built_walls==imported_model.built_walls and again.wall_attachments==imported_model.wall_attachments,name+" modern building roundtrip")
			check(again.parking_owned==imported_model.parking_owned and again.parking_paid_cost==imported_model.parking_paid_cost and same(again.parking_visits,imported_model.parking_visits) and same(again.road_traffic_state,imported_model.road_traffic_state),name+" migrated parking and road state roundtrip")
	# Boundary fixtures modify copies only; original recovery inputs stay exact.
	var wide=JSON.parse_string(FileAccess.get_file_as_string(fixtures.path_join("historical.json")))
	wide.wall_attachments[0].width=1.5
	var fixture_file=FileAccess.open("user://wide-legacy.json",FileAccess.WRITE);fixture_file.store_string(JSON.stringify(wide));fixture_file.close()
	var wide_model=Model.new();check(wide_model.load_save("user://wide-legacy.json"),"wide legacy door loads without automatic narrowing")
	check(wide_model.wall_attachments.size()==1 and is_equal_approx(wide_model.wall_attachments[0].width,1.5) and wide_model.wall_attachments[0].wall_ids.size()==3,"legacy 1.5 aperture retains its three complete supports and one identity")
	check(wide_model.save("user://wide-modern.json"),"wide legacy opening saves in common format")
	var wide_again=Model.new();check(wide_again.load_save("user://wide-modern.json") and wide_again.wall_attachments==wide_model.wall_attachments,"wide legacy aperture roundtrips exactly")
	var paid=Model.new();check(paid.load_save(fixtures.path_join("inherited_extension_full.json")),"paid covered-ninth-wall fixture loads")
	var paid_balance=paid.coins
	check(paid.remove_wall("wall:41") and paid.coins==paid_balance+27,"selling the paid covering wall returns only its existing receipt")
	check(paid.get_wall("z:0:8").is_empty(),"selling paid ninth wall reveals no dormant free default")
	check(paid.save("user://paid-removed.json"),"removed paid edge saves")
	var paid_again=Model.new();check(paid_again.load_save("user://paid-removed.json") and paid_again.get_wall("z:0:8").is_empty(),"removed paid edge never resurrects after reload")
	# A corrupt existing original archive blocks the whole native save, including
	# an existing temporary target. It is never silently repaired or overwritten.
	var protected=Model.new();var source=fixtures.path_join("public_closed.json")
	check(protected.load_save(source),"native archive failure fixture imports")
	var protected_entry=transaction_state(protected);var protected_original=protected._legacy_building_original
	protected.begin_decoration_session();check(protected.place("plant",3,6),"protected archive draft uses a normal reversible purchase")
	var protected_draft=transaction_state(protected);var protected_baseline=protected._decoration_baseline.duplicate(true)
	var protected_receipts=protected.decoration_purchases.duplicate(true)
	fixture_file=FileAccess.open("user://protected.json",FileAccess.WRITE);fixture_file.store_string("original active bytes");fixture_file.close()
	fixture_file=FileAccess.open("user://protected.json.tmp",FileAccess.WRITE);fixture_file.store_string("original temporary bytes");fixture_file.close()
	var archive_path="user://protected.json.pre-grid-"+FileAccess.get_sha256(source)+".json"
	fixture_file=FileAccess.open(archive_path,FileAccess.WRITE);fixture_file.store_string("damaged archive evidence");fixture_file.close()
	check(not protected.save("user://protected.json"),"damaged archive stops native migration")
	check(FileAccess.get_file_as_string("user://protected.json")=="original active bytes" and FileAccess.get_file_as_string("user://protected.json.tmp")=="original temporary bytes" and FileAccess.get_file_as_string(archive_path)=="damaged archive evidence","archive failure preserves active, temporary and archive bytes")
	check(protected.last_error=="Original building backup differs; save left unchanged","draft save propagates the temporary baseline model's archive error")
	check(protected.decoration_session_active and same(transaction_state(protected),protected_draft) and same(protected._decoration_baseline,protected_baseline) and protected.decoration_purchases==protected_receipts,"archive failure retains live draft, entry baseline and receipts")
	check(protected._legacy_building_original==protected_original and protected._decoration_baseline.get("_legacy_building_original")==protected_original,"archive failure never consumes either original payload")
	var hybrid=wide.duplicate(true);hybrid.building_format=Codec.FORMAT
	fixture_file=FileAccess.open("user://hybrid.json",FileAccess.WRITE);fixture_file.store_string(JSON.stringify(hybrid));fixture_file.close()
	var live_before=JSON.stringify(protected.items)+JSON.stringify(protected.built_walls)
	check(not protected.load_save("user://hybrid.json") and JSON.stringify(protected.items)+JSON.stringify(protected.built_walls)==live_before,"mixed legacy/new markers reject before mutating the live model")
	check(protected.decoration_session_active and same(transaction_state(protected),protected_draft) and same(protected._decoration_baseline,protected_baseline) and protected._legacy_building_original==protected_original,"rejected load also retains draft baseline and raw provenance")
	check(protected.cancel_decoration_session() and same(transaction_state(protected),protected_entry) and protected._legacy_building_original==protected_original,"Cancel after failed draft save restores entry gameplay and provenance")
	check(FileAccess.get_file_as_string(archive_path)=="damaged archive evidence" and FileAccess.get_file_as_string("user://protected.json")=="original active bytes" and FileAccess.get_file_as_string("user://protected.json.tmp")=="original temporary bytes","Cancel does not repair the damaged archive or roll back protected files")
	for pending in [{"records":[{}]},{"dishwashing":{"dishes":[{}]}},{"staff":[{"job_kind":"cook","station_id":1}]}]:
		var busy_model=Model.new();Minimal.apply(busy_model);busy_model.set_operating_open(false);busy_model.service_snapshot=pending
		var stove={}
		for item in busy_model.items:
			if item.kind=="stove":stove=item;break
		check(not busy_model.remove(int(stove.id)) and not busy_model.get_item(int(stove.id)).is_empty(),"closed sale still protects pending guests/jobs/cleanup "+str(pending.keys()))
	# Full sell/rebuild cycle uses the production commands and retains land and
	# staffing. Included objects keep their historical resale rules.
	model=Model.new();Minimal.apply(model);model.set_operating_open(false)
	model.coins=200000;check(model.buy_parcel("front_0"),"purchase remains owned through rebuilding")
	var ownership=model.owned_parcels.duplicate();var roster=model.staff_roster().duplicate(true)
	var duties=model.duty_counts.duplicate(true);var payroll=model.payroll_accrued
	check(model.remove_wall_attachment(1),"sell starter door with the normal attachment command")
	for wall in model.built_walls.duplicate(true):check(model.remove_wall(Walls.key_of(wall)),"sell preset wall "+str(wall.id))
	for key in model.floor_finishes.keys():
		var parts=key.split(",");check(model.remove_floor(Vector2i(int(parts[0]),int(parts[1]))),"remove installed finish "+key)
	for item in model.items.duplicate(true):
		if not model.get_item(int(item.id)).is_empty():check(model.remove(int(item.id)),"sell closed furnishing "+str(item.kind)+": "+model.last_error)
	check(model.items.is_empty() and model.built_walls.is_empty() and model.wall_attachments.is_empty() and model.floor_finishes.is_empty(),"sell everything leaves no installed structure or furnishing")
	check(model.owned_parcels==ownership and model.staff_roster()==roster and model.duty_counts==duties and model.payroll_accrued==payroll,"selling buildings preserves owned grass and staff/progress")
	check(model.register_unplaced and not model.included_checkout_pending,"sold register retains one recoverable entitlement without auto-deployment")
	var snapshot=JSON.stringify(model.items)
	check(not model.ensure_basic_register() and JSON.stringify(model.items)==snapshot,"initial deployment retry cannot respawn a deliberately sold register")
	check(not model.set_operating_open(true) and not model.operating_open,"empty cafe can be edited but cannot reopen")
	check(model.save("user://grass.json"),"bare owned grass saves: "+model.last_error)
	restored=Model.new();check(restored.load_save("user://grass.json"),"bare owned grass reloads: "+restored.last_error)
	check(restored.items.is_empty() and restored.built_walls.is_empty() and restored.floor_finishes.is_empty() and restored.register_unplaced,"reload never fills deliberate empty cells or revives the register")
	model=restored
	for x in range(12):check(model.place_wall("x",x,0,"full","original"),"rebuild original catalog wall x "+str(x))
	for z in range(9):check(model.place_wall("z",0,z,"full","original"),"rebuild original catalog wall z "+str(z))
	var support=model.get_wall("z:0:5")
	check(model.place_wall_attachment("door",Walls.identity(support),.5),"rebuild door on ordinary installed wall")
	for z in range(9):
		for x in range(12):check(model.place_floor(Vector2i(x,z),"warm_oak"),"rebuild catalog floor")
	for spec in [["stove",8,1],["beverage",9,1],["sink",10,1],["counter",6,2],["register",6,4],["table",3,3],["chair",3,4]]:
		check(model.place(spec[0],spec[1],spec[2]),"rebuild furnishing "+spec[0]+": "+model.last_error)
	check(not model.register_unplaced and model.staff_roster()==roster,"reinstalling register does not hire or duplicate a cashier")
	check(model.set_operating_open(true),"complete catalog rebuild can reopen: "+model.last_error)
	check(model.save("user://rebuilt.json"),"complete rebuild saves: "+model.last_error)
	restored=Model.new();check(restored.load_save("user://rebuilt.json"),"complete rebuild reloads: "+restored.last_error)
	check(restored.owned_parcels==ownership and restored.items==model.items and restored.built_walls==model.built_walls,"rebuilt cafe reload preserves land and installed products")
	register_custody_transactions()
	migration_draft_transactions(fixtures.path_join("public_closed.json"),"legacy")
	var v1_source="res://tests/fixtures/unified_building_candidate.json"
	var v1_raw=FileAccess.get_file_as_string(v1_source);var v1_data=JSON.parse_string(v1_raw)
	check(v1_raw.to_utf8_buffer().size()==11909 and FileAccess.get_sha256(v1_source)=="8d4754ea928bed63ac95ff5bb84a9991e55572b88d80df5c82a008014c55eacd","grid-v1 transaction input is the full pinned 11,909-byte fixture")
	check(v1_data is Dictionary and v1_data.get("building_format")==Codec.PREVIOUS_FORMAT and v1_data.get("wall_format")==Codec.PREVIOUS_WALL_FORMAT,"grid-v1 fixture has real v1/3 markers, not relabeled v2 bytes")
	migration_draft_transactions(v1_source,"grid-v1")
	var capture=OS.get_environment("PRESET_CAPTURE").get_base_dir()
	if capture!="":
		for name in ["modern","grass","rebuilt"]:
			var file=FileAccess.open(capture.path_join("candidate-"+name+".json"),FileAccess.WRITE)
			file.store_string(FileAccess.get_file_as_string("user://"+name+".json"));file.close()
	print("UNIFIED_BUILDING_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"player_save_used":false,"runtime_integration":true}))
	quit(0 if failures.is_empty() else 1)

# Explicit persisted gameplay projection, independent of DECORATION_STATE, so a
# missing production snapshot key cannot make these comparisons pass silently.
func transaction_state(m)->Dictionary:
	var state={}
	for field in ["items","dining_sets","built_walls","wall_attachments","floor_style","floor_finishes",
		"coins","owned_parcels","cooks","waiters","cleaners","cashiers","duty_targets","duty_counts",
		"payroll_elapsed","payroll_accrued","wages_due","total_wages_paid","served","total_earned","total_cleaned",
		"_next_item_id","_next_customer_id","_next_wall_id","_next_attachment_id","next_checkout_ticket",
		"included_bin_pending","included_checkout_pending","register_unplaced","operating_open"]:
		var value=m.get(field)
		state[field]=value.duplicate(true) if value is Array or value is Dictionary else value
	state.staff_roster=m.staff_roster().duplicate(true)
	return state

func register_custody_transactions():
	var m=Model.new();Minimal.apply(m);m.set_operating_open(false);m.coins=200000
	check(m.buy_parcel("front_0"),"register transaction owns nondefault land before entry")
	var registers=m.items.filter(func(item):return item.kind=="register")
	check(registers.size()==1 and not m.register_unplaced and not m.included_checkout_pending,"register entry owns exactly one deployed entitlement")
	if registers.size()!=1:return
	var original_register=registers[0].duplicate(true);var entry=transaction_state(m)
	m.begin_decoration_session();var baseline=m._decoration_baseline.duplicate(true)
	check(m.remove(int(original_register.id)),"deployed-entry draft removes the real register")
	var unplaced=entry.duplicate(true);unplaced.items.erase(original_register);unplaced.register_unplaced=true
	check(same(transaction_state(m),unplaced),"register removal changes only installed custody, not wallet, land, roster, duties or IDs")
	check(m.save("user://register-removal-draft.json"),"deployed-entry draft baseline saves: "+m.last_error)
	var loaded=Model.new();check(loaded.load_save("user://register-removal-draft.json"),"deployed-entry draft destination actually reloads: "+loaded.last_error)
	check(same(transaction_state(loaded),entry) and not loaded.decoration_session_active,"deployed-entry durable state keeps exact entry register and false custody flag")
	check(m.decoration_session_active and same(transaction_state(m),unplaced) and same(m._decoration_baseline,baseline),"baseline persistence leaves removed-register draft and original baseline intact")
	check(m.cancel_decoration_session() and same(transaction_state(m),entry),"Cancel restores exact register, false flag, wallet, entitlement, roster, duties, land and IDs")
	check(not m.cancel_decoration_session() and same(transaction_state(m),entry),"duplicate deployed-entry Cancel changes nothing")
	m.begin_decoration_session();check(m.remove(int(original_register.id)),"Apply removes register through the normal command")
	m.finish_decoration_session()
	check(m.save("user://register-unplaced-entry.json"),"committed register removal saves: "+m.last_error)
	loaded=Model.new();check(loaded.load_save("user://register-unplaced-entry.json") and same(transaction_state(loaded),unplaced),"committed unplaced entry actually reloads without economic or staffing changes")
	m=loaded;entry=transaction_state(m);m.begin_decoration_session();baseline=m._decoration_baseline.duplicate(true)
	check(m.place("register",int(original_register.x),int(original_register.z),int(original_register.rot)),"unplaced-entry draft redeploys through normal placement")
	var deployed=transaction_state(m);var expected=entry.duplicate(true)
	var replacement=original_register.duplicate(true);replacement.id=entry._next_item_id
	expected.items.append(replacement);expected._next_item_id+=1;expected.register_unplaced=false
	check(same(deployed,expected) and m.items.filter(func(item):return item.kind=="register").size()==1,"redeployment creates one register and one ID, with no cashier, entitlement or economic gain")
	check(m.save("user://register-redeployment-draft.json"),"unplaced-entry draft baseline saves: "+m.last_error)
	loaded=Model.new();check(loaded.load_save("user://register-redeployment-draft.json"),"unplaced-entry draft destination actually reloads: "+loaded.last_error)
	check(same(transaction_state(loaded),entry) and loaded.register_unplaced and loaded.items.filter(func(item):return item.kind=="register").is_empty(),"unplaced-entry durable baseline has no register and true custody flag")
	check(m.decoration_session_active and same(transaction_state(m),deployed) and same(m._decoration_baseline,baseline),"unplaced-entry persistence leaves live redeployment and baseline intact")
	check(m.cancel_decoration_session() and same(transaction_state(m),entry),"Cancel redeployment restores true flag, no register and exact entry ownership")
	check(not m.cancel_decoration_session() and same(transaction_state(m),entry),"duplicate unplaced-entry Cancel changes nothing")
	m.begin_decoration_session();check(m.place("register",int(original_register.x),int(original_register.z),int(original_register.rot)),"Apply redeploys the retained register entitlement")
	m.finish_decoration_session();m.finish_decoration_session()
	check(not m.cancel_decoration_session() and same(transaction_state(m),deployed),"Apply ends custody transaction exactly once and keeps accepted redeployment")
	check(m.save("user://register-redeployment-applied.json"),"applied redeployment saves: "+m.last_error)
	loaded=Model.new();check(loaded.load_save("user://register-redeployment-applied.json") and same(transaction_state(loaded),deployed),"Apply reload keeps exactly one register, false flag and unchanged economic value")
	check(m._legacy_building_original=="" and Array(DirAccess.get_files_at("user://")).filter(func(name):return name.begins_with("register-redeployment-applied.json.pre-grid-")).is_empty(),"fresh v2 transaction save invents no original archive")

func migration_draft_transactions(source:String,label:String):
	# All destinations are disposable generated test files. Preserve full raw text,
	# including its whitespace, rather than re-stringifying the imported fixture.
	var raw=FileAccess.get_file_as_string(source);var digest=FileAccess.get_sha256(source)
	var prefix="user://"+label+"-transaction-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec())
	var path=prefix+".json";var alternate=prefix+"-alternate.json"
	var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(raw);file.close()
	check(FileAccess.get_file_as_string(path)==raw and FileAccess.get_sha256(path)==digest,label+" disposable import copy preserves the complete original bytes")
	var m=Model.new();var loaded_ok=m.load_save(path)
	check(loaded_ok,label+" actual original transaction payload loads: "+m.last_error)
	if not loaded_ok:return
	check(not m.operating_open and m._legacy_building_original==raw,label+" closed imported model owns exact original provenance")
	var entry=transaction_state(m);m.begin_decoration_session()
	check(m.place("plant",3,6),label+" draft makes a reversible production purchase")
	var draft=transaction_state(m);var baseline=m._decoration_baseline.duplicate(true)
	var receipts=m.decoration_purchases.duplicate(true);var draft_event=m.last_event
	check(draft.coins==entry.coins-m.price_of("plant") and not receipts.is_empty(),label+" draft changes wallet and has a live purchase receipt")
	for destination in [path,path,alternate]:
		check(m.save(destination),label+" draft baseline saves at "+destination+": "+m.last_error)
		var archive=destination+".pre-grid-"+digest+".json"
		check(FileAccess.get_file_as_string(archive)==raw and FileAccess.get_sha256(archive)==digest,label+" same and alternate destinations retain exact complete original archive")
		var durable=Model.new();check(durable.load_save(destination),label+" draft destination actually reloads: "+durable.last_error)
		check(same(transaction_state(durable),entry) and not durable.decoration_session_active and durable._legacy_building_original=="",label+" durable modern state contains only entry layout and wallet")
		var saved=JSON.parse_string(FileAccess.get_file_as_string(destination))
		check(saved is Dictionary and saved.get("building_format")==Codec.FORMAT and saved.get("wall_format")==Codec.WALL_FORMAT and not saved.has("_legacy_building_original"),label+" modern save does not serialize private raw provenance")
		check(m.decoration_session_active and same(transaction_state(m),draft) and same(m._decoration_baseline,baseline) and m.decoration_purchases==receipts and m.last_event==draft_event,label+" repeated baseline saves do not mutate live draft, receipt or baseline")
		check(m._legacy_building_original==raw and m._decoration_baseline.get("_legacy_building_original")==raw,label+" repeated baseline saves do not consume live or baseline provenance")
	var archive_path=path+".pre-grid-"+digest+".json";var alternate_archive=alternate+".pre-grid-"+digest+".json"
	var primary_bytes=FileAccess.get_file_as_string(path)
	check(m.cancel_decoration_session() and same(transaction_state(m),entry) and m._legacy_building_original==raw,label+" Cancel after successful draft saves restores gameplay and provenance")
	check(FileAccess.get_file_as_string(path)==primary_bytes and FileAccess.get_file_as_string(archive_path)==raw and FileAccess.get_file_as_string(alternate_archive)==raw,label+" Cancel keeps migrated disk bytes and both existing archives")
	# Corruption after successful persistence must still block, not repair or
	# consume provenance. The alternate primary and pre-existing temp are sentinels.
	m.begin_decoration_session();check(m.place("plant",3,6),label+" second draft before archive corruption")
	draft=transaction_state(m);baseline=m._decoration_baseline.duplicate(true);receipts=m.decoration_purchases.duplicate(true)
	var alternate_bytes=FileAccess.get_file_as_string(alternate)
	file=FileAccess.open(alternate+".tmp",FileAccess.WRITE);file.store_string("existing transaction temporary bytes");file.close()
	file=FileAccess.open(alternate_archive,FileAccess.WRITE);file.store_string("damaged after successful draft save");file.close()
	check(not m.save(alternate) and m.last_error=="Original building backup differs; save left unchanged",label+" later archive corruption propagates baseline error instead of bypassing backup")
	check(FileAccess.get_file_as_string(alternate)==alternate_bytes and FileAccess.get_file_as_string(alternate+".tmp")=="existing transaction temporary bytes" and FileAccess.get_file_as_string(alternate_archive)=="damaged after successful draft save",label+" post-success archive failure preserves primary, temp and damaged archive bytes")
	check(m.decoration_session_active and same(transaction_state(m),draft) and same(m._decoration_baseline,baseline) and m.decoration_purchases==receipts and m._legacy_building_original==raw,label+" post-success failure preserves cancelable draft, baseline, receipt and provenance")
	var rejected=prefix+"-rejected.json"
	file=FileAccess.open(rejected,FileAccess.WRITE);file.store_string("not a save");file.close()
	check(not m.load_save(rejected) and m.decoration_session_active and same(transaction_state(m),draft) and same(m._decoration_baseline,baseline) and m._legacy_building_original==raw,label+" rejected load cannot clear imported provenance or active transaction")
	check(m.cancel_decoration_session() and same(transaction_state(m),entry) and m._legacy_building_original==raw,label+" Cancel after failed draft save restores the exact imported entry")
	check(FileAccess.get_file_as_string(archive_path)==raw and FileAccess.get_sha256(archive_path)==digest and FileAccess.get_file_as_string(alternate_archive)=="damaged after successful draft save" and FileAccess.get_file_as_string(alternate)==alternate_bytes and FileAccess.get_file_as_string(alternate+".tmp")=="existing transaction temporary bytes",label+" failed-save Cancel retains recovery evidence without repairing or rolling back files")
	# Apply uses the existing finish-then-save boundary. Only this test-created
	# empty directory is removed for retry; no player path or archive is deleted.
	m.begin_decoration_session();check(m.place("plant",3,6),label+" Apply failure case purchases through normal command")
	draft=transaction_state(m);m.finish_decoration_session()
	check(not m.decoration_session_active and m._decoration_baseline.is_empty() and m.decoration_purchases.is_empty() and same(transaction_state(m),draft) and m._legacy_building_original==raw,label+" Apply accepts gameplay while retaining original provenance for immediate save")
	var applied=prefix+"-applied.json"
	file=FileAccess.open(applied,FileAccess.WRITE);file.store_string("previous applied primary bytes");file.close()
	var made_temp_directory=DirAccess.make_dir_absolute(applied+".tmp")==OK
	check(made_temp_directory,label+" test owns an empty .tmp directory to force an open failure")
	if not made_temp_directory:return
	check(not m.save(applied) and m.last_error=="Could not write the reconstructed save",label+" Apply immediate save reports forced primary temp-open failure")
	var applied_archive=applied+".pre-grid-"+digest+".json"
	check(FileAccess.get_file_as_string(applied_archive)==raw and FileAccess.get_sha256(applied_archive)==digest and FileAccess.get_file_as_string(applied)=="previous applied primary bytes" and DirAccess.dir_exists_absolute(applied+".tmp"),label+" exact archive completes before temp-open failure while old primary stays protected")
	check(not m.decoration_session_active and m._decoration_baseline.is_empty() and same(transaction_state(m),draft) and m._legacy_building_original==raw and not m.cancel_decoration_session(),label+" Apply failure keeps accepted live state and retry provenance, not a reopened session")
	var removed_temp_directory=DirAccess.remove_absolute(applied+".tmp")==OK
	check(removed_temp_directory,label+" retry removes only its own empty temp directory")
	if not removed_temp_directory:return
	check(m.save(applied),label+" accepted state retries successfully after temp-open failure: "+m.last_error)
	check(FileAccess.get_file_as_string(applied_archive)==raw and FileAccess.get_sha256(applied_archive)==digest and m._legacy_building_original==raw,label+" retry reuses exact archive without consuming provenance")
	var durable=Model.new();check(durable.load_save(applied) and same(transaction_state(durable),draft),label+" retry destination reloads the applied purchase and exact accepted wallet")
	check(not m.load_save(rejected) and same(transaction_state(m),draft) and m._legacy_building_original==raw,label+" rejected post-Apply load retains accepted state and provenance")
	check(m.load_save(applied) and same(transaction_state(m),draft) and m._legacy_building_original=="",label+" successful current-format load clears provenance through the existing lifecycle")
	var current=prefix+"-current.json"
	check(m.save(current),label+" reloaded current-format model saves without import provenance")
	check(Array(DirAccess.get_files_at("user://")).filter(func(name):return name.begins_with(current.get_file()+".pre-grid-")).is_empty(),label+" current-format save invents no original archive")
	check(m.load_save(source) and m._legacy_building_original==raw,label+" reset lifecycle starts with actual imported provenance again")
	m.begin_decoration_session();m.reset_new()
	check(m._legacy_building_original=="" and not m.decoration_session_active and m._decoration_baseline.is_empty(),label+" reset clears both original provenance and transaction baseline")
	check(FileAccess.get_sha256(source)==digest and FileAccess.get_file_as_string(source)==raw,label+" original fixture remains untouched after every transaction boundary")
