extends RefCounted
## Selected shop-sign HUD: original illustrated assets, live native controls.
## Keep the HUD -> compact UI link weak; the integrated lifecycle fix is retained.
var ui_ref:WeakRef
var ui:
 get:return ui_ref.get_ref()
var game
var layout_host:Control
var rail:PanelContainer
var row:HBoxContainer
var spacer:Control
var wallet:Button
var wallet_art:TextureRect
var wallet_mobile_art:TextureRect
var mobile_coin:TextureRect
var mobile_surfaces={}
var wallet_title:Label
var wallet_box:Control
var rail_art:Control
var sign_art:TextureRect
var action_art={}
var action_captions={}
const PLAY_CONTROL_WIDTH=44.0
var pause_face:Panel
var pause_art:TextureRect
var pause_caption:Label
var font_bold:Font
var last_coins=-1
var coin_tween:Tween
var button_tweens={}
var layout_queued=false
var edit_cancel:Button
var done_face:TextureRect
var cancel_art:TextureRect
var cancel_face:TextureRect
# Painted wood landmarks measured on the original assets at their midline.
# Leaf tips and transparent padding do not define the shared panel edge.
const RAIL_WOOD_RIGHT_INSET=47.0
const PANEL_WOOD_RIGHT_INSET=17.0
var action_help
const ActionHelp=preload("res://scripts/cafe_action_help.gd")
const SoftMaterial=preload("res://shaders/soft_ui_material.gdshader")
static var textures={}
static var icon_textures={}
static var art_materials={}
var soft_buttons={}
const INK=Color("554631")
const CREAM=Color("fcf6e7")
const GREEN=Color("426b49")
const ASSETS="res://assets/ui/wood_hud/"
const BOUNDS={"rail":Rect2(23,261,2126,192),"wallet":Rect2(45,73,2095,561),"sign":Rect2(239,238,1058,512),"decorate":Rect2(105,109,1071,998),"staff":Rect2(239,108,773,1053),"settings":Rect2(91,115,1069,1022)}

class RailArtwork extends Control:
 var art:Texture2D
 func _ready():mouse_filter=Control.MOUSE_FILTER_IGNORE;resized.connect(queue_redraw)
 func _draw():
  if art==null:return
  var source=art.get_size();var cap_source=source.y*1.2
  var cap=minf(size.x*.22,size.y*1.2)
  draw_texture_rect_region(art,Rect2(0,0,cap,size.y),Rect2(0,0,cap_source,source.y))
  draw_texture_rect_region(art,Rect2(cap,0,maxf(0,size.x-2*cap),size.y),Rect2(cap_source,0,source.x-2*cap_source,source.y))
  draw_texture_rect_region(art,Rect2(size.x-cap,0,cap,size.y),Rect2(source.x-cap_source,0,cap_source,source.y))

func _init(compact):ui_ref=weakref(compact);game=compact.game
func _texture(name:String)->Texture2D:
 if textures.has(name):return textures[name]
 var faithful="res://assets/ui/fidelity_hud/"+name+".png"
 if FileAccess.file_exists(faithful):
  var source=Image.new();source.load_png_from_buffer(FileAccess.get_file_as_bytes(faithful))
  if name=="coin":
   # The original coin reaches all four image edges. A transparent sampling
   # guard prevents linear/mipmap filtering from clamping its outer rim flat.
   # Keep every painted source pixel unchanged, and center the 63px-wide art.
   var side=maxi(source.get_width(),source.get_height())+8
   var guarded=Image.create(side,side,false,Image.FORMAT_RGBA8);guarded.fill(Color.TRANSPARENT)
   guarded.blit_rect(source,Rect2i(Vector2i.ZERO,source.get_size()),Vector2i((side-source.get_width())/2,(side-source.get_height())/2));source=guarded
  source.generate_mipmaps()
  var result=ImageTexture.create_from_image(source);textures[name]=result;return result
 var image=Image.load_from_file(ASSETS+name+".png")
 # Original artwork stays intact on disk. Keep runtime HUD textures small;
 # even the largest icon renders below54px, so full2k textures waste memory.
 var limit=1536 if name=="rail" else (1024 if name=="wallet" else (512 if name=="sign" else 320))
 var ratio=minf(1.0,float(limit)/image.get_width())
 if ratio<1:image.resize(limit,maxi(1,roundi(image.get_height()*ratio)),Image.INTERPOLATE_LANCZOS)
 image.generate_mipmaps()
 var atlas=AtlasTexture.new();atlas.atlas=ImageTexture.create_from_image(image);atlas.region=Rect2(BOUNDS[name].position*ratio,BOUNDS[name].size*ratio);atlas.filter_clip=true
 textures[name]=atlas;return atlas
func _icon(name:String)->Texture2D:
 if icon_textures.has(name):return icon_textures[name]
 var image=Image.new();var source=FileAccess.get_file_as_string(ASSETS+"icons/"+name+".svg").replace("currentColor","#573d28")
 image.load_svg_from_string(source,2.0)
 var result=ImageTexture.create_from_image(image);icon_textures[name]=result;return result
func _picture(parent:Control,texture:Texture2D)->TextureRect:
 var image=TextureRect.new();image.texture=texture;image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 image.material=_material_for_texture(texture)
 image.mouse_filter=Control.MOUSE_FILTER_IGNORE;image.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS;parent.add_child(image);return image
func _art_material(kind:int=0,strength:float=1.0,details:float=0.0)->ShaderMaterial:
 var key=str(kind)+":"+str(strength)+":"+str(details)
 if art_materials.has(key):return art_materials[key]
 var material=ShaderMaterial.new();material.shader=SoftMaterial
 material.set_shader_parameter("surface_kind",kind);material.set_shader_parameter("treatment_strength",strength);material.set_shader_parameter("preserve_dark_details",details)
 art_materials[key]=material;return material
