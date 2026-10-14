extends RefCounted
## Scene-owned cleanup cues keep per-impact gain separate from cash/place voices.
## At most 32 cosmetic coins can cross their three contacts and pickup together.
signal cue_started(kind:String,volume_db:float,voice_id:int)
const MAX_VOICES=128
var game_ref:WeakRef
var player:AudioStreamPlayer
var playback:AudioStreamPlaybackPolyphonic
var active:Array[int]=[]
var epoch:Array=[]

func _init(game):game_ref=weakref(game)
func _ensure_player()->bool:
 if is_instance_valid(player):return true
 var game=game_ref.get_ref()
 if not is_instance_valid(game) or not game.is_inside_tree():return false
 player=AudioStreamPlayer.new();player.name="CleanupCoinSfx";player.bus="SFX"
 player.playback_type=AudioServer.PLAYBACK_TYPE_STREAM
 var stream=AudioStreamPolyphonic.new();stream.polyphony=MAX_VOICES
 player.stream=stream;game.add_child(player)
 game.tree_exiting.connect(stop,CONNECT_ONE_SHOT)
 return true
func play(kind:String,volume_db=0.0)->bool:
 var game=game_ref.get_ref()
 if not is_instance_valid(game):return false
 var settings=game.settings_controls
 if settings==null or not settings.sfx_enabled or settings.sfx_volume<=0:return false
 if kind not in ["coin_drop","coin_pickup"] or not settings.effects.has(kind):return false
 if not _ensure_player():return false
 _retire_finished()
 if not player.playing:
  player.play();playback=player.get_stream_playback() as AudioStreamPlaybackPolyphonic
 if playback==null:return false
 var id=playback.play_stream(settings.effects[kind],0.0,volume_db,1.0,AudioServer.PLAYBACK_TYPE_STREAM,&"SFX")
 if id==AudioStreamPlaybackPolyphonic.INVALID_ID:return false
 active.append(id);cue_started.emit(kind,volume_db,id)
 return true
func tick(current_epoch:Array):
 if not epoch.is_empty() and epoch!=current_epoch:stop()
 epoch=current_epoch.duplicate()
 _retire_finished()
func _retire_finished():
 if playback==null:return
 for i in range(active.size()-1,-1,-1):
  if not playback.is_stream_playing(active[i]):active.remove_at(i)
 if active.is_empty():stop()
func stop():
 if is_instance_valid(player):player.stop()
 playback=null;active.clear()
