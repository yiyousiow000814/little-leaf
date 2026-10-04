extends RefCounted
## Reversible grid-edge previews. Only a matching click-release commits a wall.
## Dragging the background still pans; GUI, cancel and lost-focus never charge.
const Geometry=preload("res://scripts/cafe_walls.gd")
const WallArt=preload("res://scripts/illustrated_walls.gd")
const Money=preload("res://scripts/cafe_money.gd")
const OpeningArt=preload("res://scripts/illustrated_openings.gd")
const OpeningGeometry=preload("res://scripts/cafe_wall_openings.gd")
const OPENING_MODES=["door","window","move_opening","remove_opening","select_opening"]
var opening_preview={}
var opening_source_id=-1
var opening_hit_id=-1
var _render_attachments:Array=[]
var _render_preview_active=false
const MATERIAL_NAMES=["Sage panels","Cream stripes","Little leaves"]
const FLOOR_NAMES=["Warm oak","Cream tiles","Sage tiles"]
const FLOOR_STYLES=["warm_oak","cream_tile","sage_tile"]
const FLOOR_COLORS=[Color("edd5ab"),Color("ece8d4"),Color("cbd7ba")]
var floor_material="warm_oak"
var floor_preview={}
var floor_quote={}
var _press_floor_quote=""
var game
var mode=""
var material="sage_panels"
var preferred_axis=""
var preview={}
var preview_valid=false
var replacing=false
var replacement_quote={}
var preview_shell={}
var preview_warning=""
var preview_reason=""
var selected_key=""
var pointer=Vector2.ZERO
var _pressed=false
var _dragging=false
var _press_point=Vector2.ZERO
var _last_point=Vector2.ZERO
var _press_key=""
var _cache_key=""
var successful_point=Vector2(INF,INF)
var successful_key=""
var tool_buttons={}
var floor_option:OptionButton
var shell_option:OptionButton
var paper_option:OptionButton
var wall_options:VBoxContainer
var surface_options:VBoxContainer

class WallIcon extends Control:
	var height="full"
	var wall_material="sage_panels"
	func _draw():
		var y=4.0 if height=="full" else 23.0
		var h=48.0 if height=="full" else 29.0
		var texture=preload("res://scripts/illustrated_walls.gd").texture_for(wall_material,height)
		draw_texture_rect(texture,Rect2(21,y,38,h),false)
		draw_colored_polygon(PackedVector2Array([Vector2(21,y),Vector2(59,y),Vector2(64,y-4),Vector2(26,y-4)]),Color("fff0d1"))
		draw_colored_polygon(PackedVector2Array([Vector2(59,y),Vector2(64,y-4),Vector2(64,y+h-4),Vector2(59,y+h)]),Color("aebd98"))

class OpeningIcon extends Control:
	# Catalog previews use the same wall aperture, casing, glass and threshold
	# renderer as placed openings, scaled to the card without placeholder glyphs.
	var kind="door"
	var ui_scale=.48
	func iso(x:float,z:float,h:float=0.0)->Vector2:
		return Vector2(size.x*.25+x*42-z*17,46+x*7+z*6-h*.31)
	func poly(points:Array,color):draw_colored_polygon(PackedVector2Array(points),Color(color))
	func line(a:Vector2,b:Vector2,color,width=1.0):draw_line(a,b,Color(color),width,true)
	func _draw():
		var walls=[{"id":0,"axis":"x","x":0,"z":0,"height":"full","material":"sage_panels"}]
		var attachment={"id":1,"kind":kind,"host_id":"wall:0","offset":.5,"width":.76 if kind=="door" else .70}
		var host=OpeningGeometry.wall_host(walls[0]);var opening=OpeningGeometry.aperture(attachment,walls)
		for panel in OpeningGeometry.solid_panels(host,walls,[attachment]):OpeningArt.face(self,host,panel.from,panel.to,panel.bottom,panel.top)
		OpeningArt.cap(self,host,0,1);OpeningArt.end_face(self,host,1,0,128)
		OpeningArt.threshold(self,opening)
		for part in ["start","middle","end"]:OpeningArt.casing(self,opening,part)

func _init(owner_game):game=owner_game

