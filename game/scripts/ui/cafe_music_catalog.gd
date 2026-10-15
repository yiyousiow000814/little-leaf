extends RefCounted
## Project-authored song/edition data; tier labels are not entitlement state.
const AUTOMATIC="automatic"
const DECORATE="decorate"
const DEFAULT="Default"
const PREMIUM="Premium"
const PREMIUM_TOOLTIP="Premium music is currently free. Charging is planned for the future."
const DATA_PATH="res://data/music_catalog.json"

# Read and validate once on script load. No audio streams or per-frame file work.
static var TRACKS:Array=_load_tracks()

static func _load_tracks()->Array:
	var document=JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var error=validate_document(document)
	if error!="":
		push_error("Music catalog: "+error)
		return []
	return _tracks_from_document(document)

static func validate_document(document:Variant)->String:
	if not document is Dictionary or document.get("schema_version")!=1:return "Expected schema_version 1."
	if not document.get("songs") is Array or document.songs.is_empty():return "Expected a nonempty songs array."
	var songs={};var titles={};var recordings={}
	for song in document.songs:
		if not song is Dictionary:return "Each song must be an object."
		for field in ["id","title"]:
			if not song.get(field) is String or str(song[field]).strip_edges()=="":return "Song "+field+" must be nonempty text."
		if song.id==AUTOMATIC or songs.has(song.id):return "Duplicate or reserved song ID: "+song.id
		var title_key=song.title.strip_edges().to_lower()
		if titles.has(title_key):return "Same-name recordings belong in one song: "+song.title
		songs[song.id]=true;titles[title_key]=true
		if not song.get("recordings") is Array or song.recordings.is_empty():return "Song needs a recordings array: "+song.id
		var labels={}
		for recording in song.recordings:
			if not recording is Dictionary:return "Each recording must be an object."
			for field in ["id","edition_key","edition_label","tier","audio_path"]:
				if not recording.get(field) is String or str(recording[field]).strip_edges()=="":return "Recording "+field+" must be nonempty text."
			if recording.id==AUTOMATIC or recordings.has(recording.id):return "Duplicate or reserved recording ID: "+recording.id
			if labels.has(recording.edition_label):return "Duplicate edition label in song: "+song.id
			if not recording.tier in [DEFAULT,PREMIUM]:return "Unknown recording tier: "+recording.id
			if not recording.get("selectable") is bool:return "Recording selectable must be boolean: "+recording.id
			if not recording.audio_path.begins_with("res://assets/audio/") or ".." in recording.audio_path:return "Recording needs a project audio path: "+recording.id
			if not recording.get("source") is Dictionary:return "Recording needs original source metadata: "+recording.id
			for field in ["title","loop_qualification"]:
				if not recording.source.get(field) is String or str(recording.source[field]).strip_edges()=="":return "Missing source "+field+": "+recording.id
			recordings[recording.id]=true;labels[recording.edition_label]=true
	return ""

static func _tracks_from_document(document:Dictionary)->Array:
	var tracks:Array=[]
	for song in document.songs:
		for recording in song.recordings:
			# Legacy fields keep playback consumers stable; source titles never label UI.
			tracks.append({"id":recording.id,"title":recording.source.title,
				"path":recording.audio_path,"group":recording.tier,"selectable":recording.selectable,
				"loop_qualification":recording.source.loop_qualification,
				"song_id":song.id,"song_title":song.title,
				"edition_key":recording.edition_key,"edition_label":recording.edition_label})
	return tracks

static func track(id:String)->Dictionary:
	for entry in TRACKS:
		if entry.id==id:return entry
	return {}

static func song_title(id:String)->String:
	for entry in TRACKS:
		if entry.id==id or entry.song_id==id:return entry.song_title
	return "Automatic" if id==AUTOMATIC else "Music"

static func selectable_tracks(group:String="")->Array:
	return TRACKS.filter(func(entry):return entry.get("selectable",true) and (group=="" or entry.group==group))

static func normalize_selection(value:Variant)->String:
	if value is String:
		if value==AUTOMATIC:return AUTOMATIC
		var entry=track(value)
		if not entry.is_empty() and entry.get("selectable",true):return value
	return AUTOMATIC

static func selection_ids()->PackedStringArray:
	var ids=PackedStringArray([AUTOMATIC])
	for entry in selectable_tracks():ids.append(entry.id)
	return ids

static func variant_key(id:String)->String:
	return str(track(id).get("edition_key","default"))

static func family_id(id:String)->String:
	return str(track(id).get("song_id",id))

static func families()->Array:
	var grouped:Dictionary={}
	for entry in TRACKS:
		var id=entry.song_id
		if not grouped.has(id):
			grouped[id]={"id":id,"title":entry.song_title,"variants":[],"default_id":"","premium_ids":[],"has_default":false}
		var family:Dictionary=grouped[id]
		family.variants.append(entry)
		if entry.group==DEFAULT:
			if family.default_id=="":family.default_id=entry.id
			family.has_default=true
		else:family.premium_ids.append(entry.id)
	return grouped.values()

static func family_for_track(id:String)->Dictionary:
	var wanted=family_id(id)
	for family in families():
		if family.id==wanted:return family
	return {}

static func edition_label(id:String)->String:
	return str(track(id).get("edition_label","Default"))

static func display_title(id:String)->String:
	# A song title contains only its name. Version labels belong to their controls.
	return song_title(id)

static func sibling_family_track(id:String,direction:int)->String:
	if direction==0:return normalize_selection(id)
	var all_families=families();var current=0
	for index in all_families.size():
		if all_families[index].id==family_id(id):current=index;break
	var preferred=variant_key(id)
	for step in range(1,all_families.size()+1):
		var family=all_families[posmod(current+(step if direction>0 else -step),all_families.size())]
		var fallback=""
		for entry in family.variants:
			if not entry.get("selectable",true):continue
			if fallback=="":fallback=entry.id
			if variant_key(entry.id)==preferred:return entry.id
		if fallback!="":return fallback
	return AUTOMATIC
