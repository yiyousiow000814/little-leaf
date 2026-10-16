extends RefCounted
## A listening folio: one song shelf, one edition chooser, one shared transport.
## Presentation only. Settings owns preferences; Main owns playback.
const PearlArt=preload("res://scripts/ui/pearlwood_music_art.gd")
const BotanicalFrame=preload("res://scripts/ui/reference_botanical_frame.gd")
const PearlBoard=preload("res://scripts/ui/pearlwood_music_board.gd")
const AirRipple=preload("res://scripts/ui/music_air_ripple.gd")
const Catalog=preload("res://scripts/ui/cafe_music_catalog.gd")
const INK=Color("554631")
const MUTED=Color("75644f")
const CREAM=Color("fff3d8")
const PAPER=Color("f8eed9")
const SAGE=Color("53684c")
const GOLD_INK=Color("71512b")
const POLL_SECONDS=.25
# shop_frame.png keeps its 64px nine-patch corners. Its painted inner bevel is
# ~32px from either side, 26px from the top and 20px from the bottom; leaves and
# the outer Panel rect are not a content boundary. Guard the curved corners too.
const BOARD_INSETS=Vector4(40,36,40,32)

class SongChevron extends Control:
 func _init():
  mouse_filter=Control.MOUSE_FILTER_IGNORE;custom_minimum_size=Vector2(14,24)
 func _draw():
  var c=size*.5
  draw_polyline(PackedVector2Array([c+Vector2(-3,-5),c+Vector2(2,0),c+Vector2(-3,5)]),Color("69553b"),1.65,true)
 func _notification(what):
  if what==NOTIFICATION_RESIZED:queue_redraw()

class PremiumRim extends Control:
 var style=StyleBoxFlat.new()
 func _init():
  mouse_filter=Control.MOUSE_FILTER_IGNORE;style.bg_color=Color.TRANSPARENT;style.border_color=Color("ffe5a5");style.set_border_width_all(2);style.set_corner_radius_all(10)
 func _draw():style.draw(get_canvas_item(),Rect2(Vector2.ZERO,size))
 func _notification(what):
  if what==NOTIFICATION_RESIZED:queue_redraw()

class PremiumGlint extends Control:
 func _draw():draw_line(Vector2(0,0),Vector2(16,0),Color("fff1bd"),2.5,true)

class ButtonRim extends Control:
 const PAINT=preload("res://assets/ui/music_botanical/gilded_control.gdshader")
 var owner_button:Button
 var green=false
 var compact_face=false
 var side_inset=0.0
 var paint=ShaderMaterial.new()
 var last_state=-1
 func _init():
  mouse_filter=Control.MOUSE_FILTER_IGNORE
  show_behind_parent=true;paint.shader=PAINT;material=paint
 func bind(button:Button):
  owner_button=button
  for event in [button.mouse_entered,button.mouse_exited,button.button_down,button.button_up,button.focus_entered,button.focus_exited]:event.connect(refresh_state)
  button.toggled.connect(func(_pressed):refresh_state())
 func configure(is_green:bool,is_compact:bool,inset:float):
  green=is_green;compact_face=is_compact;side_inset=inset
  paint.set_shader_parameter("green_face",green)
  paint.set_shader_parameter("paint_inset",Vector2(side_inset,5.0) if compact_face else Vector2.ZERO)
  last_state=-1;refresh_state()
 func refresh_state():
  if not is_instance_valid(owner_button):return
  var state=owner_button.get_draw_mode()
  if state==last_state:return
  last_state=state
  paint.set_shader_parameter("selected",state in [BaseButton.DRAW_PRESSED,BaseButton.DRAW_HOVER_PRESSED])
  paint.set_shader_parameter("hovered",state in [BaseButton.DRAW_HOVER,BaseButton.DRAW_HOVER_PRESSED])
  paint.set_shader_parameter("disabled",state==BaseButton.DRAW_DISABLED)
 func _draw():draw_rect(Rect2(Vector2.ZERO,size),Color.WHITE)
 func _notification(what):
  if what==NOTIFICATION_RESIZED:paint.set_shader_parameter("surface_size",size);queue_redraw()

