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
var _render_preparation: Dictionary = {}
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

func prepare_render() -> void:
 # A retained static wave draws its real shader beneath the startup cover.
 # Do not emit a touch, advance the wave pool or sample audio during this pass.
 if not _render_preparation.is_empty() or not is_visible_in_tree():return
 var wave:=_waves[0]
 _render_preparation={"position":wave.position,"visible":wave.visible,"age":wave.material.get_shader_parameter("age"),"process":is_processing(),"input":is_processing_input()}
 set_process(false);set_process_input(false)
 wave.position=(size-wave.size)*0.5
 wave.material.set_shader_parameter("age",0.3);wave.show()

func finish_render_preparation() -> void:
 if _render_preparation.is_empty():return
 var wave:=_waves[0]
 wave.position=_render_preparation.position;wave.visible=_render_preparation.visible
 wave.material.set_shader_parameter("age",_render_preparation.age)
 set_process(_render_preparation.process);set_process_input(_render_preparation.input)
 _render_preparation.clear()

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
 finish_render_preparation()
 clear()

func clear() -> void:
 _ages.fill(2.0)
 for wave in _waves:wave.visible=false
 set_process(false)

func active_count() -> int:
 var count:=0
 for wave in _waves:count+=int(wave.visible)
 return count
