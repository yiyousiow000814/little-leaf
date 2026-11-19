extends Node
## QA only: synchronous exclusive elapsed wall-clock scopes on the main thread.
const KEYS=["main_dispatch","duty_sync","input_hud","service_coordination","model_tick","staff_runtime","task_assignment","navigation","autosave","ui_refresh","roster","audio","renderer_update","street_motion","actor_motion","draw_prepare","ground_draw","exterior_draw","depth_sort","entity_draw","draw_finish","native_redraw"]
static var current: Node
var enabled:=false
var _slots:=PackedInt32Array()
var _elapsed:=PackedInt64Array()
var _calls:=PackedInt64Array()
var _last:=0
var _error:=""

func _ready()->void:
	current=self
	_elapsed.resize(KEYS.size());_calls.resize(KEYS.size())

func _exit_tree()->void:
	if current==self:current=null

static func switch_to(slot:int)->void:
	if current!=null and current.enabled:current.pivot(slot)

func set_enabled(active:bool)->void:
	if active==enabled:return
	if not _slots.is_empty():
		_error="enable transition inside scope"
		return
	enabled=active
	_elapsed.fill(0);_calls.fill(0)
	_last=Time.get_ticks_usec();_error=""

func _accrue(now:int)->void:
	if now<_last:
		_error="scope clock went backwards"
		return
	if not _slots.is_empty():
		var slot:=_slots[_slots.size()-1]
		_elapsed[slot]+=now-_last
	_last=now

func is_top(slot:int)->bool:
	return not _slots.is_empty() and _slots[_slots.size()-1]==slot

func enter(slot:int)->void:
	_accrue(Time.get_ticks_usec())
	_slots.append(slot);_calls[slot]+=1

func pivot(slot:int)->void:
	if not enabled:return
	if _slots.is_empty():
		_error="pivot without scope"
		return
	_accrue(Time.get_ticks_usec())
	_slots[_slots.size()-1]=slot;_calls[slot]+=1

func leave()->void:
	if _slots.is_empty():
		_error="leave without scope"
		return
	_accrue(Time.get_ticks_usec())
	_slots.resize(_slots.size()-1)

func cut(now_us:int)->Dictionary:
	if not _slots.is_empty():_error="phase cut inside synchronous scope"
	if now_us<_last:_error="phase cut went backwards"
	if _error!="":return {"ok":false,"error":_error,"buckets":{}}
	var buckets:Dictionary={}
	for slot in KEYS.size():
		if _calls[slot]<=0:continue
		buckets[KEYS[slot]]={"usec":_elapsed[slot],"calls":_calls[slot]}
	_elapsed.fill(0);_calls.fill(0);_last=now_us
	return {"ok":true,"error":"","buckets":buckets}
