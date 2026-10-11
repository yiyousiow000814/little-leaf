extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
const Contract=preload("res://scripts/cafe_save_contract.gd")
const Main=preload("res://scripts/main.gd")
const Review=preload("res://scripts/cafe_reception_review.gd")
var checks=0
var failures=[]
func _initialize():
	create_timer(30).timeout.connect(func():printerr("RECEPTION_PROTOCOL_TIMEOUT");quit(2))
	run.call_deferred()
func check(ok,label):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func fresh():
	var m=Model.new();check(m.enable_reception_review(),"fresh scoped activation: "+m.last_error);return m
func state(m):
	return JSON.stringify(Model.RuntimeCodec.new().encode([m.reception_review_enabled,m.reception_visits,m.departing_bodies,m.items,m.customers,m.outside_queue,m.parking_visits,m.service_snapshot,m.dining_sets,m.coins,m.served,m.total_earned,m.total_cleaned,m._next_item_id,m._next_customer_id,m._arrival_elapsed,m._walking_customer_id,m.next_checkout_ticket,m.loaded_save_version]))
func write(path,data):
	var f=FileAccess.open(path,FileAccess.WRITE);assert(f!=null);f.store_string(JSON.stringify(data));f.close()
func refuse(m,raw,label):
	var path="user://invalid-reception.json";write(path,raw)
	var hash=FileAccess.get_sha256(path);var before=state(m)
	check(not m.load_reception(path),label+" refuses")
	check(state(m)==before and FileAccess.get_sha256(path)==hash,label+" atomic state and bytes")
