extends SceneTree
## Full generated Main, frozen after construction. No real save/account loader.
## Normal frames are paired; exceptional ownership mutations are candidate-only.
const Native = preload("res://scripts/rendering/cafe_native_draw_node.gd")
const Shape = preload("res://scripts/rendering/cafe_shape_2d.gd")
const Pick = preload("res://scripts/rendering/cafe_character_pick_geometry.gd")
const LABELS = ["initial", "equal-depth-approach-a", "equal-depth-approach-b", "seated-table-reach", "waiter-food-delivery", "chef-station-rear", "cleaner-litter-foreground", "body-overlay-depth-reversal", "front-back-turn", "reflected-placement", "blink-on", "blink-off", "pan-offscreen", "pan-back", "zoom-out", "zoom-back", "decorate-hide", "decorate-return", "guest-departure", "same-id-guest-replacement", "staff-node-replacement", "same-main-service-restore", "model-replacement", "final-normal-scene"]
const PROFILE_KEYS = ["HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]
const VIEW = Rect2(0, 0, 1360, 880)
class SyntheticMain extends "res://scripts/main.gd":
 var save_calls = 0
 func _load_startup():
  save_writes_suppressed = true
  fresh_start = true
  music_enabled = false
  MinimalStart.apply(model)
  paused = true
 func _setup_music(): pass
 func _save():
  save_calls += 1
  assert(false, "Capture must not invoke a save callback")
  return false

var game
var art
var frames = []
var pending_frame = {}
var cafe_guest_cohort = []
var actor_domains = {}
var output = OS.get_environment("OUTPUT")
var smoke = OS.get_environment("STABLE_ACTOR_CAPTURE_HEADLESS_SMOKE") == "1"
var candidate = false
var fixture_table = -1
var fixture_chair = -1
var wall_id = ""
var normal_guest
var lifecycle = {"guest_replacements":0, "staff_replacements":0, "service_restores":0, "model_replacements":0}
var failures = []
var abnormal_safety = {"executed":false, "passed":false, "cases":[]}

func _initialize():
 if "--classifier-only" in OS.get_cmdline_user_args(): classifier_checks.call_deferred()
 else: run.call_deferred()

# Pure domain classification: no ID ranges and no dependency on the live café
# roster. A retired cohort ID remains café and cannot hide a departed ghost.
static func make_actor_domains(cohort:Array, sources:Dictionary)->Dictionary:
 var cafe = {}
 var ambient = {}
 var errors = []
 for id in cohort:
  if cafe.has(int(id)): errors.append("Duplicate café cohort ID " + str(id))
  cafe[int(id)] = true
 for source in sources:
  for actor in sources[source]:
   if not actor.has("appearance"):
    errors.append("Ambient appearance missing in " + str(source))
    continue
   var id = int(actor.appearance)
   if cafe.has(id): errors.append("Café/ambient appearance collision " + str(id))
   if ambient.has(id): errors.append("Duplicate ambient appearance " + str(id))
   ambient[id] = str(source) + "/" + str(actor.get("key", ""))
 return {"ok":errors.is_empty(), "errors":errors, "cafe":cafe, "ambient":ambient}

static func classify_actor(is_staff:bool, appearance:int, domains:Dictionary)->String:
 if is_staff: return "cafe"
 if domains.cafe.has(appearance) and domains.ambient.has(appearance): return "collision"
 if domains.cafe.has(appearance): return "cafe"
 if domains.ambient.has(appearance): return "ambient"
 return "unknown"

static func body_multiset_matches(actual:Array, expected:Array, allow_culled=false)->bool:
 var left = actual.duplicate()
 var right = expected.duplicate()
 left.sort()
 right.sort()
 if not allow_culled: return left == right
 # Culling may omit a current body, never add a departed/duplicate one.
 for key in left:
  var index = right.find(key)
  if index < 0: return false
  right.remove_at(index)
 return true

func refresh_actor_domains():
 actor_domains = make_actor_domains(cafe_guest_cohort, {
  "street_walkers":art.street_pedestrians.walkers,
  "street_departures":art.street_pedestrians.departures.values(),
  "bus_stop":art.bus_stop_pedestrians.actors
 })

func actor_domain(key:String)->String:
 if key == "": return "unknown"
 var identity = key.get_slice("|",0)
 var family = identity.get_slice("/",0)
 var appearance = identity.get_slice("/",1)
 if family not in ["staff", "guest"] or not appearance.is_valid_int(): return "unknown"
 return classify_actor(family == "staff", int(appearance), actor_domains)

func expected_cafe_bodies()->Array:
 var result = []
 if not game.editing:
  for guest in game.model.customers: result.append("guest/" + str(guest.id) + "|body")
  for index in game.staff_states.size(): result.append("staff/" + str(index) + "|body")
 result.sort()
 return result

func classifier_checks():
 var rows = []
 var sources = {"street_walkers":[{"appearance":112,"key":"walker"}], "street_departures":[{"appearance":114,"key":"departure"}], "bus_stop":[{"appearance":401,"key":"bus"}]}
 var domains = make_actor_domains([1,2,3], sources)
 rows.append({"case":"positive-source-enumeration", "passed":domains.ok and domains.ambient.size() == 3})
 for id in [112,114,401]: rows.append({"case":"ambient-" + str(id), "passed":classify_actor(false,id,domains) == "ambient"})
 rows.append({"case":"all-staff-remain-cafe", "passed":classify_actor(true,401,domains) == "cafe"})
 rows.append({"case":"unknown-id-rejected", "passed":classify_actor(false,999,domains) == "unknown"})
 rows.append({"case":"retired-cohort-id-remains-cafe", "passed":classify_actor(false,3,domains) == "cafe"})
 rows.append({"case":"cafe-ambient-collision-rejected", "passed":not make_actor_domains([112],sources).ok})
 rows.append({"case":"duplicate-cohort-rejected", "passed":not make_actor_domains([1,1],sources).ok})
 var duplicate = sources.duplicate(true)
 duplicate.bus_stop.append({"appearance":112,"key":"duplicate"})
 rows.append({"case":"duplicate-ambient-rejected", "passed":not make_actor_domains([1,2,3],duplicate).ok})
 var expected = ["guest/1|body","guest/2|body","staff/0|body"]
 rows.append({"case":"exact-cafe-multiset", "passed":body_multiset_matches(expected,expected)})
 rows.append({"case":"departed-ghost-rejected", "passed":not body_multiset_matches(expected+["guest/3|body"],expected)})
 rows.append({"case":"duplicate-body-rejected", "passed":not body_multiset_matches(expected+["guest/1|body"],expected)})
 rows.append({"case":"equal-count-wrong-identity-rejected", "passed":not body_multiset_matches(["guest/1|body","guest/3|body","staff/0|body"],expected)})
 rows.append({"case":"intentional-culling-subset", "passed":body_multiset_matches(["staff/0|body"],expected,true)})
 rows.append({"case":"culled-departed-ghost-rejected", "passed":not body_multiset_matches(["guest/3|body"],expected,true)})
 rows.append({"case":"culled-duplicate-rejected", "passed":not body_multiset_matches(["staff/0|body","staff/0|body"],expected,true)})
 rows.append({"case":"decorate-empty-cafe", "passed":body_multiset_matches([],[]) and not body_multiset_matches(["guest/3|body"],[])})
 var result = {"checks":rows, "passed":rows.all(func(row): return row.passed), "game_instance_created":false, "native_render_executed":false}
 if output != "":
  DirAccess.make_dir_recursive_absolute(output)
  FileAccess.open(output.path_join("classifier.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("STABLE_ACTOR_DOMAIN_CLASSIFIER_RESULT ",JSON.stringify(result))
 quit(0 if result.passed else 2)

func check(ok:bool, message:String):
 if ok: return
 failures.append(message)
 push_error(message)
 write_report()
 quit(2)
 assert(ok, message)

func plain(value):
 match typeof(value):
  TYPE_VECTOR2, TYPE_VECTOR2I: return [value.x, value.y]
  TYPE_VECTOR3, TYPE_VECTOR3I: return [value.x, value.y, value.z]
  TYPE_COLOR: return [value.r, value.g, value.b, value.a]
  TYPE_RECT2, TYPE_RECT2I: return [plain(value.position), plain(value.size)]
  TYPE_TRANSFORM2D: return [plain(value.x), plain(value.y), plain(value.origin)]
  TYPE_FLOAT:
   return value if is_finite(value) else ("nan" if is_nan(value) else ("+inf" if value > 0 else "-inf"))
  TYPE_DICTIONARY:
   var result = {}
   for key in value:
    if str(key) in ["native_owner", "node"]: continue
    result[str(key)] = plain(value[key])
   return result
  TYPE_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
   var result = []
   for entry in value: result.append(plain(entry))
   return result
  TYPE_OBJECT:
   check(false, "Input/contact receipt must not contain an object identity")
   return null
  _: return value

func digest(value)->String:
 return JSON.stringify(plain(value), "", true, true).sha256_text()

func inputs()->Dictionary:
 var components = {
  "model":{"width":game.model.width, "depth":game.model.depth, "revision":game.model.revision, "operating_open":game.model.operating_open, "duty_targets":game.model.duty_targets, "duty_counts":game.model.duty_counts, "service_snapshot":game.model.service_snapshot, "ground_mess_generation":game.ground_mess_generation},
  "layout":{"items":game.model.items, "walls":game.model.built_walls, "attachments":game.model.wall_attachments, "floor_finishes":game.model.floor_finishes, "dining_sets":game.model.dining_sets, "owned_parcels":game.model.owned_parcels},
  "guests":{"customers":game.model.customers, "outside_queue":game.model.outside_queue, "service":game.service_guests, "floor":game.floor_tasks.snapshot(), "floor_generation":game.floor_tasks.generation, "dishes":game.dishwashing.snapshot()},
  "staff":game.staff_states,
  "clock":{"animation_time":game.animation_time, "paused":game.paused, "editing":game.editing, "cooking_motion_strength":art.cooking_motion_strength},
  "camera":{"zoom":art.zoom, "pan":art.pan_offset, "origin":art.origin, "tile":art.tile, "ui_scale":art.ui_scale, "wall_detail":game.wall_detail},
  "presentation":{"motion":art.motion._actors, "facings":art.character_facings, "seats":art.seat_blends, "stances":art.stance_offsets, "carry_hands":art.carry_hand_offsets, "meal_chairs":art.meal_chair_offsets, "table_directions":art.table_dining_directions, "traffic":art.road_traffic.cars},
  "actor_domains":{"cafe_guest_cohort":cafe_guest_cohort, "classification":actor_domains, "street_walkers":art.street_pedestrians.walkers, "street_departures":art.street_pedestrians.departures, "bus_stop":art.bus_stop_pedestrians.actors},
  "lifecycle":lifecycle.duplicate(true)
 }
 var hashes = {}
 for key in components: hashes[key] = digest(components[key])
 return {"state":plain(components), "sha256":hashes}

func freeze(node:Node):
 node.set_process(false)
 node.set_physics_process(false)
 node.set_process_input(false)
 node.set_process_unhandled_input(false)
 for child in node.get_children(): freeze(child)

func staff(role:String)->Dictionary:
 for worker in game.staff_states:
  if worker.role == role: return worker
 check(false, "Missing generated staff role " + role)
 return {}

func place_worker(role:String, at:Vector2, action="standby", target_id=-1, progress=.25, payload="none"):
 var worker = staff(role)
 worker.pos = at
 worker.node.position = Vector3(at.x, 0, at.y)
 worker.path = []
 worker.index = 0
 worker.on_duty = true
 game._set_staff_art(worker, action, game.model.get_item(target_id), progress, payload)
 worker.art_heading = Vector2(1, 0)

func clear_presentation():
 art.motion._actors.clear()
 art.stance_offsets.clear()
 art.shared_stance_cache.clear()
 art.seat_blends.clear()
 art.meal_chair_offsets.clear()
 art.table_dining_directions.clear()
 art.character_facings.clear()
 art.carry_hand_offsets.clear()

func prepare_scene():
 game.model.coins = 1000000
 check(game.model.move(int(game.model.checkout_register().id), 7, 7, 1, []), "Register placement: " + game.model.last_error)
 check(game.model.place("table_set", 6, 5, 2, []), "Rear dining set: " + game.model.last_error)
 check(game.model.place("table_set", 9, 6, 0, []), "Third dining set: " + game.model.last_error)
 check(game.model.place_wall("x", 4, 5, "full", "original", []), "Centered wall: " + game.model.last_error)
 wall_id = game.model.get_wall("x:4:5").id
 var host = game.model.wall_hosts().filter(func(row): return wall_id in row.wall_ids)[0]
 check(game.model.place_wall_attachment("window", host.host_id, .5, []), "Wall attachment: " + game.model.last_error)
 game.model.rebuild_dining_sets()
 check(game.model.layout_access_issues().is_empty(), "Generated layout must preserve all service access")
 game._rebuild_room()
 game._rebuild_furniture()
 game._update_people()
 if not game.staff_states.any(func(row): return row.role == "cashier"):
  check(game._add_staff("cashier", Vector2(7.5, 8.3)), "Generated cashier identity")
 game.model.cashiers = 1
 game.model.duty_targets.cashier = 1
 game.model.duty_counts.cashier = 1
 game.model.customers.clear()
 game.model.outside_queue.clear()
 game.model.operating_open = true
 game.model.first_guest_pending = false
 # Spawn via the real reservation/entry construction, then freeze the poses.
 for count in 3:
  game.model._spawn_walkers(1)
  check(game.model.customers.size() == count + 1, "Generated guest reservation " + str(count))
  game.model.customers[-1].phase = "ordering"
 game.model.operating_open = false
 for guest in game.model.customers:
  var chair = game.model.get_item(int(guest.chair_id))
  guest.x = chair.x + .5
  guest.z = chair.z + .5
  guest.elapsed = .25
  guest.duration = 1.0
  guest.seated = false
  guest.admitted = true
  guest.waiting = false
  guest.route = []
  guest.route_index = 0
  guest.heading = Vector2(1, 0)
  guest.dismounting = false
  guest.phase = "cooking"
  if int(chair.x) == 6:
   fixture_chair = int(chair.id)
   fixture_table = int(guest.table_id)
   normal_guest = guest
 check(fixture_table >= 0 and game.model.customers.size() == 3, "Three species and rear seat are present")
 check(cafe_guest_cohort.is_empty(), "Initial café identity cohort must be enrolled only once")
 for guest in game.model.customers: cafe_guest_cohort.append(int(guest.id))
 cafe_guest_cohort.sort()
 refresh_actor_domains()
 check(actor_domains.ok, "Generated café and ambient appearance domains must be disjoint")
 game._sync_service_guests()
 check(game.floor_tasks.spawn(Vector2i(5, 6), "banana") >= 0, "Real floor litter geometry")
 place_worker("chef", Vector2(8.5, .5))
 place_worker("waiter", Vector2(6.0, 4.5))
 place_worker("cleaner", Vector2(4.7, 6.5))
 place_worker("cashier", Vector2(7.5, 8.3))
 clear_presentation()
 art.road_traffic.cars.clear()
 game.animation_time = .35
 art.zoom = 1.0
 art.pan_offset = Vector2.ZERO
 art.update_projection()

func actor_key(node)->String:
 if node.get_script() != Native or node.appearance.is_empty(): return ""
 var shape = node.appearance[0]
 if not shape is Array or shape.is_empty() or shape[0] != "character": return ""
 return ("staff/" if bool(shape[3]) else "guest/") + str(shape[2]) + ("|overlay" if bool(shape[12].get("reach_overlay", false)) else "|body")

func semantic(node)->Dictionary:
 var result = {"order":int(node.get_meta("native_painter_order", -1)), "placement":plain(node.transform)}
 if node.get_script() == Native:
  var shape = node.appearance[0]
  result["kind"] = str(shape[0])
  if shape[0] == "character":
   result["actor"] = actor_key(node)
   result["domain"] = actor_domain(result.actor)
   result["pose"] = plain(shape)
  elif shape[0] == "furniture":
   result["part"] = shape[1]
   result["item"] = plain(shape[2])
  elif shape[0] == "wall-slice":
   result["wall"] = plain(shape)
  else:
   result["shape"] = plain(shape)
 else:
  result["kind"] = "world-shape"
  result["command"] = str(node.draw_method)
 return result

func current_order(issues:Array)->Array:
 var rows = []
 var last = -1
 for child in art.get_children():
  var order = int(child.get_meta("native_painter_order", -1))
  if order < 0 or not child.is_visible_in_tree(): continue
  var generation = child.generation if child.get_script() == Native else child.get_meta("generation", -1)
  if generation != art.canvas_stream.frame_id: issues.append("Visible stale painter sibling")
  if order <= last: issues.append("Mixed native/world sibling order differs from submitted order")
  last = order
  if child.get_script() == Native:
   if child.draw_order != order or art.native_object_nodes.get(order) != child: issues.append("Active native owner lookup/order mismatch")
  else:
   if art.native_world_shapes.get(order) != child: issues.append("Active world shape lookup mismatch")
  rows.append(semantic(child))
 return rows

func contacts_normalized(source:Array, issues:Array)->Array:
 var owner_keys = {}
 for owner in art.native_object_nodes.values():
  if owner.visible: owner_keys[owner.get_instance_id()] = actor_key(owner)
 var result = []
 var seen = {}
 for contact in source:
  var key = owner_keys.get(contact.get("native_owner", -1), "")
  if key == "" or seen.has(key): issues.append("Missing or double-rendered semantic actor contact: " + key)
  seen[key] = true
  var row = plain(contact)
  row["actor"] = key
  row["domain"] = actor_domain(key)
  result.append(row)
 result.sort_custom(func(a,b): return a.actor < b.actor)
 return result

func completed_native(node:Node, counts:Dictionary):
 for child in node.get_children():
  if child is CanvasItem and not child.is_visible_in_tree(): continue
  if child.get_script() == Native or child.get_script() == Shape:
   check(child.paint_revision == child.painted_revision, "Visible native descendant missed first completed frame")
   counts["native_groups" if child.get_script() == Native else "shapes"] += 1
  completed_native(child, counts)

func node_bounds(node:Node2D)->Rect2:
 var bounds = Rect2()
 if node.get_script() == Native:
  for mesh in node.resources:
   var box = mesh.get_aabb()
   var rect = node.get_global_transform_with_canvas() * Rect2(Vector2(box.position.x, box.position.y), Vector2(box.size.x, box.size.y))
   bounds = rect if not bounds.has_area() else bounds.merge(rect)
  for child in node.get_children():
   if child is Node2D and child.is_visible_in_tree():
    var rect = node_bounds(child)
    if rect.has_area(): bounds = rect if not bounds.has_area() else bounds.merge(rect)
 elif node.get_script() == Shape:
  var args = node.draw_arguments
  var local = Rect2()
  match str(node.draw_method):
   "draw_mesh", "retained_aa_mesh", "scaled_contours":
    var box = args[0].get_aabb()
    local = Rect2(Vector2(box.position.x, box.position.y), Vector2(box.size.x, box.size.y))
    if str(node.draw_method) == "draw_mesh": local = args[2] * local
    if str(node.draw_method) == "scaled_contours" and node.material is ShaderMaterial:
     var scale = float(node.material.get_shader_parameter("geometry_scale"))
     local = Rect2(local.position * scale, local.size * scale)
    local = local.grow(2)
   "draw_texture_rect_region": local = args[1].abs()
   "draw_rect": local = args[0].abs().grow(2)
   "draw_circle": local = Rect2(args[0] - Vector2.ONE * args[1], Vector2.ONE * args[1] * 2).grow(2)
   "draw_line", "scalable_line": local = Rect2(args[0], Vector2.ZERO).expand(args[1]).grow(maxf(2, float(args[3])))
   "draw_polygon", "draw_colored_polygon", "draw_polyline", "scalable_polyline", "draw_multiline", "scalable_multiline", "ordered_triangles":
    var points = args[1] if str(node.draw_method) == "ordered_triangles" else args[0]
    if not points.is_empty():
     local = Rect2(points[0], Vector2.ZERO)
     for point in points: local = local.expand(point)
     local = local.grow(2)
   _: check(false, "Unaccounted silhouette command " + str(node.draw_method))
  bounds = node.get_global_transform_with_canvas() * local
 return bounds

func actor_bounds(label:String, issues:Array)->Array:
 var rows = []
 for node in art.native_object_nodes.values():
  var key = actor_key(node)
  if key == "" or not node.visible: continue
  var bounds = node_bounds(node)
  var domain = actor_domain(key)
  if not bounds.has_area(): issues.append("Actor has no completed geometry bounds: " + key)
  if domain == "cafe" and label != "pan-offscreen" and not VIEW.encloses(bounds): issues.append("Complete café silhouette outside viewport: " + key + " " + str(bounds))
  rows.append({"actor":key, "domain":domain, "bounds":plain(bounds), "fully_in_view":VIEW.encloses(bounds), "reflected":node.transform.determinant() < 0})
 rows.sort_custom(func(a,b): return a.actor < b.actor)
 return rows

func actual_owner(key:String):
 for node in art.native_object_nodes.values():
  if node.visible and actor_key(node) == key: return node
 return null

func sample_pick(name:String, point:Vector2, expected:bool, owner=null)->Dictionary:
 var hit = art.ground_mess_occluded(point)
 var uncertain = art.character_pick_geometry.last_uncertain
 check(hit == expected and not uncertain, "Real completed picker differs at " + name)
 var primitive = -1
 if owner != null:
  primitive = art.character_pick_geometry._node_hit(owner, point, 1.0, art.ground_hit_images())
  check(primitive == Pick.HIT, "Fixed semantic sample misses completed primitive: " + name)
 return {"name":name, "screen":plain(point), "expected_occluded":expected, "occluded":hit, "uncertain":uncertain, "source_primitive_hit":primitive}

func pick_receipt(label:String)->Dictionary:
 var pick = art.character_pick_geometry
 check(pick.presented_frame == art.canvas_stream.frame_id, "Normal real picker query lacks first-frame receipt")
 var samples = []
 # These are fixed source-derived points, never searched for a passing result.
 var actor_keys = []
 for node in art.native_object_nodes.values():
  var key = actor_key(node)
  if node.visible and key.ends_with("|body") and VIEW.has_point(node.get_global_transform_with_canvas() * Vector2(0,-40)): actor_keys.append(key)
 actor_keys.sort()
 if not actor_keys.is_empty():
  var actor = actual_owner(actor_keys[0])
  samples.append(sample_pick(actor_keys[0] + "-head", actor.get_global_transform_with_canvas() * Vector2(0,-40), true, actor))
 if label != "pan-offscreen":
  var chair = game.model.get_item(fixture_chair)
  var point = art.iso(chair.x+.5, chair.z+.5) + Vector2(0,-18) * art.ui_scale * art.zoom
  samples.append(sample_pick("rear-chair-seat-region", point, true))
  samples.append(sample_pick("centered-wall-lower-panel", art.iso(4.25,5.0,18), true))
  samples.append(sample_pick("clear-front-floor", art.iso(2.5,7.5), false))
 if label == "waiter-food-delivery":
  var key = "staff/" + str(game.staff_states.find(staff("waiter"))) + "|overlay"
  var carrier = actual_owner(key)
  check(carrier != null, "Delivery must exercise a real reach overlay")
  samples.append(sample_pick("carried-plate-center", carrier.get_global_transform_with_canvas() * Vector2(21,-25), true, carrier))
 check(not samples.is_empty(), "Frame must contain at least one verified query point")
 # A shared pre-existing transform dependency invalidates both source receipts.
 # Candidate-only sibling-order protection is checked in exceptional_safety().
 var node = art.native_object_nodes.values().filter(func(n): return n.visible and n.draw_order >= art.ground_occlusion_start and n.draw_order < art.ground_occlusion_end)[0]
 var old = node.position
 node.position = old + Vector2(1,0)
 var invalid = pick.occludes(art, art.iso(2.5,7.5)) and pick.last_uncertain
 node.position = old
 check(invalid, "Transform mutation must invalidate old picker receipt")
 var result = {"query_requested_before_draw":true, "submitted_current":pick.submitted_frame == art.canvas_stream.frame_id, "presented_current":true, "samples":samples, "transform_mutation_invalidates":invalid}
 pick.close_query()
 return result

func validate_scene(label:String, rows:Array, contacts:Array):
 var keys = contacts.map(func(row): return row.actor)
 check(actor_domains.ok, "Café/ambient domain collision: " + str(actor_domains.errors))
 for contact in contacts: check(contact.domain in ["cafe","ambient"], "Unknown actor appearance domain: " + str(contact.actor))
 for row in rows:
  if row.has("actor"): check(row.domain in ["cafe","ambient"], "Unknown painter actor appearance domain: " + str(row.actor))
 var bodies = rows.filter(func(row): return row.get("domain", "") == "cafe" and str(row.get("actor", "")).ends_with("|body")).map(func(row): return row.actor)
 var contact_bodies = contacts.filter(func(row): return row.domain == "cafe" and row.actor.ends_with("|body")).map(func(row): return row.actor)
 var expected = expected_cafe_bodies()
 check(body_multiset_matches(contact_bodies,bodies), "Visible café bodies and live contact bodies differ")
 check(body_multiset_matches(bodies,expected,label == "pan-offscreen"), "Café body identities differ; expected " + str(expected) + ", actual " + str(bodies))
 for row in rows + contacts:
  if row.get("domain", "") == "cafe":
   check(row.actor.get_slice("|",0) + "|body" in expected, "Departed or unknown café actor pass remains: " + str(row.actor))
 check(rows.any(func(row): return row.kind == "wall-slice"), "Real wall slices missing")
 if label != "pan-offscreen": check(rows.any(func(row): return row.kind == "furniture" and row.item.kind == "chair"), "Real chairs missing")
 if label in ["seated-table-reach", "waiter-food-delivery", "chef-station-rear"]:
  var prefix = "guest/" + str(normal_guest.id) if label == "seated-table-reach" else "staff/" + str(game.staff_states.find(staff("waiter" if label == "waiter-food-delivery" else "chef")))
  var body = -1
  var overlay = -1
  for index in rows.size():
   if rows[index].get("actor", "") == prefix + "|body": body = index
   if rows[index].get("actor", "") == prefix + "|overlay": overlay = index
  check(body >= 0 and overlay > body, "Actor body must precede its own overlay")
  var surfaces = []
  if label == "chef-station-rear":
   var station = game.model.get_item(int(staff("chef").art_target_id))
   check(not station.is_empty() and station.kind == "stove", "Chef must target its real stove item")
   var anchor = plain(art.iso(station.x+.5, station.z+.5))
   for index in rows.size():
    var row = rows[index]
    # Station native keys intentionally omit item IDs. Its authored base part,
    # rotation and exact projected anchor bind this existing row to the target.
    if row.kind == "station-part" and row.shape[1] == "stove_base" and int(row.shape[2]) == posmod(int(station.rot),4) and row.placement[2] == anchor:
     surfaces.append(index)
  else:
   for index in rows.size():
    var row = rows[index]
    if row.kind == "furniture" and row.part == "item" and row.item.kind == "table" and int(row.item.id) == fixture_table:
     surfaces.append(index)
  check(surfaces.size() == 1, "Interleaving requires exactly the actor's actual table/stove foreground")
  if surfaces.size() == 1:
   check(body < surfaces[0] and surfaces[0] < overlay, "Target foreground must be between this actor's body and overlay")
 if label in ["blink-on", "blink-off"]:
  var chef_index = game.staff_states.find(staff("chef"))
  var chef = actual_owner("staff/" + str(chef_index) + "|body")
  check(chef != null and chef_index == 0, "Blink coverage requires the visible chef with clock offset zero")
  if chef != null:
   var appearance = chef.appearance[0]
   var options = appearance[12]
   check(options.has("blink") and bool(options.blink) == (label == "blink-on"), "Chef appearance must exercise blink on/off")
   check(not bool(appearance[6]) and not bool(options.get("view_back",true)), "Blink coverage must use the chef's front-facing head")
 if label == "body-overlay-depth-reversal":
  var prefix = "staff/" + str(game.staff_states.find(staff("waiter")))
  check(prefix + "|body" in keys and not prefix + "|overlay" in keys, "Foreground turn must remove waiter overlay")
 if label == "reflected-placement":
  check(actual_owner("staff/" + str(game.staff_states.find(staff("waiter"))) + "|body").transform.determinant() < 0, "Reflection must change the actual art transform")
 if label == "pan-offscreen":
  check(actual_owner("guest/" + str(normal_guest.id) + "|body") == null, "Offscreen camera case must actually cull the selected actor")

func save_image(filename:String)->String:
 var img = root.get_texture().get_image()
 img.convert(Image.FORMAT_RGBA8)
 check(img.get_size() == Vector2i(1360,880), "Viewport changed")
 var hash_context = HashingContext.new()
 hash_context.start(HashingContext.HASH_SHA256)
 hash_context.update(img.get_data())
 check(img.save_png(output.path_join(filename)) == OK, "PNG save failed")
 return hash_context.finish().hex_encode()

func capture_failed()->bool:
 if failures.is_empty(): return false
 pending_frame.status = "failed_incomplete"
 pending_frame.first_completed_frame = false
 pending_frame.completed.all_completed = false
 write_report()
 return true

func capture(label:String):
 if not failures.is_empty(): return
 # Keep incomplete evidence outside frames. Nothing becomes a completed pair
 # until every first-frame assertion and the PNG write have succeeded.
 pending_frame = {"label":label, "status":"preparing", "first_completed_frame":false, "input":{}, "completed":{"native_groups":0,"shapes":0,"all_completed":false}, "contacts":[], "emitted_contacts":[], "semantic_order":[], "silhouettes":[], "picking":{}, "file":"%02d-%s.png" % [frames.size(),label], "rgba_sha256":""}
 art.update_projection()
 refresh_actor_domains()
 pending_frame.input = inputs()
 pending_frame["expected_cafe_bodies"] = expected_cafe_bodies()
 write_report()
 check(label == LABELS[frames.size()], "Capture order differs")
 check(game.save_calls == 0, "Save callback occurred")
 check(actor_domains.ok, "Café/ambient domain collision: " + str(actor_domains.errors))
 if capture_failed(): return
 if not smoke: art.character_pick_geometry.request_query()
 pending_frame.status = "awaiting_first_post_draw"
 art.queue_redraw()
 if smoke: await process_frame
 else: await RenderingServer.frame_post_draw
 if not smoke:
  pending_frame.status = "first_post_draw_observed_unvalidated"
  var owner_contacts = []
  for owner in art.native_object_nodes.values():
   if owner.visible: owner_contacts.append_array(owner.contacts)
  var contact_issues = []
  var order_issues = []
  pending_frame.contacts = contacts_normalized(owner_contacts,contact_issues)
  pending_frame.emitted_contacts = contacts_normalized(art.render_contacts,contact_issues)
  pending_frame.semantic_order = current_order(order_issues)
  pending_frame["visible_cafe_bodies"] = pending_frame.semantic_order.filter(func(row): return row.get("domain", "") == "cafe" and str(row.get("actor", "")).ends_with("|body")).map(func(row): return row.actor)
  pending_frame.visible_cafe_bodies.sort()
  pending_frame["contact_issues"] = contact_issues
  pending_frame["order_issues"] = order_issues
  # Persist complete raw identity/contact/order observations before assertions.
  write_report()
  check(contact_issues.is_empty(), "Contact observation errors: " + str(contact_issues))
  check(order_issues.is_empty(), "Painter observation errors: " + str(order_issues))
  check(pending_frame.emitted_contacts == pending_frame.contacts, "Emitted/current owner contacts differ")
  if capture_failed(): return
  completed_native(art,pending_frame.completed)
  check(pending_frame.completed.native_groups > 0 and pending_frame.completed.shapes > 0, "Full scene lacks completed native paint")
  if capture_failed(): return
  var silhouette_issues = []
  pending_frame.silhouettes = actor_bounds(label,silhouette_issues)
  pending_frame["silhouette_issues"] = silhouette_issues
  write_report()
  validate_scene(label,pending_frame.semantic_order,pending_frame.contacts)
  check(silhouette_issues.is_empty(), "Silhouette observation errors: " + str(silhouette_issues))
  if capture_failed(): return
  pending_frame.picking = pick_receipt(label)
  if capture_failed(): return
  pending_frame.rgba_sha256 = save_image(pending_frame.file)
  pending_frame["post_draw_state"] = inputs()
  if capture_failed(): return
  pending_frame.completed.all_completed = true
  pending_frame.first_completed_frame = true
 pending_frame.status = "headless_smoke_only" if smoke else "validated_first_post_draw"
 frames.append(pending_frame)
 pending_frame = {}
 write_report()

func fresh_safety_frame():
 art.character_pick_geometry.request_query()
 art.queue_redraw()
 await RenderingServer.frame_post_draw
 var completed = {"native_groups":0, "shapes":0, "all_completed":true}
 completed_native(art, completed)
 check(art.character_pick_geometry.presented_frame == art.canvas_stream.frame_id, "Fresh frame did not restore a valid picker receipt")
 return completed

func safety_image(label:String, evidence:Dictionary):
 evidence["label"] = label
 evidence["first_completed_frame"] = true
 evidence["file"] = "abnormal/" + label + ".png"
 evidence["rgba_sha256"] = save_image(evidence.file)
 abnormal_safety.cases.append(evidence)
 write_report()

func exceptional_safety():
 if smoke or not candidate or not failures.is_empty(): return
 DirAccess.make_dir_recursive_absolute(output.path_join("abnormal"))
 abnormal_safety.executed = true
 var guest_key = "guest/" + str(normal_guest.id) + "|body"
 for event in ["queued-paint-cull", "queued-paint-departure", "queued-paint-reset"]:
  await fresh_safety_frame()
  var owner = actual_owner(guest_key)
  check(owner != null, "Adversarial actor must begin submitted")
  var saved = normal_guest
  var old_epoch = game.ground_mess_generation
  # Change only the retained appearance receipt so the real child _draw is queued.
  # Parent redraw then retires/hides that owner before the deferred child callback.
  var changed = owner.appearance.duplicate(true)
  changed.append(["candidate-only-pending-paint", event])
  owner.configure(art, owner.paint, changed, owner.transform)
  check(owner.paint_revision != owner.painted_revision, "Child paint was not actually pending")
  if event == "queued-paint-cull": game.editing = true
  elif event == "queued-paint-departure": game.model.customers.erase(normal_guest)
  else: game.ground_mess_generation += 1
  var retired = weakref(owner)
  var stale_id = owner.get_instance_id()
  art.character_pick_geometry.request_query()
  art.queue_redraw()
  await RenderingServer.frame_post_draw
  var active_keys = []
  for current in art.native_object_nodes.values():
   if current.visible: active_keys.append(actor_key(current))
  if event != "queued-paint-reset": check(guest_key not in active_keys, "Retired actor still draws")
  check(not art.render_contacts.any(func(contact): return int(contact.get("native_owner",-2)) == stale_id), "Retired owner emitted stale contacts")
  if is_instance_valid(retired.get_ref()):
   check(not retired.get_ref().visible and (event == "queued-paint-cull" or retired.get_ref().contacts.is_empty()), "Retired owner remains drawable/contact-bearing")
  safety_image(event, {"pending_child_queued":true, "no_stale_emitted_contacts":true, "old_owner_not_drawable":true})
  game.editing = false
  if event == "queued-paint-departure": game.model.customers.append(saved)
  game.ground_mess_generation = old_epoch + 1
  game._sync_service_guests()
  await fresh_safety_frame()
 # Hidden owners remain owned but unsubmitted. Revealing one cannot certify input.
 var hidden = actual_owner(guest_key)
 var sibling_index = hidden.get_index()
 art.move_child(hidden, 0 if sibling_index != 0 else art.get_child_count()-1)
 var order_rejected = art.character_pick_geometry.occludes(art, art.iso(2.5,7.5)) and art.character_pick_geometry.last_uncertain
 check(order_rejected, "Changed actual sibling order must invalidate the candidate receipt")
 art.move_child(hidden, sibling_index)
 await fresh_safety_frame()
 game.editing = true
 await fresh_safety_frame()
 check(not hidden.visible and not art.native_object_nodes.values().has(hidden), "Decorate must leave an unsubmitted hidden actor")
 hidden.show()
 var rejected = art.character_pick_geometry.occludes(art, art.iso(2.5,7.5)) and art.character_pick_geometry.last_uncertain
 check(rejected, "Resurrected unsubmitted owner must fail closed")
 hidden.hide()
 art.queue_redraw()
 await RenderingServer.frame_post_draw
 safety_image("hidden-owner-resurrection", {"unsubmitted_owner_revealed":true, "picker_failed_closed":true, "hidden_before_completion":true, "actual_sibling_order_invalidates":order_rejected, "fresh_receipt_restored":true})
 game.editing = false
 await fresh_safety_frame()
 var pending = actual_owner(guest_key)
 game.editing = true
 await fresh_safety_frame()
 pending.queue_free()
 pending.show()
 rejected = art.character_pick_geometry.occludes(art, art.iso(2.5,7.5)) and art.character_pick_geometry.last_uncertain
 check(rejected, "Queue-free-pending unsubmitted owner must fail closed")
 pending.hide()
 await RenderingServer.frame_post_draw
 safety_image("queue-free-owner-resurrection", {"queue_free_pending":true, "picker_failed_closed":true, "hidden_before_completion":true})
 # End here: no next artist draw may touch the deliberately queue-freed registry.
 abnormal_safety.passed = true

func write_report():
 if output == "": return
 var report = {"engine":Engine.get_version_info(), "display":DisplayServer.get_name(), "renderer":RenderingServer.get_current_rendering_method(), "viewport":[1360,880], "fixture_seed":13017, "generated_profile":true, "save_calls":game.save_calls if is_instance_valid(game) else 0, "game_instance_created":is_instance_valid(game), "smoke_only":smoke, "frames":frames, "pending_frame":pending_frame, "abnormal_safety":abnormal_safety, "failures":failures, "scope":"24 frozen generated full-Main first-post-draw frames; fixed logical poses, real native painter/query protocol. Candidate-only exceptional ownership cases are not paired pixels. No browser, continuous gameplay, FPS, GPU or user visual acceptance."}
 var file = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
 if file != null: file.store_string(JSON.stringify(report, "  ", true, true))

func run():
 check(output != "" and "saveguard" in OS.get_user_data_dir(), "Disposable output/profile required")
 for key in PROFILE_KEYS: check("saveguard" in OS.get_environment(key), "Isolated profile root missing: " + key)
 check(not OS.has_feature("web") and not OS.has_feature("crazygames"), "Native generated fixture only")
 for property in ProjectSettings.get_property_list():
  check(not str(property.name).begins_with("autoload/"), "Review autoload before permitting fixture startup")
 check(smoke or (DisplayServer.get_name() == "X11" and RenderingServer.get_current_rendering_method() == "gl_compatibility"), "Native GL Compatibility pixels required")
 DirAccess.make_dir_recursive_absolute(output)
 root.size = Vector2i(1360,880)
 seed(13017)
 game = SyntheticMain.new()
 root.add_child(game)
 game.set_process(false)
 art = game.illustration
 art.set_process(false)
 candidate = "native_actor_nodes" in art
 check(game.web_save == null and game.platform_music == null and game.audio_players.is_empty(), "Account/music route unexpectedly started")
 for wait_frame in 900:
  if smoke or not is_instance_valid(game.startup_readiness) or game.startup_readiness.completed: break
  await process_frame
 if not smoke:
  check(not game.startup_preparation_report.is_empty() and not game.startup_preparation_report.timed_out and game.startup_preparation_report.ready == 3, "Existing atlases failed ordinary startup preparation")
 if game.cafe_intro != null: game.cafe_intro.finish()
 for tween in get_processed_tweens(): tween.kill()
 freeze(game)
 game.ui.visible = false
 game.tray.hide()
 prepare_scene()
 await capture("initial")
 place_worker("waiter", Vector2(5.25,4.75))
 place_worker("cleaner", Vector2(4.75,5.25))
 await capture("equal-depth-approach-a")
 place_worker("waiter", Vector2(4.75,5.25))
 place_worker("cleaner", Vector2(5.25,4.75))
 await capture("equal-depth-approach-b")
 normal_guest.phase = "eating"
 normal_guest.seated = true
 normal_guest.elapsed = .4
 var meal = game.service_guests[int(normal_guest.id)]
 meal.plate_owner = "table"
 meal.plate_target_id = fixture_table
 meal.meal_ready = true
 meal.meal_done = true
 game._sync_service_guests()
 art.seat_blends[int(normal_guest.id)] = 1.0
 await capture("seated-table-reach")
 place_worker("waiter", Vector2(5.65,5.5), "serving", fixture_table, .4, "plate")
 await capture("waiter-food-delivery")
 place_worker("chef", Vector2(8.5,.7), "preparing_food", 1, .65, "plate")
 await capture("chef-station-rear")
 place_worker("cleaner", Vector2(5.5,7.15), "sweeping", -1, .55)
 staff("cleaner").art_target = Vector2(5.5,6.5)
 await capture("cleaner-litter-foreground")
 place_worker("waiter", Vector2(6.5,6.35), "serving", fixture_table, .8, "plate")
 await capture("body-overlay-depth-reversal")
 place_worker("waiter", Vector2(6.5,6.35), "standby")
 staff("waiter").art_station = staff("waiter").pos + Vector2(1,1)
 await capture("front-back-turn")
 staff("waiter").art_station = staff("waiter").pos + Vector2(-1,1)
 await capture("reflected-placement")
 game.animation_time = 0.0
 await capture("blink-on")
 game.animation_time = .2
 await capture("blink-off")
 # Inspection pan is clamped by the real camera. Zoom makes culling decisive.
 art.zoom = 3.0
 art.pan_offset = Vector2(-1300,0)
 await capture("pan-offscreen")
 art.zoom = 1.0
 art.pan_offset = Vector2.ZERO
 await capture("pan-back")
 art.zoom = .65
 await capture("zoom-out")
 art.zoom = 1.0
 await capture("zoom-back")
 game.editing = true
 await capture("decorate-hide")
 game.editing = false
 await capture("decorate-return")
 var departed = game.model.customers[-1]
 game.model.customers.erase(departed)
 game._sync_service_guests()
 await capture("guest-departure")
 var previous = normal_guest
 normal_guest = previous.duplicate(true)
 game.model.customers[game.model.customers.find(previous)] = normal_guest
 lifecycle.guest_replacements += 1
 game._sync_service_guests()
 await capture("same-id-guest-replacement")
 var worker = staff("waiter")
 worker.node.queue_free()
 worker.node = Node3D.new()
 game.people.add_child(worker.node)
 worker.node.position = Vector3(worker.pos.x,0,worker.pos.y)
 lifecycle.staff_replacements += 1
 await capture("staff-node-replacement")
 game.model.service_snapshot = game._current_service_snapshot()
 game._restore_service_runtime()
 lifecycle.service_restores += 1
 clear_presentation()
 await capture("same-main-service-restore")
 var old_model = game.model
 var replacement = game.Model.new()
 for property in old_model.get_property_list():
  if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
  var key = str(property.name)
  var value = old_model.get(key)
  replacement.set(key, value.duplicate(true) if value is Array or value is Dictionary else value)
 game.model = replacement
 game._connect_model_events()
 game._restore_service_runtime()
 lifecycle.model_replacements += 1
 normal_guest = game.model.customers.filter(func(row): return int(row.id) == int(normal_guest.id))[0]
 clear_presentation()
 await capture("model-replacement")
 place_worker("chef", Vector2(8.5,.7), "preparing_food", 1, .65, "plate")
 place_worker("waiter", Vector2(5.65,5.5), "serving", fixture_table, .4, "plate")
 place_worker("cleaner", Vector2(5.5,7.15), "sweeping", -1, .55)
 staff("cleaner").art_target = Vector2(5.5,6.5)
 await capture("final-normal-scene")
 check(frames.size() == 24 and game.save_calls == 0, "Complete normal sequence without saves")
 await exceptional_safety()
 write_report()
 game.queue_free()
 await process_frame
 print("STABLE_ACTOR_RETENTION_CAPTURE ", JSON.stringify({"frames":frames.size(), "smoke_only":smoke, "save_calls":0, "abnormal_executed":abnormal_safety.executed, "abnormal_passed":abnormal_safety.passed}))
 quit(0 if failures.is_empty() else 2)
