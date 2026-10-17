extends Node
## Actual production MusicPanel, Settings and HUD material. No café/world/audio playback.
const MusicPanel=preload("res://scripts/ui/cafe_music_panel.gd")
const Hud=preload("res://scripts/ui/cafe_hud.gd")
const Settings=preload("res://scripts/ui/cafe_settings.gd")
const Catalog=preload("res://scripts/ui/cafe_music_catalog.gd")
const ArtFont=preload("res://assets/fonts/NotoSans-Regular.ttf")
const DARK=Color("29473c")
const CREAM=Color("f6f0dc")
const SAGE=Color("72896b")
class HostAdapter extends RefCounted:
 var game
 var hud
 var music_access
 func _init(owner):game=owner
 func _panel():
  var p=PanelContainer.new();p.z_index=50;game.ui.add_child(p);p.hide();return p
 func _popup_at(p:Control,_width=320.0):p.show()
 func has_open_popup():return true
 func sync():pass
var ui=CanvasLayer.new()
var settings=Control.new()
var settings_controls
var pause_button
var paused=true
var editing=false
var browser_suspended=false
var save_writes_suppressed=true
var music_catalog_ready=true
var music_state="service"
var music_enabled=true
var compact
var music
var frames=[]
var output=""
var switch_frame=0
func _apply_music_selection():music_state=settings_controls.music_track
func set_music_enabled(value):music_enabled=value
func music_transport_snapshot():
 return {"effective_id":settings_controls.music_track,"playing":false,"paused":false,"can_play":false,"can_step":false,"seekable":false,"muted":not settings_controls.bgm_enabled,"available":true,"duration":0.0,"position":0.0,"context_reason":"UI preview · audio not running","unavailable_reason":"Audio playback is not part of this interface-only preview."}
func step_music_transport(_value):pass
func set_music_transport_paused(_value):pass
func seek_music_transport(_value):pass
func _update_ui():pass
func _style(bg: Color, border=Color.TRANSPARENT, radius=14) -> StyleBoxFlat:
 var s=StyleBoxFlat.new()
 s.bg_color=bg
 s.border_color=border
 s.set_border_width_all(1 if border.a>0 else 0)
 s.set_corner_radius_all(radius)
 s.content_margin_left=16
 s.content_margin_right=16
 s.content_margin_top=10
 s.content_margin_bottom=10
 return s

func label(words: String,size=16,color=DARK) -> Label:
 var n=Label.new()
 n.text=words
 n.add_theme_font_size_override("font_size",size)
 n.add_theme_font_override("font",ArtFont)
 n.add_theme_color_override("font_color",color)
 return n

func _ready():run.call_deferred()

func shot(state:String):
 var img=get_viewport().get_texture().get_image()
 assert(img!=null and img.get_size()==Vector2i(1360,880))
 img.convert(Image.FORMAT_RGBA8)
 var hash=HashingContext.new();assert(hash.start(HashingContext.HASH_SHA256)==OK)
 assert(hash.update(img.get_data())==OK)
 var file="1360x880-"+state+".png"
 assert(img.save_png(output+"/"+file)==OK)
 frames.append({"file":file,"width":img.get_width(),"height":img.get_height(),"rgba_sha256":hash.finish().hex_encode(),"rgba_bytes":img.get_data().size(),"selected":settings_controls.music_track,"board_reveal":music.board_material.reveal,"hero_reveal":music.record_mark.reveal,"frames_after_switch":Engine.get_process_frames()-switch_frame,"panel":str(music.panel.get_global_rect())})

