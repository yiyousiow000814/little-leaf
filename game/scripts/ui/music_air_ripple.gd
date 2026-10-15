extends Control
## Four retained pressure-wave quads. No input interception, full-screen copy,
## post-processing, timers, allocations or draw-list rebuilds during playback.
const PAINT = preload("res://assets/ui/music_pearlwood/music_air_ripple.gdshader")
const CAPACITY := 4
var _waves: Array[ColorRect] = []
var _ages := PackedFloat32Array()
var _cursor := 0
var reduced := false
var _music_energy := 0.0
signal touched(point: Vector2)

func _init() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 clip_contents=true
 set_process(false)
 _ages.resize(CAPACITY);_ages.fill(2.0)
 for index in CAPACITY:
  var wave:=ColorRect.new();wave.name="AirPressure%02d"%index
  wave.mouse_filter=Control.MOUSE_FILTER_IGNORE;wave.size=Vector2(160,160)
  var paint:=ShaderMaterial.new();paint.shader=PAINT;wave.material=paint
  wave.visible=false;add_child(wave);_waves.append(wave)
 visibility_changed.connect(_visibility_changed)

func emit_at(point:Vector2) -> void:
 if reduced or not is_visible_in_tree():return
 var wave:=_waves[_cursor];_ages[_cursor]=0.0
 wave.position=point-wave.size*0.5;wave.visible=true
 wave.material.set_shader_parameter("age",0.0)
 _cursor=(_cursor+1)%CAPACITY
 set_process(true);touched.emit(point)

func _input(event:InputEvent) -> void:
 if not is_visible_in_tree() or reduced:return
 var pressed:bool=event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed
 if event is InputEventScreenTouch:pressed=event.pressed
 if not pressed:return
 var local:Vector2=get_global_transform().affine_inverse()*event.position
 if Rect2(Vector2.ZERO,size).has_point(local):emit_at(local)

func _process(delta:float) -> void:
 var active:=false
 var bus:=AudioServer.get_bus_index("BGM")
 var target:=0.0
 if bus>=0 and not AudioServer.is_bus_mute(bus):
  target=clampf(db_to_linear(maxf(AudioServer.get_bus_peak_volume_left_db(bus,0),AudioServer.get_bus_peak_volume_right_db(bus,0)))*6.0,0.0,1.0)
 _music_energy=lerpf(_music_energy,target,1.0-exp(-delta*9.0))
 for index in CAPACITY:
  if _ages[index]>=0.95:continue
  _ages[index]+=delta
  _waves[index].material.set_shader_parameter("age",_ages[index])
  _waves[index].material.set_shader_parameter("music_energy",_music_energy)
  _waves[index].visible=_ages[index]<0.95
  active=active or _waves[index].visible
 set_process(active)

func _visibility_changed() -> void:
 if is_visible_in_tree():return
 clear()

func clear() -> void:
 _ages.fill(2.0)
 for wave in _waves:wave.visible=false
 set_process(false)

func active_count() -> int:
 var count:=0
 for wave in _waves:count+=int(wave.visible)
 return count
