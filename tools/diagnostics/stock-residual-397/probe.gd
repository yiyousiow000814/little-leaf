extends Node
## Stock engine probe in an isolated synthetic-only project; no engine patches.
const WARM:=8
const SAMPLE:=24
const STRIDE:=6
const MODES:=[false,false,true,false,true,false]
var _thread:=0
var _rid:=RID()
var _query:=false
var _pre:=0
var _post:=0
var _last_frame:=-1
var _index:=0
var _advance:=0
var _running:=false
var _fault:=""
var _rows:=PackedFloat64Array()
var _guest_id:=-1
var _cap:=60
var _restore:=false

func _ready()->void:
 if not "--stock-residual-397" in OS.get_cmdline_user_args():return
 if not _host_ok() or OS.get_environment("LL397_STOCK_RAW").is_empty():
  get_tree().quit(7);return
 _thread=OS.get_main_thread_id()
 _rid=get_tree().root.get_viewport_rid()
 if not _rid.is_valid():
  get_tree().quit(8);return
 _rows.resize(SAMPLE*STRIDE)
 _await_active()

func _host_ok()->bool:
 var adapter:=RenderingServer.get_video_adapter_name().to_lower()
 var info:=(RenderingServer.get_video_adapter_vendor()+" "+RenderingServer.get_video_adapter_api_version()).to_lower()
 return DisplayServer.get_name()=="X11" and DisplayServer.window_get_size()==Vector2i(1360,880) and "llvmpipe" in adapter and "mesa" in info and not OS.has_feature("web") and RenderingServer.get_current_rendering_method()=="gl_compatibility" and RenderingServer.get_current_rendering_driver_name()=="opengl3" and Engine.get_version_info().get("hash")=="7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3" and DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_DISABLED

func _state()->Dictionary:
 var game:=get_tree().current_scene
 if game==null or not "model" in game or game.model==null or not game.model.operating_open or game.paused or game.editing or game.save_recovery_blocked or (game.cafe_intro!=null and game.cafe_intro.active):return {}
 if game.model.items.size()!=7 or game.model.built_walls.size()!=21 or game.model.wall_attachments.size()!=1:return {}
 for guest in game.model.customers:
  if (_guest_id<0 or int(guest.id)==_guest_id) and guest.phase=="cooking" and guest.seated:
   return {"cooking_id":int(guest.id),"customers":game.model.customers.size(),"served":int(game.model.served),"items":7,"walls":21,"openings":1}
 return {}

func _await_active()->void:
 var deadline:=Time.get_ticks_msec()+180000
 while Time.get_ticks_msec()<deadline:
  await get_tree().create_timer(.20,true,false,true).timeout
  var state:=_state()
  if not state.is_empty():
   _guest_id=state.cooking_id
   await _measure(state)
   return
 _finish(4)

func _measure(state:Dictionary)->void:
 _cap=Engine.max_fps
 if _cap!=60 or RenderingServer.viewport_get_measured_render_time_cpu(_rid)!=0.0:
  _finish(7);return
 _restore=true;Engine.max_fps=0
 RenderingServer.frame_pre_draw.connect(_on_pre)
 RenderingServer.frame_post_draw.connect(_on_post)
 var windows:Array=[]
 for flag in MODES:
  if not _host_ok() or _state()!=state or Engine.max_fps!=0:
   _fault="scenario or host changed";break
  _query=flag
  RenderingServer.viewport_set_measure_render_time(_rid,_query)
  _index=0;_advance=0;_pre=0;_post=0;_last_frame=-1
  _running=true
  var deadline:=Time.get_ticks_msec()+12000
  while _running and _fault=="" and Time.get_ticks_msec()<deadline:
   await get_tree().process_frame
  _running=false
  if _fault!="" or _index!=SAMPLE or _state()!=state or Engine.max_fps!=0:
   _fault="incomplete window or changed fixture" if _fault=="" else _fault
   break
  windows.append({"query":flag,"rows":Array(_rows)})
 RenderingServer.frame_pre_draw.disconnect(_on_pre)
 RenderingServer.frame_post_draw.disconnect(_on_post)
 if _fault!="" or windows.size()!=MODES.size():
  _finish(8);return
 var receipt:={"schema":"ll397-stock-residual-raw-v1","state":state,"windows":windows}
 var file:=FileAccess.open(OS.get_environment("LL397_STOCK_RAW"),FileAccess.WRITE)
 if file==null:
  _finish(3);return
 file.store_string(JSON.stringify(receipt));file.close()
 _finish(0)

func _on_pre()->void:
 if not _running:return
 if OS.get_thread_caller_id()!=_thread or _pre!=0:
  _fault="pre order or thread";return
 _pre=Time.get_ticks_usec()

func _on_post()->void:
 if not _running or _fault!="":return
 var now:=Time.get_ticks_usec()
 var frame:=Engine.get_frames_drawn()
 if OS.get_thread_caller_id()!=_thread or _pre<=0 or _pre>=now or (_last_frame>=0 and frame!=_last_frame+1):
  _fault="post order, thread or draw serial";return
 var prep:=RenderingServer.get_frame_setup_time_cpu()
 if not is_finite(prep) or prep<0.0 or prep*1000.0>now-_pre:
  _fault="same-frame preparation outside its draw span";return
 if _advance>=WARM:
  var start:=_index*STRIDE
  _rows[start]=frame
  _rows[start+1]=now-_post
  _rows[start+2]=now-_pre
  _rows[start+3]=prep*1000.0
  # Read CPU in both arms to match getter cost. When off it must freeze after settling.
  _rows[start+4]=RenderingServer.viewport_get_measured_render_time_cpu(_rid)*1000.0
  _rows[start+5]=RenderingServer.viewport_get_measured_render_time_gpu(_rid)*1000.0
  _index+=1
  if _index==SAMPLE:_running=false
 _advance+=1;_last_frame=frame;_post=now;_pre=0

func _finish(code:int)->void:
 if _restore:
  RenderingServer.viewport_set_measure_render_time(_rid,false)
  Engine.max_fps=_cap
 if _fault!="":printerr("STOCK_RESIDUAL397 declined: ",_fault)
 get_tree().quit(code)