func run():
 output=OS.get_environment("MUSIC_CAPTURE_OUTPUT")
 var profile=OS.get_environment("XDG_DATA_HOME")
 assert(not output.is_empty() and not profile.is_empty())
 assert(OS.get_user_data_dir().begins_with(profile+"/"))
 assert(DisplayServer.get_name()!="headless")
 var version=Engine.get_version_info()
 assert(version.major==4 and version.minor==6 and version.patch==3 and version.status=="stable" and version.build=="official")
 assert(RenderingServer.get_current_rendering_method()=="gl_compatibility")
 seed(8246)
 get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
 get_window().content_scale_factor=1.0;get_window().size=Vector2i(1360,880)
 RenderingServer.set_default_clear_color(Color("c9d5c2"))
 add_child(ui);ui.add_child(settings);settings.hide()
 settings_controls=Settings.new(self,"music-palette-capture")
 settings_controls.persist_enabled=false;settings_controls.sfx_enabled=false
 settings_controls.set_music_track("service")
 compact=HostAdapter.new(self);compact.hud=Hud.new(compact)
 var font=FontFile.new();assert(font.load_dynamic_font("res://assets/fonts/Nunito-ExtraBold.ttf")==OK)
 compact.hud.font_bold=font
 set_meta("hud_reduce_motion",false)
 music=MusicPanel.new(compact);music.setup();music.show()
 Input.warp_mouse(Vector2(1359,879))
 # Same production layout, animation and resources on both sides. Fixed 60 Hz
 # advances the original one-second tween; this is not a real-time FPS probe.
 for n in 16:await get_tree().process_frame
 await RenderingServer.frame_post_draw
 assert(music.board_material.reveal==0.0 and music.record_mark.reveal==0.0)
 assert(music.board_material.TRANSITION_SECONDS==1.0 and music.record_mark.TRANSITION_SECONDS==1.0)
 await get_tree().process_frame
 switch_frame=Engine.get_process_frames()
 music._select("service-1nd")
 # No settle loop, reveal override or redraw suppression before this frame.
 await RenderingServer.frame_post_draw
 shot("first-painted")
 assert(music.board_material.reveal<1.0 and music.record_mark.reveal<1.0)
 for n in 66:await get_tree().process_frame
 await RenderingServer.frame_post_draw
 assert(music.board_material.reveal==1.0 and music.record_mark.reveal==1.0)
 shot("settled-premium")
 assert(settings_controls.music_track=="service-1nd" and not settings_controls.persist_enabled and save_writes_suppressed)
 var receipt={"scope":"actual Music component, synthetic host/transport; no full cafe or audio playback","generated_profile":true,"player_save_used":false,"preferences_persist_enabled":false,"engine":version.string,"engine_info":version,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),"viewport":[1360,880],"scale":1.0,"fixed_fps":60,"transition_seconds":1.0,"frames":frames}
 FileAccess.open(output+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
 print("MUSIC_PALETTE_CAPTURE "+JSON.stringify(receipt))
 music.panel.queue_free();settings_controls=null;music=null;compact=null
 await get_tree().process_frame
 get_tree().quit()

func button(words: String,callback: Callable,accent=false) -> Button:
 var n=Button.new()
 n.text=words
 n.custom_minimum_size=Vector2(80,38)
 n.add_theme_font_size_override("font_size",15)
 n.add_theme_font_override("font",ArtFont)
 n.add_theme_color_override("font_color",CREAM if accent else DARK)
 n.add_theme_color_override("font_hover_color",CREAM if accent else DARK)
 n.add_theme_color_override("font_pressed_color",CREAM if accent else DARK)
 n.add_theme_color_override("font_focus_color",CREAM if accent else DARK)
 n.add_theme_stylebox_override("normal",_style(DARK if accent else Color("ebe8d7"),Color.TRANSPARENT,9))
 n.add_theme_stylebox_override("hover",_style(Color("547961") if accent else Color("dfdfc8"),Color.TRANSPARENT,9))
 n.add_theme_stylebox_override("pressed",_style(SAGE,Color.TRANSPARENT,9))
 n.add_theme_stylebox_override("disabled",_style(Color("e3e0d1"),Color.TRANSPARENT,9))
 n.add_theme_color_override("font_disabled_color",Color("5b6850"))
 n.pressed.connect(callback)
 n.pressed.connect(func():
  if settings_controls!=null: settings_controls.play_sfx("click"))
 return n

