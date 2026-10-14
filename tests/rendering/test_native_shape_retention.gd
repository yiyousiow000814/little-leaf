extends SceneTree
const FloorSnapshot=preload("res://scripts/rendering/floor_state_diagnostics.gd")
const FloorModel=preload("res://scripts/core/cafe_model.gd")
const Ground=preload("res://scripts/rendering/illustrated_ground.gd")
const Shape=preload("res://scripts/rendering/cafe_shape_2d.gd")
class FloorGame extends RefCounted:
	var model=FloorModel.new()
class FloorArtist extends Node2D:
	var game=FloorGame.new()
	var ground_art=Ground.new()
	var native_world_shapes={}
	var use_batched_ground=true
	var use_native_object_nodes=true
	var use_command_retention=true
	var use_retained_geometry=true
	var icon_kind=""
	var canvas_stream=preload("res://scripts/rendering/retained_canvas_stream.gd").new()
class FakeWebDiagnostic extends RefCounted:
	var latest_json=""
	var disposals=0
	func dispose():disposals+=1;latest_json=""
class CaptureMain extends "res://scripts/main.gd":
	var capture_save_calls=0
	func _ready():pass
	func _save():capture_save_calls+=1;return true
class CountingShape extends "res://scripts/rendering/cafe_shape_2d.gd":
	var draws=0
	func _draw():
		draws+=1
		super._draw()
var checks=0
var failures=[]
func check(condition:bool,label:String):
	checks+=1
	if not condition:failures.append(label);printerr("FAIL ",label)
func _init():run.call_deferred()
func settle():
	for frame in 3:await process_frame