class PremiumFeedback extends Control:
 var rim=PremiumRim.new()
 var glint=PremiumGlint.new()
 var pulse:Tween
 func _init():
  mouse_filter=Control.MOUSE_FILTER_IGNORE;clip_contents=true;add_child(rim);add_child(glint);glint.mouse_filter=Control.MOUSE_FILTER_IGNORE;hide()
 func _notification(what):
  if what==NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():cancel()
  elif what==NOTIFICATION_RESIZED and visible:cancel()
 func cancel():
  if pulse!=null and pulse.is_valid():pulse.kill()
  hide()
 func play_on(button:Button,reduced:bool):
  cancel()
  if reduced or not button.is_visible_in_tree():return
  if get_parent()!=button:reparent(button)
  set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);size=button.size
  rim.position=Vector2(6,6);rim.size=size-Vector2(12,12);rim.pivot_offset=rim.size/2;rim.scale=Vector2.ONE*.97;rim.modulate.a=.8
  glint.position=Vector2(8,7);glint.modulate.a=0;show()
  pulse=create_tween().set_parallel(true)
  pulse.tween_property(rim,"scale",Vector2.ONE*1.01,.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
  pulse.tween_property(rim,"scale",Vector2.ONE,.14).set_delay(.16).set_trans(Tween.TRANS_SINE)
  pulse.tween_property(rim,"modulate:a",0,.22).set_delay(.14)
  pulse.tween_property(glint,"position:x",maxf(8,size.x-26),.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
  pulse.tween_property(glint,"modulate:a",1,.08)
  pulse.tween_property(glint,"modulate:a",0,.16).set_delay(.16)
  pulse.chain().tween_callback(hide)
 func ink_rects()->Array[Rect2]:return [rim.get_global_transform()*Rect2(Vector2.ZERO,rim.size),glint.get_global_transform()*Rect2(-2,-2,20,4)]

class SpeakerMark extends Control:
 var muted=false
 var ink_scale=1.0
 func _draw():
  draw_set_transform(size/2,0,Vector2.ONE*ink_scale)
  var c=Vector2.ZERO;var ink=Color("554631")
  draw_colored_polygon(PackedVector2Array([c+Vector2(-9,-4),c+Vector2(-5,-4),c+Vector2(1,-9),c+Vector2(1,9),c+Vector2(-5,4),c+Vector2(-9,4)]),ink)
  if muted:draw_line(c+Vector2(5,-5),c+Vector2(12,5),ink,2,true);draw_line(c+Vector2(12,-5),c+Vector2(5,5),ink,2,true)
  else:
   draw_arc(c+Vector2(1,0),6,-.8,.8,14,ink,1.8,true)
   draw_arc(c+Vector2(1,0),10,-.8,.8,16,ink,1.8,true)
 func _notification(what):
  if what==NOTIFICATION_RESIZED:queue_redraw()

class ControlMark extends Control:
 var glyph="play"
 var ink=Color("554631")
 var ink_scale=1.0
 func _draw():
  draw_set_transform(size/2,0,Vector2.ONE*ink_scale)
  var c=Vector2.ZERO
  match glyph:
   "close":
    draw_line(c+Vector2(-6,-6),c+Vector2(6,6),ink,2.4,true)
    draw_line(c+Vector2(6,-6),c+Vector2(-6,6),ink,2.4,true)
   "play":draw_colored_polygon(PackedVector2Array([c+Vector2(-4.5,-8),c+Vector2(8,0),c+Vector2(-4.5,8)]),ink)
   "pause":
    draw_rect(Rect2(c+Vector2(-6,-8),Vector2(4,16)),ink)
    draw_rect(Rect2(c+Vector2(2,-8),Vector2(4,16)),ink)
   "previous", "next":
    var direction=-1.0 if glyph=="previous" else 1.0
    draw_colored_polygon(PackedVector2Array([c+Vector2(-6*direction,-7),c+Vector2(4*direction,0),c+Vector2(-6*direction,7)]),ink)
    draw_line(c+Vector2(7*direction,-7),c+Vector2(7*direction,7),ink,2.4,true)
 func set_glyph(value:String,color:Color):
  if glyph==value and ink==color:return
  glyph=value;ink=color;queue_redraw()
 func _notification(what):
  if what==NOTIFICATION_RESIZED:queue_redraw()

var compact_ref:WeakRef
var compact:
 get:return compact_ref.get_ref()
var game:
 get:return compact.game if compact!=null else null
var panel:PanelContainer
var body:VBoxContainer
var header:HBoxContainer
var header_margin:MarginContainer
var content_margin:MarginContainer
var heading:Label
var close_button:Button
var close_mark:ControlMark
var play_mark:ControlMark
var previous_mark:ControlMark
var next_mark:ControlMark
var control_marks:Array[Control]=[]
var content:BoxContainer
var library:PanelContainer
var library_body:VBoxContainer
var library_heading:Label
var automatic_button:Button
var group_note:Label
var scroll:ScrollContainer
var track_body:VBoxContainer
var family_cards:Dictionary={}
var family_choices:Dictionary={}
var selection_faces:Dictionary={}
var rows:Dictionary={}
var track_buttons:Dictionary={}
var player:PanelContainer
var player_body:VBoxContainer
var hero:BoxContainer
var record_mark:Control
var board_material:Control
var air_ripple:Control
var content_insets=BOARD_INSETS
var botanical_frame:Control
var library_skin:Control
var transport_skin:Control
var header_skin:Control
var heading_indent:TextureRect
var ordinary_library_skin:Control
var premium_palette=false
var palette_ready=false
var ordinary_faces:Dictionary={}
var ordinary_focus:Dictionary={}
var gilded_focus:Dictionary={}
var gilded_faces:Dictionary={}
var compact_faces:Dictionary={}
var compact_controls=false
var premium_feedback:PremiumFeedback
var overview:VBoxContainer
var edition_host:VBoxContainer
var status_label:Label
var now_playing:Label
var selection_label:Label
var context_label:Label
var dock:VBoxContainer
var controls_row:BoxContainer
var controls_margin:MarginContainer
var timeline:HBoxContainer
var progress_slider:HSlider
var elapsed_label:Label
var duration_label:Label
var previous_button:Button
var play_button:Button
var next_button:Button
var transport:HBoxContainer
var footer:HBoxContainer
var mute_button:Button
var speaker_mark:SpeakerMark
var volume_slider:HSlider
var volume_value:Label
var slider_faces:Dictionary={}
var button_rims:Dictionary={}
var poll_timer:Timer
var return_focus:WeakRef
var fit_queued=false
var stacked_layout=false
var short_layout=false
var seeking=false
var preparing_render=false
var last_state:Array=[]
var last_playback:Array=[]
var last_layout:Array=[]
var snapshot:Dictionary={}

func _init(owner):compact_ref=weakref(owner)

func setup():
 if is_instance_valid(panel):return
 assert(compact.hud!=null,"Music setup requires the shared HUD theme")
 panel=compact._panel();panel.name="MusicPanel";panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
 board_material=PearlBoard.new();board_material.name="MusicMaterialTransition";panel.add_child(board_material)
 botanical_frame=BotanicalFrame.new();botanical_frame.name="ReferenceBotanicalLayers";board_material.add_child(botanical_frame)
 board_material.resized.connect(_fit_air_ripple)
 body=VBoxContainer.new();body.add_theme_constant_override("separation",10);panel.add_child(body)
 header_margin=MarginContainer.new();body.add_child(header_margin)
 header=HBoxContainer.new();header.add_theme_constant_override("separation",8);header_margin.add_child(header)
 heading_indent=TextureRect.new();heading_indent.name="MusicTitleLeaves"
 heading_indent.texture=preload("res://assets/ui/music_pearlwood/selected_song_leaves_r25.svg")
 heading_indent.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;heading_indent.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 heading_indent.self_modulate=Color(1.35,1.06,.58);heading_indent.mouse_filter=Control.MOUSE_FILTER_IGNORE
 heading_indent.custom_minimum_size=Vector2(44,48);header.add_child(heading_indent)
 heading=_label("Music",24);heading.add_theme_font_override("font",compact.hud.font_bold);heading.size_flags_vertical=Control.SIZE_SHRINK_CENTER;header.add_child(heading)
 automatic_button=_button("Auto",_select.bind(Catalog.AUTOMATIC));automatic_button.name="AutomaticMusic";automatic_button.toggle_mode=true;automatic_button.accessibility_name="Automatic music"
 automatic_button.size_flags_horizontal=Control.SIZE_SHRINK_END;automatic_button.set_meta("music_track_id",Catalog.AUTOMATIC)
 automatic_button.tooltip_text="Let the café choose music for its service intensity.\nDecorate uses Quiet Table.";header.add_child(automatic_button)
 close_button=_button("",dismiss);close_button.name="CloseMusic";close_button.custom_minimum_size.x=44
 close_button.size_flags_horizontal=Control.SIZE_SHRINK_END
 close_button.accessibility_name="Close Music";close_button.tooltip_text="Close Music";header.add_child(close_button)
 _theme_close();close_mark=_control_mark(close_button,"close",INK)
 content_margin=MarginContainer.new();content_margin.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_child(content_margin)
 content=BoxContainer.new();content.name="ListeningFolio";content.size_flags_vertical=Control.SIZE_EXPAND_FILL
 content.add_theme_constant_override("separation",12);content_margin.add_child(content)
 _build_player();_build_library();_build_transport()
 ordinary_library_skin=board_material.make_ordinary_surface(_face(10));ordinary_library_skin.name="OrdinaryLibrarySurface"
 library_skin=board_material.make_reference_surface("library");library_skin.name="IllustratedLibrarySurface"
 transport_skin=board_material.make_reference_surface("transport");transport_skin.name="IllustratedTransportSurface"
 header_skin=Control.new();header_skin.name="UnusedHeaderBacking";header_skin.mouse_filter=Control.MOUSE_FILTER_IGNORE;board_material.add_child(header_skin)
 library.item_rect_changed.connect(_fit_air_ripple);dock.item_rect_changed.connect(_fit_air_ripple)
 automatic_button.item_rect_changed.connect(_fit_air_ripple);close_button.item_rect_changed.connect(_fit_air_ripple)
 # Quiet regions follow final nested-container geometry after a viewport resize.
 for target in [heading,heading_indent,now_playing,edition_host]:target.item_rect_changed.connect(_fit_air_ripple)
 for card in family_cards.values():card.versions.item_rect_changed.connect(_fit_air_ripple)
 premium_feedback=PremiumFeedback.new();panel.add_child(premium_feedback)
 air_ripple=AirRipple.new();air_ripple.name="MusicAirRipple";board_material.add_child(air_ripple)
 air_ripple.z_index=20
 board_material.reveal_changed.connect(_apply_material_reveal)
 _theme_board();compact.hud.theme_scroll(scroll)
 poll_timer=Timer.new();poll_timer.name="VisibleMusicProgress";poll_timer.wait_time=POLL_SECONDS
 panel.add_child(poll_timer);poll_timer.timeout.connect(_poll_playback)
 game.get_viewport().size_changed.connect(_queue_layout);body.minimum_size_changed.connect(_queue_layout)
 panel.visibility_changed.connect(_visibility_changed);panel.tree_exiting.connect(_release_viewport_connection);panel.hide()

func _label(words:String,font_size:int,color:Color=INK)->Label:
 var label=game.label(words,font_size,color);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label.mouse_filter=Control.MOUSE_FILTER_IGNORE
 return label

func _surface(color:Color,border:Color=Color.TRANSPARENT,padding:float=10)->StyleBoxFlat:
 var style=StyleBoxFlat.new();style.bg_color=color;style.border_color=border
 style.set_corner_radius_all(10);style.set_border_width_all(1)
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,padding)
 return style

func _theme_board():
 compact.hud.theme_panel(panel,true,0)
 if board_material.original==null:board_material.set_original_material(panel.get_theme_stylebox("panel").duplicate(),panel.material)
 var frame=StyleBoxEmpty.new();panel.add_theme_stylebox_override("panel",frame)
 frame.content_margin_left=content_insets.x;frame.content_margin_top=content_insets.y
 frame.content_margin_right=content_insets.z;frame.content_margin_bottom=content_insets.w
 board_material.set_content_insets(content_insets)

func inner_board_rect()->Rect2:
 return panel.get_global_rect().grow_individual(-content_insets.x,-content_insets.y,-content_insets.z,-content_insets.w)

func _fit_air_ripple():
 if is_instance_valid(botanical_frame):
  botanical_frame.position=Vector2(-content_insets.x,-content_insets.y);botanical_frame.size=panel.size
 if is_instance_valid(library_skin):
  header_skin.hide()
  _apply_material_reveal(board_material.reveal)
  library_skin.position=library.get_global_rect().position-board_material.global_position;library_skin.size=library.size
  ordinary_library_skin.position=library_skin.position;ordinary_library_skin.size=library_skin.size
  var wide=not short_layout and not stacked_layout
  transport_skin.position=dock.get_global_rect().position-board_material.global_position-Vector2(20 if wide else 12,5 if wide else 9)
  transport_skin.size=dock.size+Vector2(40 if wide else 24,20 if wide else 18)
  var header_bounds=automatic_button.get_global_rect().merge(close_button.get_global_rect()).grow(10)
  header_skin.position=header_bounds.position-board_material.global_position;header_skin.size=header_bounds.size
  botanical_frame.occluders.assign([Rect2(library.get_global_rect().position-panel.global_position,library.size),Rect2(transport_skin.get_global_rect().position-panel.global_position,transport_skin.size)])
  if header_skin.visible:botanical_frame.occluders.append(Rect2(header_bounds.position-panel.global_position+Vector2(5,5),header_bounds.size-Vector2(10,10)))
  var quiet:Array[Rect2]=[]
  if not short_layout and not stacked_layout:
   var title_ink=heading.get_global_rect()
   title_ink.size.x=heading.get_theme_font("font").get_string_size(heading.text,HORIZONTAL_ALIGNMENT_LEFT,-1,heading.get_theme_font_size("font_size")).x
   title_ink=title_ink.merge(heading_indent.get_global_rect()).grow(3)
   title_ink.position-=panel.global_position;title_ink.size.y+=title_ink.position.y;title_ink.position.y=0;quiet.append(title_ink)
   for button in [automatic_button,close_button]:
    var area=button.get_global_rect().grow(3);area.position-=panel.global_position;area.size.y+=area.position.y;area.position.y=0;quiet.append(area)
   # One continuous quiet block spans the real copy/control ink. Using the
   # entire overview allocation would cut the newly anchored left-edge vine.
   var song_ink=Rect2()
   for copy in [status_label,now_playing,selection_label,group_note,context_label]:
    if not copy.visible or copy.text.is_empty():continue
    var area=copy.get_global_rect()
    var width=minf(area.size.x,copy.get_theme_font("font").get_string_size(copy.text,HORIZONTAL_ALIGNMENT_LEFT,-1,copy.get_theme_font_size("font_size")).x)
    if copy.horizontal_alignment==HORIZONTAL_ALIGNMENT_CENTER:area.position.x+=(area.size.x-width)*.5
    elif copy.horizontal_alignment==HORIZONTAL_ALIGNMENT_RIGHT:area.position.x+=area.size.x-width
    area.size.x=width;song_ink=song_ink.merge(area) if song_ink.has_area() else area
   song_ink=song_ink.grow(6);song_ink.position-=panel.global_position;quiet.append(song_ink)
   for card in family_cards.values():
    if card.versions.visible:
     var area=card.versions.get_global_rect().grow(3);area.position-=panel.global_position;quiet.append(area)
  botanical_frame.set_quiet_rects(quiet)
  botanical_frame.set_surfaces(Rect2(library.get_global_rect().position-panel.global_position,library.size),Rect2(transport_skin.get_global_rect().position-panel.global_position,transport_skin.size),not short_layout and not stacked_layout,content_insets.x)
 if is_instance_valid(air_ripple):
  air_ripple.position=Vector2(24-content_insets.x,24-content_insets.y)
  air_ripple.size=(board_material.size+Vector2(content_insets.x+content_insets.z-48,content_insets.y+content_insets.w-48)).max(Vector2.ZERO)

func _gilded_face(padding:float=4,radius:int=40)->StyleBoxFlat:
 # The retained background painter supplies the actual face below native text.
 # Keep native content margins and hit geometry identical to the r22 control.
 var face=_surface(Color.TRANSPARENT,Color.TRANSPARENT,padding);face.set_corner_radius_all(radius)
 face.set_border_width_all(2);face.border_width_bottom=5;face.border_blend=true
 return face

func _apply_palette():
 # Build each state's small retained style once. No theme or layout work in
 # the steady playback loop; the board material crossfade supplies the reveal.
 var buttons:Array[Button]=[automatic_button,close_button,previous_button,play_button,next_button,mute_button]
 for button in track_buttons.values():buttons.append(button)
 for button in buttons:
  var key=button.get_instance_id()
  button_rims[key].visible=premium_palette
  button_rims[key].configure(button==play_button,compact_controls,2.0 if button.has_meta("music_track_id") and button!=automatic_button else 5.0)
  if not ordinary_faces.has(key):
   ordinary_faces[key]={};gilded_faces[key]={};compact_faces[key]={"ordinary":{},"premium":{}}
   ordinary_focus[key]=button.get_theme_stylebox("focus")
   var focus=_surface(Color.TRANSPARENT,Color("9b753d"),0);focus.set_corner_radius_all(40);focus.set_border_width_all(2);focus.set_expand_margin_all(-5)
   gilded_focus[key]=focus
   for state in ["normal","hover","pressed","hover_pressed","disabled"]:
    ordinary_faces[key][state]=button.get_theme_stylebox(state)
    gilded_faces[key][state]=_gilded_face()
    for tier in ["ordinary","premium"]:
     var inset_face=(gilded_faces[key][state] if tier=="premium" else ordinary_faces[key][state]).duplicate()
     # Keep the 44px native hit box. Only the visible paint is made compact.
     var side_inset=2 if button.has_meta("music_track_id") and button!=automatic_button else 5
     inset_face.set_expand_margin(SIDE_LEFT,-side_inset);inset_face.set_expand_margin(SIDE_RIGHT,-side_inset)
     inset_face.set_expand_margin(SIDE_TOP,-5);inset_face.set_expand_margin(SIDE_BOTTOM,-5)
     if inset_face is StyleBoxFlat:inset_face.set_corner_radius_all(16);inset_face.border_width_bottom=2
     compact_faces[key][tier][state]=inset_face
  for state in ordinary_faces[key]:
   var face=compact_faces[key]["premium" if premium_palette else "ordinary"][state] if compact_controls else gilded_faces[key][state] if premium_palette else ordinary_faces[key][state]
   button.add_theme_stylebox_override(state,face)
  button.add_theme_stylebox_override("focus",gilded_focus[key] if premium_palette else ordinary_focus[key])
  if premium_palette and button!=play_button:
   for state in ["font_color","font_hover_color","font_focus_color","font_pressed_color","font_hover_pressed_color"]:button.add_theme_color_override(state,Color("654a2b"))
  elif button!=play_button:
   var is_premium=button.has_meta("music_track_id") and Catalog.track(str(button.get_meta("music_track_id"))).get("group","")==Catalog.PREMIUM
   for state in ["font_color","font_hover_color","font_focus_color"]:button.add_theme_color_override(state,GOLD_INK if is_premium else INK)
   for state in ["font_pressed_color","font_hover_pressed_color"]:button.add_theme_color_override(state,GOLD_INK if is_premium else CREAM)
 heading.add_theme_color_override("font_color",Color("654627") if premium_palette else INK)
 now_playing.add_theme_color_override("font_color",Color("664425") if premium_palette else INK)
 library_heading.add_theme_color_override("font_color",Color("748057") if premium_palette else MUTED)
 for card in family_cards.values():
  card.title.add_theme_color_override("font_color",Color("684a2e") if premium_palette else INK)
  card.button.add_theme_stylebox_override("hover",_surface(Color("f0e9ce") if premium_palette else Color("eee3c8"),Color.TRANSPARENT,8))
 _theme_music_sliders()

func _theme_music_sliders():
 if slider_faces.is_empty():
  var paper=Image.new();paper.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><circle cx="12" cy="13" r="10" fill="#a08b60" opacity=".18"/><circle cx="12" cy="11" r="8.8" fill="#fff9e9" stroke="#c4aa70" stroke-width="1.4"/><path d="M6 8Q12 3 18 8" fill="none" stroke="#fffdf5" stroke-width="1.5"/></svg>')
  var thumb=ImageTexture.create_from_image(paper)
  var track=_surface(Color("d8ceaa"),Color.TRANSPARENT,0);track.set_corner_radius_all(5);track.set_border_width_all(0);track.content_margin_top=5;track.content_margin_bottom=5
  var filled=track.duplicate();filled.bg_color=Color("607849")
  for slider in [progress_slider,volume_slider]:
   slider_faces[slider.get_instance_id()]={"slider":slider.get_theme_stylebox("slider"),"grabber_area":slider.get_theme_stylebox("grabber_area"),"grabber":slider.get_theme_icon("grabber"),"grabber_highlight":slider.get_theme_icon("grabber_highlight")}
  slider_faces["premium"]={"slider":track,"grabber_area":filled,"grabber":thumb,"grabber_highlight":thumb}
 for slider in [progress_slider,volume_slider]:
  var faces=slider_faces["premium" if premium_palette else slider.get_instance_id()]
  for key in ["slider","grabber_area"]:slider.add_theme_stylebox_override(key,faces[key])
  for key in ["grabber","grabber_highlight"]:slider.add_theme_icon_override(key,faces[key])
 var bar=scroll.get_v_scroll_bar()
 if not premium_palette:
  compact.hud.theme_scroll(scroll)
  var ordinary_rail=bar.get_theme_stylebox("scroll").duplicate()
  ordinary_rail.content_margin_left=7;ordinary_rail.content_margin_right=7
  bar.custom_minimum_size.x=14;bar.add_theme_stylebox_override("scroll",ordinary_rail);return
 var rail=_surface(Color("f8edcf"),Color("a17c45"),0);rail.set_corner_radius_all(7);rail.set_border_width_all(2);rail.content_margin_left=7;rail.content_margin_right=7
 bar.custom_minimum_size.x=14;bar.add_theme_stylebox_override("scroll",rail)
 for state in ["grabber","grabber_highlight","grabber_pressed"]:
  var grip=_surface(Color("efcc83") if state=="grabber_pressed" else Color("f7dfa7"),Color("b78a44"),0);grip.set_corner_radius_all(7);grip.set_border_width_all(2)
  bar.add_theme_stylebox_override(state,grip)

func _apply_material_reveal(amount:float):
 var material_mix=smoothstep(0.0,.24,amount)
 if is_instance_valid(ordinary_library_skin):ordinary_library_skin.modulate.a=1.0-material_mix
 if is_instance_valid(library_skin):
  library_skin.visible=amount>0;library_skin.modulate.a=material_mix
  transport_skin.visible=amount>0;transport_skin.modulate.a=material_mix
 if is_instance_valid(botanical_frame):
  botanical_frame.set_premium(amount>0);botanical_frame.modulate.a=smoothstep(.10,.48,amount)

func _apply_palette_surfaces(desktop:bool,short_view:bool,small_portrait:bool):
 # Geometry is shared across editions; only the retained skins crossfade.
 var padding=6 if short_view and game.get_viewport().get_visible_rect().size.x<650 else 8 if short_view or small_portrait else 12
 player.add_theme_stylebox_override("panel",_surface(Color.TRANSPARENT,Color.TRANSPARENT,0) if desktop else _surface(Color.TRANSPARENT,Color.TRANSPARENT,padding))
 var clear=StyleBoxEmpty.new()
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:clear.set_content_margin(side,26 if desktop else 14)
 library.add_theme_stylebox_override("panel",clear)

func _face(padding:float=4,tint:Color=Color.WHITE,sage=false)->StyleBoxTexture:
 # Reuse the original shallow painted bevel; no cast shadow, extra decoration,
 # new raster asset or per-frame drawing. All ink stays inside the control rect.
 var style=compact.hud.texture_style("green_face" if sage else "cream_face",14,tint)
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,padding)
 return style

