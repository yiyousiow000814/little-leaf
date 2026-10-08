extends SceneTree
class TestGame extends "res://scripts/main.gd":
	func _load_startup():
		save_writes_suppressed=true;fresh_start=true;model=Model.new();MinimalStart.apply(model)
	func _save():return true
	func _setup_music():pass
class UnknownController extends Node:
	var paused=true
	var editing=false
var checks=0
var failures=[]
var game
var draws=0
func check(ok,label):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func settle():
	for frame in 8:
		game.illustration._process(1.0/60);await process_frame
func changed(label,mutate:Callable,restore:Callable):
	var idle=game.illustration.render_idle
	idle.invalidate();check(idle.needs_redraw(game.illustration),label+" initial")
	check(not idle.needs_redraw(game.illustration),label+" stable")
	mutate.call();check(idle.needs_redraw(game.illustration),label+" invalidates")
	restore.call();check(idle.needs_redraw(game.illustration),label+" restores")
func run():
	root.size=Vector2i(390,844);game=TestGame.new();root.add_child(game);game.set_process(false)
	game.cafe_intro.finish();game.paused=true;game.illustration.set_process(false)
	for tween in get_processed_tweens():tween.kill()
	await settle()
	for tween in get_processed_tweens():tween.kill()
	game.illustration.draw.connect(func():draws+=1)
	await settle();var before=draws
	for frame in 60:game.illustration._process(1.0/60);await process_frame
	check(draws==before,"settled paused world retains canvas commands for60frames")
	for frame in 30:game._process(1.0/60);game.illustration._process(1.0/60);await process_frame
	for tween in get_processed_tweens():tween.kill()
	await settle();before=draws
	for frame in 60:game._process(1.0/60);game.illustration._process(1.0/60);await process_frame
	check(draws==before,"normal main UI ticks preserve settled paused canvas")
	var art=game.illustration;var m=game.model;var idle=art.render_idle
	changed("animation clock",func():game.animation_time+=.5,func():game.animation_time-=.5)
	changed("deep item mutation",func():m.items[0].rot+=1,func():m.items[0].rot-=1)
	changed("staff action",func():game.staff_states[0].art_action="blocked",func():game.staff_states[0].art_action="idle")
	changed("deep service record",func():game.service_guests[-44]={"plate_remaining":.5},func():game.service_guests.erase(-44))
	changed("floor mess",func():game.floor_tasks.messes[-44]={"remaining":.5},func():game.floor_tasks.messes.erase(-44))
	changed("dish queue",func():game.dishwashing.dishes[-44]={"remaining":.5},func():game.dishwashing.dishes.erase(-44))
	changed("selection",func():game.selected_id=12345,func():game.selected_id=-1)
	changed("wall detail",func():game.wall_detail=true,func():game.wall_detail=false)
	changed("build preview",func():game.build_tools.preview={"x":1},func():game.build_tools.preview={})
	changed("floor preview",func():game.build_tools.floor_preview={"x":1},func():game.build_tools.floor_preview={})
	changed("drag validity",func():game.interaction.drag_valid=true,func():game.interaction.drag_valid=false)
	changed("selected shell",func():game.compact_ui.selected_shell="shell:west#0",func():game.compact_ui.selected_shell="")
	changed("camera pan",func():art.pan_offset+=Vector2(5,5),func():art.pan_offset-=Vector2(5,5))
	changed("docking",func():art.meal_chair_offsets[-44]=Vector2.ONE,func():art.meal_chair_offsets.erase(-44))
	changed("street actor",func():art.street_pedestrians.walkers[0].position.y+=1,func():art.street_pedestrians.walkers[0].position.y-=1)
	changed("cache mode",func():art.use_cached_heads=false,func():art.use_cached_heads=true)
	# Custom controllers do not implement the complete snapshot contract.
	# The real historical fixture is exercised by test_role_boundaries.
	for controller in [Node.new(),UnknownController.new()]:
		art.game=controller
		check(idle.needs_redraw(art) and idle.needs_redraw(art),"unsupported controller always redraws")
		check(not idle.retained and idle.previous.is_empty(),"unsupported controller clears previous snapshot")
		controller.free()
	art.game=null
	check(idle.needs_redraw(art),"missing controller redraws safely")
	art.game=game
	for name in ["model","floor_tasks","dishwashing","interaction","build_tools","compact_ui"]:
		var value=game.get(name);game.set(name,null)
		check(idle.needs_redraw(art) and idle.needs_redraw(art),"incomplete dependency redraws "+name)
		game.set(name,value)
	check(idle.needs_redraw(art) and not idle.needs_redraw(art),"current subclass resumes retention after unsupported controller")
	game.paused=false
	check(idle.needs_redraw(art) and idle.needs_redraw(art),"live play always redraws")
	game.paused=true;game.cafe_intro.active=true
	check(idle.needs_redraw(art) and idle.needs_redraw(art),"intro always redraws")
	game.cafe_intro.active=false
	var tween=create_tween();tween.tween_interval(1)
	check(idle.needs_redraw(art) and idle.needs_redraw(art),"transient tweens always redraw")
	tween.kill();game.editing=true;await settle();before=draws
	for frame in 60:art._process(1.0/60);await process_frame
	check(draws==before,"settled editing retains commands")
	var mouse=InputEventMouseMotion.new();mouse.position=Vector2(100,150);mouse.global_position=mouse.position;Input.parse_input_event(mouse);Input.flush_buffered_events()
	check(idle.needs_redraw(art),"hover movement invalidates")
	print("RENDER_IDLE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"suppressed_frames":idle.suppressed_frames}));game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