func _material_for_texture(texture:Texture2D)->Material:
 if texture in icon_textures.values():return null # live symbols keep full ink contrast
 if texture==textures.get("cream_face"):return _art_material(1)
 if texture==textures.get("green_face"):return _art_material(2)
 if texture in [textures.get("wallet"),textures.get("mobile_purse")]:return _art_material(0,.65)
 if texture==textures.get("coin"):return _art_material(0,.35)
 if texture in [textures.get("decorate"),textures.get("staff"),textures.get("settings")]:return _art_material(0,.70,.45)
 return _art_material()
func _soft_button(button:Button):
 # Put only the painted face behind the native Button's live glyphs. Children
 # (catalog previews and labels) never inherit the shader or change their bounds.
 var id=button.get_instance_id()
 if soft_buttons.has(id):return
 var originals={}
 for state in ["normal","hover","pressed","hover_pressed","disabled"]:
  var original=button.get_theme_stylebox(state);originals[state]=original
  var empty=StyleBoxEmpty.new()
  for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:empty.set_content_margin(side,original.get_content_margin(side))
  button.add_theme_stylebox_override(state,empty)
 var surface=Panel.new();surface.name="PaintedSurface";surface.mouse_filter=Control.MOUSE_FILTER_IGNORE;surface.show_behind_parent=true;button.add_child(surface);surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 soft_buttons[id]={"button":button,"surface":surface,"styles":originals,"state":""}
 for signal_name in ["mouse_entered","mouse_exited","button_down","button_up","pressed","toggled"]:
  if signal_name=="toggled":button.toggled.connect(func(_pressed):_sync_soft_button(id))
  else:button.connect(signal_name,_sync_soft_button.bind(id))
 _sync_soft_button(id)
func _sync_soft_button(id:int):
 if not soft_buttons.has(id):return
 var record:Dictionary=soft_buttons[id]
 if not is_instance_valid(record.button):soft_buttons.erase(id);return
 var button:Button=record.button
 var state="normal"
 match button.get_draw_mode():
  BaseButton.DRAW_PRESSED:state="pressed"
  BaseButton.DRAW_HOVER:state="hover"
  BaseButton.DRAW_DISABLED:state="disabled"
  BaseButton.DRAW_HOVER_PRESSED:state="hover_pressed"
 if button.has_meta("soft_panel_button"):
  var focus_ink=CREAM if bool(button.get_meta("soft_panel_accent",false)) or state in ["pressed","hover_pressed"] else INK
  if button.get_theme_color("font_focus_color")!=focus_ink:button.add_theme_color_override("font_focus_color",focus_ink)
 if record.state==state:return
 record.state=state
 var style:StyleBox=record.styles[state];record.surface.add_theme_stylebox_override("panel",style)
 record.surface.material=_material_for_texture((style as StyleBoxTexture).texture) if style is StyleBoxTexture else null
func _refresh_soft_buttons():
 for id in soft_buttons.keys():_sync_soft_button(id)
func theme_panel(panel:PanelContainer,frame:bool=false,padding:float=16.0):
 var texture_name="shop_frame" if frame else "cream_face"
 var surface=texture_style(texture_name,18)
 if frame:
  # Retain complete leaf clusters and curved shadow in their original corners.
  # Only the clean middle strips stretch into a tall dialog.
  surface.texture_margin_left=64;surface.texture_margin_right=64;surface.texture_margin_top=64;surface.texture_margin_bottom=64
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:surface.set_content_margin(side,padding)
 if frame:
  surface.content_margin_left=padding+8;surface.content_margin_right=padding+8;surface.content_margin_top=padding+4;surface.content_margin_bottom=maxf(0,padding-4)
 panel.add_theme_stylebox_override("panel",surface);panel.material=_art_material(0 if frame else 1)
func theme_button(button:Button,accent:bool=false):
 if button.has_meta("soft_panel_button"):return
 button.set_meta("soft_panel_button",true)
 button.set_meta("soft_panel_accent",accent)
 var normal_texture="green_face" if accent else "cream_face"
 button.add_theme_stylebox_override("normal",texture_style(normal_texture,14))
 button.add_theme_stylebox_override("hover",texture_style(normal_texture,14,Color(1.06,1.05,1.0)))
 button.add_theme_stylebox_override("pressed",texture_style("green_face",14))
 button.add_theme_stylebox_override("hover_pressed",texture_style("green_face",14,Color(1.06,1.05,1.0)))
 button.add_theme_stylebox_override("disabled",texture_style("cream_face",14,Color(.82,.80,.74)))
 button.add_theme_font_override("font",font_bold)
 for state in ["font_color","font_hover_color","font_focus_color"]:button.add_theme_color_override(state,CREAM if accent else INK)
 for state in ["font_pressed_color","font_hover_pressed_color"]:button.add_theme_color_override(state,CREAM)
 button.add_theme_color_override("font_disabled_color",Color("817764"))
 var focus=_surface(Color.TRANSPARENT,Color("725237"),12,0);focus.set_border_width_all(2);button.add_theme_stylebox_override("focus",focus)
 button.custom_minimum_size.y=maxf(44,button.custom_minimum_size.y);_soft_button(button)
func theme_panel_contents(node:Node):
 for child in node.get_children():
  if child==game.pause_button:continue
  if child is Button:
   theme_button(child)
  elif child is Label:
   if child.get_theme_font_size("font_size")>=18:child.add_theme_font_override("font",font_bold);child.add_theme_color_override("font_color",INK)
   if child.autowrap_mode!=TextServer.AUTOWRAP_OFF:child.custom_minimum_size.x=0;child.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  theme_panel_contents(child)
