extends RefCounted
const SaveProfiles=preload("res://scripts/cafe_save_profiles.gd")
const WebPreferences=preload("res://scripts/cafe_web_preferences.gd")
var web_preferences
var preference_storage_note:Label
# Compact live controls; preferences are independent of restaurant progress.
var game
var panel:PanelContainer
var bgm_enabled=true
var sfx_enabled=true
var bgm_volume=70.0
var sfx_volume=55.0
var config_path="user://little_leaf_settings.cfg"
var persist_enabled=true
var progress_profile=""
var loaded_preferences_source=""
var last_seen_update_version=""
var speed_buttons=[]
var audio_rows={}
var sfx_player:AudioStreamPlayer
var effects={}
func _init(owner_game=null,profile=""):
	game=owner_game;progress_profile=profile
	persist_enabled=not _review_mode()
	_ensure_bus("BGM");_ensure_bus("SFX")
	load_preferences()
func _ensure_bus(name:String):
	if AudioServer.get_bus_index(name)<0:
		# Godot 4.6 Web Sample playback misorders add_bus(-1)'s JS bus array.
		# Growing the count appends consistently in both the engine and Web mixer,
		# so SFX's mute/volume can never address the Master output by mistake.
		var index=AudioServer.bus_count
		AudioServer.set_bus_count(index+1)
		AudioServer.set_bus_name(index,name)
func load_preferences():
	var cfg=ConfigFile.new()
	var source=config_path
	var loaded=false
	if OS.has_feature("web") and config_path=="user://little_leaf_settings.cfg":
		web_preferences=WebPreferences.new()
		loaded=web_preferences.load_into(cfg)
		source="browser-preferences:"+web_preferences.source
	else:
		if config_path=="user://little_leaf_settings.cfg":
			var existing=SaveProfiles.first_existing(SaveProfiles.settings_candidates(progress_profile))
			if existing!="":source=existing
		loaded=cfg.load(source)==OK
	loaded_preferences_source=source
	if loaded:
		bgm_enabled=bool(cfg.get_value("audio","bgm_enabled",true))
		sfx_enabled=bool(cfg.get_value("audio","sfx_enabled",true))
		bgm_volume=clampf(float(cfg.get_value("audio","bgm_volume",70)),0,100)
		sfx_volume=clampf(float(cfg.get_value("audio","sfx_volume",55)),0,100)
		var seen=cfg.get_value("updates","last_seen_version","")
		last_seen_update_version=seen if seen is String else ""
		if game!=null:game.speed=2.0 if int(cfg.get_value("play","speed",1))==2 else 1.0
	_apply_buses()
func _review_mode()->bool:
	var args=OS.get_cmdline_user_args()
	return "--visual-qa" in args or "--fresh-review" in args or "--review-checkpoint" in args
func _preferences_writes_allowed()->bool:
	return persist_enabled and not _review_mode() and (game==null or not bool(game.save_writes_suppressed))
func save_preferences()->bool:
	if not _preferences_writes_allowed():return false
	var cfg=ConfigFile.new()
	cfg.set_value("audio","bgm_enabled",bgm_enabled);cfg.set_value("audio","sfx_enabled",sfx_enabled)
	cfg.set_value("audio","bgm_volume",bgm_volume);cfg.set_value("audio","sfx_volume",sfx_volume)
	cfg.set_value("play","speed",int(game.speed) if game!=null else 1)
	cfg.set_value("updates","last_seen_version",last_seen_update_version)
	if OS.has_feature("web") and config_path=="user://little_leaf_settings.cfg":
		var saved=web_preferences!=null and web_preferences.save_from(cfg)
		if not saved and game!=null and is_instance_valid(game.status_text):
			game._notify("Preferences not saved · "+(web_preferences.last_error if web_preferences!=null else "Storage unavailable"))
		_sync_preference_storage_notice()
		return saved
	return cfg.save(config_path)==OK