func run():
	var shape=CountingShape.new();root.add_child(shape)
	var points=PackedVector2Array([Vector2(10,10),Vector2(40,10),Vector2(40,40),Vector2(10,40)])
	shape.configure(&"draw_colored_polygon",[points,Color.WHITE],Transform2D.IDENTITY)
	points.append(points[0])
	check(shape.draw_arguments[0].size()==4,"outline closure cannot mutate cached fill")
	await settle()
	check(shape.draws==1,"initial native draw recorded once")
	var unchanged=PackedVector2Array([Vector2(10,10),Vector2(40,10),Vector2(40,40),Vector2(10,40)])
	shape.configure(&"draw_colored_polygon",[unchanged,Color.WHITE],Transform2D(0,Vector2(20,30)))
	unchanged.append(unchanged[0])
	await settle()
	check(shape.draws==1,"same fill and moved transform retain native commands")
	var changed=PackedVector2Array([Vector2(10,10),Vector2(45,10),Vector2(40,40),Vector2(10,40)])
	shape.configure(&"draw_colored_polygon",[changed,Color.WHITE],Transform2D.IDENTITY)
	changed[1]=Vector2(90,10)
	await settle()
	check(shape.draws==2,"actual geometry change redraws once")
	check(shape.draw_arguments[0][1]==Vector2(45,10),"later edits cannot change submitted geometry")
	var colors=PackedColorArray([Color.WHITE]);var uvs=PackedVector2Array([Vector2.ZERO])
	var texture=ImageTexture.new()
	shape.configure(&"draw_polygon",[changed,colors,uvs,texture],Transform2D.IDENTITY)
	colors[0]=Color.RED;uvs[0]=Vector2.ONE
	check(shape.draw_arguments[1][0]==Color.WHITE,"color array has independent ownership")
	check(shape.draw_arguments[2][0]==Vector2.ZERO,"UV array has independent ownership")
	check(shape.draw_arguments[3]==texture,"texture resource is retained without duplication")
	shape.free()
	await _check_floor_diagnostics()
	print("NATIVE_SHAPE_RETENTION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _add_floor(artist,order):
	var node=Shape.new();artist.add_child(node)
	node.set_meta("generation",artist.canvas_stream.frame_id)
	node.configure(&"draw_mesh",[artist.ground_art.floor_mesh,null],Transform2D.IDENTITY)
	artist.native_world_shapes[order]=node
	return node
func _check_floor_diagnostics():
	var artist=FloorArtist.new();root.add_child(artist)
	artist.canvas_stream.begin(artist,true)
	var model=artist.game.model;model.coins=10000000
	check(model.buy_parcel("front_0"),"synthetic land bought")
	check(model.place_floor(Vector2i(0,9),"cream_tile"),"white tile in expansion")
	check(model.place_floor(Vector2i(3,4),"cream_tile"),"white tile in original land")
	artist.ground_art.prepare(model);var node=_add_floor(artist,20)
	await process_frame
	var records_before=model.floor_finishes.duplicate(true)
	var mesh_before=artist.ground_art.floor_mesh
	var healthy=FloorSnapshot.capture(artist)
	check(healthy.model.styles.cream_tile==2,"both white tile regions counted")
	check(healthy.model.regions.base.styles.cream_tile==1 and healthy.model.regions.expansion.styles.cream_tile==1,"model original and expansion split")
	check(healthy.mesh.regions.base.cream_tile==4 and healthy.mesh.regions.expansion.cream_tile==4 and healthy.mesh.regions_complete,"cached mesh original and expansion split")
	check(healthy.mesh.style_vertices.cream_tile==8,"mesh white vertices counted")
	check(healthy.model.record_count==109,"all floor records counted")
	check(healthy.model.owned_count==117,"owned land includes bare purchased cells")
	check(healthy.observations.is_empty(),"healthy state has no mismatch observation")
	check(healthy.native.visible==1 and healthy.native.matching==1,"completed native floor node detected")
	check(healthy.ground.model_matches,"cache owner identity matches")
	check(model.floor_finishes==records_before and artist.ground_art.floor_mesh==mesh_before,"capture is read-only")
	var again=FloorSnapshot.capture(artist)
	check(again.model.content_hash==healthy.model.content_hash and again.mesh.geometry_hash==healthy.mesh.geometry_hash,"stable hashes across repeated capture")
	model.floor_finishes.erase("3,4")
	var data_loss=FloorSnapshot.capture(artist)
	check(data_loss.model.styles.cream_tile==1 and data_loss.mesh.style_vertices.cream_tile==8,"data mutation separated from retained mesh")
	check(data_loss.observations.has("terrain_cache_content_differs"),"silent change catches cache mismatch without revision change")
	check(data_loss.observations.has("mesh_style_count_differs:cream_tile"),"style mismatch observed")
	check(data_loss.model.content_hash!=healthy.model.content_hash and data_loss.mesh.geometry_hash==healthy.mesh.geometry_hash,"data hash changes while mesh hash stays stable")
	model.floor_finishes=records_before.duplicate(true)
	model.floor_finishes["0,9"].style="warm_oak"
	model.floor_finishes["2,3"].style="cream_tile"
	var regional=FloorSnapshot.capture(artist)
	check(regional.model.styles==healthy.model.styles,"regional mutation keeps global style counts equal")
	check(regional.observations.has("mesh_region_style_differs:base:cream_tile") and regional.observations.has("mesh_region_style_differs:expansion:cream_tile"),"region mismatch distinguishes original footprint from expansion")
	check(not regional.observations.has("mesh_style_count_differs:cream_tile"),"global count does not invent a mismatch")
	model.floor_finishes=records_before.duplicate(true)
	artist.canvas_stream.finish()
	check(not artist.canvas_stream.active,"actual stream finish closes submission")
	node.hide();var hidden=FloorSnapshot.capture(artist)
	check(hidden.native.expected and not hidden.native.submission_active,"native expectation survives completed frame")
	check(hidden.model.content_hash==healthy.model.content_hash and hidden.mesh.geometry_hash==healthy.mesh.geometry_hash,"hidden node preserves data and geometry hashes")
	check(hidden.native.matching==1 and hidden.native.visible==0,"hidden node remains observable")
	check(hidden.observations.has("visible_native_floor_count_differs"),"missing visibility distinguished")
	node.show();node.material=CanvasItemMaterial.new()
	var material=FloorSnapshot.capture(artist)
	check(material.native.nodes[0].material_instance!="","unexpected floor material recorded without mutation")
	node.material=null
	var replacement=FloorModel.new();replacement.revision=model.revision;artist.game.model=replacement
	var replaced=FloorSnapshot.capture(artist)
	check(not replaced.ground.model_matches,"same-revision model replacement distinguished")
	check(replaced.model.instance!=healthy.model.instance,"runtime model identity recorded")
	check(healthy.model.instance is String and healthy.mesh.instance is String and healthy.native.nodes[0].instance is String,"64-bit identities remain exact through browser JSON")
	check(replaced.observations.has("terrain_cache_model_differs"),"cache ownership mismatch observed")
	artist.game.model=model
	for order in range(21,27):_add_floor(artist,order)
	var duplicate=FloorSnapshot.capture(artist)
	check(duplicate.native.matching==7 and duplicate.native.nodes.size()==4,"node records bounded while full counts preserved")
	check(duplicate.observations.has("visible_native_floor_count_differs"),"duplicate floor nodes distinguished")
	var saved_shapes=artist.native_world_shapes.duplicate()
	for order in range(30,4130):artist.native_world_shapes[order]=node
	var capped=FloorSnapshot.capture(artist)
	check(capped.native.scanned==4096 and not capped.native.scan_complete,"oversized native scan capped with explicit incompleteness")
	check(capped.native.nodes.size()==4,"oversized node output remains bounded")
	check(not capped.observations.has("visible_native_floor_count_differs"),"incomplete scan never claims exact floor-node count")
	artist.native_world_shapes=saved_shapes
	artist.use_native_object_nodes=false
	check(not FloorSnapshot.capture(artist).observations.has("visible_native_floor_count_differs"),"non-native fallback does not report missing native floor")
	artist.use_native_object_nodes=true
	var payload=JSON.stringify(healthy)
	for forbidden in ["coins","profile","account","save_payload","floor_finishes","owned_parcels"]:check(not forbidden in payload,"no private/raw field "+forbidden)
	var total=0
	for sample in 100:
		var receipt=FloorSnapshot.capture(artist);total+=int(receipt.capture_usec)
	var controller=CaptureMain.new();root.add_child(controller);controller.set_process(false)
	controller.model=model;controller.illustration=artist
	check(controller._diagnostics_mode([])=="","diagnostics disabled by default")
	check(controller._diagnostics_mode(["--capture-diagnostics"])=="runtime","legacy opt-in retained")
	check(controller._diagnostics_mode(["--floor-diagnostics"])=="floor","floor mode requires explicit opt-in")
	check(controller._diagnostics_mode(["--floor-diagnostics","--capture-diagnostics"])=="floor","read-only floor mode wins when both flags supplied")
	controller._start_floor_diagnostic_web()
	check(not controller.has_meta("floor_diagnostic_web_api") and not controller.has_meta("floor_diagnostic_web_callback"),"native/default mode installs no web callback")
	controller._capture()
	check(not controller.has_meta("floor_diagnostic_previous") and controller.capture_save_calls==0,"disabled/headless capture performs no collection or save")
	var isolated="saveguard" in OS.get_user_data_dir() or "floor-diagnostics" in OS.get_user_data_dir()
	check(isolated,"diagnostic writer test uses disposable profile")
	if isolated:
		for order in artist.native_world_shapes.keys():
			if order==20:continue
			artist.native_world_shapes[order].free();artist.native_world_shapes.erase(order)
		var web_packet=FakeWebDiagnostic.new()
		controller.set_meta("floor_diagnostic_web_api",web_packet)
		controller.set_meta("floor_diagnostic_web_callback",func(_arguments:Array):pass)
		var image=Image.create(4,4,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
		check(controller._write_diagnostic_capture(image,"floor"),"read-only floor capture writes synthetic image and packet")
		var path="user://diagnostics/floor_diagnostics.json"
		var first=JSON.parse_string(FileAccess.get_file_as_string(path))
		check(web_packet.latest_json==FileAccess.get_file_as_string(path),"browser packet equals bounded file receipt")
		check(first.floor.current.model.styles.cream_tile==2 and first.floor.previous.is_empty(),"first capture has no invented previous record")
		model.floor_finishes.erase("3,4")
		check(controller._write_diagnostic_capture(image,"floor"),"second floor capture succeeds")
		var second=JSON.parse_string(FileAccess.get_file_as_string(path))
		check(second.floor.previous.model.styles.cream_tile==2 and second.floor.current.model.styles.cream_tile==1,"current and previous counts expose the transition")
		model.floor_finishes=records_before.duplicate(true)
		check(controller._write_diagnostic_capture(image,"floor"),"third floor capture succeeds")
		var text=FileAccess.get_file_as_string(path);var third=JSON.parse_string(text)
		check(third.floor.previous.model.styles.cream_tile==1 and third.floor.current.model.styles.cream_tile==2,"only immediately previous snapshot retained")
		check(third.floor.size()==2 and not third.floor.previous.has("previous"),"capture history is bounded without nested packets")
		check(controller.capture_save_calls==0,"all floor captures bypass progress saving")
		for forbidden in ["coins","served","account","profile","floor_finishes","owned_parcels"]:
			check(not forbidden in text,"floor packet excludes legacy/private field "+forbidden)
		var previous_hash=FileAccess.get_sha256(path)
		check(not controller._write_diagnostic_capture(image,"disabled"),"unrecognized mode cannot capture")
		check(FileAccess.get_sha256(path)==previous_hash and controller.capture_save_calls==0,"disabled writer preserves files and save state")
		check(controller._write_diagnostic_capture(image,"runtime") and controller.capture_save_calls==1,"legacy runtime capture still uses its prior save path")
		check(FileAccess.get_sha256(path)==previous_hash,"legacy capture cannot replace floor evidence")
		check(web_packet.latest_json==text,"legacy mode cannot overwrite developer floor packet")
		controller._stop_floor_diagnostic_web()
		controller._stop_floor_diagnostic_web()
		check(web_packet.disposals==1 and not controller.has_meta("floor_diagnostic_web_api") and not controller.has_meta("floor_diagnostic_web_callback"),"web cleanup detaches once before releasing callback")
		var result_path=OS.get_environment("LL_UI_RESULT")
		if result_path!="":
			FileAccess.open(result_path,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"sample":healthy,"transition":second.floor,"mean_capture_usec_100":float(total)/100,"player_save_used":false,"scope":"synthetic headless diagnostic correctness; no GPU/fix claim"},"  "))
	controller.people.free();controller.ui.free();controller.queue_free()
	artist.queue_free();await process_frame