func theme_scroll(scroll:ScrollContainer):
 scroll.add_theme_constant_override("scrollbar_h_separation",6)
 var bar=scroll.get_v_scroll_bar();bar.custom_minimum_size.x=9
 var track=_surface(Color("a69678"),Color.TRANSPARENT,4,0)
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:track.set_content_margin(side,0)
 # ScrollContainer reserves the intrinsic minimum, not custom_minimum_size.
 # Give the painted 9px bar real width before it lays out wrapped content.
 track.content_margin_left=4;track.content_margin_right=5
 bar.add_theme_stylebox_override("scroll",track)
 for state in ["grabber","grabber_highlight","grabber_pressed"]:
  var grab=_surface(Color("f2e8d2"),Color("8e8168"),4,0)
  for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:grab.set_content_margin(side,0)
  bar.add_theme_stylebox_override(state,grab)
func _label(parent:Control,text:String,size:int,color:Color=INK)->Label:
 var label=game.label(text,size,color);label.add_theme_font_override("font",font_bold);label.mouse_filter=Control.MOUSE_FILTER_IGNORE
 label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;label.clip_text=true;parent.add_child(label);return label
func _surface(fill:Color,border:Color,radius:int=10,padding:float=3)->StyleBoxFlat:
 var style=game._style(fill,border,radius);style.content_margin_left=padding;style.content_margin_right=padding;style.content_margin_top=2;style.content_margin_bottom=2;return style
func _bind_motion(button:Button):
 button.size_flags_vertical=Control.SIZE_SHRINK_CENTER
 button.resized.connect(func():button.pivot_offset=button.size/2)
 button.resized.connect(_queue_layout)
 button.button_down.connect(func():_press_motion(button,true))
 button.button_up.connect(func():_press_motion(button,false))
 button.mouse_exited.connect(func():_press_motion(button,false))
func _press_motion(button:Button,down:bool):
 var id=button.get_instance_id()
 if button_tweens.has(id) and is_instance_valid(button_tweens[id]):button_tweens[id].kill()
 var tween=game.create_tween();button_tweens[id]=tween;tween.set_trans(Tween.TRANS_QUAD);tween.set_ease(Tween.EASE_OUT)
 tween.tween_property(button,"scale",Vector2.ONE*(.95 if down else 1.0),.07 if down else .13)
func _art_button(button:Button,name:String):
 for state in ["normal","disabled","hover","pressed","hover_pressed"]:button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
 var focus=_surface(Color.TRANSPARENT,Color("fff3be"),12);focus.set_border_width_all(2);button.add_theme_stylebox_override("focus",focus)
 for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color","font_disabled_color"]:button.add_theme_color_override(state,Color.TRANSPARENT)
 button.add_theme_font_override("font",font_bold);button.add_theme_font_size_override("font_size",1) # live caption owns visual type; keep semantic Button text
 action_art[name]=_picture(button,_texture(name));action_captions[name]=_label(button,button.text,14)
 button.mouse_entered.connect(func():action_art[name].modulate=Color(1.08,1.06,1.02) if not button.disabled else Color(.6,.6,.6))
 button.mouse_exited.connect(func():action_art[name].modulate=Color.WHITE if not button.disabled else Color(.6,.6,.6))
 _bind_motion(button)
func texture_style(name:String,corner=16.0,tint=Color.WHITE)->StyleBoxTexture:
 var style=StyleBoxTexture.new();style.texture=_texture(name);style.modulate_color=tint
 corner=minf(corner,18.0)
 var texture_size=style.texture.get_size()
 style.set_texture_margin_all(minf(texture_size.x,texture_size.y)*.24)
 style.axis_stretch_horizontal=StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH;style.axis_stretch_vertical=StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_expand_margin(side,0)
 style.content_margin_left=6;style.content_margin_right=6;style.content_margin_top=4;style.content_margin_bottom=5
 # Corner rendering uses a scale factor; artwork remains original painted pixels.
 style.texture_margin_left=corner;style.texture_margin_right=corner;style.texture_margin_top=corner;style.texture_margin_bottom=corner
 return style
func _cream_button(button:Button,roundness:int=10):
 button.add_theme_stylebox_override("normal",texture_style("cream_face",roundness))
 button.add_theme_stylebox_override("hover",texture_style("cream_face",roundness,Color(1.08,1.06,1.02)))
 button.add_theme_stylebox_override("pressed",texture_style("green_face" if FileAccess.file_exists("res://assets/ui/fidelity_hud/green_face.png") else "cream_face",roundness))
 button.add_theme_stylebox_override("hover_pressed",button.get_theme_stylebox("pressed"))
 button.add_theme_stylebox_override("disabled",texture_style("cream_face",roundness,Color(.74,.73,.69)))
 var focus=_surface(Color.TRANSPARENT,Color("fff8df"),roundness,4);focus.set_border_width_all(2);button.add_theme_stylebox_override("focus",focus)
 button.add_theme_font_override("font",font_bold)
 for state in ["font_color","font_hover_color","font_focus_color"]:button.add_theme_color_override(state,INK)
 button.add_theme_color_override("font_pressed_color",CREAM);button.add_theme_color_override("font_hover_pressed_color",CREAM);button.add_theme_color_override("font_disabled_color",Color("887965"))
 _bind_motion(button)

