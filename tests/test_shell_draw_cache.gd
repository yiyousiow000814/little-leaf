extends SceneTree
const Cache=preload("res://scripts/cafe_shell_draw_cache.gd")
const Art=preload("res://scripts/illustrated_openings.gd")
const Geometry=preload("res://scripts/cafe_wall_openings.gd")
class View extends RefCounted:
	var game={"model":{"built_walls":[]},"wall_detail":true}
	var origin=Vector2(390,250)
	var tile=Vector2(39,19.5)
	var ui_scale=1.0
	var zoom=1.0
	var commands=[]
	var projections=0
	func iso(x,z,h=0.0):
		projections+=1
		return origin+Vector2((x-z)*tile.x,(x+z)*tile.y)-Vector2(0,h*ui_scale*zoom*(1.55 if game.wall_detail else 1.0))
	func poly(points,color):commands.append(["poly",points,color])
	func line(a,b,color,width=1.0):commands.append(["line",a,b,color,width])
	func draw_polygon(points,colors,uvs=PackedVector2Array(),texture=null):commands.append(["polygon",points,colors,uvs,texture])
var checks=0
var failures=[]
func check(ok,label):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func parity(cache,view,host,attachments):
	view.commands=[];Art.draw_shell(view,host,attachments,"e0e7d0","91a27d")
	var expected=view.commands
	view.commands=[];cache.draw(view,host,attachments,"e0e7d0","91a27d")
	check(view.commands==expected,"ordered command parity")
	var before=cache.rebuilds
	view.commands=[];view.projections=0;cache.draw(view,host,attachments,"e0e7d0","91a27d")
	check(view.commands==expected,"warm command parity")
	check(view.projections==0,"warm frames do no geometry projection")
	check(cache.rebuilds==before,"warm retains prepared commands")
