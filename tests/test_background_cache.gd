extends SceneTree
const Cache=preload("res://scripts/cafe_background_cache.gd")
const Neighborhood=preload("res://scripts/exterior_environment.gd")
class TestGame extends "res://scripts/main.gd":
	func _load_startup():
		save_writes_suppressed=true;fresh_start=true;model=Model.new();MinimalStart.apply(model)
	func _save():return true
	func _setup_music():pass
# Native CanvasItem calls are statically bound, so derive an instrumented copy
# of current source and redirect only its submission calls to recording methods.
# Geometry, colors, AA helpers and transforms remain the actual shipped code.
func recording_script():
	var script=GDScript.new()
	var code=FileAccess.get_file_as_string("res://scripts/illustrated_cafe.gd")
	for name in ["_ready","_draw","_process"]:code=code.replace("func "+name+"(","func disabled"+name+"(")
	for name in ["draw_set_transform_matrix","draw_rect","draw_mesh","draw_colored_polygon","draw_polyline","draw_line"]:code=code.replace(name+"(","record_"+name+"(")
	code+="""
var commands=[]
func record_draw_set_transform_matrix(value):commands.append(["transform",value])
func record_draw_rect(rect,color,_filled=true,_width=-1.0,_antialiased=false):commands.append(["rect",rect,color])
func record_draw_mesh(mesh,_texture,_transform=Transform2D.IDENTITY,_modulate=Color.WHITE):commands.append(["mesh",mesh.get_rid()])
func record_draw_colored_polygon(points,color,_uvs=PackedVector2Array(),_texture=null):commands.append(["polygon",points,PackedColorArray([color])])
func record_draw_polyline(points,color,width=-1.0,antialiased=false):commands.append(["polyline",points,PackedColorArray([color]),width,antialiased])
func record_draw_line(a,b,color,width=-1.0,antialiased=false):commands.append(["line",a,b,color,width,antialiased])
@warning_ignore("native_method_override")
func draw_mesh(mesh,_texture,_transform=Transform2D.IDENTITY,_modulate=Color.WHITE):record_draw_mesh(mesh,_texture,_transform,_modulate)
"""
	script.source_code=code
	check(script.reload()==OK,"instrument current source")
	return script
class ServerRecorder extends RefCounted:
	var commands=[]
	var operations=[]
	func canvas_item_create():
		var rid=RenderingServer.canvas_item_create();operations.append(["create",rid]);return rid
	func free_rid(rid):operations.append(["free",rid]);RenderingServer.free_rid(rid)
	func canvas_item_set_parent(rid,parent):operations.append(["parent",rid,parent])
	func canvas_item_set_draw_behind_parent(rid,value):operations.append(["behind",rid,value])
	func canvas_item_set_draw_index(rid,value):operations.append(["index",rid,value])
	func canvas_item_set_visible(rid,value):operations.append(["visible",rid,value])
	func canvas_item_clear(_rid):commands=[]
	func canvas_item_add_set_transform(_rid,value):commands.append(["transform",value])
	func canvas_item_add_rect(_rid,rect,color):commands.append(["rect",rect,color])
	func canvas_item_add_mesh(_rid,mesh):commands.append(["mesh",mesh])
	func canvas_item_add_polygon(_rid,points,colors):commands.append(["polygon",points,colors])
	func canvas_item_add_polyline(_rid,points,colors,width,antialiased):commands.append(["polyline",points,colors,width,antialiased])
	func canvas_item_add_line(_rid,a,b,color,width,antialiased):commands.append(["line",a,b,color,width,antialiased])
var checks=0
var failures=[]
func check(ok,label):
	checks+=1
	if not ok and failures.size()<30:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func original(art):
	art.commands=[]
	var size=art.get_viewport_rect().size
	art.record_draw_rect(Rect2(Vector2.ZERO,size),Color("c6d5ad"))
	art._grass(size);Neighborhood.draw_ground(art);art.ground_art.draw_pavement(art);Neighborhood.draw_crossing(art)
func settle(art):
	for frame in 8:art._process(1.0/60);await process_frame