func setup():
 var file=FontFile.new();file.load_dynamic_font("res://assets/fonts/Nunito-ExtraBold.ttf")
 font_bold=file # Explicit static800 weight; no variable-axis fallback to200.
 rail=ui.top_row.get_parent();row=ui.top_row;spacer=row.get_child(2)
 row.resized.connect(_queue_layout)
 rail.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
 rail_art=RailArtwork.new();rail_art.art=_texture("rail");rail_art.material=_art_material();game.ui.add_child(rail_art);rail_art.z_index=-1
 # A CanvasLayer child keeps screen positioning without top-level draw-order promotion.
 ui.title.hide();spacer.hide();game.state_badge.hide()
 wallet=Button.new();wallet.mouse_filter=Control.MOUSE_FILTER_STOP;wallet.size_flags_vertical=Control.SIZE_SHRINK_CENTER
 for state in ["normal","hover","pressed","hover_pressed","disabled"]:wallet.add_theme_stylebox_override(state,StyleBoxEmpty.new())
 var wallet_focus=_surface(Color.TRANSPARENT,Color("fff3be"),12);wallet_focus.set_border_width_all(2);wallet.add_theme_stylebox_override("focus",wallet_focus)
 wallet.pressed.connect(_show_wallet_balance);wallet.focus_entered.connect(_show_wallet_balance)
 row.add_child(wallet);row.move_child(wallet,2);wallet.resized.connect(_queue_layout)
 wallet_art=_picture(wallet,_texture("wallet"))
 wallet_mobile_art=_picture(wallet,_texture("mobile_purse"))
 mobile_coin=_picture(wallet,_texture("coin"));mobile_coin.hide()
 wallet_box=Control.new();wallet_box.mouse_filter=Control.MOUSE_FILTER_IGNORE;wallet.add_child(wallet_box)
 wallet_title=_label(wallet_box,"Coins",11)
 game.top_text.reparent(wallet_box);game.top_text.add_theme_font_override("font",font_bold);game.top_text.add_theme_color_override("font_color",INK)
 game.top_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;game.top_text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;game.top_text.mouse_filter=Control.MOUSE_FILTER_IGNORE;game.top_text.clip_text=true
 for state in ["normal","disabled","pressed","hover_pressed"]:game.business_button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
 game.business_button.add_theme_stylebox_override("hover",_surface(Color(1,.95,.77,.12),Color.TRANSPARENT,12))
 var focus=_surface(Color.TRANSPARENT,Color("fff3be"),12);focus.set_border_width_all(2);game.business_button.add_theme_stylebox_override("focus",focus)
 _bind_motion(game.business_button)
 sign_art=_picture(game.business_button,_texture("sign"));game.business_button.move_child(sign_art,0)
 ui.business_state.reparent(game.business_button);ui.business_action.reparent(game.business_button)
 for label in [ui.business_state,ui.business_action]:label.add_theme_font_override("font",font_bold);label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;label.clip_text=true
 _art_button(game.edit_button,"decorate");_art_button(ui.staff_access,"staff");_art_button(ui.settings_button,"settings")
 done_face=_picture(game.edit_button,_texture("cream_face"));game.edit_button.move_child(done_face,0);done_face.hide()
 edit_cancel=ui._small_button("",cancel_edit_action,44);_cream_button(edit_cancel,12);cancel_face=_picture(edit_cancel,_texture("cream_face"));cancel_art=_picture(edit_cancel,_icon("plus"));cancel_art.rotation=PI/4.0
 for state in ["normal","hover","pressed","hover_pressed","disabled"]:edit_cancel.add_theme_stylebox_override(state,StyleBoxEmpty.new())
 edit_cancel.accessibility_name="Cancel current action";edit_cancel.tooltip_text="Cancel current preview or move. Completed changes stay saved.";edit_cancel.accessibility_description=edit_cancel.tooltip_text
 game.edit_button.tooltip_text="Decorate the café";ui.staff_access.tooltip_text="Staff · shifts, hiring and wages";ui.settings_button.tooltip_text="Settings · music and sound"
 for state in ["normal","disabled"]:game.pause_button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
 game.pause_button.add_theme_font_size_override("font_size",1) # The visible icon owns this44px target; hidden Pause/Resume text must not grow the HBox.
 for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color","font_disabled_color"]:game.pause_button.add_theme_color_override(state,Color.TRANSPARENT)
 game.pause_button.add_theme_stylebox_override("hover",_surface(Color(1,.95,.77,.1),Color.TRANSPARENT,10))
 game.pause_button.add_theme_stylebox_override("pressed",_surface(Color(.3,.2,.1,.1),Color.TRANSPARENT,10))
 game.pause_button.add_theme_stylebox_override("hover_pressed",game.pause_button.get_theme_stylebox("pressed"))
 game.pause_button.add_theme_stylebox_override("focus",focus)
 pause_face=Panel.new();pause_face.material=_art_material(1);pause_face.mouse_filter=Control.MOUSE_FILTER_IGNORE;pause_face.add_theme_stylebox_override("panel",texture_style("cream_face",14));game.pause_button.add_child(pause_face)
 pause_art=_picture(game.pause_button,_icon("player-pause"));pause_caption=_label(game.pause_button,"Pause",13);_bind_motion(game.pause_button)
 game.business_button.accessibility_name="Café service controls";game.edit_button.accessibility_name="Decorate café";ui.staff_access.accessibility_name="Staff";ui.settings_button.accessibility_name="Settings"
 layout_host=Control.new();layout_host.mouse_filter=Control.MOUSE_FILTER_IGNORE;game.ui.add_child(layout_host)
 for control in [wallet,game.business_button,game.edit_button,ui.staff_access,ui.settings_button]:control.reparent(layout_host)
 layout_host.add_child(edit_cancel);edit_cancel.hide()
 for button in [wallet,game.business_button,game.edit_button,ui.staff_access,ui.settings_button]:
  var surface=Panel.new();surface.mouse_filter=Control.MOUSE_FILTER_IGNORE;surface.show_behind_parent=true;surface.material=_art_material(2 if button==game.business_button else 1)
  surface.add_theme_stylebox_override("panel",texture_style("green_face" if button==game.business_button else "cream_face",14));button.add_child(surface);button.move_child(surface,0);surface.hide();mobile_surfaces[button]=surface
 rail.hide()
 game.edit_button.pressed.connect(_after_edit_toggle)
 action_help=ActionHelp.new(self);action_help.setup([game.business_button,game.edit_button,edit_cancel,ui.staff_access,ui.settings_button,game.pause_button])

