extends SceneTree
const Cache=preload("res://scripts/cafe_background_cache.gd")
const Intro=preload("res://scripts/cafe_intro.gd")
class Game extends "res://scripts/main.gd":
	func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
	func _autosave():return
	func _save():return true
	func _setup_music():pass
var checks=0
var failures=[]
func check(ok,label):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
	Intro.shown_this_session=false;root.size=Vector2i(1360,880)
	var game=Game.new();root.add_child(game);game.process_mode=Node.PROCESS_MODE_DISABLED
	var art=game.illustration;var cache=Cache.new();var intro=game.cafe_intro
	art.ground_art.prepare(game.model)
	check(intro.active,"generated intro starts")
	art.update_projection();art.origin+=intro.render_offset(art.get_viewport_rect().size);check(cache.update(art),"intro background eligible")
	var before=cache.rebuilds;var count=cache.command_count
	for elapsed in [1.25,2.5,3.75,5.0,6.25]:
		intro.elapsed=elapsed;intro.descent=smoothstep(intro.DESCENT_START,intro.DURATION,elapsed)
		art.update_projection();art.origin+=intro.render_offset(art.get_viewport_rect().size);cache.update(art)
		check(cache.rebuilds==before,"normal descent retains native background commands")
		check(cache.command_count==count,"normal descent does not append commands")
	check(cache.intro_used and cache.intro_canvas.is_valid(),"intro uses bounded extra canvas")
	art.opacity=.5;cache.update(art);check(cache.rebuilds==before+1,"opacity invalidates")
	before=cache.rebuilds;art.origin+=Vector2(10000,0);cache.update(art)
	check(cache.rebuilds==before+1,"unexpected pan outside cached coverage safely rebuilds")
	art.self_modulate=Color(.5,1,1);check(not cache.update(art) and not cache.used,"unsupported drawing state falls back")
	art.self_modulate=Color.WHITE;art.update_projection();art.origin+=intro.render_offset(art.get_viewport_rect().size);cache.update(art)
	before=cache.rebuilds;intro.finish();art.update_projection();art.origin+=intro.render_offset(art.get_viewport_rect().size);cache.update(art)
	check(not cache.intro_used and cache.rebuilds==before+1,"intro finish restores ordinary single background cache")
	cache.update(art);check(cache.rebuilds==before+1,"settled frame remains cached")
	cache.release();check(not cache.canvas.is_valid() and not cache.intro_canvas.is_valid(),"release frees both native canvases")
	check(cache.signature.is_empty() and cache.intro_signature.is_empty(),"release clears both keys")
	cache.release();game.queue_free();await process_frame
	print("ORIGIN_BACKGROUND_CACHE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"raster_parity":"not_tested_here"}));quit(0 if failures.is_empty() else 1)