func build()->Control:
	var panel=HBoxContainer.new();panel.add_theme_constant_override("separation",12)
	for spec in [["half","Half wall","35 coins"],["full","Full wall","55 coins"],["paint","Wallpaper","Free finish"],["remove","Remove wall","Half refund"],["door","Door","40 coins"],["window","Window","30 coins"],["move_opening","Move opening","Keeps item"],["remove_opening","Remove opening","Restores wall"]]:
		var chosen=str(spec[0])
		var card=game.button("",func():choose(chosen));card.toggle_mode=true;card.custom_minimum_size=Vector2(92,105);panel.add_child(card);tool_buttons[chosen]=card
		var column=VBoxContainer.new();column.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);card.add_child(column)
		if chosen in ["half","full"]:
			var icon=WallIcon.new();icon.height=chosen;icon.custom_minimum_size=Vector2(84,56);icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_child(icon)
		elif chosen in ["door","window"]:
			var icon=OpeningIcon.new();icon.kind=chosen;icon.custom_minimum_size=Vector2(84,56);icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_child(icon)
		else:
			var symbol=game.label({"paint":"▧","remove":"×","door":"▯","window":"⊞","move_opening":"↔","remove_opening":"−"}.get(chosen,""),36,Color("819874"));symbol.custom_minimum_size=Vector2(84,56);symbol.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;column.add_child(symbol)
		for text in [spec[1],spec[2]]:
			var title=game.label(text,11);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;column.add_child(title)
	var options=VBoxContainer.new();wall_options=options;options.add_theme_constant_override("separation",6);panel.add_child(options)
	options.add_child(game.label("Wall finish · included",12))
	var papers=_option(MATERIAL_NAMES);paper_option=papers;options.add_child(papers)
	papers.item_selected.connect(func(index):material=Geometry.MATERIALS[index];_cache_key="";refresh(pointer))
	options.add_child(game.label("R turns edge · Esc cancels",11,Color("7b856c")))
	var finishes=VBoxContainer.new();surface_options=finishes;finishes.add_theme_constant_override("separation",6);panel.add_child(finishes)
	var floor_row=HBoxContainer.new();floor_row.add_child(game.label("Floor",12));floor_option=_option(FLOOR_NAMES);floor_row.add_child(floor_option);finishes.add_child(floor_row)
	var shell_row=HBoxContainer.new();shell_row.add_child(game.label("Back walls",12));shell_option=_option(["Original"]+MATERIAL_NAMES);shell_row.add_child(shell_option);finishes.add_child(shell_row)
	shell_option.item_selected.connect(func(index):
		if game.model.set_shell_material((["original"]+Geometry.MATERIALS)[index]):_changed("Back-wall wallpaper changed"))
	finishes.add_child(game.label("Flooring is bought per tile · land stays open",11,Color("7b856c")))
	sync();return panel

func _option(names:Array)->OptionButton:
	var control=OptionButton.new();control.custom_minimum_size=Vector2(156,29)
	control.add_theme_font_override("font",game.ArtFont);control.add_theme_font_size_override("font_size",12)
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:control.add_theme_color_override(key,Color("29473c"))
	for key in ["normal","hover","pressed","focus"]:
		var style=game._style(Color("e1e3cd") if key in ["hover","pressed"] else Color("ebe8d7"),Color("cdd3b7"),6)
		style.content_margin_left=9;style.content_margin_right=24;style.content_margin_top=5;style.content_margin_bottom=5
		control.add_theme_stylebox_override(key,style)
	var popup=control.get_popup()
	popup.add_theme_font_override("font",game.ArtFont);popup.add_theme_font_size_override("font_size",13)
	popup.add_theme_color_override("font_color",Color("29473c"));popup.add_theme_color_override("font_hover_color",Color("29473c"))
	popup.add_theme_stylebox_override("panel",game._style(Color("f8f4e7"),Color("cdd3b7"),8))
	popup.add_theme_stylebox_override("hover",game._style(Color("dfdfc8"),Color.TRANSPARENT,4))
	for title in names:control.add_item(str(title))
	return control

func sync():
	if is_instance_valid(shell_option):shell_option.select((["original"]+Geometry.MATERIALS).find(str(game.model.shell_material)))
	for key in tool_buttons:tool_buttons[key].button_pressed=key==mode

func active()->bool:return game.editing and game.catalog_category=="Build" and mode!="" and not game.save_recovery_blocked

func choose(tool:String):
	game._cancel_selection();mode=tool;preferred_axis="";_cache_key="";sync();refresh(game.get_viewport().get_mouse_position())