func _safe_insets()->Vector4:
 if game.has_meta("hud_safe_insets"):
  var explicit=game.get_meta("hud_safe_insets")
  if explicit is Vector4:return explicit
 if OS.has_feature("android") or OS.has_feature("ios"):
  var safe=Rect2(DisplayServer.get_display_safe_area());var window=Vector2(DisplayServer.window_get_size())
  var view=game.get_viewport().get_visible_rect().size
  if safe.size.x>0 and window.x>0:
   var ratio=view/window
   return Vector4(maxf(0,safe.position.x)*ratio.x,maxf(0,safe.position.y)*ratio.y,maxf(0,window.x-safe.end.x)*ratio.x,maxf(0,window.y-safe.end.y)*ratio.y)
 return Vector4.ZERO
func _place(control:Control,rect:Rect2):
 control.custom_minimum_size=Vector2.ZERO;control.position=rect.position;control.size=rect.size
func _font(label:Label,size:int):label.add_theme_font_size_override("font_size",size)
func _fit_mobile_caption(label:Label):
 var target=11
 if font_bold.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,target).x>label.size.x:target=10
 _font(label,target)
func _show_wallet_balance():
 # Compact balances remain discoverable by mouse, touch and keyboard.
 if action_help!=null and game.top_text.text!=ui.Money.amount(game.model.coins):
  action_help.show(wallet)
  # On wrapped layouts, keep the hint below the second row of live controls.
  action_help.panel.position.y=maxf(action_help.panel.position.y,layout_host.get_global_rect().end.y+6)
func sync(width:float):
 if layout_host==null:return
 var insets=_safe_insets()
 ui.title.hide();spacer.hide();game.state_badge.hide();rail.hide()
 game.top_text.text=ui.Money.amount(game.model.coins);game.top_text.custom_minimum_size=Vector2.ZERO
 wallet.tooltip_text="Leaf Coins · "+ui.Money.amount(game.model.coins)
 sign_art.modulate=Color.WHITE if game.model.operating_open else Color(.81,.77,.68)
 ui.business_state.add_theme_color_override("font_color",CREAM)
 ui.staff_access.show();ui.mobile_staff_access.hide()
 edit_cancel.visible=game.editing;edit_cancel.disabled=not has_edit_action();done_face.visible=game.editing
 action_art.decorate.texture=_icon("check") if game.editing else _texture("decorate")
 action_art.decorate.material=null if game.editing else _material_for_texture(action_art.decorate.texture)
 cancel_face.modulate=Color(.74,.73,.69) if edit_cancel.disabled else Color.WHITE
 cancel_art.modulate=Color(.55,.55,.55) if edit_cancel.disabled else Color.WHITE
 for name in ["decorate","staff","settings"]:
  var button=game.edit_button if name=="decorate" else (ui.staff_access if name=="staff" else ui.settings_button)
  action_art[name].modulate=Color(1,1,1,.48) if button.disabled else Color.WHITE
 game.edit_button.accessibility_name="Finish decorating" if game.editing else "Decorate café"
 game.edit_button.tooltip_text="Finish decorating. Completed changes stay saved." if game.editing else game.edit_button.accessibility_name
 game.edit_button.accessibility_description=game.edit_button.tooltip_text
 game.pause_button.accessibility_name="Resume service" if game.paused else "Pause service";game.pause_button.tooltip_text=game.pause_button.accessibility_name
 game.edit_button.toggle_mode=true;game.edit_button.set_pressed_no_signal(game.editing);ui.staff_access.toggle_mode=true;ui.staff_access.set_pressed_no_signal(ui.staff_panel.panel.visible);ui.settings_button.toggle_mode=true;ui.settings_button.set_pressed_no_signal(game.settings.visible)
 pause_art.texture=_icon("player-play" if game.paused else "player-pause")
 _layout_unified_toolbar(width)
 _refresh_soft_buttons()
 if last_coins>=0 and game.model.coins>last_coins:
  if is_instance_valid(coin_tween):coin_tween.kill()
  wallet.pivot_offset=wallet.size/2;wallet.scale=Vector2.ONE*1.035
  coin_tween=game.create_tween();coin_tween.set_trans(Tween.TRANS_BACK);coin_tween.set_ease(Tween.EASE_OUT);coin_tween.tween_property(wallet,"scale",Vector2.ONE,.22)
 last_coins=game.model.coins
 var notice_y=layout_host.get_global_rect().end.y+8
 ui.earnings.position=Vector2(clampf(game.top_text.get_global_rect().get_center().x-60,insets.x+8,width-insets.z-132),notice_y)
 if ui.wallet_notice!=null:ui.wallet_notice.sync_position()