func run():
	var game=TestGame.new();root.add_child(game);game.set_process(false);game.cafe_intro.finish();game.paused=true;game.illustration.set_process(false)
	for tween in get_processed_tweens():tween.kill()
	var art=recording_script().new();art.game=game;root.add_child(art);art.ground_art.prepare(game.model)
	var cache=Cache.new();var server=ServerRecorder.new();cache.server=server
	var cases=0
	for size in [Vector2i(390,844),Vector2i(1360,880),Vector2i(844,390)]:
		root.size=size
		for scale in [.25,.5,1.0,2.0,4.0]:
			for detail in [false,true]:
				game.wall_detail=detail
				for origin in [Vector2.ZERO,Vector2(390,250),Vector2(-1100,-700)]:
					for opacity in [1.0,.4]:
						art.origin=origin;art.tile=Vector2(39,19.5)*scale;art.ui_scale=.8;art.zoom=scale;art.opacity=opacity
						original(art)
						var previous_rebuilds=cache.rebuilds
						check(cache.update(art),"cache eligible")
						check(art.commands==server.commands,"exact ordered native command parity %s"%[cases])
						check(cache.command_count==art.commands.size(),"command count")
						check(cache.rebuilds==previous_rebuilds+1,"changed projection or opacity rebuilds exactly once")
						var before=cache.rebuilds
						check(cache.update(art) and cache.rebuilds==before,"stable update retains commands")
						cases+=1
	check(server.operations[1]==["parent",cache.canvas,art.get_canvas_item()],"parent inherits transform visibility modulate and z")
	check(server.operations[2]==["behind",cache.canvas,true] and server.operations[3]==["index",cache.canvas,-1],"prefix precedes original dynamic commands")
	var before=cache.rebuilds
	game.animation_time+=1;game.model.revision+=1;art.ground_art.prepare(game.model)
	cache.update(art);check(cache.rebuilds==before,"simulation and unchanged terrain do not rebuild background")
	for property in ["material","use_parent_material","self_modulate","clip_children","light_mask","visibility_layer","y_sort_enabled","use_batched_ground","use_grass_mesh","transform"]:
		var old=art.get(property)
		var value={"material":CanvasItemMaterial.new(),"use_parent_material":true,"self_modulate":Color(.8,1,1),"clip_children":CanvasItem.CLIP_CHILDREN_AND_DRAW,"light_mask":2,"visibility_layer":2,"y_sort_enabled":true,"use_batched_ground":false,"use_grass_mesh":false,"transform":Transform2D(0,Vector2(2,2))}[property]
		art.set(property,value)
		check(not cache.update(art) and not cache.used,"fallback "+property)
		check(server.operations.back()==["visible",cache.canvas,false],"fallback hides retained prefix "+property)
		art.set(property,old);check(cache.update(art),"restore "+property)
	art.ground_art.use_stroke_mesh=false;check(not cache.update(art),"legacy strokes fall back");art.ground_art.use_stroke_mesh=true
	cache.update(art);before=cache.rebuilds
	art.ground_art.pavement_stroke_mesh=null
	cache.update(art);check(cache.rebuilds==before+1,"stroke resource replacement invalidates")
	before=cache.rebuilds;art.use_screen_culling=not art.use_screen_culling
	cache.update(art);check(cache.rebuilds==before+1,"culling switch invalidates")
	before=cache.rebuilds;art.grass_mesh=null
	cache.update(art);check(cache.rebuilds==before+1,"grass resource replacement invalidates")
	before=cache.rebuilds;art.ground_art._build_pavement()
	cache.update(art);check(cache.rebuilds==before+1,"pavement resource replacement invalidates")
	before=cache.rebuilds
	art.modulate=Color(.5,.6,.7,.8);art.visible=false;art.z_index=3
	cache.update(art);check(cache.rebuilds==before,"inherited modulate visibility and z do not rebuild")
	art.modulate=Color.WHITE;art.visible=true;art.z_index=0
	cache.hide();check(not cache.used,"hide disables prefix");cache.update(art)
	var old_rid=cache.canvas;cache.release();check(not cache.canvas.is_valid() and cache.signature.is_empty() and not cache.used,"release clears lifetime state")
	check(server.operations.back()==["free",old_rid],"release frees native resource")
	var operations=server.operations.size();cache.release();check(server.operations.size()==operations,"release idempotent")
	check(cache.update(art) and cache.rebuilds==before+1,"recreate rebuilds after release")
	cache.release();art.free()
	# Actual game draw path: compatibility changes must wake settled idle art.
	var live=game.illustration;game.wall_detail=false;await settle(live)
	for tween in get_processed_tweens():tween.kill()
	await settle(live)
	check(live.background_cache.used,"real draw uses retained background")
	for property in ["material","use_parent_material","self_modulate","clip_children","light_mask","visibility_layer","y_sort_enabled"]:
		var old=live.get(property)
		var value={"material":CanvasItemMaterial.new(),"use_parent_material":true,"self_modulate":Color(.8,1,1),"clip_children":CanvasItem.CLIP_CHILDREN_AND_DRAW,"light_mask":2,"visibility_layer":2,"y_sort_enabled":true}[property]
		live.set(property,value);await settle(live);check(not live.background_cache.used,"idle fallback "+property)
		live.set(property,old);await settle(live);check(live.background_cache.used,"idle restore "+property)
	before=live.background_cache.rebuilds
	for frame in 60:live._process(1.0/60);await process_frame
	check(live.background_cache.rebuilds==before,"settled frames do not rebuild")
	live.use_background_cache=false;await settle(live);check(not live.background_cache.used,"idle switch off")
	live.use_background_cache=true;await settle(live);check(live.background_cache.used,"idle switch on")
	live.icon_kind="chair";live.queue_redraw();await process_frame;await process_frame
	check(not live.background_cache.used,"repurposed icon hides background")
	live.icon_kind="";live.queue_redraw();await process_frame;await process_frame
	check(live.background_cache.used,"world restores background")
	live.game=null;live.queue_redraw();await process_frame;await process_frame
	check(not live.background_cache.used,"invalid game hides background")
	live.game=game;live.queue_redraw();await process_frame;await process_frame
	check(live.background_cache.used,"valid game restores background")
	var timed=Cache.new();timed.update(live)
	var start=Time.get_ticks_usec()
	for frame in 100:timed.signature=[];timed.update(live)
	var rebuild_us=Time.get_ticks_usec()-start
	start=Time.get_ticks_usec()
	for frame in 100:timed.update(live)
	var retained_us=Time.get_ticks_usec()-start
	timed.release()
	var held=live.background_cache
	game.remove_child(live);check(not held.canvas.is_valid(),"exit tree frees RID")
	game.add_child(live);await settle(live);check(held.canvas.is_valid() and held.used,"reenter recreates RID")
	var doomed=Cache.new();doomed.update(live);var destructor_rid=doomed.canvas
	var destructor_server=ServerRecorder.new();doomed.server=destructor_server;doomed=null
	check(destructor_server.operations==[["free",destructor_rid]],"unreleased cache destructor frees RID once")
	game.queue_free();await process_frame;check(not held.canvas.is_valid(),"owner free releases RID")
	print("BACKGROUND_CACHE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"parity_cases":cases,"headless_100_rebuild_us":rebuild_us,"headless_100_retained_us":retained_us}));quit(0 if failures.is_empty() else 1)