func cancel():
	successful_key="";successful_point=Vector2(INF,INF)
	mode="";floor_preview={};floor_quote={};_press_floor_quote="";preview={};preview_shell={};replacing=false;replacement_quote={};opening_preview={};opening_source_id=-1;opening_hit_id=-1;_render_attachments=[];_render_preview_active=false;selected_key="";_pressed=false;_dragging=false;_cache_key="";sync()

func on_focus_lost():
	_pressed=false;_dragging=false;floor_preview={};floor_quote={};_press_floor_quote="";preview={};preview_shell={};replacing=false;replacement_quote={};opening_preview={};_render_attachments=[];_render_preview_active=false;_cache_key=""

func rotate():
	if not active() or mode not in ["half","full"]:return
	preferred_axis="z" if (preferred_axis if preferred_axis!="" else str(preview.get("axis","x")))=="x" else "x"
	_cache_key="";refresh(pointer)

func actor_positions()->Array:
	var result=[]
	for index in game.staff_states.size():
		var staff=game.staff_states[index];result.append(game.illustration._render_position("staff_%s"%index,staff.pos))
	for guest in game.model.customers:
		if str(guest.phase) not in ["dirty","cleaning"]:result.append(game.illustration._render_position("guest_%s"%guest.id,Vector2(float(guest.x),float(guest.z))))
	return result

func _world(screen:Vector2)->Vector2:
	game.illustration.update_projection()
	var relative=(screen-game.illustration.origin)/game.illustration.tile
	return Vector2((relative.y+relative.x)*.5,(relative.y-relative.x)*.5)

func _available(screen:Vector2)->bool:
	return game.get_viewport().get_visible_rect().has_point(screen) and not game.interaction._over_ui(screen)

func refresh(screen:Vector2):
	if screen.distance_to(successful_point)>6:successful_key=""
	pointer=screen
	if not active() or not _available(screen):preview_valid=false;preview_reason="";preview={};floor_preview={};floor_quote={};preview_shell={};opening_preview={};_render_attachments=[];_render_preview_active=false;_cache_key="";return
	if mode=="floor":
		_refresh_floor(screen);return
	floor_preview={};floor_quote={}
	if mode in OPENING_MODES:
		_refresh_opening(screen)
		if selected_key==successful_key and successful_key!="":preview_reason=""
		return
	replacing=false;replacement_quote={};preview_shell={}
	if mode in ["half","full"]:
		var host=game.illustration.hit_wall_host(screen)
		if not host.is_empty() and host.shell:
			replacing=true;selected_key=str(host.host_id);preview={};preview_shell=host.duplicate(true)
			preview_shell.height=mode;preview_shell.material=material
			replacement_quote=game.model.wall_replacement_quote(selected_key,mode,material,actor_positions())
			preview_valid=bool(replacement_quote.valid);preview_warning=""
			preview_reason=replacement_price_text() if preview_valid else str(replacement_quote.reason)
			game.tool_text.text=preview_reason
			return
	var hit=game.illustration.hit_wall(screen)
	var proposed=hit.duplicate(true) if mode in ["half","full"] and not hit.is_empty() else (Geometry.nearest_edge(_world(screen),preferred_axis) if mode in ["half","full"] else hit)
	if proposed.is_empty():preview={};selected_key="";_cache_key="";preview_reason="Select a built wall";game.tool_text.text=preview_reason;return
	if mode in ["half","full"]:proposed.height=mode;proposed.material=material
	elif mode=="paint":proposed=proposed.duplicate();proposed.material=material
	var key=Geometry.key_of(proposed)
	var actors=actor_positions()
	replacing=mode in ["half","full","paint"] and not game.model.get_wall(key).is_empty()
	var signature=str([key,mode,material,preferred_axis,game.model.revision,game.model.coins,actors])
	preview=proposed;selected_key=key
	# Replacement quotes are cheap and refreshed even on a cached render so
	# the context always exposes the current cost, refund and net payment.
	if replacing:replacement_quote=game.model.wall_replacement_quote(key,str(proposed.height),material,actors)
	if signature==_cache_key:
		if selected_key==successful_key and successful_key!="":preview={};preview_reason=""
		return
	_cache_key=signature;preview_warning="";preview_valid=true
	if replacing:
		preview_valid=bool(replacement_quote.valid)
		preview_reason=replacement_price_text() if preview_valid else str(replacement_quote.reason)
	elif mode in ["half","full"]:
		preview_valid=game.model.can_place_wall(str(proposed.axis),int(proposed.x),int(proposed.z),mode,material,actors)
		preview_reason=str(game.model.last_error)
		if preview_valid and int(game.model.coins)<int(Geometry.PRICES[mode]):preview_valid=false;preview_reason="Not enough coins · "+Money.amount(int(Geometry.PRICES[mode]))+" needed"
		if preview_valid:preview_warning=game.model.wall_placement_warning(str(proposed.axis),int(proposed.x),int(proposed.z),mode,material,actors)
		if preview_valid:preview_reason=preview_warning if preview_warning!="" else "Build %s wall · %s coins · R turns · drag to pan"%[mode,Money.amount(int(Geometry.PRICES[mode]))]
	elif mode=="remove":
		preview_valid=game.model.can_remove_wall(key)
		preview_reason="Remove this wall · half-price refund" if preview_valid else str(game.model.last_error)
	else:preview_valid=false;preview_reason="Select a wall product first"
	game.tool_text.text=preview_reason
	if selected_key==successful_key and successful_key!="":preview={};preview_reason=""

