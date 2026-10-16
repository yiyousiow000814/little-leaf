extends SceneTree
## Actual controls and generated model/preferences; no existing profile or hearing.
const Catalog=preload("res://scripts/ui/cafe_music_catalog.gd")
class TestMain extends "res://scripts/main.gd":
	var saves=0
	var hold_music_completion=false
	func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
	func _save():saves+=1;return true
	func _finish_music_crossfade(state:String,generation:int=-1):
		if not hold_music_completion:super(state,generation)
var game
var checks=0
var failures=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func persist_theme(id:String):
	game.save_writes_suppressed=false
	game.settings_controls.set_music_track(id)
	game.save_writes_suppressed=true
func run():
	game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
	if game.cafe_intro!=null:game.cafe_intro.finish()
	await process_frame
	var controls=game.settings_controls
	controls.config_path="user://synthetic_music_context.cfg";controls.persist_enabled=true
	check(game.music_catalog_ready and game.music_available.size()==20,"All20 retained tracks are imported and available without20 retained streams")
	check(game.audio_players.size()<=2,"Only incoming/outgoing streams are retained")
	for player in game.audio_players.values():
		check(player.playback_type==AudioServer.PLAYBACK_TYPE_DEFAULT,"Native BGM keeps its original default playback backend")
	check(Catalog.selection_ids().size()==21 and Catalog.selection_ids().has("cloverlight-phrasefix-r3"),"Automatic plus20 retained gameplay choices include Cloverlight")
	check(Catalog.selectable_tracks(Catalog.PREMIUM).size()==13,"All13 marked versions belong to free Premium")
	var music_panel=game.compact_ui.music_panel
	check(is_instance_valid(music_panel.panel) and not music_panel.panel.visible,"Independent Music window exists without opening at startup")
	var premium_choices=0
	for id in music_panel.rows:
		var row=music_panel.rows[id]
		check(row.button.get_meta("music_track_id")==id,"Track row preserves stable ID "+id)
		check(row.button.disabled==not row.selectable,"Selectable music remains currently free "+id)
		if row.group==Catalog.PREMIUM:premium_choices+=1
	check(music_panel.rows.size()==20 and premium_choices==13,"Independent window exposes Default and Premium tracks")
	check("free" in music_panel.group_note.text and "planned" in music_panel.group_note.text and music_panel.group_note.tooltip_text==Catalog.PREMIUM_TOOLTIP,"Visible disclosure and full tooltip explain free Premium and future charging")
	for invalid in [null,true,12,{},[],"Premium","removed-theme"]:
		check(Catalog.normalize_selection(invalid)==Catalog.AUTOMATIC,"Invalid preference safely defaults to Automatic")
	check(Catalog.selection_ids().has(Catalog.DECORATE) and Catalog.normalize_selection(Catalog.DECORATE)==Catalog.DECORATE,"Quiet Table remains a valid selection as well as the Decorate fallback")
	var coins=game.model.coins;var served=game.model.served
	var customers=game.model.customers.duplicate(true);var items=game.model.items.duplicate(true)
	for id in Catalog.selection_ids():
		persist_theme(id)
		music_panel.show();music_panel.sync()
		var selected_button=music_panel.automatic_button if id==Catalog.AUTOMATIC else music_panel.rows[id].button
		check(selected_button.button_pressed,"Independent window syncs exact saved ID "+id)
		music_panel.dismiss()
		var reload=ConfigFile.new()
		check(reload.load(controls.config_path)==OK,"Synthetic preferences file is readable "+id)
		check(reload.get_value("audio","music_track","")==id,"Independent preferences retain exact ID "+id)
		var previous=game.music_state
		game.music_age=8.5;game.music_positions[previous]=12.5
		var preference_bytes=FileAccess.get_file_as_bytes(controls.config_path)
		var saves=game.saves
		game._toggle_edit()
		check(game.editing and game.music_state==Catalog.DECORATE,"Decorate selects Quiet Table from "+id)
		check(controls.music_track==id and FileAccess.get_file_as_bytes(controls.config_path)==preference_bytes,"Entering Decorate preserves saved theme "+id)
		check(game.saves==saves,"Music context adds no progress save on entry "+id)
		game._music_tick(120.0)
		check(game.music_state==Catalog.DECORATE and controls.music_track==id,"Quiet Table retains the context over time "+id)
		game._toggle_edit()
		check(not game.editing and game.music_state==previous and is_equal_approx(game.music_age,8.5),"Previous gameplay state and age resume "+id)
		check(game.music_positions[previous]==12.5,"Stored gameplay position is not reset "+id)
		check(controls.music_track==id and FileAccess.get_file_as_bytes(controls.config_path)==preference_bytes,"Leaving Decorate preserves saved theme "+id)
		check(game.saves==saves+1,"Original Decorate exit save behavior retained "+id)
		check(game.audio_players.size()<=2,"Track/context switches preserve bounded stream ownership "+id)
	# Automatic may be between service-intensity transitions when Decorate opens.
	persist_theme(Catalog.AUTOMATIC);game._switch_music("busy");game.music_age=11.0
	game._toggle_edit();game._music_tick(300.0);game._toggle_edit()
	check(game.music_state=="busy" and is_equal_approx(game.music_age,11.0),"Automatic restores the actual previous busy state without recomputing it")
	# A deliberate user choice made inside Decorate applies when that context ends.
	persist_theme("cloverlight-phrasefix-r3");game._toggle_edit()
	var decorate_generation=game.music_fade_generation
	persist_theme("fiesta-en-flor-trumpet-throughout-r4")
	check(game.music_fade_generation==decorate_generation,"Changing preference during Decorate preserves the existing Quiet Table fade")
	check(game.music_state==Catalog.DECORATE and controls.music_track=="fiesta-en-flor-trumpet-throughout-r4","Theme change during Decorate keeps effective Quiet Table playback")
	game._toggle_edit()
	check(game.music_state=="fiesta-en-flor-trumpet-throughout-r4" and is_zero_approx(game.music_age),"Explicit new preference is honored after Decorate")
	# Existing volume/mute rules operate on the effective context, not the preference.
	persist_theme("cloverlight-phrasefix-r3");game._toggle_edit()
	controls.set_audio_volume("BGM",17);controls.set_audio_enabled("BGM",false)
	check(not game.music_enabled and game.music_state==Catalog.DECORATE and controls.music_track=="cloverlight-phrasefix-r3","BGM mute preserves context and selected theme")
	controls.set_audio_enabled("BGM",true)
	check(game.music_enabled and game.music_state==Catalog.DECORATE and controls.bgm_volume==17,"Re-enable retains Quiet Table and chosen volume")
	game._toggle_edit()
	check(game.music_state=="cloverlight-phrasefix-r3" and controls.music_track=="cloverlight-phrasefix-r3" and controls.bgm_volume==17,"Exit restores Cloverlight with existing volume settings")
	for cycle in 12:game._toggle_edit();game._toggle_edit()
	await process_frame;await process_frame
	check(game.audio_players.size()<=2,"Repeated contexts release retired stream resources")
	var live_bgm_nodes=0
	for child in game.get_children():
		if child is AudioStreamPlayer and child.bus=="BGM":live_bgm_nodes+=1
	check(live_bgm_nodes==game.audio_players.size(),"Deferred deletion leaves no retired BGM nodes or retained stream capacity")
	var generation=game.music_fade_generation
	game._switch_music("service");game._switch_music("busy");game._switch_music("service")
	game._ensure_music_player("busy")
	game._finish_music_crossfade("service",generation)
	check(game.music_state=="service" and game.audio_players.has("service") and game.audio_players.has("busy"),"Stale A-B-A fade completion cannot retire either member of the current fade")
	game._finish_music_crossfade("service",game.music_fade_generation)
	check(game.audio_players.has("service") and not game.audio_players.has("busy"),"Only the current fade completion releases its outgoing stream")
	# Real players under the Dummy device expose start/stop positions without hearing.
	persist_theme("cloverlight-phrasefix-r3")
	var cafe_player=game.audio_players["cloverlight-phrasefix-r3"]
	var seek_node_ref=weakref(cafe_player)
	var seek_stream_ref=weakref(cafe_player.stream)
	cafe_player.play(23.75)
	check(cafe_player.playing,"Synthetic decoder starts at the explicit gameplay offset")
	game.music_tween=game.create_tween()
	game.music_tween.tween_property(cafe_player,"volume_db",-17.0,1.2)
	var same_target_generation=game.music_fade_generation
	game._switch_music("cloverlight-phrasefix-r3")
	check(game.music_fade_generation==same_target_generation,"Re-selecting an already playing target preserves its transition")
	var observed_gameplay_position=cafe_player.get_playback_position()
	check(absf(observed_gameplay_position-23.75)<.25,"Dummy decoder exposes the distinctive nonzero gameplay offset")
	game.music_positions["cloverlight-phrasefix-r3"]=0.0
	game.hold_music_completion=true
	game._toggle_edit()
	controls.set_audio_enabled("BGM",false)
	game.hold_music_completion=false
	game._finish_music_crossfade(Catalog.DECORATE,game.music_fade_generation)
	cafe_player=null
	# Observe deferred node/audio retirement before shutting the fixture down.
	var release_started=Time.get_ticks_msec()
	var release_deadline=release_started+1000
	while seek_stream_ref.get_ref()!=null and Time.get_ticks_msec()<release_deadline:
		await create_timer(.05).timeout
	var played_retirement_wait_ms=Time.get_ticks_msec()-release_started
	check(seek_node_ref.get_ref()==null and seek_stream_ref.get_ref()==null,"Actually played decoder and node retire before fixture shutdown")
	check(absf(float(game.music_positions.get("cloverlight-phrasefix-r3",0.0))-observed_gameplay_position)<.25,"Muting during Decorate entry retains the previous gameplay offset")
	game._toggle_edit()
	check(absf(float(game.music_positions.get("cloverlight-phrasefix-r3",0.0))-observed_gameplay_position)<.25,"Decorate exit preserves that retained decoder position")
	controls.set_audio_enabled("BGM",true)
	# Retirement must release both the node and its compressed stream after deletion.
	var retired_player=game.audio_players["cloverlight-phrasefix-r3"]
	var retired_stream=weakref(retired_player.stream)
	var retired_node=weakref(retired_player)
	retired_player=null;cafe_player=null
	persist_theme("petal-promenade-clarinet-main-r3")
	await process_frame;await process_frame
	check(retired_node.get_ref()==null and retired_stream.get_ref()==null,"Retired player and compressed stream have no retained ownership")
	# A new selection made while suspended must be started after visibility returns.
	game.set_browser_suspended(true)
	persist_theme("cloverlight-phrasefix-r3")
	var suspended_generation=game.music_fade_generation
	game.music_age=7.5
	game.set_browser_suspended(false)
	check(game.music_fade_generation==suspended_generation+1 and game.music_state=="cloverlight-phrasefix-r3","Resume retries a selection deferred while suspended")
	check(is_equal_approx(game.music_age,7.5),"Resume retains the selection's state age")
	game.set_browser_suspended(true)
	controls.set_audio_enabled("BGM",false)
	persist_theme("petal-promenade-clarinet-main-r3")
	suspended_generation=game.music_fade_generation
	game.set_browser_suspended(false)
	check(not game.music_enabled and game.music_fade_generation==suspended_generation,"Resume never starts an explicitly disabled track")
	controls.set_audio_enabled("BGM",true)
	game.set_browser_suspended(true)
	persist_theme("cloverlight-phrasefix-r3")
	check(game.music_resume_pending,"Suspended enabled selection owns a pending start")
	controls.set_audio_enabled("BGM",false)
	game.set_browser_suspended(false)
	check(not game.music_resume_pending and not game.audio_players["cloverlight-phrasefix-r3"].playing,"Disable before resume safely consumes pending start without playback")
	controls.set_audio_enabled("BGM",true)
	check(game.model.coins==coins and game.model.served==served and game.model.customers==customers and game.model.items==items,"Music context does not change jobs, wallet, customers or furniture")
	# No context state is added to the ordinary preference schema.
	for removed_id in ["harmony-study-A","harmony-study-B","corner-cafe-reference-rearrangement-112","corner-cafe-main-street-112","corner-cafe-main-street-112-1nd","corner-cafe-main-street-112-2nd","corner-cafe-shop-rhythm-fix-112","corner-cafe-shop-rhythm-fix-112-1nd","corner-cafe-shop-rhythm-fix-112-2nd"]:
		var cfg=ConfigFile.new();cfg.set_value("audio","music_track",removed_id);cfg.save(controls.config_path)
		var original_bytes=FileAccess.get_file_as_bytes(controls.config_path)
		controls.load_preferences()
		check(controls.music_track==Catalog.AUTOMATIC,"Removed saved ID safely normalizes to Automatic: "+removed_id)
		check(FileAccess.get_file_as_bytes(controls.config_path)==original_bytes,"Loading removed ID does not rewrite saved preferences: "+removed_id)
		game._apply_music_selection();game._music_tick(120.0)
		check(game.music_state in ["service","busy"],"Removed saved ID resumes retained Automatic music: "+removed_id)
		check(Catalog.track(removed_id).is_empty() and not game.music_available.has(removed_id) and not game._ensure_music_player(removed_id),"Removed recording cannot be selected or loaded for playback: "+removed_id)
	DirAccess.remove_absolute(controls.config_path)
	print("MUSIC_CONTEXT_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"scope":"Generated model/preferences and actual headless controller; audible crossfades/browser joins unassessed","original_player_save_used":false,"players":game.audio_players.size(),"observed_gameplay_position":observed_gameplay_position,"played_retirement_wait_ms":played_retirement_wait_ms}))
	game.queue_free();await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)
