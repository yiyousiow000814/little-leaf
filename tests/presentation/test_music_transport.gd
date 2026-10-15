extends SceneTree
## Real imported MP3/Ogg players under Dummy audio; no hearing or player saves.
const Catalog=preload("res://scripts/ui/cafe_music_catalog.gd")
class TestMain extends "res://scripts/main.gd":
	var saves=0
	func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
	func _save():saves+=1;return true
	# Opt this fixture into actual decoder playback under the headless Dummy driver.
	func _music_playback_supported()->bool:return true
var game
var checks=0
var failures=[]
var timing_evidence=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():run.call_deferred()
func run():
	check_catalog_config()
	game=TestMain.new();root.add_child(game);game.set_process(false);game.paused=true
	if game.cafe_intro!=null:game.cafe_intro.finish()
	await process_frame
	var controls=game.settings_controls
	controls.persist_enabled=false
	var saved_profile=controls.config_path
	var had_profile=FileAccess.file_exists(saved_profile)
	var sfx=controls.sfx_player
	var sfx_volume=controls.sfx_volume;var sfx_enabled=controls.sfx_enabled
	var sfx_bus=AudioServer.get_bus_index("SFX")
	var sfx_db=AudioServer.get_bus_volume_db(sfx_bus);var sfx_mute=AudioServer.is_bus_mute(sfx_bus)
	var coins=game.model.coins;var customers=game.model.customers.duplicate(true)
	check(Catalog.TRACKS.size()==23 and game.music_available.size()==23,"All retained recording IDs remain available")
	var families=Catalog.families();var unique_ids={};var paired=0
	for family in families:
		if family.has_default and family.premium_ids.size()==2:paired+=1
		for entry in family.variants:
			check(not unique_ids.has(entry.id) and entry==Catalog.track(entry.id),"Family preserves one exact original recording "+entry.id)
			unique_ids[entry.id]=true
	check(families.size()==9 and unique_ids.size()==23 and paired==6,"Nine configured songs preserve all23 retained recordings, including Harmony and the requested Sunshine versions")
	var harmony=Catalog.family_for_track("harmony-study-A")
	check(harmony.id=="harmony-study" and harmony.title=="Harmony" and harmony.variants.size()==2,"Harmony Study1 and2 share one requested family")
	check(Catalog.family_for_track("harmony-study-B").id==harmony.id and harmony.variants[0].id=="harmony-study-A" and harmony.variants[1].id=="harmony-study-B","Harmony choices retain both original IDs and source order")
	check(Catalog.edition_label("harmony-study-A")=="Version 1" and Catalog.edition_label("harmony-study-B")=="Version 2","Harmony edition selectors use requested Version 1/Version 2 labels")
	for entry in Catalog.TRACKS:
		check(not "1nd" in Catalog.display_title(entry.id) and not "2nd" in Catalog.display_title(entry.id),"Visible title excludes source suffix "+entry.id)
		if entry.group==Catalog.PREMIUM:check(Catalog.edition_label(entry.id)==("Premium A" if entry.id.ends_with("-1nd") else "Premium B"),"Premium A/B retains exact source mapping "+entry.id)
	var sunshine=Catalog.family_for_track("sunshine-skip-150-r6-2nd")
	check(sunshine.id==Catalog.family_for_track("sunshine-skip-176-new-theme").id and sunshine.title=="Sunshine Skip" and sunshine.variants.size()==2,"Requested same-name Sunshine versions share one song row")
	check(sunshine.default_id=="sunshine-skip-176-new-theme" and sunshine.premium_ids==["sunshine-skip-150-r6-2nd"] and sunshine.variants[0].id==sunshine.default_id,"Sunshine retains exact Default/Premium B mapping and order")
	for id in ["service","corner-cafe-reference-rearrangement-112"]:
		controls.set_music_track(id)
		var player=game.audio_players[id]
		var state=game.music_transport_snapshot()
		check(state.effective_id==id and state.title==Catalog.display_title(id),"Snapshot reports the effective imported track "+id)
		check(state.duration>30.0 and is_equal_approx(state.duration,player.stream.get_length()),"Duration comes from the current MP3/Ogg stream "+id)
		check(state.available and state.can_play and state.playing and state.seekable,"Actual decoder exposes supported controls "+id)
		check(game.seek_music_transport(7.25),"Seek accepted for imported recording "+id)
		await create_timer(.12).timeout
		check(absf(game.music_transport_snapshot().position-player.get_playback_position())<.1,"Progress follows the real player position "+id)
		check(absf(game.music_transport_snapshot().position-7.25)<.5,"Seek moves the actual decoder "+id)
		var before=game.music_transport_snapshot().position
		var progress_deadline=Time.get_ticks_msec()+1000
		while game.music_transport_snapshot().position<=before and Time.get_ticks_msec()<progress_deadline:
			await create_timer(.05).timeout
		var after=game.music_transport_snapshot().position
		timing_evidence.append({"id":id,"before":before,"after":after})
		check(after>before,"Real decoder advances, without a UI clock "+id)
		game.music_age=8.5
		game.set_music_transport_paused(true)
		var held=game.music_transport_snapshot().position
		var generation=game.music_fade_generation
		game.set_music_transport_paused(true)
		await create_timer(.12).timeout
		state=game.music_transport_snapshot()
		check(state.paused and not state.playing and not player.playing,"Pause stops actual decoder "+id)
		check(is_equal_approx(state.position,held) and game.music_fade_generation==generation,"Repeated pause is idempotent and position is held "+id)
		check(game.audio_players.size()==1 and not game.music_tween.is_running(),"Pause settles and retires the outgoing fade "+id)
		check(game.seek_music_transport(11.5) and is_equal_approx(game.music_transport_snapshot().position,11.5),"Paused seek records an explicit resume offset "+id)
		game.set_music_transport_paused(false)
		check(player.playing and not game.music_transport_snapshot().paused,"Resume restarts the actual decoder "+id)
		check(absf(player.get_playback_position()-11.5)<.25 and is_equal_approx(game.music_age,8.5),"Resume honors seek and preserves Automatic age "+id)
		check(not game.seek_music_transport(NAN) and not game.seek_music_transport(INF),"Nonfinite seek values are rejected "+id)
		check(game.seek_music_transport(-5.0) and player.get_playback_position()<.25,"Negative seek safely clamps to start "+id)
		check(game.seek_music_transport(state.duration+200) and player.get_playback_position()<.25,"End seek enters the next loop at zero "+id)
	# Every repeated skip replaces only the bounded incoming/outgoing ownership.
	controls.set_music_track("cloverlight-phrasefix-r3-2nd")
	game.set_music_transport_paused(true)
	var expected=Catalog.sibling_family_track(game.music_state,1)
	check(game.step_music_transport(1) and game.music_state==expected and controls.music_track==expected,"Next uses the saved family/variant selection owner")
	check(game.music_transport_snapshot().paused and not game.audio_players[expected].playing,"Track changes retain session pause")
	for direction in [1,1,-1,1,-1,-1,1,1,1,-1]:
		expected=Catalog.sibling_family_track(game.music_state,direction)
		check(game.step_music_transport(direction) and game.music_state==expected,"Repeated navigation resolves a real selectable family member")
		check(game.audio_players.size()<=2,"Repeated navigation retains no more than two streams")
	check(not game.step_music_transport(0),"Zero-direction navigation is inert")
	game.set_music_transport_paused(false)
	controls.set_music_track("service");controls.set_music_track("busy");controls.set_music_track("corner-cafe-reference-rearrangement-112")
	check(game.audio_players.size()==2,"Interrupted fades keep exactly current and outgoing streams")
	var stale_generation=game.music_fade_generation
	game.set_music_transport_paused(true)
	game.set_music_transport_paused(false)
	controls.set_music_track("service")
	game._finish_music_crossfade("service",stale_generation)
	check(game.audio_players.size()==2,"Old fade callbacks cannot retire current playback after pause/resume")
	# Mute and zero-volume are separate from transport pause and preserve SFX.
	check(game.seek_music_transport(19.0),"Prepare nonzero mute resume offset")
	controls.set_audio_enabled("BGM",false)
	check(not game.music_transport_snapshot().playing and game.music_transport_snapshot().muted,"Mute stops playback without creating a transport pause")
	check(not game.music_transport_snapshot().paused and absf(game.music_transport_snapshot().position-19.0)<.25,"Mute retains real position and independent pause intent")
	game.set_music_transport_paused(true)
	check(game.seek_music_transport(22.0),"Muted paused seek prepares a valid resume offset")
	controls.set_audio_enabled("BGM",true)
	check(game.music_transport_snapshot().paused and not game.audio_players[game.music_state].playing,"Unmute does not cancel the explicit pause")
	game.set_music_transport_paused(false)
	check(absf(game.audio_players[game.music_state].get_playback_position()-22.0)<.25,"Resume after mute honors the selected offset")
	controls.set_audio_volume("BGM",0)
	check(game.music_transport_snapshot().muted and game.music_transport_snapshot().playing,"Zero volume keeps the transport running silently")
	controls.set_audio_volume("BGM",37)
	check(game.music_transport_snapshot().volume==37 and not game.music_transport_snapshot().muted,"Independent volume reports the existing BGM setting")
	# Pausing is retained across the existing Quiet Table override and restore lifecycle.
	controls.set_music_track("corner-cafe-reference-rearrangement-112");game.seek_music_transport(15.0);game.set_music_transport_paused(true)
	game.editing=true;game._apply_music_selection()
	var state=game.music_transport_snapshot()
	check(state.effective_id==Catalog.DECORATE and state.paused and not state.can_step and state.context_reason!="","Decorate truthfully reports Quiet Table and unavailable family navigation")
	check(not game.step_music_transport(1) and controls.music_track=="corner-cafe-reference-rearrangement-112","Disabled Quiet Table navigation cannot alter the saved selection")
	check(game.seek_music_transport(4.5),"Paused Quiet Table seeks its own loaded stream")
	game.editing=false;game._apply_music_selection()
	check(game.music_state=="corner-cafe-reference-rearrangement-112" and absf(game.music_transport_snapshot().position-15.0)<.25,"Leaving Decorate restores the gameplay track and independent offset")
	game.editing=true;game._apply_music_selection();controls.set_music_track("harmony-study-A")
	check(game.music_state==Catalog.DECORATE,"Explicit selection while decorating preserves Quiet Table")
	game.editing=false;game._apply_music_selection()
	check(game.music_state=="harmony-study-A" and game.music_transport_snapshot().paused,"New selection takes effect after Decorate while remaining paused")
	# Visibility never releases a user pause or permits hidden transport work.
	game.set_browser_suspended(true)
	state=game.music_transport_snapshot()
	check(not state.can_play and not state.can_step and not state.seekable and not state.playing,"Hidden game exposes unavailable transport without synthetic progress")
	check(not game.seek_music_transport(9.0) and not game.step_music_transport(-1),"Hidden seek/navigation are inert")
	controls.set_music_track("corner-cafe-reference-rearrangement-112")
	game.set_browser_suspended(false)
	check(game.music_transport_snapshot().paused and not game.audio_players["corner-cafe-reference-rearrangement-112"].playing,"Visibility return never releases a user pause")
	game.set_browser_suspended(true);game.set_music_transport_paused(false)
	check(game.music_resume_pending and not game.audio_players["corner-cafe-reference-rearrangement-112"].playing,"Unpausing while hidden defers real playback")
	game.set_browser_suspended(false)
	check(game.audio_players["corner-cafe-reference-rearrangement-112"].playing and not game.music_resume_pending,"Visibility return starts the deferred real decoder")
	game.set_browser_suspended(true);controls.set_music_track("service");controls.set_audio_enabled("BGM",false);game.set_browser_suspended(false)
	check(not game.audio_players.service.playing and not game.music_resume_pending,"Muting before visibility return cancels deferred playback")
	controls.set_audio_enabled("BGM",true)
	controls.set_music_track(Catalog.AUTOMATIC);game.music_age=9.0;game.set_music_transport_paused(true);game._music_tick(200.0)
	check(is_equal_approx(game.music_age,9.0),"User pause freezes Automatic's intensity-switch age")
	check(controls.sfx_player==sfx and controls.sfx_volume==sfx_volume and controls.sfx_enabled==sfx_enabled,"Transport preserves SFX player and preferences")
	check(AudioServer.get_bus_volume_db(sfx_bus)==sfx_db and AudioServer.is_bus_mute(sfx_bus)==sfx_mute,"Transport never changes SFX bus volume or mute")
	check(game.saves==0 and game.model.coins==coins and game.model.customers==customers,"Transport never saves or changes restaurant state")
	check(FileAccess.file_exists(saved_profile)==had_profile,"Session pause creates no settings schema or file")
	# Current snapshots never load another stream; deferred nodes are actually freed.
	var current=game.audio_players[game.music_state]
	var stream_ref=weakref(current.stream);var node_ref=weakref(current)
	for sample in 100:game.music_transport_snapshot()
	check(game.audio_players.size()==1 and game.audio_players[game.music_state]==current,"Repeated snapshots retain no extra stream/player resources")
	current=null;controls.set_music_track("corner-cafe-reference-rearrangement-112")
	var release_deadline=Time.get_ticks_msec()+1000
	while stream_ref.get_ref()!=null and Time.get_ticks_msec()<release_deadline:
		await create_timer(.05).timeout
	check(node_ref.get_ref()==null and stream_ref.get_ref()==null,"Retired paused stream and node leave no retained ownership")
	var live_players=0
	for child in game.get_children():
		if child is AudioStreamPlayer and child.bus=="BGM":live_players+=1
	check(live_players==game.audio_players.size() and live_players<=2,"Only owned BGM nodes survive repeated transport actions")
	print("MUSIC_TRANSPORT_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"scope":"Actual imported decoder timing under Dummy audio; no audible, browser or visual acceptance","original_player_save_used":false,"timing_evidence":timing_evidence}))
	game.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)