func _initialize():
	var view=View.new();var cache=Cache.new();var attachments=Geometry.initial_attachments()
	for scale in [.25,.5,1.,2.,4.]:
		view.tile=Vector2(39,19.5)*scale;view.zoom=scale
		for detail in [true,false]:
			view.game.wall_detail=detail
			for material in ["original","sage_panels","cream_stripe","leaf_print"]:
				for height in ["full","half"]:
					for host in Geometry.shell_hosts():
						host.material=material;host.height=height
						parity(cache,view,host,attachments)
	var host=Geometry.shell_hosts()[1]
	host["segment_runs"]=[{"from":0.,"to":2.,"height":"full","material":"leaf_print"},{"from":2.,"to":4.,"height":"half","material":"original"},{"from":4.,"to":host.a.distance_to(host.b),"height":"full","material":"cream_stripe"}]
	parity(cache,view,host,attachments)
	for field in ["origin","tile","ui_scale","zoom"]:
		var before=cache.rebuilds
		view.set(field,view.get(field)*1.1);parity(cache,view,host,attachments)
		check(cache.rebuilds==before+1,"projection invalidates "+field)
	var before=cache.rebuilds
	host.segment_runs[0].material="sage_panels";parity(cache,view,host,attachments)
	check(cache.rebuilds==before+1,"nested host mutation invalidates")
	before=cache.rebuilds
	attachments[0].offset+=.1;parity(cache,view,host,attachments)
	check(cache.rebuilds==before+1,"nested attachment mutation invalidates")
	before=cache.rebuilds
	view.game.model.built_walls.append({"id":7,"x":0,"z":3,"axis":"x","height":"full","material":"original"});parity(cache,view,host,attachments)
	check(cache.rebuilds==before+1,"walls invalidate host resolution")
	before=cache.rebuilds
	cache.draw(view,host,attachments,"ffffff","91a27d")
	check(cache.rebuilds==before+1,"palette invalidates")
	check(cache.entries.size()==2,"bounded two slots")
	# Preview removal/cancel and reset restore exact previous shell geometry.
	parity(cache,view,host,[])
	parity(cache,view,host,attachments)
	view.game.model.built_walls[0].z=4
	parity(cache,view,host,attachments)
	view.game.model.built_walls=[]
	parity(cache,view,host,attachments)
	before=cache.rebuilds
	view.game["animation_time"]=200.0;view.game.model["revision"]=900
	parity(cache,view,host,attachments)
	check(cache.rebuilds==before,"unrelated simulation does not invalidate")
	var unknown=host.duplicate(true);unknown.host_id="custom:host"
	view.commands=[];Art.draw_shell(view,unknown,attachments,"e0e7d0","91a27d")
	var expected=view.commands;view.commands=[]
	cache.draw(view,unknown,attachments,"e0e7d0","91a27d")
	check(view.commands==expected and cache.entries.size()==2,"unknown host direct fallback stays bounded")
	var source=FileAccess.get_file_as_string("res://scripts/illustrated_cafe.gd")
	var shell_start=source.find('shell_draw_cache.draw(self,game.build_tools.render_shell_host("shell:back")')
	var finish=source.find('shell_draw_cache.draw(self,game.build_tools.render_shell_host("shell:west")')
	check(shell_start>source.find("_draw_street_people(show_service)") and finish>shell_start and finish<source.find("var corner_height="),"shells keep exact live drawing positions")
	# With no apertures, global walls never enter solid_panels/cuts geometry.
	view.game.model.built_walls=[]
	for index in 200:view.game.model.built_walls.append({"id":index,"x":index%12,"z":index/12,"axis":"x","height":"full","material":"original"})
	parity(cache,view,host,[]);before=cache.rebuilds
	view.game.model.built_walls[0].z+=1
	parity(cache,view,host,[])
	check(cache.rebuilds==before,"empty attachments ignore unrelated wall mutation")
	host.b+=Vector2(0,1)
	parity(cache,view,host,[])
	check(cache.rebuilds==before+1,"wall-induced host change still invalidates without attachments")
	parity(cache,view,host,attachments);before=cache.rebuilds
	view.game.model.built_walls[0].z+=1
	parity(cache,view,host,attachments)
	check(cache.rebuilds==before+1,"restored attachments restore wall dependency")
	parity(cache,view,host,[])
	var dense_original=[];var dense_cached=[]
	for trial in 5:
		var started=Time.get_ticks_usec()
		for frame in 1000:view.commands=[];Art.draw_shell(view,host,[],"e0e7d0","91a27d")
		dense_original.append(Time.get_ticks_usec()-started);started=Time.get_ticks_usec()
		for frame in 1000:view.commands=[];cache.draw(view,host,[],"e0e7d0","91a27d")
		dense_cached.append(Time.get_ticks_usec()-started)
	print("DENSE_EMPTY_SHELL_BENCHMARK ",JSON.stringify({"walls":200,"draws":1000,"original_us":dense_original,"cached_us":dense_cached}))
	view.game.model.built_walls=[];host.b-=Vector2(0,1)
	# Same commands still pass through the view on every draw. Preparation alone
	# is retained; opacity, outer transforms, AA and submission remain live.
	var rounds=1000;var original_us=[];var cached_us=[]
	var original_projections=0;var cached_projections=0
	for trial in 5:
		view.projections=0;var start=Time.get_ticks_usec()
		for frame in rounds:view.commands=[];Art.draw_shell(view,host,attachments,"e0e7d0","91a27d")
		original_us.append(Time.get_ticks_usec()-start);original_projections=view.projections
		cache.draw(view,host,attachments,"e0e7d0","91a27d");view.projections=0;start=Time.get_ticks_usec()
		for frame in rounds:view.commands=[];cache.draw(view,host,attachments,"e0e7d0","91a27d")
		cached_us.append(Time.get_ticks_usec()-start);cached_projections=view.projections
	check(original_projections>0 and cached_projections==0,"measured warm preparation reduction")
	print("SHELL_DRAW_CACHE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"status":"passed" if failures.is_empty() else "failed","benchmark":{"rounds":rounds,"original_us":original_us,"cached_us":cached_us,"original_projections":original_projections,"cached_projections":cached_projections,"commands_per_frame":view.commands.size()}}));quit(0 if failures.is_empty() else 1)