func mark_update_notes_seen(version:String)->bool:
	version=version.strip_edges()
	if version=="" or not _preferences_writes_allowed():return false
	if last_seen_update_version==version:return true
	var previous=last_seen_update_version
	last_seen_update_version=version
	if save_preferences():return true
	last_seen_update_version=previous
	return false
func _apply_buses():
	for kind in ["BGM","SFX"]:
		var index=AudioServer.get_bus_index(kind)
		var value=bgm_volume if kind=="BGM" else sfx_volume
		var enabled=bgm_enabled if kind=="BGM" else sfx_enabled
		AudioServer.set_bus_mute(index,not enabled or value<=0)
		AudioServer.set_bus_volume_db(index,linear_to_db(maxf(.0001,value/100)))
func setup_audio():
	for player in game.audio_players.values():player.bus="BGM"
	sfx_player=AudioStreamPlayer.new();sfx_player.bus="SFX";sfx_player.max_polyphony=4;game.add_child(sfx_player)
	for kind in ["click","place","coin"]:effects[kind]=_make_effect(kind)
	game.music_enabled=bgm_enabled
	if not bgm_enabled:
		for player in game.audio_players.values():player.stop()
	_apply_buses()
func _make_effect(kind:String) -> AudioStreamWAV:
	var rate=22050
	var seconds=.045 if kind=="click" else (.09 if kind=="place" else .18)
	var length=int(rate*seconds)
	var bytes=PackedByteArray();bytes.resize(length*2)
	for i in range(length):
		var t=float(i)/rate;var u=t/seconds
		var hz=610.0 if kind=="click" else (430.0+180*u if kind=="place" else (880.0 if u<.45 else 1174.7))
		var envelope=sin(minf(1,u*9)*PI/2)*pow(1-u,2)
		var value=sin(t*TAU*hz)*envelope*.12
		bytes.encode_s16(i*2,int(value*32767))
	var stream=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=rate;stream.stereo=false;stream.data=bytes
	return stream
func play_sfx(kind="click"):
	if not sfx_enabled or sfx_volume<=0 or not is_instance_valid(sfx_player):return
	if effects.has(kind):sfx_player.stream=effects[kind];sfx_player.play()
func set_speed(value:float):
	game.speed=2.0 if value>=2 else 1.0
	sync();save_preferences()
func set_audio_enabled(kind:String,value:bool):
	if kind=="BGM":
		bgm_enabled=value;game.music_enabled=value
		if value:game._switch_music(game.music_state if game.music_state!="" else "service")
		else:
			if is_instance_valid(game.music_tween):game.music_tween.kill()
			for player in game.audio_players.values():player.stop()
	else:sfx_enabled=value
	_apply_buses();sync();save_preferences()
func set_audio_volume(kind:String,value:float):
	if kind=="BGM":bgm_volume=clampf(value,0,100)
	else:sfx_volume=clampf(value,0,100)
	_apply_buses();sync();save_preferences()
func _rail(color:Color) -> StyleBoxFlat:
	var rail=StyleBoxFlat.new();rail.bg_color=color;rail.set_corner_radius_all(3);rail.content_margin_top=3;rail.content_margin_bottom=3;return rail
func _thumb() -> Texture2D:
	var img=Image.new()
	img.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><circle cx="8" cy="8" r="6" fill="#78916c" stroke="#f5efd8" stroke-width="2"/></svg>')
	return ImageTexture.create_from_image(img)