func render_shell_host(key:String)->Dictionary:
	return preview_shell if active() and preview_valid and not preview_shell.is_empty() and selected_key==key else game.model.get_wall_host(key)

func replacement_price_text()->String:
	if replacement_quote.is_empty():return ""
	return "New %s · refund %s · pay %s"%[Money.amount(int(replacement_quote.new_cost)),Money.amount(int(replacement_quote.refund)),Money.amount(int(replacement_quote.net))]

func handle_input(event:InputEvent)->bool:
	if not active():return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:cancel();return true
		if event.keycode==KEY_R:rotate();return true
	if event is InputEventMouseButton:
		if mode=="floor" and _pressed and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:on_focus_lost()
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:cancel();return true
		if event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and _pressed:
			refresh(event.position)
			if not _dragging and _available(event.position) and selected_key==_press_key and (not preview.is_empty() or not preview_shell.is_empty() or mode in OPENING_MODES or mode=="floor"):
				if mode=="floor" and _press_floor_quote!=_floor_quote_signature():game._notify("Floor price changed · click again to review")
				elif replacing or preview_valid:_commit()
				else:game._notify(preview_reason)
			_pressed=false;_dragging=false;return true
	if event is InputEventMouseMotion:
		if _pressed and not (event.button_mask&MOUSE_BUTTON_MASK_LEFT):on_focus_lost()
		if _pressed:
			if event.position.distance_to(_press_point)>7:_dragging=true
			if _dragging:game.interaction._pan_by(event.position-_last_point)
			_last_point=event.position;refresh(event.position);return true
		refresh(event.position)
	return false

func handle_unhandled_input(event:InputEvent)->bool:
	if not active():return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		if mode=="floor" and not _available(event.position):on_focus_lost();return true
		successful_key="";_cache_key=""
		refresh(event.position);_pressed=true;_dragging=false;_press_point=event.position;_last_point=event.position;_press_key=selected_key
		_press_floor_quote=_floor_quote_signature() if mode=="floor" else ""
		return true
	return false

func _commit():
	if mode=="floor":_commit_floor();return
	if mode in OPENING_MODES:_commit_opening();return
	var ok=false
	if replacing:
		game.compact_ui.review_wall_replacement(selected_key,mode if not preview_shell.is_empty() else str(preview.height),material)
		return
	elif mode in ["half","full"]:ok=game.model.place_wall(str(preview.axis),int(preview.x),int(preview.z),mode,material,actor_positions())
	elif mode=="paint":ok=game.model.replace_wall(selected_key,str(preview.height),material,actor_positions())
	elif mode=="remove":ok=game.model.remove_wall(selected_key)
	if ok:
		successful_key=selected_key;successful_point=pointer;_changed(str(game.model.last_event))
	else:game._notify(str(game.model.last_error))
	_cache_key="";refresh(pointer)

func _changed(message:String):
	game._update_ui();game._save();game._notify(message);game.illustration.queue_redraw()

func get_render_attachments()->Array:
	return _render_attachments if active() and mode in OPENING_MODES and _render_preview_active else game.model.wall_attachments

