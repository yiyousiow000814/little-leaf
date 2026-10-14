extends RefCounted
## Lossless background music pack, requested only after real gameplay begins.
const MAX_ATTEMPTS=3
const RETRY_DELAY_MSEC=5000
var requested=false
var attempts=0
var retry_at_msec=0
var game
var request:HTTPRequest
func _init(owner):game=owner
func begin():
	# Main calls this only during playable foreground gameplay. Never schedule
	# background work, or turn a failed download into a request every frame.
	if requested or attempts>=MAX_ATTEMPTS or _now_msec()<retry_at_msec:return
	requested=true
	attempts+=1
	request=HTTPRequest.new();game.add_child(request)
	request.timeout=30.0
	# Browser fetch already decodes Content-Encoding; avoid Godot double decoding.
	request.accept_gzip=false
	request.request_completed.connect(_loaded)
	if _start_request()!=OK:
		_failed("Background music could not start loading")
func _now_msec()->int:return Time.get_ticks_msec()
func _start_request()->Error:
	var url=str(JavaScriptBridge.eval('new URL("music.pck",location.href).href'))
	return request.request(url)
func _release_request():
	if request==null:return
	request.cancel_request()
	game.remove_child(request)
	request.queue_free()
	request=null
func _failed(message:String):
	_release_request()
	requested=false
	retry_at_msec=_now_msec()+RETRY_DELAY_MSEC
	push_warning(message+"; gameplay and saves remain available")
func _loaded(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray):
	_release_request()
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
		_failed("Background music could not load");return
	DirAccess.make_dir_recursive_absolute("/tmp")
	var path="/tmp/little_leaf_cg_music.pck"
	var file=FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		_failed("Background music package could not be saved");return
	file.store_buffer(body);file.flush()
	var write_error=file.get_error();file.close()
	if write_error!=OK:
		_failed("Background music package could not be saved");return
	if not ProjectSettings.load_resource_pack(path):
		_failed("Background music package could not be opened");return
	game._setup_music()
	# Preserve current preferences; do not create a second SFX player.
	game.settings_controls._apply_buses()

	JavaScriptBridge.eval("globalThis.LittleLeafPlatform.musicReady="+str(game.audio_players.size()==3))