func _button(words:String,callback:Callable,accent=false)->Button:
 var button=game.button(words,callback);button.custom_minimum_size=Vector2(44,44)
 button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.add_theme_font_override("font",compact.hud.font_bold)
 button.add_theme_font_size_override("font_size",14)
 button.add_theme_stylebox_override("normal",_face(4,Color.WHITE,accent))
 button.add_theme_stylebox_override("hover",_face(4,Color(1.04,1.04,1.01),accent))
 button.add_theme_stylebox_override("pressed",_face(4,Color.WHITE,true))
 button.add_theme_stylebox_override("hover_pressed",_face(4,Color(1.04,1.04,1.01),true))
 button.add_theme_stylebox_override("disabled",_face(4,Color(.88,.88,.85)))
 var focus=_surface(Color.TRANSPARENT,Color("6d512f"),0);focus.set_border_width_all(2);button.add_theme_stylebox_override("focus",focus)
 for state in ["font_color","font_hover_color","font_focus_color"]:button.add_theme_color_override(state,CREAM if accent else INK)
 for state in ["font_pressed_color","font_hover_pressed_color"]:button.add_theme_color_override(state,CREAM)
 button.add_theme_color_override("font_disabled_color",Color("857a65"))
 var rim=ButtonRim.new();rim.hide();button.add_child(rim);rim.bind(button);rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);button_rims[button.get_instance_id()]=rim
 return button

