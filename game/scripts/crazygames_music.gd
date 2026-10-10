extends RefCounted
## Lossless background music pack, requested only after real gameplay begins.
var requested=false
var game
var request:HTTPRequest
func _init(owner):game=owner
func begin():
	if requested:return
	requested=true
	request=HTTPRequest.new();game.add_child(request)
	# Browser fetch already decodes Content-Encoding; avoid Godot double decoding.
	request.accept_gzip=false
	request.request_completed.connect(_loaded)
	var url=str(JavaScriptBridge.eval('new URL("music.pck",location.href).href'))
	if request.request(url)!=OK:
		push_warning("Background music could not start loading")
func _loaded(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray):
	request.queue_free()
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
		push_warning("Background music could not load; gameplay and saves remain available");return
	DirAccess.make_dir_recursive_absolute("/tmp")
	var path="/tmp/little_leaf_cg_music.pck"
	var file=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return
	file.store_buffer(body);file.close()
	if not ProjectSettings.load_resource_pack(path):
		push_warning("Background music package could not be opened");return
	game._setup_music()
	# Preserve current preferences; do not create a second SFX player.
	game.settings_controls._apply_buses()

	JavaScriptBridge.eval("globalThis.LittleLeafPlatform.musicReady="+str(game.audio_players.size()==3))