func _refresh_opening(screen:Vector2):
	preview={};opening_preview={};opening_hit_id=-1;selected_key="";preview_valid=false;preview_warning=""
	var picked=-1
	var attachment={}
	if mode in ["move_opening","remove_opening","select_opening"] and (mode in ["remove_opening","select_opening"] or opening_source_id<0):
		picked=game.illustration.hit_wall_attachment(screen)
		if picked>=0:attachment=game.model.get_wall_attachment(picked).duplicate(true)
		selected_key="opening:%d"%picked if picked>=0 else ""
		opening_hit_id=picked
	else:
		var host=game.illustration.hit_wall_host(screen)
		if not host.is_empty():
			var source=game.model.get_wall_attachment(opening_source_id) if mode=="move_opening" else {}
			if mode=="move_opening" and source.is_empty():opening_source_id=-1;_cache_key="";_render_preview_active=false;return
			var width=float(source.width) if not source.is_empty() else float(OpeningGeometry.WIDTHS[mode])
			host=game.model.host_for_attachment_width(str(host.host_id),width)
			if not host.is_empty():
				# Vertical wall height does not alter its screen-x coordinate.
				# Snap along that axis, rather than projecting its face onto floor.
				var start=game.illustration.iso(host.a.x,host.a.y)
				var finish=game.illustration.iso(host.b.x,host.b.y)
				var length=host.a.distance_to(host.b)
				var offset=(screen.x-start.x)/(finish.x-start.x)*length
				var origin=float(host.a.x if host.axis=="x" else host.a.y)
				offset=roundf(origin+offset-.5)+.5-origin
				if host.wall_ids.size()>1:offset=length*.5
				attachment={"id":int(source.id) if not source.is_empty() else -100,"kind":str(source.kind) if not source.is_empty() else mode,"host_id":host.host_id,"offset":offset,"width":width,"paid_cost":int(source.paid_cost) if not source.is_empty() else game.model.attachment_price(mode)}
				selected_key=str(host.host_id)+":"+str(offset)
	var actors=actor_positions()
	var signature=str([mode,opening_source_id,selected_key,game.model.revision,game.model.coins,actors])
	if signature==_cache_key:
		# Reuse the last validation but keep the latest hit record.
		opening_preview=attachment
		preview_valid=bool(_opening_cached.get("valid",false));preview_reason=str(_opening_cached.get("reason",""));return
	_cache_key=signature;_render_attachments=[];_render_preview_active=false
	if attachment.is_empty():
		preview_reason="Select an attached door or window" if mode in ["move_opening","remove_opening"] and opening_source_id<0 else "Attach to a full-height wall · empty floor is not a host"
	else:
		opening_preview=attachment
		if mode=="select_opening" or (mode=="move_opening" and opening_source_id<0):
			preview_valid=true;preview_reason="Select this %s, then click a new wall host"%attachment.kind
		elif mode=="remove_opening":
			preview_valid=game.model.can_remove_wall_attachment(int(attachment.id),actors)
			preview_reason="Remove %s · restore solid wallpapered wall"%attachment.kind if preview_valid else str(game.model.last_error)
		elif mode=="move_opening":
			preview_valid=game.model.can_move_wall_attachment(opening_source_id,str(attachment.host_id),float(attachment.offset),actors)
			preview_reason="Move %s here · old wall restored · no charge"%attachment.kind if preview_valid else str(game.model.last_error)
		else:
			preview_valid=game.model.can_place_wall_attachment(mode,str(attachment.host_id),float(attachment.offset),actors)
			preview_reason="Attach %s · %s coins · drag to pan"%[mode,Money.amount(game.model.attachment_price(mode))] if preview_valid else str(game.model.last_error)
			if preview_valid and game.model.coins<game.model.attachment_price(mode):preview_valid=false;preview_reason="Not enough coins for this "+mode
		if preview_valid and mode!="select_opening" and not (mode=="move_opening" and opening_source_id<0):
			_render_preview_active=true;_render_attachments=game.model.wall_attachments.duplicate(true)
			if mode=="remove_opening":
				_render_attachments=_render_attachments.filter(func(a):return int(a.id)!=int(attachment.id))
			elif mode=="move_opening":
				_render_attachments=_render_attachments.filter(func(a):return int(a.id)!=opening_source_id)
				var proposed=attachment.duplicate(true);proposed["preview"]=true;_render_attachments.append(proposed)
			else:
				var proposed=attachment.duplicate(true);proposed["preview"]=true;_render_attachments.append(proposed)
	_opening_cached={"valid":preview_valid,"reason":preview_reason}
	game.tool_text.text=preview_reason