func _control_mark(button:Button,glyph:String,ink:Color)->ControlMark:
 var mark=ControlMark.new();mark.name="MusicControl_"+glyph;mark.glyph=glyph;mark.ink=ink
 mark.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(mark);mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 control_marks.append(mark);return mark

func _theme_close():
 # A quiet round close face belongs to the frame, not to the playback bank.
 for state in ["normal","hover","pressed","hover_pressed","disabled"]:
  var face=_surface(Color("dfcfae") if state in ["pressed","hover_pressed"] else Color("fff5df") if state=="hover" else Color("f3e7cc"),Color("b8a27a"),0)
  face.set_corner_radius_all(22);face.border_width_bottom=2;close_button.add_theme_stylebox_override(state,face)
 var focus=_surface(Color.TRANSPARENT,SAGE,0);focus.set_corner_radius_all(19);focus.set_border_width_all(2);focus.set_expand_margin_all(-3)
 close_button.add_theme_stylebox_override("focus",focus)

func _build_player():
 player=PanelContainer.new();player.name="SelectedRecording";player.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 player.size_flags_stretch_ratio=1.0;player.add_theme_stylebox_override("panel",_face(12,Color(1,.98,.91)));content.add_child(player)
 player_body=VBoxContainer.new();player_body.add_theme_constant_override("separation",8);player.add_child(player_body)
 hero=BoxContainer.new();hero.size_flags_vertical=Control.SIZE_SHRINK_CENTER;hero.add_theme_constant_override("separation",10);player_body.add_child(hero)
 record_mark=PearlArt.new();record_mark.name="RecordMark";record_mark.mouse_filter=Control.MOUSE_FILTER_IGNORE
 record_mark.custom_minimum_size=Vector2(72,72);record_mark.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
 record_mark.size_flags_vertical=Control.SIZE_SHRINK_CENTER;hero.add_child(record_mark)
 overview=VBoxContainer.new();overview.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 overview.size_flags_vertical=Control.SIZE_SHRINK_CENTER;overview.add_theme_constant_override("separation",4);hero.add_child(overview)
 status_label=_label("NOW PLAYING",11,SAGE);status_label.add_theme_font_override("font",compact.hud.font_bold);overview.add_child(status_label)
 now_playing=_label("Music is loading",26);now_playing.add_theme_font_override("font",compact.hud.font_bold);overview.add_child(now_playing)
 selection_label=_label("",13,MUTED);overview.add_child(selection_label)
 edition_host=VBoxContainer.new();edition_host.name="RecordingEditions";player_body.add_child(edition_host)
 context_label=_label("",12,MUTED);context_label.hide();player_body.add_child(context_label)
 group_note=_label("Premium is free now · fees planned",11,GOLD_INK);group_note.tooltip_text=Catalog.PREMIUM_TOOLTIP
 group_note.accessibility_description=Catalog.PREMIUM_TOOLTIP;player_body.add_child(group_note)

func _build_library():
 library=PanelContainer.new();library.name="MusicLibrary";library.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 library.size_flags_vertical=Control.SIZE_EXPAND_FILL;library.size_flags_stretch_ratio=1.22
 library.add_theme_stylebox_override("panel",_face(10));content.add_child(library)
 library_body=VBoxContainer.new();library_body.add_theme_constant_override("separation",4);library.add_child(library_body)
 library_heading=_label("SONGS  /  "+str(Catalog.families().size()),11,MUTED);library_heading.add_theme_font_override("font",compact.hud.font_bold);library_body.add_child(library_heading)
 scroll=ScrollContainer.new();scroll.name="MusicTracks";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
 scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
 scroll.scroll_deadzone=12
 scroll.follow_focus=true;scroll.focus_mode=Control.FOCUS_ALL;scroll.accessibility_name="Songs. Arrow keys browse; Enter chooses a song; Tab moves to its editions.";library_body.add_child(scroll)
 track_body=VBoxContainer.new();track_body.mouse_filter=Control.MOUSE_FILTER_PASS;track_body.add_theme_constant_override("separation",2);track_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(track_body)
 for family in Catalog.families():_add_family(family)

func _add_family(family:Dictionary):
 var button=_button("",_choose_family.bind(str(family.id)));button.name="MusicFamily_"+str(family.id)
 button.toggle_mode=true;button.alignment=HORIZONTAL_ALIGNMENT_LEFT
 # Native ScrollContainer cancels release activation once its drag begins.
 button.mouse_filter=Control.MOUSE_FILTER_PASS;button.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
 button.add_theme_stylebox_override("normal",_surface(Color.TRANSPARENT,Color.TRANSPARENT,8))
 button.add_theme_stylebox_override("hover",_surface(Color("eee3c8"),Color.TRANSPARENT,8))
 button.add_theme_stylebox_override("pressed",_surface(Color("dce4cc"),Color("a7b596"),8))
 button.add_theme_stylebox_override("hover_pressed",_surface(Color("d5dfc3"),Color("a7b596"),8))
 for state in ["font_pressed_color","font_hover_pressed_color"]:button.add_theme_color_override(state,INK)
 button.accessibility_name=str(family.title);button.tooltip_text=str(family.title)+" · choose a recording";track_body.add_child(button)
 var copy=HBoxContainer.new();copy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);copy.offset_left=10;copy.offset_right=-10
 copy.add_theme_constant_override("separation",8);copy.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(copy)
 # Selection persists during pause/mute; the separate note still means audible.
 # Reserve the same gutter in every row, so selection never moves the title.
 var marker_slot=Control.new();marker_slot.name="SelectedSongMarkerSlot"
 marker_slot.custom_minimum_size=Vector2(24,28);marker_slot.size_flags_vertical=Control.SIZE_SHRINK_CENTER
 marker_slot.mouse_filter=Control.MOUSE_FILTER_IGNORE;copy.add_child(marker_slot)
 var selected_leaf=TextureRect.new();selected_leaf.name="SelectedSongLeaf"
 selected_leaf.texture=preload("res://assets/ui/music_pearlwood/selected_song_leaves_r25.svg")
 selected_leaf.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;selected_leaf.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 selected_leaf.mouse_filter=Control.MOUSE_FILTER_IGNORE;marker_slot.add_child(selected_leaf)
 selected_leaf.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);selected_leaf.hide()
 var separator=ColorRect.new();separator.name="SongRowRule";separator.color=Color(.65,.53,.32,.14);separator.mouse_filter=Control.MOUSE_FILTER_IGNORE
 button.add_child(separator);separator.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);separator.offset_left=10;separator.offset_right=-10;separator.offset_top=-1
 var title=_label(str(family.title),15);title.size_flags_vertical=Control.SIZE_SHRINK_CENTER;copy.add_child(title)
 var normal_font=title.get_theme_font("font")
 var status=_label("",11,SAGE);status.autowrap_mode=TextServer.AUTOWRAP_OFF;status.size_flags_horizontal=Control.SIZE_SHRINK_END
 status.size_flags_vertical=Control.SIZE_SHRINK_CENTER;copy.add_child(status);status.hide()
 var versions=HBoxContainer.new();versions.add_theme_constant_override("separation",4);versions.hide();edition_host.add_child(versions)
 var chevron=SongChevron.new();chevron.name="SelectedSongChevron"
 chevron.size_flags_horizontal=Control.SIZE_SHRINK_END;chevron.size_flags_vertical=Control.SIZE_SHRINK_CENTER
 chevron.hide();copy.add_child(chevron)
 family_cards[family.id]={"panel":button,"button":button,"versions":versions,"title":title,"status":status,"tracks":family.variants,"marker_slot":marker_slot,"selected_leaf":selected_leaf,"chevron":chevron,"normal_font":normal_font,"separator":separator}
 for entry in family.variants:
  var id=str(entry.id);var edition=_button(Catalog.edition_label(id),_select.bind(id));edition.name="MusicTrack_"+id;edition.toggle_mode=true
  edition.add_theme_font_size_override("font_size",12);edition.set_meta("music_track_id",id);edition.accessibility_name=Catalog.display_title(id)+", "+Catalog.edition_label(id)
  edition.tooltip_text=Catalog.display_title(id)+"\n"+Catalog.edition_label(id)+("\n"+Catalog.PREMIUM_TOOLTIP if entry.group==Catalog.PREMIUM else "")
  edition.disabled=not entry.get("selectable",true)
  if entry.group==Catalog.PREMIUM:
   edition.add_theme_stylebox_override("normal",_face(4,Color(1,.96,.83)))
   edition.add_theme_stylebox_override("hover",_face(4,Color(1.04,1,.89)))
   edition.add_theme_stylebox_override("pressed",_face(4,Color(1,.86,.58)))
   edition.add_theme_stylebox_override("hover_pressed",_face(4,Color(1.04,.9,.63)))
   for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color"]:edition.add_theme_color_override(state,GOLD_INK)
  versions.add_child(edition);track_buttons[id]=edition
  rows[id]={"button":edition,"title":title,"status":status,"group":entry.group,"selectable":entry.get("selectable",true),"family_id":family.id}