func check_catalog_config():
	var document=JSON.parse_string(FileAccess.get_file_as_string(Catalog.DATA_PATH))
	check(Catalog.validate_document(document)=="","Project catalog JSON validates without filename inference")
	var originals=Catalog.TRACKS.duplicate(true)
	originals.sort_custom(func(a,b):return a.id<b.id)
	var lines=PackedStringArray()
	for entry in originals:
		lines.append("\t".join(PackedStringArray([entry.id,entry.title,entry.path,entry.group,entry.loop_qualification,"true" if entry.selectable else "false"])))
	# Retained recording metadata, sorted by stable ID; no audio/source renames.
	check("\n".join(lines).sha256_text()=="ecf09ec532f6cbc946563a0c4df6a604c268a91c52b2be1551d6a5b97a1f7383","All23 retained IDs, exact paths, raw titles, tiers, qualification notes and selectability match original provenance")
	var presets=ConfigFile.new()
	check(presets.load("res://export_presets.cfg")==OK,"Export presets are available for the config packaging contract")
	for index in [0,1]:
		check("data/music_catalog.json" in str(presets.get_value("preset.%d"%index,"include_filter","")).split(","),"Main Web preset includes the plain catalog JSON: "+str(index))
	var packed=presets.get_value("preset.2","export_files",PackedStringArray())
	var expected=PackedStringArray()
	for entry in Catalog.TRACKS:
		if not entry.path in expected:expected.append(entry.path)
	packed.sort();expected.sort()
	check(packed==expected,"Delayed CrazyGames music pack contains every catalog recording once, with no removed songs")
	var excluded=str(presets.get_value("preset.1","exclude_filter","")).split(",")
	for entry in Catalog.TRACKS:
		check(entry.path.trim_prefix("res://") in excluded,"Only exact catalog recordings leave the main payload: "+entry.id)
	check("assets/audio/sfx/SfxCash.mp3".match("assets/audio/*.mp3"),"Regression control detects the rejected broad wildcard matching nested SFX")
	for effect in ["SfxCash.mp3","SfxCoinDrop.mp3","SfxCoinPickUp.mp3"]:
		var path="assets/audio/sfx/"+effect
		var would_exclude=false
		for pattern in excluded:
			if path.match(pattern):would_exclude=true
		check(not would_exclude,"Catalog packaging keeps existing SFX in the playable main payload: "+effect)
	for index in [0,1,2]:
		check("assets/audio/TIMGM6MB_PACKAGE_NOTICE.txt" in str(presets.get_value("preset.%d"%index,"include_filter","")).split(","),"Existing supplied-music package notice is retained in export preset "+str(index))
	var malformed=[null,{}, {"schema_version":2,"songs":[]}, {"schema_version":1,"songs":[]}, {"schema_version":1,"songs":[null]}]
	for value in malformed:check(Catalog.validate_document(value)!="","Invalid document shape is rejected without partial catalog state")
	check(Catalog.song_title("harmony-study")=="Harmony" and Catalog.display_title("sunshine-skip")=="Sunshine Skip","Clean title lookup supports stable song IDs as well as recording IDs")
	var reserved=document.duplicate(true);reserved.songs[0].id=Catalog.AUTOMATIC
	check(Catalog.validate_document(reserved)!="","Automatic cannot shadow a configured song row")
	var duplicate=document.duplicate(true);duplicate.songs.append(duplicate.songs[0].duplicate(true))
	check(Catalog.validate_document(duplicate)!="","Duplicate stable song IDs are rejected")
	duplicate=document.duplicate(true);duplicate.songs[1].title=duplicate.songs[0].title
	check(Catalog.validate_document(duplicate)!="","Same-name songs cannot silently split into duplicate rows")
	duplicate=document.duplicate(true);duplicate.songs[1].recordings[0].id=duplicate.songs[0].recordings[0].id
	check(Catalog.validate_document(duplicate)!="","Duplicate recording preference IDs are rejected")
	for field in ["id","edition_key","edition_label","tier","audio_path","selectable","source"]:
		var missing=document.duplicate(true);missing.songs[0].recordings[0].erase(field)
		check(Catalog.validate_document(missing)!="","Missing required recording field is rejected: "+field)
	for field in ["title","loop_qualification"]:
		var missing=document.duplicate(true);missing.songs[0].recordings[0].source.erase(field)
		check(Catalog.validate_document(missing)!="","Missing provenance remains explicit: "+field)
	var invalid_tier=document.duplicate(true);invalid_tier.songs[0].recordings[0].tier="Paid"
	check(Catalog.validate_document(invalid_tier)!="","Unknown tier cannot imply an unsupported entitlement")
	var invalid_path=document.duplicate(true);invalid_path.songs[0].recordings[0].audio_path="https://example.invalid/song.mp3"
	check(Catalog.validate_document(invalid_path)!="","Catalog cannot load external audio paths")
	# A config-only new song and version deliberately have unrelated opaque IDs/files.
	var authored=document.duplicate(true)
	var edition=document.songs[0].recordings[0].duplicate(true)
	edition.id="opaque-recording-z";edition.edition_key="1nd";edition.edition_label="Premium A";edition.tier="Premium"
	edition.audio_path="res://assets/audio/Unrelated_Source_Name.ogg"
	authored.songs.append({"id":"evening-cafe","title":"Evening Café","recordings":[edition]})
	var extra=edition.duplicate(true);extra.id="opaque-recording-y";extra.edition_key="2nd";extra.edition_label="Premium B"
	authored.songs[-1].recordings.append(extra)
	check(Catalog.validate_document(authored)=="","New song and version require only valid authored config entries")
	var retained=Catalog.TRACKS
	Catalog.TRACKS=Catalog._tracks_from_document(authored)
	check(Catalog.family_id(edition.id)=="evening-cafe" and Catalog.family_for_track(extra.id).variants.size()==2,"Opaque recording IDs follow explicit song grouping")
	check(Catalog.display_title(extra.id)=="Evening Café" and Catalog.edition_label(extra.id)=="Premium B" and Catalog.variant_key(extra.id)=="2nd","Display and preferred edition come only from config")
	check(Catalog.track(edition.id).path==edition.audio_path and Catalog.normalize_selection(edition.id)==edition.id,"Explicit config audio mapping and saved recording identity require no code case")
	check(Catalog.sibling_family_track("petal-promenade-clarinet-main-r3-2nd",1)=="sunshine-skip-150-r6-2nd","Next retains Premium B into grouped Sunshine")
	Catalog.TRACKS=retained
	check(Catalog.TRACKS.size()==23,"Synthetic authoring probe restores the real catalog before constructing Main")