var _opening_cached={}
func _commit_opening():
	if opening_preview.is_empty():return
	if mode=="select_opening":
		opening_source_id=int(opening_preview.id);_cache_key="";game._update_ui();return
	if mode=="move_opening" and opening_source_id<0:
		opening_source_id=int(opening_preview.id);_cache_key="";_render_attachments=[]
		game._notify("Selected %s · click another full wall · Esc keeps it here"%opening_preview.kind);refresh(pointer);return
	var ok=false
	if mode in ["door","window"]:ok=game.model.place_wall_attachment(mode,str(opening_preview.host_id),float(opening_preview.offset),actor_positions())
	elif mode=="move_opening":ok=game.model.move_wall_attachment(opening_source_id,str(opening_preview.host_id),float(opening_preview.offset),actor_positions())
	elif mode=="remove_opening":ok=game.model.remove_wall_attachment(int(opening_preview.id),actor_positions())
	if ok:
		successful_key=selected_key;successful_point=pointer
		if mode=="move_opening":opening_source_id=-1
		_changed(str(game.model.last_event))
	else:game._notify(str(game.model.last_error))
	_cache_key="";_render_attachments=[];refresh(pointer)

# Flooring is a decorative layer: picking never selects/moves furniture and the
# model owns all payment and ownership checks. One matching release buys one tile.
func floor_name()->String:
	return FLOOR_NAMES[maxi(0,FLOOR_STYLES.find(floor_material))]

func floor_price_text()->String:
	var prefix=floor_name()+" · 1 tile"
	if floor_quote.is_empty():return prefix+" · "+Money.amount(game.model.floor_price(floor_material))+" coins · click owned land"
	if not floor_preview.is_empty() and game.model.floor_style_at(Vector2i(int(floor_preview.x),int(floor_preview.z)))==floor_material:return prefix+" · Already installed · no charge"
	var price="New %s · refund %s · pay %s"%[Money.amount(int(floor_quote.new_cost)),Money.amount(int(floor_quote.refund)),Money.amount(int(floor_quote.net))]
	return prefix+" · "+price+("" if bool(floor_quote.valid) else "\n"+str(floor_quote.reason))

func _floor_quote_signature()->String:
	return str([floor_material,floor_quote.get("new_cost",-1),floor_quote.get("refund",-1),floor_quote.get("net",-1)])

func _refresh_floor(screen:Vector2):
	preview={};preview_shell={};opening_preview={};replacing=false;replacement_quote={};preview_warning=""
	var world=_world(screen);var cell=Vector2i(floori(world.x),floori(world.y))
	selected_key="floor:%d:%d"%[cell.x,cell.y]
	floor_quote=game.model.floor_quote(cell,floor_material)
	preview_valid=bool(floor_quote.valid)
	floor_preview={"x":cell.x,"z":cell.y,"style":floor_material} if cell.x>=0 and cell.y>=0 and cell.x<game.model.MAX_WIDTH and cell.y<game.model.MAX_DEPTH else {}
	preview_reason="" if preview_valid else str(floor_quote.reason)
	game.tool_text.text=floor_price_text()

func _commit_floor():
	if floor_preview.is_empty():return
	var cell=Vector2i(int(floor_preview.x),int(floor_preview.z))
	if game.model.place_floor(cell,floor_material):
		successful_key=selected_key;successful_point=pointer;_changed(str(game.model.last_event))
	else:game._notify(str(game.model.last_error))
	refresh(pointer)

func draw_floor_preview(artist):
	if not active() or mode!="floor" or floor_preview.is_empty():return
	var x=float(floor_preview.x);var z=float(floor_preview.z)
	var corners=[artist.iso(x+.04,z+.04),artist.iso(x+.96,z+.04),artist.iso(x+.96,z+.96),artist.iso(x+.04,z+.96)]
	var color=FLOOR_COLORS[maxi(0,FLOOR_STYLES.find(floor_material))];color.a=.78 if preview_valid else .30
	artist.poly(corners,color)
	for i in range(4):artist.line(corners[i],corners[(i+1)%4],"527c58" if preview_valid else "b67561",2.0)