func _choose_family(id:String):
 var card:Dictionary=family_cards[id]
 var selected=str(game.settings_controls.music_track)
 if Catalog.family_id(selected)==id:
  card.button.set_pressed_no_signal(true);return
 var choice=str(family_choices.get(id,""))
 if choice.is_empty():
  for entry in card.tracks:
   if entry.get("selectable",true):choice=entry.id;break
 if not choice.is_empty():_select(choice)

func _build_transport():
 dock=VBoxContainer.new();dock.name="PlaybackDock";dock.add_theme_constant_override("separation",0);body.add_child(dock)
 controls_margin=MarginContainer.new();controls_margin.size_flags_vertical=Control.SIZE_EXPAND_FILL;dock.add_child(controls_margin)
 controls_row=BoxContainer.new();controls_row.add_theme_constant_override("separation",12);controls_row.size_flags_vertical=Control.SIZE_SHRINK_CENTER;controls_margin.add_child(controls_row)
 transport=HBoxContainer.new();transport.alignment=BoxContainer.ALIGNMENT_CENTER;transport.add_theme_constant_override("separation",6);controls_row.add_child(transport)
 previous_button=_button("",_step.bind(-1));previous_button.name="PreviousMusic";previous_button.accessibility_name="Previous song"
 previous_button.add_theme_font_size_override("font_size",24);previous_button.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;transport.add_child(previous_button);previous_mark=_control_mark(previous_button,"previous",INK)
 play_button=_button("",_toggle_pause,true);play_button.name="PlayPauseMusic";play_button.custom_minimum_size.x=76
 play_button.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;transport.add_child(play_button);play_mark=_control_mark(play_button,"pause",CREAM)
 next_button=_button("",_step.bind(1));next_button.name="NextMusic";next_button.accessibility_name="Next song"
 next_button.add_theme_font_size_override("font_size",24);next_button.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;transport.add_child(next_button);next_mark=_control_mark(next_button,"next",INK)
 timeline=HBoxContainer.new();timeline.add_theme_constant_override("separation",6);timeline.size_flags_horizontal=Control.SIZE_EXPAND_FILL;controls_row.add_child(timeline)
 elapsed_label=_label("0:00",11,MUTED);elapsed_label.custom_minimum_size.x=28;elapsed_label.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;elapsed_label.size_flags_vertical=Control.SIZE_SHRINK_CENTER;timeline.add_child(elapsed_label)
 progress_slider=_slider("Playback position");progress_slider.name="MusicPosition";progress_slider.step=.1;timeline.add_child(progress_slider)
 progress_slider.drag_started.connect(func():seeking=true);progress_slider.drag_ended.connect(_seek_finished);progress_slider.value_changed.connect(_seek_changed)
 duration_label=_label("--:--",11,MUTED);duration_label.custom_minimum_size.x=30;duration_label.size_flags_horizontal=Control.SIZE_SHRINK_END;duration_label.size_flags_vertical=Control.SIZE_SHRINK_CENTER;timeline.add_child(duration_label)
 footer=HBoxContainer.new();footer.add_theme_constant_override("separation",6);controls_row.add_child(footer)
 mute_button=_button("",_toggle_mute);mute_button.name="MusicEnabled"
 mute_button.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;footer.add_child(mute_button)
 speaker_mark=SpeakerMark.new();speaker_mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);speaker_mark.mouse_filter=Control.MOUSE_FILTER_IGNORE;mute_button.add_child(speaker_mark)
 volume_slider=_slider("Background music volume");volume_slider.name="MusicVolume";volume_slider.custom_minimum_size.x=64;footer.add_child(volume_slider)
 volume_value=_label("",11,MUTED);volume_value.autowrap_mode=TextServer.AUTOWRAP_OFF;volume_value.custom_minimum_size.x=28;volume_value.size_flags_horizontal=Control.SIZE_SHRINK_END;volume_value.size_flags_vertical=Control.SIZE_SHRINK_CENTER;footer.add_child(volume_value)
 volume_slider.value_changed.connect(_set_volume);volume_slider.drag_ended.connect(func(_changed):game.settings_controls.flush_preferences())

func _slider(purpose:String)->HSlider:
 var slider=HSlider.new();slider.min_value=0;slider.max_value=100;slider.step=1
 slider.custom_minimum_size=Vector2(44,44);slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;slider.size_flags_vertical=Control.SIZE_SHRINK_CENTER;slider.accessibility_name=purpose;slider.tooltip_text=purpose
 var settings=game.settings_controls
 slider.add_theme_stylebox_override("slider",settings._rail(Color("c9cfb6")));slider.add_theme_stylebox_override("grabber_area",settings._rail(Color("71865e")))
 var thumb=settings._thumb();slider.add_theme_icon_override("grabber",thumb);slider.add_theme_icon_override("grabber_highlight",thumb)
 return slider
func _select(id:String):
 if id!=Catalog.AUTOMATIC:
  var entry=Catalog.track(id)
  if entry.is_empty() or not entry.get("selectable",true):return
 if game.settings_controls.music_track!=id:game.settings_controls.set_music_track(id)
 last_state.clear();sync()
 if Catalog.track(id).get("group","")==Catalog.PREMIUM:premium_feedback.play_on(track_buttons[id],compact.hud._reduced_motion_requested())
 else:premium_feedback.cancel()

func _toggle_mute():
 game.settings_controls.set_audio_enabled("BGM",not game.settings_controls.bgm_enabled)
 last_state.clear();sync()

func _set_volume(value:float):
 game.settings_controls.set_audio_volume("BGM",value)
 last_state.clear();sync()

func _step(direction:int):
 game.step_music_transport(direction);last_state.clear();sync()

func _toggle_pause():
 game.set_music_transport_paused(not bool(snapshot.get("paused",false)))
 _poll_playback()

func _seek_changed(value:float):
 if seeking:elapsed_label.text=_time(value)
 else:
  game.seek_music_transport(value);_poll_playback()

func _seek_finished(changed:bool):
 var was_seeking=seeking;seeking=false
 if changed and was_seeking and snapshot.get("seekable",false):game.seek_music_transport(progress_slider.value)
 _poll_playback()

func _time(seconds:float)->String:
 var whole=maxi(0,int(seconds))
 return "%d:%02d"%[whole/60,whole%60]


func sync(force:bool=false):
 if preparing_render and not force:return
 if not is_instance_valid(panel) or not panel.is_visible_in_tree():return
 var settings=game.settings_controls
 var state=[settings.music_track,settings.bgm_enabled,settings.bgm_volume,game.music_state,game.editing,game.browser_suspended,game.music_catalog_ready]
 if state==last_state:return
 last_state=state
 automatic_button.set_pressed_no_signal(settings.music_track==Catalog.AUTOMATIC)
 automatic_button.add_theme_color_override("font_focus_color",CREAM if settings.music_track==Catalog.AUTOMATIC else INK)
 automatic_button.accessibility_name="Automatic music"+(", selected" if settings.music_track==Catalog.AUTOMATIC else "")
 speaker_mark.muted=not settings.bgm_enabled;speaker_mark.queue_redraw()
 mute_button.accessibility_name="Background music "+("on; mute" if settings.bgm_enabled else "off; unmute");mute_button.tooltip_text=mute_button.accessibility_name
 volume_slider.set_value_no_signal(settings.bgm_volume);volume_value.text="%d%%"%int(settings.bgm_volume)
 volume_slider.tooltip_text="Background music volume: "+volume_value.text
 last_playback.clear();_poll_playback(force)

