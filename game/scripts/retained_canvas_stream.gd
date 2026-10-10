extends RefCounted
## Native draw commands retain painter order and strong resource references.
## Geometry, local transforms, and culling bounds have separate lifetimes.
const IDLE_FRAME_LIMIT = 120

class Slot extends RefCounted:
 var rid: RID
 var signature: Array = []
 var idle_frames: int = 0
 var visible: bool = false
 var transform: Transform2D
 var modulate: Color
 var initialized: bool = false
 var bounds: Variant = null

var slots: Array[Slot] = []
var cursor: int = 0
var active: bool = false
var transform := Transform2D.IDENTITY
var owner_ref: WeakRef
var owner: Node2D:
 get:return owner_ref.get_ref() if owner_ref != null else null
var rebuilds: int = 0
var hits: int = 0
var frame_id: int = 0

func begin(artist: Node2D, enabled: bool) -> void:
 frame_id += 1
 owner_ref = weakref(artist)
 cursor = 0
 active = enabled
 transform = Transform2D.IDENTITY
 if not enabled:
  for slot in slots:
   _set_visible(slot, false)

func command(signature: Array, bounds: Variant = null) -> RID:
 if cursor == slots.size():
  var created := Slot.new()
  created.rid = RenderingServer.canvas_item_create()
  RenderingServer.canvas_item_set_parent(created.rid, owner.get_canvas_item())
  RenderingServer.canvas_item_set_draw_index(created.rid, cursor)
  slots.append(created)
 var slot: Slot = slots[cursor]
 cursor += 1
 slot.idle_frames = 0
 _set_visible(slot, true)
 if not slot.initialized or slot.transform != transform:
  RenderingServer.canvas_item_set_transform(slot.rid, transform)
  slot.transform = transform
 if not slot.initialized or slot.modulate != owner.self_modulate:
  RenderingServer.canvas_item_set_self_modulate(slot.rid, owner.self_modulate)
  slot.modulate = owner.self_modulate
 slot.initialized = true

 # Inferred CanvasItem bounds omit the mesh command's transform and do not
 # invalidate when its vertices move. Update explicit bounds independently.
 # Clear the override on mesh-to-primitive reuse: clear() preserves custom_rect.
 if slot.bounds != bounds:
  if bounds == null:
   RenderingServer.canvas_item_set_custom_rect(slot.rid, false)
  else:
   RenderingServer.canvas_item_set_custom_rect(slot.rid, true, bounds)
  slot.bounds = bounds
 if slot.signature == signature:
  hits += 1
  return RID()
 RenderingServer.canvas_item_clear(slot.rid)
 # Packed arrays are copy-on-write. Keep mesh/texture references alive until
 # their native commands are replaced; cache eviction cannot free a live RID.
 slot.signature = signature.duplicate()
 rebuilds += 1
 return slot.rid

func finish() -> void:
 if not active:
  return
 for index in range(cursor, slots.size()):
  var slot: Slot = slots[index]
  slot.idle_frames += 1
  _set_visible(slot, false)
 while slots.size() > cursor and slots[-1].idle_frames > IDLE_FRAME_LIMIT:
  RenderingServer.free_rid(slots[-1].rid)
  slots.pop_back()
 active = false

func _set_visible(slot: Slot, visible: bool) -> void:
 if slot.visible != visible:
  RenderingServer.canvas_item_set_visible(slot.rid, visible)
  slot.visible = visible

func release() -> void:
 for slot in slots:
  RenderingServer.free_rid(slot.rid)
 slots.clear()
 active = false

func _notification(what: int) -> void:
 if what == NOTIFICATION_PREDELETE:
  # Script methods may already be detached during reference-cycle teardown.
  # Release the owned server handles directly instead of dispatching a method.
  for slot in slots:
   RenderingServer.free_rid(slot.rid)