func run():
	check(Review.scope_allowed() and "saveguard" in OS.get_user_data_dir(),"dedicated disposable native scope")
	check(Contract.VERSION==15 and Contract.PRIMARY_FILE=="user://little_leaf_cafe_layout_motion_v15.json","default contract remains15")
	var ordinary=Model.new()
	check(not ordinary.reception_review_enabled and not Model.Reception.add(ordinary),"default does not activate reception")
	check(ordinary.save("user://ordinary-control.json"),"ordinary15 synthetic writer retained")
	var control_hash=FileAccess.get_sha256("user://ordinary-control.json")
	var control=JSON.parse_string(FileAccess.get_file_as_string("user://ordinary-control.json"))
	var primary=Contract.PRIMARY_FILE;write(primary,control);var primary_hash=FileAccess.get_sha256(primary)
	var m=fresh();var path=Contract.RECEPTION_REVIEW_FILE
	check(m.save_reception(path),"empty enabled18 snapshot saves: "+m.last_error)
	if not FileAccess.file_exists(path):quit(1);return
	var raw=JSON.parse_string(FileAccess.get_file_as_string(path));var hash=FileAccess.get_sha256(path)
	check(int(raw.version)==18 and raw.reception_review_format==Contract.RECEPTION_REVIEW_FORMAT and raw.reception.format==Contract.RECEPTION_FORMAT,"separate exact18 envelope")
	check(not Contract.accepts_header(raw) and Contract.accepts_header(raw,true),"ordinary header refuses18")
	check(not ordinary.load_save(path),"ordinary API refuses private filename")
	check(not m.save(primary) and not m.load_save(primary),"enabled empty mode refuses ordinary APIs")
	for protected in Review.PROTECTED:
		check(not m.save_reception("user://"+protected) and not m.load_reception("user://"+protected),"protected read/write "+protected)
	for historical in [Main.RECENT_SAVE_FILE,Main.LEGACY_SAVE_FILE,Main.OLDER_SAVE_FILE,Main.OLDEST_SAVE_FILE,Main.HISTORICAL_SAVE_FILE]:
		check(not Review.path_allowed(historical) and not Review.path_allowed(historical+".tmp",true),"actual Main historical target and temp refused "+historical)
		check(not m.save_reception(historical) and not m.load_reception(historical) and not FileAccess.file_exists(historical) and not FileAccess.file_exists(historical+".tmp"),"historical refusals create no generated target/temp "+historical)
	var before=state(m)
	check(m.load_reception(path),"exact18 load")
	var loaded=state(m)
	for repeat in range(3):check(m.load_reception(path) and state(m)==loaded,"repeated load does not append/reset claims "+str(repeat))
	check(FileAccess.get_sha256(path)==hash,"load never rewrites snapshot")
	for version in [1,2,14,15,16,17,19]:
		var bad=raw.duplicate(true);bad.version=version;refuse(m,bad,"wrong version "+str(version))
	refuse(m,control,"copied authentic15 cannot promote")
	for marker in ["reception_review_format","reception_format","reception"]:
		var bad=raw.duplicate(true);bad.erase(marker);refuse(m,bad,"missing "+marker)
	for marker in ["reception_review_format","reception_format"]:
		var bad=raw.duplicate(true);bad[marker]="unknown";refuse(m,bad,"unknown "+marker)
	var bad=raw.duplicate(true);bad.reception.format="little_leaf.reception.v1";refuse(m,bad,"receptionv1 unsupported")
	bad=raw.duplicate(true);bad.reception.erase("departures");refuse(m,bad,"missing departures")
	for marker in ["navigation_format","footprint_placement_format","reception_format","reception_review_format","navigation_phase"]:
		bad=raw.duplicate(true);bad.runtime[marker]="foreign";refuse(m,bad,"runtime foreign "+marker)
	for version in [1,2,15]:
		bad=control.duplicate(true);bad.version=version;bad.reception={}
		check(not Contract.accepts_header(bad),"early legacy path refuses ledger "+str(version))
		bad.erase("reception");bad.runtime["nested"]={"reception_review_format":"foreign"}
		check(not Contract.accepts_header(bad),"early legacy nested refusal "+str(version))
	var temporary=path+".tmp";FileAccess.open(temporary,FileAccess.WRITE).store_string("interrupted staging bytes")
	check(m.load_reception(path) and FileAccess.get_sha256(path)==hash,"interrupted temp does not replace/read committed snapshot")
	FileAccess.open("user://truncated.json",FileAccess.WRITE).store_string("{")
	before=state(m);check(not m.load_reception("user://truncated.json") and state(m)==before,"interrupted input leaves state atomic")
	check(m.save_reception(path) and JSON.parse_string(FileAccess.get_file_as_string(path))==raw,"repeated write replaces atomically with equivalent snapshot")
	hash=FileAccess.get_sha256(path)
	# A directory occupying the temp name simulates a failed write/finalize path.
	DirAccess.remove_absolute(temporary);DirAccess.make_dir_absolute(temporary)
	before=state(m);check(not m.save_reception(path) and state(m)==before and FileAccess.get_sha256(path)==hash,"failed staging leaves previous save and model unchanged")
	DirAccess.remove_absolute(temporary)
	var data=Review.canonical(OS.get_user_data_dir());var root_scope=OS.get_environment("LL_RECEPTION_REVIEW_ROOT")
	for outside in [data+"-sibling/file.json",root_scope+"/outside.json",data+"/../outside.json"]:
		check(not Review.path_allowed(outside),"component containment refuses "+outside)
	check(Review.path_allowed(data+"/./alias.json"),"dot alias resolves inside verified parent")
	if OS.get_name()=="Windows":
		check(Review.path_allowed(data.to_upper().replace("/","\\")+"\\alias.json"),"case separator alias remains scoped")
	check(not Review.path_allowed(data+"/escape/escaped.json"),"reparse ancestor escape refused")
	OS.set_environment("LL_RECEPTION_REVIEW_ROOT",root_scope+"-sibling")
	before=state(m);check(not m.load_reception(path) and not m.save_reception(path) and state(m)==before,"each API independently rechecks scope")
	var refused=Model.new();check(not refused.enable_reception_review() and not refused.reception_review_enabled,"enable fails without mutation on invalid scope")
	OS.set_environment("LL_RECEPTION_REVIEW_ROOT",root_scope)
	check(FileAccess.get_sha256(primary)==primary_hash,"synthetic default save never modified")
	check(FileAccess.get_sha256("user://ordinary-control.json")==control_hash,"original control bytes unchanged")
	print("RECEPTION_PRIVATE_CONTRACT_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