func _poll_playback(force:bool=false):
 if preparing_render and not force:return
 if compact==null or not is_instance_valid(panel) or not panel.is_visible_in_tree():return
 snapshot=game.music_transport_snapshot()
 if seeking and not snapshot.get("seekable",false):seeking=false
 var duration=float(snapshot.get("duration",0));var position=float(snapshot.get("position",0))
 if not seeking:
  # A shorter duration may clamp the previous value. That is a display refresh,
  # never a user seek on the newly selected recording.
  progress_slider.set_block_signals(true)
  progress_slider.max_value=maxf(1,duration);progress_slider.set_value_no_signal(position)
  progress_slider.set_block_signals(false);elapsed_label.text=_time(position)
 duration_label.text=_time(duration) if duration>0 else "--:--";progress_slider.editable=bool(snapshot.get("seekable",false))
 progress_slider.tooltip_text="Seek within this recording" if progress_slider.editable else str(snapshot.get("unavailable_reason","Playback position is unavailable."))
 if progress_slider.tooltip_text.is_empty():progress_slider.tooltip_text="This recording cannot be seeked yet."
 var selected=str(game.settings_controls.music_track)
 var state=[selected,snapshot.get("effective_id",""),snapshot.get("playing",false),snapshot.get("paused",false),snapshot.get("can_play",false),snapshot.get("can_step",false),snapshot.get("muted",false),snapshot.get("context_reason",""),snapshot.get("unavailable_reason","")]
 var motion_id=str(snapshot.get("effective_id","")) if selected==Catalog.AUTOMATIC else selected
 var moving=bool(snapshot.get("playing",false)) and not snapshot.get("muted",false) and motion_id==str(snapshot.get("effective_id",""))
 var premium=Catalog.track(motion_id).get("group","")==Catalog.PREMIUM
 var reduced=compact.hud._reduced_motion_requested()
 air_ripple.reduced=reduced
 if reduced:air_ripple.clear()
 record_mark.set_state(moving,premium,reduced,motion_id)
 board_material.set_state(premium,reduced,moving)
 _apply_material_reveal(board_material.reveal)
 if not palette_ready or premium_palette!=premium:
  premium_palette=premium;palette_ready=true;_apply_palette();_queue_layout()
 if compact.hud._reduced_motion_requested():premium_feedback.cancel()
 if state==last_playback:return
 last_playback=state
 var effective=str(snapshot.get("effective_id",""));var shown=effective if selected==Catalog.AUTOMATIC else selected
 var entry=Catalog.track(shown);var family=Catalog.family_for_track(shown)
 var muted=bool(snapshot.get("muted",false));var paused=bool(snapshot.get("paused",false))
 status_label.text="MUTED" if muted else "PAUSED" if paused or game.browser_suspended else "SELECTED FOR SERVICE" if shown!=effective else "NOW PLAYING" if snapshot.get("playing",false) else "READY" if snapshot.get("available",false) else "LOADING"
 now_playing.text=str(family.get("title",snapshot.get("title","Music is loading")))
 selection_label.text=Catalog.edition_label(shown) if not entry.is_empty() else "Waiting for audio"
 context_label.text=str(snapshot.get("context_reason",""))
 var reason=str(snapshot.get("unavailable_reason",""))
 if not reason.is_empty() and not reason in context_label.text:context_label.text+=("\n" if not context_label.text.is_empty() else "")+reason
 context_label.visible=not context_label.text.is_empty() and not muted;context_label.tooltip_text=context_label.text
 now_playing.accessibility_description=selection_label.text+". "+context_label.text
 play_button.accessibility_name="Resume music" if paused else "Pause music" if snapshot.get("playing",false) else "Play music"
 play_button.disabled=not bool(snapshot.get("can_play",false));play_button.tooltip_text=reason if play_button.disabled else play_button.accessibility_name
 play_mark.set_glyph("play" if paused or not snapshot.get("playing",false) else "pause",MUTED if play_button.disabled else CREAM)
 for button in [previous_button,next_button]:
  button.disabled=not bool(snapshot.get("can_step",false));button.tooltip_text="Song changes resume after Decorate." if game.editing else reason if button.disabled else button.accessibility_name
 previous_mark.set_glyph("previous",MUTED if previous_button.disabled else INK);next_mark.set_glyph("next",MUTED if next_button.disabled else INK)
 _sync_cards(shown,effective)
 # Native toggle/disabled setters deliberately suppress signals; update only
 # after this playback state actually changes, never in the steady poll path.
 for rim in button_rims.values():rim.refresh_state()

func _sync_cards(shown:String,effective:String):
 var old_focus=game.get_viewport().gui_get_focus_owner()
 var edition_had_focus=is_instance_valid(old_focus) and edition_host.is_ancestor_of(old_focus)
 var family_id=Catalog.family_id(shown)
 for id in rows:
  var row=rows[id];row.button.set_pressed_no_signal(id==shown)
  row.button.add_theme_color_override("font_focus_color",GOLD_INK if row.group==Catalog.PREMIUM else CREAM if id==shown else INK)
  row.button.accessibility_description=("Selected. " if id==shown else "")+("Playing now. " if id==effective else "")+("Decorate only; not selectable." if not row.selectable else "")
  if not row.selectable:row.button.tooltip_text="Plays automatically in Decorate.\nChoose a Premium edition for café service."
 for id in family_cards:
  var card:Dictionary=family_cards[id];var current=id==family_id
  card.button.set_pressed_no_signal(current);card.versions.visible=current
  card.separator.visible=not current;card.separator.modulate.a=1.0 if premium_palette else 0.0
  if card.selected_leaf.visible!=current:
   card.selected_leaf.visible=current;card.chevron.visible=current
   card.title.add_theme_font_override("font",compact.hud.font_bold if current else card.normal_font)
  var audible=id==Catalog.family_id(effective) and snapshot.get("playing",false) and not snapshot.get("muted",false)
  card.status.text="♪" if audible else ""
  if current:
   var premium=Catalog.track(shown).get("group","")==Catalog.PREMIUM
   for hovered in [false,true]:
    var style_key=str(premium)+str(hovered)
    if not selection_faces.has(style_key):selection_faces[style_key]=_surface(Color("e8d29e") if premium and hovered else Color("eddeba") if premium else Color("d5dfc3") if hovered else Color("dce4cc"),Color("b89d67") if premium else Color("a7b596"),8)
    card.button.add_theme_stylebox_override("hover_pressed" if hovered else "pressed",selection_faces[style_key])
  card.button.accessibility_description=("Selected song. " if current else "")+str(card.tracks.size())+" recordings."
 if rows.has(shown) and rows[shown].selectable:family_choices[family_id]=shown
 if edition_had_focus and not old_focus.is_visible_in_tree():
  var target=track_buttons.get(shown)
  if not is_instance_valid(target) or target.disabled:target=family_cards[family_id].button if family_cards.has(family_id) else automatic_button
  target.grab_focus()
  if scroll.is_ancestor_of(target):scroll.ensure_control_visible(target)
 _queue_layout()
func prepare_render(premium:bool,amount:float=1.0)->bool:
 # Draw the existing materials only under the startup gate's opaque cover.
 # This presentation pass never selects a recording or changes playback.
 if not preparing_render:
  if panel.visible:return false
  preparing_render=true;panel.show();last_state.clear();sync(true);layout()
 if not palette_ready or premium_palette!=premium:
  premium_palette=premium;palette_ready=true;_apply_palette();_queue_layout()
 record_mark.set_state(false,premium,true)
 board_material.set_state(premium,true,false)
 if premium:record_mark.set_reveal(amount);board_material.set_reveal(amount)
 air_ripple.prepare_render()
 return true

func finish_render_preparation():
 if not preparing_render:return
 air_ripple.finish_render_preparation()
 last_state.clear();sync(true);panel.hide()
 preparing_render=false;last_state.clear()

func show(origin:Control=null):
 if panel.visible:return
 if origin==null:origin=compact.music_access
 return_focus=weakref(origin) if is_instance_valid(origin) else null
 game.settings.hide();compact._popup_at(panel,game.get_viewport().get_visible_rect().size.x*.8)
 last_state.clear();sync();layout();_queue_layout();close_button.grab_focus()

func dismiss():
 if not is_instance_valid(panel) or not panel.visible:return
 panel.hide();compact.sync()

func _visibility_changed():
 if compact==null or preparing_render:return
 if panel.is_visible_in_tree():
  if is_instance_valid(poll_timer):poll_timer.start()
 else:
  if is_instance_valid(poll_timer):poll_timer.stop()
  if is_instance_valid(premium_feedback):premium_feedback.cancel()
  seeking=false
  if not panel.visible:
   game.settings_controls.flush_preferences();_restore_focus.call_deferred()

func _restore_focus():
 if compact==null or not is_instance_valid(panel) or panel.visible or compact.has_open_popup():return
 var target=return_focus.get_ref() if return_focus!=null else null
 if not is_instance_valid(target):target=compact.music_access
 if is_instance_valid(target) and target.is_visible_in_tree():target.grab_focus()

func _release_viewport_connection():
 if is_instance_valid(poll_timer):poll_timer.stop()
 if compact==null:return
 var viewport=game.get_viewport()
 if viewport.size_changed.is_connected(_queue_layout):viewport.size_changed.disconnect(_queue_layout)

func _queue_layout():
 if compact==null or fit_queued:return
 fit_queued=true;_deferred_layout.call_deferred()

func _deferred_layout():
 fit_queued=false;last_layout.clear();layout()