func build() -> PanelContainer:
	panel=PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left=-352;panel.offset_right=-22;panel.offset_top=88;panel.offset_bottom=480
	panel.custom_minimum_size=Vector2(330,0)
	panel.add_theme_stylebox_override("panel",game._style(Color("f8f2df"),Color("d9dcc4"),15))
	var box=VBoxContainer.new();box.add_theme_constant_override("separation",11);panel.add_child(box)
	box.add_child(game.label("Settings",21,Color("4d6d56")))
	for kind in ["BGM","SFX"]:
		var row=HBoxContainer.new();box.add_child(row)
		var title=game.label("Background music" if kind=="BGM" else "Sound effects",15)
		title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(title)
		var toggle=game.button("On",func():set_audio_enabled(kind,not (bgm_enabled if kind=="BGM" else sfx_enabled)))
		toggle.custom_minimum_size=Vector2(60,32);toggle.toggle_mode=true
		toggle.add_theme_stylebox_override("pressed",game._style(Color("4f7056"),Color.TRANSPARENT,9))
		toggle.add_theme_color_override("font_pressed_color",Color("fff3d8"))
		row.add_child(toggle)
		var volumes=HBoxContainer.new();volumes.add_theme_constant_override("separation",10);box.add_child(volumes)
		var slider=HSlider.new();slider.min_value=0;slider.max_value=100;slider.step=1;slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;slider.custom_minimum_size=Vector2(220,22)
		slider.add_theme_stylebox_override("slider",_rail(Color("d9ddc6")))
		slider.add_theme_stylebox_override("grabber_area",_rail(Color("99ad83")))
		var thumb=_thumb();slider.add_theme_icon_override("grabber",thumb);slider.add_theme_icon_override("grabber_highlight",thumb)
		volumes.add_child(slider)
		var value=game.label("",13,Color("758368"));value.custom_minimum_size.x=42;value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;volumes.add_child(value)
		audio_rows[kind]={"toggle":toggle,"slider":slider,"value":value}
		slider.value_changed.connect(func(v):set_audio_volume(kind,v))
	preference_storage_note=game.label("Changes are saved automatically",11,Color("8b937b"))
	preference_storage_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(preference_storage_note)
	box.add_child(game.button("Close",func():panel.hide()))
	sync();panel.hide();return panel
func build_play_controls() -> HBoxContainer:
	var controls=HBoxContainer.new();controls.add_theme_constant_override("separation",5)
	game.pause_button=game.button("Pause",func():game.paused=not game.paused;sync();game._update_ui())
	game.pause_button.custom_minimum_size=Vector2(74,42);game.pause_button.tooltip_text="Pause or resume service"
	controls.add_child(game.pause_button)
	var group=ButtonGroup.new()
	for n in [1,2]:
		var b=game.button("%d×"%n,func():set_speed(n))
		b.custom_minimum_size=Vector2(44,42);b.toggle_mode=true;b.button_group=group
		b.tooltip_text="Normal speed" if n==1 else "Fast speed"
		for state in ["normal","hover","pressed","disabled"]:
			var style=b.get_theme_stylebox(state);style.content_margin_left=8;style.content_margin_right=8
		var selected_style=game._style(Color("4f7056"),Color.TRANSPARENT,9)
		selected_style.content_margin_left=8;selected_style.content_margin_right=8
		b.add_theme_stylebox_override("pressed",selected_style)
		b.add_theme_color_override("font_pressed_color",Color("fff3d8"))
		controls.add_child(b);speed_buttons.append(b)
	sync();return controls
func _sync_preference_storage_notice():
	if not is_instance_valid(preference_storage_note):return
	preference_storage_note.text="Changes are saved automatically" if web_preferences==null or web_preferences.last_error=="" else "Preferences not saved · "+web_preferences.last_error
func sync():
	if game==null:return
	_sync_preference_storage_notice()
	if is_instance_valid(game.pause_button):game.pause_button.text="Resume" if game.paused else "Pause"
	for i in range(speed_buttons.size()):speed_buttons[i].set_pressed_no_signal(int(game.speed)==i+1)
	for kind in audio_rows:
		var row=audio_rows[kind];var enabled=bgm_enabled if kind=="BGM" else sfx_enabled;var volume=bgm_volume if kind=="BGM" else sfx_volume
		row.toggle.text="On" if enabled else "Off";row.toggle.set_pressed_no_signal(enabled)
		row.slider.set_value_no_signal(volume);row.value.text="%d%%"%int(volume)