func _reduced_motion_requested()->bool:
 if game.has_meta("hud_reduce_motion"):return bool(game.get_meta("hud_reduce_motion"))
 # Godot4.6 exposes the operating-system preference on supported platforms.
 if DisplayServer.accessibility_should_reduce_animation()==1:return true
 if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
  return bool(Engine.get_singleton("JavaScriptBridge").eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches"))
 return false

func has_edit_action()->bool:
 if not game.editing:return false
 return game.selected_kind!="" or game.selected_id>=0 or game.build_tools.active() or ui.selected_wall!="" or ui.selected_shell!="" or not ui.pending_wall.is_empty() or game.interaction.drag_active or game.interaction.preview_active
func _close_pending_edit_popovers():
 ui.pending_wall={}
 for popup in [ui.finishes,ui.floor_repair_review,ui.wall_review]:
  if is_instance_valid(popup):popup.hide()
func _after_edit_toggle():
 if game.editing:return
 _close_pending_edit_popovers();ui.sync()
func cancel_edit_action():
 if not has_edit_action():return
 # Existing atomic actions are already committed; only the live selection/preview is discarded.
 _close_pending_edit_popovers();game._cancel_selection();ui.sync();game.illustration.queue_redraw()
func popup_right()->float:
 if layout_host.get_meta("mobile_layout",false):return game.get_viewport().get_visible_rect().size.x-_safe_insets().z-8
 var view=game.get_viewport().get_visible_rect().size;var insets=_safe_insets()
 var safe_right=view.x-insets.z
 if rail_art==null:return safe_right
 var source=_texture("rail").get_size();var cap=minf(rail_art.size.x*.22,rail_art.size.y*1.2)
 var painted_right=rail_art.get_global_rect().end.x-RAIL_WOOD_RIGHT_INSET*cap/(source.y*1.2)
 return minf(safe_right,painted_right+PANEL_WOOD_RIGHT_INSET)
func popup_left(width:float)->float:
 return maxf(_safe_insets().x,popup_right()-width)

func popup_top()->float:
 if game.get_viewport().get_visible_rect().size.y<600:return _safe_insets().y+12
 return maxf(92,layout_host.get_global_rect().end.y+8)
func popup_height_budget()->float:
 var view=game.get_viewport().get_visible_rect().size;var insets=_safe_insets()
 var safe_height=maxf(0,view.y-insets.y-insets.w)
 return minf(maxf(0,view.y-insets.w-popup_top()-12),safe_height*.82)
func popup_y(height:float)->float:
 var view=game.get_viewport().get_visible_rect().size;var insets=_safe_insets()
 if view.y<600:return insets.y+maxf(12,(view.y-insets.y-insets.w-height)*.5)
 return popup_top()
func safe_bottom()->float:
 return _safe_insets().w

func _queue_layout():
 if layout_queued:return
 layout_queued=true
 _settle_layout.call_deferred()
func _settle_layout():
 layout_queued=false
 if ui==null or not is_instance_valid(game) or not is_instance_valid(rail):return
 sync(game.get_viewport().get_visible_rect().size.x)

func _layout_unified_toolbar(width:float):
 var safe=_safe_insets();var view=game.get_viewport().get_visible_rect().size
 var mobile=width-safe.x-safe.z<700 or (view.y-safe.y-safe.w<500 and width<1000)
 layout_host.set_meta("mobile_layout",mobile)
 rail_art.visible=not mobile;mobile_coin.visible=mobile
 for surface in mobile_surfaces.values():surface.visible=mobile
 if mobile:
  _layout_mobile_toolbar(width)
  return
 sign_art.show()
 # One control/art family on every device. Narrow views wrap the same real
 # buttons instead of turning Open into a different controls-menu action.
 var inset=_safe_insets();var usable=width-inset.x-inset.z
 var wrapped=usable<566.0;var scale=1.0
 # Lay out the right-hand actions by painted bounds, not transparent targets.
 # The portrait staff art and landscape gear keep their original proportions.
 var roomy=usable>=850.0
 var action_gap=18.0 if roomy else 8.0
 var group_gap=2.0 if usable<370.0 else (4.0 if not wrapped and usable<650.0 else (16.0 if roomy else 8.0))
 var pair_gap=2.0 if usable<370.0 else (6.0 if roomy else 4.0)
 # Balance the wide sparse brush/bucket against the denser portrait silhouette.
 # Compact dimensions remain unchanged; all artwork keeps its native aspect.
 var decorate_width=48.0 if roomy else 40.0
 var decorate_size=Vector2(decorate_width,decorate_width*_texture("decorate").get_height()/_texture("decorate").get_width())
 var staff_size=Vector2(float(_texture("staff").get_width())/_texture("staff").get_height(),1)*(48.0 if roomy else 44.0)
 var settings_size=Vector2(1,float(_texture("settings").get_height())/_texture("settings").get_width())*(56.0 if roomy else 40.0)
 var edit_width=88.0+pair_gap if game.editing else decorate_size.x
 var action_width=edit_width+action_gap*2+staff_size.x+settings_size.x
 var max_action_width=88.0+pair_gap+action_gap*2+staff_size.x+settings_size.x
 var wallet_width=140.0;var sign_width=76.0;var gap=8.0 if usable>=750 else 4.0
 # The end cap and the clear gap after the gear are separate from its hit box.
 var end_padding=32.0 if not wrapped and usable<650.0 else (44.0 if roomy else 40.0)
 if not wrapped:
  var identity_limit=280.0 if game.get_viewport().get_visible_rect().size.y-inset.y-inset.w<600.0 else 380.0
  var outer_margin=0.0 if usable<650.0 else 16.0
  var identity_width=minf(identity_limit,usable-outer_margin-(PLAY_CONTROL_WIDTH+group_gap+max_action_width+gap*2+end_padding))
  sign_width=maxf(76,identity_width*120.0/380.0)
  wallet_width=identity_width-sign_width
 var design_width=wallet_width+sign_width+gap*2+PLAY_CONTROL_WIDTH+group_gap+action_width+end_padding
 var w=minf(430,usable if usable<370.0 else usable-16) if wrapped else design_width
 var wallet_height=wallet_width*155.0/415.0*scale
 var h=108.0 if wrapped else maxf(56*scale,wallet_height)+4.0
 layout_host.position=Vector2(inset.x+(usable-w)*.5,inset.y+2);layout_host.size=Vector2(w,h)
 rail_art.position=layout_host.position+Vector2(0,5);rail_art.size=Vector2(w,h-5);rail_art.queue_redraw()
 wallet_art.show();wallet_mobile_art.hide();wallet_title.show();ui.play_controls.show();ui.play_panel.hide()
 var wallet_x=(w-wallet_width-sign_width-12)*.5 if wrapped else 0.0
 var wallet_y=0.0;var sign_x=wallet_x+wallet_width+12 if wrapped else (wallet_width+gap)*scale
 _place(wallet,Rect2(wallet_x,wallet_y,wallet_width*scale,wallet_height));wallet_art.position=Vector2.ZERO;wallet_art.size=wallet.size
 _place(game.business_button,Rect2(sign_x,0,sign_width*scale,(52 if wrapped else maxf(44,sign_width*0.7))*scale))
 sign_art.position=Vector2.ZERO;sign_art.size=game.business_button.size
 var sw=wallet.size.x/415.0
 wallet_box.position=Vector2(180*sw,32*sw);wallet_box.size=Vector2(163*sw,110*sw)
 # Center the amount under Coins, preserving clearance from the painted
 # purse/coins and leaf pins on either side of the cream plaque.
 var money_font=maxi(13,roundi(32*sw));var money_width=136*sw
 game.top_text.text=_wallet_amount(game.model.coins,money_width,money_font)
 # At the narrow one-row breakpoint, even 999M can need one smaller step.
 while money_font>12 and font_bold.get_string_size(game.top_text.text,HORIZONTAL_ALIGNMENT_LEFT,-1,money_font).x>money_width:
  money_font-=1;game.top_text.text=_wallet_amount(game.model.coins,money_width,money_font)
 var exact=ui.Money.amount(game.model.coins)+" Leaf Coins"
 var compact=game.top_text.text!=ui.Money.amount(game.model.coins)
 game.top_text.tooltip_text=exact;wallet.tooltip_text=exact;wallet.accessibility_name=exact
 wallet.accessibility_description="Tap or click to show the full balance" if compact else ""
 wallet.focus_mode=Control.FOCUS_ALL if compact else Control.FOCUS_NONE
 wallet.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND if compact else Control.CURSOR_ARROW
 var title_font=maxi(11,roundi(20*sw));var title_h=font_bold.get_height(title_font);var money_h=font_bold.get_height(money_font)
 var ty=maxf(0,(wallet_box.size.y-title_h-money_h-1)*.5)
 wallet_title.position=Vector2(0,ty);wallet_title.size=Vector2(wallet_box.size.x,title_h);_font(wallet_title,title_font)
 game.top_text.position=Vector2((wallet_box.size.x-money_width)*.5,ty+title_h+1);game.top_text.size=Vector2(money_width,money_h);_font(game.top_text,money_font)
 ui.business_action.hide();ui.business_state.show();ui.business_state.text="RECOVERY" if game.save_recovery_blocked else game.model.operating_status().to_upper()
 var sign_scale=game.business_button.size.y/56.0
 var text_inset=(10.0 if game.save_recovery_blocked else 2.0)*sign_scale
 ui.business_state.position=Vector2(text_inset,24*sign_scale);ui.business_state.size=Vector2(game.business_button.size.x-2*text_inset,20*sign_scale)
 var state_font=maxi(13,floori(13*sign_scale))
 while state_font>9 and font_bold.get_string_size(ui.business_state.text,HORIZONTAL_ALIGNMENT_LEFT,-1,state_font).x>ui.business_state.size.x:state_font-=1
 _font(ui.business_state,state_font)
 game.business_button.accessibility_name="Close café admissions" if game.model.operating_open else "Reopen café admissions"
 game.business_button.accessibility_description="Current guests can finish" if game.model.operating_open else "Welcome new guests"
 game.business_button.tooltip_text=game.business_button.accessibility_name
 var controls_width=PLAY_CONTROL_WIDTH+group_gap+action_width
 var controls_x=(w-controls_width)*.5 if wrapped else wallet_width+sign_width+gap*2
 if wrapped:
  var cap=minf(w*.22,rail_art.size.y*1.2)
  var wood_inset=RAIL_WOOD_RIGHT_INSET*cap/(_texture("rail").get_height()*1.2)
  controls_x=minf(controls_x,w-wood_inset-(8 if usable<370.0 else 12)-controls_width)
 var controls_y=52.0 if wrapped else maxf(2,(h-56*scale)*.5)
 _layout_unified_play_controls(scale)
 _place(ui.play_controls,Rect2(controls_x,controls_y,PLAY_CONTROL_WIDTH,56))
 var center_y=controls_y+28
 var action_x=controls_x+PLAY_CONTROL_WIDTH+group_gap
 if game.editing:
  _place(game.edit_button,Rect2(action_x,center_y-22,44,44))
  _place(edit_cancel,Rect2(action_x+44+pair_gap,center_y-22,44,44))
 else:
  _place_action_art(game.edit_button,"decorate",Vector2(action_x,center_y),decorate_size)
 edit_cancel.visible=game.editing
 action_x+=edit_width+action_gap
 _place_action_art(ui.staff_access,"staff",Vector2(action_x,center_y),staff_size)
 action_x+=staff_size.x+action_gap
 _place_action_art(ui.settings_button,"settings",Vector2(action_x,center_y),settings_size)
 for name in ["decorate","staff","settings"]:action_captions[name].hide()
 if game.editing:
  done_face.position=Vector2.ZERO;done_face.size=game.edit_button.size;action_art.decorate.position=Vector2(9,9)*scale;action_art.decorate.size=Vector2(26,26)*scale
  cancel_face.position=Vector2.ZERO;cancel_face.size=edit_cancel.size;cancel_art.position=Vector2(10,10)*scale;cancel_art.size=Vector2(24,24)*scale;cancel_art.pivot_offset=cancel_art.size/2
 layout_host.set_meta("unified_wrapped",wrapped)
 game.settings.offset_top=popup_top()
func _layout_mobile_toolbar(width:float):
 # Phone UI is composed from small painted controls, not a squeezed shop sign.
 # Status and tools have distinct groups; every live action retains a 44px target.
 var inset=_safe_insets();var usable=width-inset.x-inset.z;var wrapped=usable<550
 var w=usable-16;var h=92.0 if wrapped else 44.0
 layout_host.position=Vector2(inset.x+8,inset.y+6);layout_host.size=Vector2(w,h)
 layout_host.set_meta("unified_wrapped",wrapped)
 wallet_art.hide();wallet_mobile_art.hide();wallet_title.hide();sign_art.hide()
 ui.play_controls.show();ui.play_panel.hide();ui.business_action.hide();ui.business_state.show()
 _place(wallet,Rect2(0,0,106,44))
 mobile_coin.position=Vector2(7,8);mobile_coin.size=Vector2(28,28)
 wallet_box.position=Vector2(38,0);wallet_box.size=Vector2(62,44)
 game.top_text.position=Vector2.ZERO;game.top_text.size=wallet_box.size;_font(game.top_text,18)
 game.top_text.text=_wallet_amount(game.model.coins,62,18)
 var exact=ui.Money.amount(game.model.coins)+" Leaf Coins";var compact=game.top_text.text!=ui.Money.amount(game.model.coins)
 game.top_text.tooltip_text=exact;wallet.tooltip_text=exact;wallet.accessibility_name=exact
 wallet.accessibility_description="Tap or click to show the full balance" if compact else ""
 wallet.focus_mode=Control.FOCUS_ALL if compact else Control.FOCUS_NONE
 wallet.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND if compact else Control.CURSOR_ARROW
 _place(game.business_button,Rect2(112,0,80,44))
 ui.business_state.position=Vector2(3,0);ui.business_state.size=Vector2(74,44);_font(ui.business_state,12 if game.save_recovery_blocked else 14)
 ui.business_state.text="RECOVERY" if game.save_recovery_blocked else game.model.operating_status().to_upper()
 game.business_button.accessibility_name="Close café admissions" if game.model.operating_open else "Reopen café admissions"
 game.business_button.accessibility_description="Current guests can finish" if game.model.operating_open else "Welcome new guests"
 game.business_button.tooltip_text=game.business_button.accessibility_name
 var tool_y=48.0 if wrapped else 0.0
 _layout_unified_play_controls(1.0,true)
 _place(ui.play_controls,Rect2(0 if wrapped else 198,tool_y,PLAY_CONTROL_WIDTH,44))
 var action_width=44.0;var gap=6.0
 var action_count=(2 if wrapped else 3)+(1 if game.editing else 0)
 var action_x=w-action_count*action_width-(action_count-1)*gap
 _place(game.edit_button,Rect2(action_x,tool_y,44,44))
 _mobile_action_art(game.edit_button,"decorate")
 var staff_x=action_x+action_width+gap
 if game.editing:
  _place(edit_cancel,Rect2(action_x+50,tool_y,44,44));staff_x+=50
  done_face.position=Vector2.ZERO;done_face.size=game.edit_button.size
  action_art.decorate.position=Vector2(11,11);action_art.decorate.size=Vector2(22,22)
  cancel_face.position=Vector2.ZERO;cancel_face.size=edit_cancel.size;cancel_art.position=Vector2(11,11);cancel_art.size=Vector2(22,22);cancel_art.pivot_offset=cancel_art.size/2
 _place(ui.staff_access,Rect2(staff_x,tool_y,44,44));_mobile_action_art(ui.staff_access,"staff")
 _place(ui.settings_button,Rect2(w-44,0,44,44));_mobile_action_art(ui.settings_button,"settings")
 for button in mobile_surfaces:
  var surface:Panel=mobile_surfaces[button];surface.position=Vector2.ZERO;surface.size=button.size
 mobile_surfaces[game.business_button].modulate=Color.WHITE if game.model.operating_open else Color(.81,.77,.68)
 mobile_surfaces[game.edit_button].visible=not game.editing
 edit_cancel.visible=game.editing
 game.settings.offset_top=popup_top()
func _mobile_action_art(button:Button,name:String):
 var art:TextureRect=action_art[name];var texture_size=art.texture.get_size()
 var extent=Vector2(30,32) if name=="staff" else Vector2(32,32)
 var fitted=texture_size*minf(extent.x/texture_size.x,extent.y/texture_size.y)
 art.position=(button.size-fitted)*.5;art.size=fitted;action_captions[name].hide()

func _place_action_art(button:Button,name:String,paint_origin:Vector2,paint_size:Vector2):
 # One optical centerline and one edge-to-edge gap, with independent 44px targets.
 var target=Vector2(maxf(44,paint_size.x+4),maxf(44,paint_size.y))
 _place(button,Rect2(paint_origin-Vector2((target.x-paint_size.x)*.5,target.y*.5),target))
 action_art[name].position=(target-paint_size)*.5
 action_art[name].size=paint_size

func _wallet_amount(value:int,width:float,font_size:int)->String:
 var exact=ui.Money.amount(value)
 if font_bold.get_string_size(exact,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x<=width:return exact
 # Abbreviate only when the measured exact amount cannot fit at this size.
 # The wallet tooltip and click/tap hint retain the full balance.
 var magnitude=absf(float(value));var units=[[1000000000000.0,"T"],[1000000000.0,"B"],[1000000.0,"M"],[1000.0,"K"]]
 for unit in units:
  if magnitude>=unit[0]:
   var truncated=floorf(magnitude/unit[0]*10)/10.0
   var prefix="−" if value<0 else ""
   var text=prefix+("%.1f"%truncated).trim_suffix(".0")+unit[1]
   if font_bold.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width:
    text=prefix+str(floori(magnitude/unit[0]))+unit[1]
   return text
 return exact
func _layout_unified_play_controls(s:float,mobile:bool=false):
 var top=0.0 if mobile else 6.0
 var target_height=44.0 if mobile else 56.0
 ui.play_controls.add_theme_constant_override("separation",roundi(4*s));ui.play_controls.alignment=BoxContainer.ALIGNMENT_BEGIN
 game.pause_button.custom_minimum_size=Vector2(44,target_height)*s
 pause_face.position=Vector2(0,top)*s;pause_face.size=Vector2(44,44)*s;pause_art.position=Vector2(12,top+12)*s;pause_art.size=Vector2(20,20)*s;pause_caption.hide()