func layout():
 if compact==null or not is_instance_valid(panel) or not panel.visible:return
 var view=game.get_viewport().get_visible_rect().size;var insets=compact.hud._safe_insets()
 var usable=Vector2(maxf(0,view.x-insets.x-insets.z),maxf(0,view.y-insets.y-insets.w))
 var short_view=usable.y<650
 var portrait=usable.x<500 or (not short_view and usable.x<760)
 var small_portrait=portrait and usable.y<680
 var desktop=not portrait and not short_view
 var reference_desktop=desktop and usable.x>=1000 and usable.y>=720
 var reference_scale=minf(usable.x/1528.0,usable.y/1029.0)
 heading_indent.visible=true
 var landscape_bay=short_view and not portrait and usable.x>=740
 var small_controls=usable.x<500 or (short_view and usable.x<900)
 var target=usable*Vector2(.934,.906) if reference_desktop else usable*(.92 if desktop else .8)
 if portrait:target.x=usable.x-24
 elif short_view:target=usable-Vector2(48 if landscape_bay else 24,32 if landscape_bay else 24)
 var key=[view,insets,target,portrait,short_view,context_label.visible,premium_palette]
 if key==last_layout:return
 last_layout=key;stacked_layout=portrait;short_layout=short_view
 if not desktop:
  _compose_phone(usable,insets,portrait)
  return
 if compact_controls!=small_controls:
  compact_controls=small_controls;_apply_palette()
 for mark in control_marks:
  mark.ink_scale=1.65*reference_scale if reference_desktop else .82 if compact_controls else 1.0;mark.queue_redraw()
 speaker_mark.ink_scale=1.5*reference_scale if reference_desktop else .82 if compact_controls else 1.0;speaker_mark.queue_redraw()
 automatic_button.add_theme_font_size_override("font_size",int(22*reference_scale) if reference_desktop else 11 if compact_controls else 14)
 content_insets=Vector4(28,34,28,18)*reference_scale if reference_desktop else Vector4(84,60,84,54) if desktop else Vector4(48,36,48,32) if landscape_bay else BOARD_INSETS
 header_margin.add_theme_constant_override("margin_left",int(52*reference_scale) if reference_desktop else 0)
 header_margin.add_theme_constant_override("margin_right",int(20*reference_scale) if reference_desktop else 0)
 content_margin.add_theme_constant_override("margin_left",int(44*reference_scale) if reference_desktop else 0)
 controls_margin.add_theme_constant_override("margin_left",int(50*reference_scale) if reference_desktop else 0)
 controls_margin.add_theme_constant_override("margin_right",int(50*reference_scale) if reference_desktop else 0)
 # The wide tray extends 5 px above and 15 px below the dock. A 10 px top
 # inset moves the centered row down 5 px, centering it in the visible tray.
 controls_margin.add_theme_constant_override("margin_top",10 if not portrait and not short_view else 0)
 heading_indent.custom_minimum_size=Vector2(50,48)*reference_scale if reference_desktop else Vector2(22,0)
 header.add_theme_constant_override("separation",int(12*reference_scale) if reference_desktop else 8)
 close_button.custom_minimum_size=Vector2(64,64)*reference_scale if reference_desktop else Vector2(44,44)
 automatic_button.custom_minimum_size=Vector2(88,64)*reference_scale if reference_desktop else Vector2(44,44)
 _theme_board()
 body.add_theme_constant_override("separation",int(6*reference_scale) if reference_desktop else 6 if portrait or short_view else 10)
 heading.add_theme_font_size_override("font_size",22 if short_view else 24)
 content.vertical=portrait;content.add_theme_constant_override("separation",8 if portrait or short_view else 16)
 player.size_flags_vertical=Control.SIZE_SHRINK_BEGIN if portrait else Control.SIZE_EXPAND_FILL
 library.custom_minimum_size.x=0 if portrait else 140 if usable.x<650 else 220
 player.add_theme_stylebox_override("panel",_surface(Color.TRANSPARENT,Color.TRANSPARENT,12) if desktop else _face(6 if short_view and usable.x<650 else 8 if short_view or small_portrait else 12,Color(1,.98,.91)))
 player.size_flags_stretch_ratio=1.55 if landscape_bay else 1.05 if desktop else 1.35 if short_view else 1.0
 player_body.add_theme_constant_override("separation",int(8*reference_scale) if reference_desktop else 4 if short_view or small_portrait else 8)
 player_body.alignment=BoxContainer.ALIGNMENT_BEGIN if portrait else BoxContainer.ALIGNMENT_CENTER
 library.add_theme_stylebox_override("panel",_face(8 if short_view else 10))
 library_heading.visible=not short_view
 hero.vertical=desktop
 # Editions have a dedicated full-width row below artwork/title on landscape.
 # Their allocation no longer competes with the artwork for title-column width.
 if edition_host.get_parent()!=player_body:
  edition_host.reparent(player_body);player_body.move_child(edition_host,1)
  group_note.reparent(player_body)
 hero.add_theme_constant_override("separation",int(5*reference_scale) if reference_desktop else 8)
 overview.add_theme_constant_override("separation",0 if reference_desktop else 4)
 record_mark.visible=(not short_view and not small_portrait) or (short_view and usable.x>=740)
 record_mark.custom_minimum_size=Vector2(600,460)*reference_scale if reference_desktop else Vector2(112,92) if landscape_bay else Vector2(62,62) if short_view else Vector2(140,115) if portrait else Vector2(264,216) if usable.y<720 else Vector2(464,380)
 record_mark.size_flags_vertical=Control.SIZE_SHRINK_CENTER
 status_label.show()
 selection_label.visible=not short_view and not small_portrait
 now_playing.add_theme_font_size_override("font_size",int(48*reference_scale) if reference_desktop else 16 if short_view and usable.x<650 else 18 if short_view else 19 if portrait else 36)
 status_label.add_theme_font_size_override("font_size",int(18*reference_scale) if reference_desktop else 11)
 selection_label.add_theme_font_size_override("font_size",int(24*reference_scale) if reference_desktop else 13)
 library_heading.add_theme_font_size_override("font_size",int(18*reference_scale) if reference_desktop else 13)
 library_body.add_theme_constant_override("separation",int(24*reference_scale) if reference_desktop else 4)
 now_playing.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER if hero.vertical else HORIZONTAL_ALIGNMENT_LEFT
 status_label.horizontal_alignment=now_playing.horizontal_alignment;selection_label.horizontal_alignment=now_playing.horizontal_alignment
 group_note.add_theme_font_size_override("font_size",int(16*reference_scale) if reference_desktop else 10 if short_view else 11)
 group_note.text="Premium free · fees planned" if short_view else "Premium is free now · fees planned"
 group_note.add_theme_color_override("font_color",MUTED)
 group_note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER if desktop else HORIZONTAL_ALIGNMENT_LEFT
 # Context reasons occupy their own bounded explanation; they never hide transport.
 context_label.add_theme_font_size_override("font_size",11 if short_view else 12)
 for card in family_cards.values():
  card.title.add_theme_font_size_override("font_size",int(24*reference_scale) if reference_desktop else 20 if desktop else 13 if usable.x<650 and not portrait else 15)
  card.button.custom_minimum_size.y=60*reference_scale if reference_desktop else 49 if desktop else 44
  card.versions.size_flags_horizontal=Control.SIZE_SHRINK_CENTER if desktop else Control.SIZE_EXPAND_FILL
  card.versions.custom_minimum_size.x=484*reference_scale if reference_desktop else 300 if desktop else 0
  card.versions.add_theme_constant_override("separation",8 if short_view else 6)
 for id in track_buttons:
  var edition=Catalog.edition_label(id)
  track_buttons[id].text=edition
  track_buttons[id].add_theme_font_size_override("font_size",int(19*reference_scale) if reference_desktop else 14 if desktop else 11 if short_view and usable.x<650 else 12)
  track_buttons[id].custom_minimum_size.y=60*reference_scale if reference_desktop else 44
 scroll.custom_minimum_size.y=88 if portrait else 104 if usable.x<650 else 128 if short_view else 132
 if portrait:
  if timeline.get_parent()!=dock:timeline.reparent(dock);dock.move_child(timeline,0)
 else:
  if timeline.get_parent()!=controls_row:timeline.reparent(controls_row);controls_row.move_child(timeline,1)
 controls_row.vertical=false;controls_row.add_theme_constant_override("separation",int(28*reference_scale) if reference_desktop else 4 if portrait else 6 if usable.x<900 else 14)
 transport.add_theme_constant_override("separation",int(16*reference_scale) if reference_desktop else 4 if usable.x<900 else 6)
 dock.custom_minimum_size.y=110*reference_scale if reference_desktop else 0
 for button in [previous_button,play_button,next_button,mute_button]:
  button.size_flags_vertical=Control.SIZE_SHRINK_CENTER
  button.custom_minimum_size.y=68*reference_scale if reference_desktop else 54 if desktop else 44
  button.custom_minimum_size.x=68*reference_scale if reference_desktop else 54 if desktop else 44
 if reference_desktop:play_button.custom_minimum_size=Vector2(76,76)*reference_scale
 else:play_button.custom_minimum_size.x=44 if compact_controls else 48 if usable.x<900 else 60
 transport.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
 timeline.add_theme_constant_override("separation",int(16*reference_scale) if reference_desktop else 4 if usable.x<900 else 8)
 footer.size_flags_horizontal=Control.SIZE_EXPAND_FILL if portrait else Control.SIZE_SHRINK_END
 footer.add_theme_constant_override("separation",int(14*reference_scale) if reference_desktop else 4)
 volume_slider.custom_minimum_size.x=132*reference_scale if reference_desktop else 44 if usable.x<900 else 80
 for label in [elapsed_label,duration_label,volume_value]:label.add_theme_font_size_override("font_size",int(21*reference_scale) if reference_desktop else 11)
 elapsed_label.custom_minimum_size.x=48*reference_scale if reference_desktop else 28
 duration_label.custom_minimum_size.x=48*reference_scale if reference_desktop else 30
 volume_value.custom_minimum_size.x=44*reference_scale if reference_desktop else 28
 volume_value.visible=usable.x>=900
 heading.add_theme_font_size_override("font_size",int(44*reference_scale) if reference_desktop else 30 if desktop else 24)
 _apply_palette_surfaces(desktop,short_view,small_portrait)
 board_material.reference_surface.render_scale=.42 if desktop else .24
 board_material.reference_surface.quiet_inset=30.0 if desktop else 18.0
 board_material.reference_surface.queue_redraw()
 library_skin.set_compact(not desktop);transport_skin.set_compact(not desktop)
 if not desktop:target=_layout_mobile(usable,portrait)
 panel.size=target;panel.position=Vector2(insets.x,insets.y)+(usable-panel.size)/2
 if reference_desktop:panel.position.y+=8*reference_scale
 _fit_air_ripple()


func _compose_phone(usable:Vector2,insets:Vector4,portrait:bool):
 # A separate layout path avoids repeatedly applying desktop minima and then
 # undoing them, which can leave native containers mid-reflow during toggles.
 if compact_controls:compact_controls=false;_apply_palette()
 for margin in [header_margin,content_margin,controls_margin]:
  for side in ["left","top","right","bottom"]:margin.add_theme_constant_override("margin_"+side,0)
 content.vertical=portrait
 player.size_flags_vertical=Control.SIZE_SHRINK_BEGIN if portrait else Control.SIZE_EXPAND_FILL
 record_mark.size_flags_vertical=Control.SIZE_SHRINK_CENTER
 if edition_host.get_parent()!=player_body:
  edition_host.reparent(player_body);player_body.move_child(edition_host,1);group_note.reparent(player_body)
 for card in family_cards.values():
  card.versions.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card.versions.custom_minimum_size.x=0
  for button in card.versions.get_children():button.custom_minimum_size.y=44
 if portrait:
  if timeline.get_parent()!=dock:timeline.reparent(dock);dock.move_child(timeline,0)
 else:
  if timeline.get_parent()!=controls_row:timeline.reparent(controls_row);controls_row.move_child(timeline,1)
 controls_row.vertical=false;dock.custom_minimum_size.y=0
 transport.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
 footer.size_flags_horizontal=Control.SIZE_EXPAND_FILL if portrait else Control.SIZE_SHRINK_END
 timeline.add_theme_constant_override("separation",4)
 elapsed_label.custom_minimum_size.x=28;duration_label.custom_minimum_size.x=30
 close_button.custom_minimum_size=Vector2(44,44)
 board_material.reference_surface.render_scale=.24;board_material.reference_surface.quiet_inset=18.0;board_material.reference_surface.queue_redraw()
 library_skin.set_compact(true);transport_skin.set_compact(true)
 var target=_layout_mobile(usable,portrait)
 panel.size=target;panel.position=Vector2(insets.x,insets.y)+(usable-panel.size)/2
 _fit_air_ripple()

func _layout_mobile(usable:Vector2,portrait:bool)->Vector2:
 # Phone compositions have their own spacing and hierarchy. No scaled desktop
 # ornament or tiny control bank; reuse the same native controls and owners.
 var narrow=usable.x<370
 var tight_landscape=not portrait and usable.x<700
 content_insets=Vector4(40,36,40,32)
 _theme_board()
 heading_indent.show();heading_indent.custom_minimum_size=Vector2(24,28)
 heading.add_theme_font_size_override("font_size",24)
 body.add_theme_constant_override("separation",8 if portrait else 6)
 header.add_theme_constant_override("separation",8)
 automatic_button.custom_minimum_size=Vector2(52,44)
 automatic_button.add_theme_font_size_override("font_size",13)
 for mark in control_marks:mark.ink_scale=1.0;mark.queue_redraw()
 speaker_mark.ink_scale=1.0;speaker_mark.queue_redraw()
 if compact_controls:compact_controls=false;_apply_palette()
 content.add_theme_constant_override("separation",12 if portrait or tight_landscape else 18)
 player.size_flags_stretch_ratio=1.0 if portrait or tight_landscape else .82
 library.size_flags_stretch_ratio=1.0 if tight_landscape else 1.22
 library.custom_minimum_size.x=0 if portrait else 280 if usable.x>=740 else 200
 player.add_theme_stylebox_override("panel",_surface(Color.TRANSPARENT,Color.TRANSPARENT,0))
 player_body.alignment=BoxContainer.ALIGNMENT_CENTER
 player_body.add_theme_constant_override("separation",6 if portrait else 3)
 hero.vertical=not portrait
 hero.add_theme_constant_override("separation",3 if not portrait else 12)
 record_mark.show();record_mark.custom_minimum_size=Vector2(104,86) if narrow else Vector2(120,98) if portrait else Vector2(78,42) if tight_landscape else Vector2(92,48) if context_label.visible else Vector2(112,56)
 now_playing.add_theme_font_size_override("font_size",17 if tight_landscape else 18 if narrow else 20)
 status_label.add_theme_font_size_override("font_size",10)
 status_label.visible=portrait
 selection_label.visible=portrait;selection_label.add_theme_font_size_override("font_size",12)
 now_playing.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT if portrait else HORIZONTAL_ALIGNMENT_CENTER
 status_label.horizontal_alignment=now_playing.horizontal_alignment;selection_label.horizontal_alignment=now_playing.horizontal_alignment
 overview.add_theme_constant_override("separation",3)
 library_heading.show();library_heading.add_theme_font_size_override("font_size",11)
 library_heading.text="SONGS  /  "+str(Catalog.families().size())
 library_body.add_theme_constant_override("separation",6)
 var page=StyleBoxEmpty.new()
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:page.set_content_margin(side,12)
 library.add_theme_stylebox_override("panel",page)
 for card in family_cards.values():
  card.title.add_theme_font_size_override("font_size",15)
  card.button.custom_minimum_size.y=48 if portrait else 44
  card.versions.add_theme_constant_override("separation",5)
 for button in track_buttons.values():button.add_theme_font_size_override("font_size",11 if narrow or tight_landscape else 12)
 group_note.add_theme_font_size_override("font_size",10)
 group_note.text="Premium free · fees planned" if tight_landscape else "Premium is free now · fees planned"
 group_note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 context_label.add_theme_font_size_override("font_size",10)
 scroll.custom_minimum_size.y=(96 if usable.y<680 else 144) if portrait else 116
 transport.add_theme_constant_override("separation",4 if portrait else 8)
 controls_row.add_theme_constant_override("separation",4 if portrait else 8)
 footer.add_theme_constant_override("separation",4)
 volume_slider.custom_minimum_size.x=44 if portrait else 64
 elapsed_label.add_theme_font_size_override("font_size",12);duration_label.add_theme_font_size_override("font_size",12)
 volume_value.hide()
 for button in [previous_button,play_button,next_button,mute_button]:button.custom_minimum_size=Vector2(44,44)
 play_button.custom_minimum_size=Vector2(48,48)
 return usable-Vector2(20,28) if portrait else usable-Vector2(24,20)

func handle_input(event:InputEvent)->bool:
 if not is_instance_valid(panel) or not panel.is_visible_in_tree() or not event is InputEventKey or not event.pressed:return false
 var focused=game.get_viewport().gui_get_focus_owner()
 var family_controls:Array[Control]=[]
 var shelf_focus:Control=null
 for card in family_cards.values():
  family_controls.append(card.button)
  if card.button.button_pressed:shelf_focus=card.button
 var family_index=family_controls.find(focused)
 if family_index>=0:
  shelf_focus=focused
  if event.keycode in [KEY_UP,KEY_DOWN,KEY_HOME,KEY_END]:
   var next_index=0 if event.keycode==KEY_HOME else family_controls.size()-1 if event.keycode==KEY_END else clampi(family_index+(-1 if event.keycode==KEY_UP else 1),0,family_controls.size()-1)
   family_controls[next_index].grab_focus();scroll.ensure_control_visible(family_controls[next_index]);return true
 if event.keycode!=KEY_TAB:return false
 if shelf_focus==null:shelf_focus=family_controls[0]
 var controls:Array[Control]=[close_button,automatic_button,shelf_focus]
 for row in rows.values():
  if row.button.is_visible_in_tree() and not row.button.disabled:controls.append(row.button)
 if progress_slider.editable:controls.append(progress_slider)
 for button in [previous_button,play_button,next_button]:
  if not button.disabled:controls.append(button)
 controls.append(mute_button);controls.append(volume_slider)
 var index=controls.find(focused)
 var next=controls[posmod(index+(-1 if event.shift_pressed else 1),controls.size())]
 next.grab_focus()
 if scroll.is_ancestor_of(next):scroll.ensure_control_visible(next)
 return true
